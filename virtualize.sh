#!/bin/bash
#
# Copyright (C) 2015 eNovance SAS <licensing@enovance.com>
#
# Author: Frederic Lepied <frederic.lepied@enovance.com>
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

set -e
set -x

ORIG=$(cd $(dirname $0); pwd)

if [ $# != 6 ]; then
    echo "Usage: $0 <tag> <deployement git url> <release> <OS version> <libvirt host> <install server hostname>"
    echo
    echo "ex: $0 I.1.3.1 file:///home/fred/testenv/virt-RH7.0.yml I.1.3.0 RH7.0 192.168.100.12 os-ci-test4"
    exit 1
fi

tag=$1
deployment=$2
stable=$3
version=$4-$stable
virthost=$5
installserver=$6


# Default values if not set by user env
if [ -z "$TIMEOUT_ITERATION" ]; then
    TIMEOUT_ITERATION=150
fi

SSHOPTS="-oBatchMode=yes -oCheckHostIP=no -oHashKnownHosts=no  -oStrictHostKeyChecking=no -oPreferredAuthentications=publickey  -oChallengeResponseAuthentication=no -oKbdInteractiveDevices=no -oUserKnownHostsFile=/dev/null"

test_connectivity() {
    set +x
    local i=0
    local host_ip=$1
    local host_name=$2
    while true; do
        echo -n "."
        ssh $SSHOPTS jenkins@$host_ip uname -a > /dev/null 2>&1 && break
        sleep 4
        i=$[i+1]
        if [[ $i -ge $TIMEOUT_ITERATION ]]; then
	    echo "uname timeout on $host_name..."
	    return 1
        fi
    done
    echo "Node $host_name is alive !"
    return 0
}

$ORIG/download.sh $tag $deployment version=$version stable=$stable

installserverip=$($ORIG/extract.py hosts.${installserver}.ip top/etc/config-tools/global.yml)

if ! ssh $SSHOPTS root@$virthost test -r /var/lib/libvirt/images/install-server-$version.img.qcow2; then
    edeployurl=$($ORIG/extract.py roles "env/$(basename $deployment)"|sed -e "s/@VERSION@/$version/")
    ssh $SSHOPTS root@$virthost wget -q -O /var/lib/libvirt/images/install-server-$version.img.qcow2 $edeployurl/install-server-$version.img.qcow2
fi

if [ -n "$SSH_AUTH_SOCK" ]; then
    ssh-add -L > pubfile
    pubfile=pubfile
else
    pubfile=~/.ssh/id_rsa.pub
fi

$ORIG/virtualization/collector.py --sps-version $version --config-dir top/etc

$ORIG/virtualization/virtualizor.py --replace --pub-key-file $pubfile virt_platform.yml $virthost

ssh-keygen -f "$HOME/.ssh/known_hosts" -R $installserverip

test_connectivity $installserverip $installserver

set -x

MASTER=$installserverip ./send.sh

ssh $SSHOPTS root@$installserverip "echo -e 'RSERV=localhost\nRSERV_PORT=873' >> /var/lib/edeploy/conf"

ssh $SSHOPTS root@$installserverip service dnsmasq restart
ssh $SSHOPTS root@$installserverip service httpd restart
ssh $SSHOPTS root@$installserverip service rsyncd restart

. top/etc/config-tools/config

JOBS=
declare -a assoc

for node in $HOSTS; do
    (
	echo "Testing $hostname"
        ip=$(./extract.py hosts.${node}.ip top/etc/config-tools/global.yml)
        test_connectivity $ip $node || exit 1
    ) &
    JOBS="$JOBS $!"
    assoc[$!]=$hostname
done

set -x
set +e

rc=0
for job in $JOBS; do
    wait $job
    ret=$?
    if [ $ret -eq 127 ]; then
	echo "$job doesn't exist anymore"
    elif [ $ret -ne 0 ]; then
	echo "${assoc[$job]} wasn't installed"
	rc=1
    fi
done

set -e

curl http://$installserverip:8282/job/puppet/build
#ssh $SSHOPTS -A root@$installserverip configure.sh

# virtualize.sh ends here
