#!/bin/bash
#
# Copyright (C) 2014 eNovance SAS <licensing@enovance.com>
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

stackname=${stackname:=spinal-stack}

if [ "$1" = "-l" ]; then
    flag=-l
    shift
else
    flag=
fi

dist="$1"
release="$2"
deployfile="$3"
remote="$4"
imageurl="$5"
tag="$6"

if [ -z "dist" -o -z "$release" -o -z "$deployfile" -o -z "$remote" -o -z "$imageurl" ]; then
    echo "$0 [-l] <dist> <release> <deployment file url> <remote> <image url>" 1>&2
    exit 1
fi

ORIG=$(cd $(dirname $0); pwd)

SSHOPTS="-oBatchMode=yes -oCheckHostIP=no -oHashKnownHosts=no \
      -oStrictHostKeyChecking=no -oPreferredAuthentications=publickey \
      -oChallengeResponseAuthentication=no -oKbdInteractiveDevices=no \
      -oConnectTimeout=3 -oUserKnownHostsFile=/dev/null"

set -e
set -x

# $tag defaults to $release
if [ -z "$tag" ]; then
    tag="$release"
fi

# Get remote access settings

if [ -r "$remote" ]; then
    . "$remote"
else
    scp $SSHOPTS $remote:/etc/config-tools/openrc.sh .

    . openrc.sh
fi

# Get VM images

for name in install-server-$dist-$release openstack-full-$dist-$release; do
    md5glance=$(glance -k image-show $name|fgrep checksum|cut -f3 -d\| |sed 's/ *//g' || :)
    rm -f $name.img.md5
    wget -q $imageurl/$name.img.md5
    md5img=$(cut -f1 -d' ' < $name.img.md5|sed 's/ *//g')
    if [ "$md5glance" != "$md5img" ]; then
        wget -q -O $name.img $imageurl/$name.img
        md5sum -c $name.img.md5
        glance --insecure image-create --name $name --container-format bare --disk-format raw < $name.img
    fi
done

# Get config from deployment file

${ORIG}/download.sh $flag $tag $deployfile version=$dist-$release
CFG=./top/etc/config-tools/global.yml

if [ ! -d top/etc/config-tools/infra ]; then
    mkdir top/etc/config-tools/infra
fi

scenario=$(${ORIG}/extract.py scenario env/$(basename $deployfile) || :)

if [ -r infra/scenarios/${scenario}/heat.yaml.tmpl ]; then
    cp infra/scenarios/${scenario}/heat.yaml.tmpl top/etc/config-tools/infra/
else
    cp infra/heat.yaml.tmpl top/etc/config-tools/infra/
fi

# Create stack

if ! heat stack-show ${stackname}; then
    netname=$(${ORIG}/extract.py config.floating_network_name $CFG)

    if [ -n "$netname" ]; then
        pubnet=$(neutron --insecure net-show $netname|fgrep '| id'| cut -d'|' -f3| sed -e 's/ //g')
    fi

    if [ -r top/etc/config-tools/infra/heat.yaml.tmpl ]; then
        $ORIG/generate.py 0 $CFG top/etc/config-tools/infra/heat.yaml.tmpl floating_network_id=$pubnet > heat.yaml
        heat stack-create --parameters="dist=$dist;release=$release" -f heat.yaml ${stackname}

        while heat stack-show ${stackname} | fgrep CREATE_IN_PROGRESS; do
            sleep 5
        done
    else
        echo "no heat.yaml.tmpl template in infra" 1>&2
        exit 1
    fi
fi

# Verify that VM are reachable

if ! heat stack-show ${stackname} | fgrep CREATE_COMPLETE; then
    echo "Problem creating heat stack:"
    heat stack-show ${stackname}
    exit 1
else
    ip=$(heat output-show ${stackname} output_public_ip|sed 's/"//g')
    user=$(${ORIG}/extract.py config.remote_user $CFG)

    # wait a bit that the install-server is up and running
    sleep 50
    if ! timeout 200 sh -c "while ! ping -w 1 -c 1 $ip; do sleep 1; done"; then
      echo "The floating IP $ip is unreachable"
      exit 1
    fi
    # wait a bit that the openstack-full is up and running
    sleep 50
    ssh $SSHOPTS $user@$ip uname -a
    for privip in $(grep '    ip:' $CFG | sed 's/    ip: //'); do
        ssh -A $SSHOPTS $user@$ip sudo ping -c 1 $privip
        ssh -A $SSHOPTS $user@$ip ssh $SSHOPTS $privip uname -a
    done
    MASTER=$ip ${ORIG}/send.sh
fi

# inception.sh ends here
