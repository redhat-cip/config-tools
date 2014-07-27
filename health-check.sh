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

# Purpose: deploy a set of nodes using the eDeploy according to the
# list on the command line or all the nodes described in the config
# file.
#
# eDeploy configuration must have been prepared before calling this
# script.

DIR=$(cd $(dirname $0); pwd)

if [ $(id -u) != 0 ]; then
    exec sudo -i WORKSPACE=$WORKSPACE "$DIR/$(basename $0)" "$@"
fi

NODES="$*"

HOSTS=/etc/edeploy/hosts.conf

LOGDIR=$WORKSPACE

if [ ! -d "$LOGDIR" ]; then
    LOGDIR=$(mktemp -d)
fi

if [ ! -r $HOSTS ]; then
    echo "$HOSTS not present. Aborting"
    exit 1
fi

if [ -z "$NODES" ]; then
    NODES="$(cut -f1 -d' ' $HOSTS)"
fi

# Default values if not set by user env
if [ -z "$TIMEOUT_ITERATION" ]; then
    TIMEOUT_ITERATION=150
fi

SSHOPTS="-oBatchMode=yes -oCheckHostIP=no -oHashKnownHosts=no \
      -oStrictHostKeyChecking=no -oPreferredAuthentications=publickey \
      -oChallengeResponseAuthentication=no -oKbdInteractiveDevices=no \
      -oConnectTimeout=600 -oUserKnownHostsFile=/dev/null \
      -i /var/lib/jenkins/.ssh/id_rsa"

poweroff_node() {
    local ipmi_ip=$1
    local ipmi_user=$2
    local ipmi_password=$3
    local try=10
    ipmitool -I lanplus -H $ipmi_ip -U $ipmi_user -P $ipmi_password power off
    while ! [[ $(ipmitool -I lanplus -H $ipmi_ip -U $ipmi_user -P $ipmi_password power status) =~ .*off ]]; do
	sleep 6
	try=$(($try - 1))
	if [ $try -eq 0 ]; then
	    echo "Unable to poweroff $ipmi_ip"
	    break
	fi
    done
}

configure_pxe() {
    local host_name=$1
    # edeploy|local
    local boot_medium=$2
    pxemngr nextboot $host_name $boot_medium
}

reboot_node() {
    local ipmi_ip=$1
    local ipmi_user=$2
    local ipmi_password=$3
    status=$(ipmitool -I lanplus -H $ipmi_ip -U $ipmi_user -P $ipmi_password power status)
    if [[  "$status" =~ .*off ]]; then
        cmd="on"
    else
        cmd="reset"
    fi
    ipmitool -I lanplus -H $ipmi_ip -U $ipmi_user -P $ipmi_password power $cmd
}

test_connectivity() {
    local i=0
    local host_ip=$1
    local host_name=$2
    local ipmi_ip=$3
    local ipmi_user=$4
    local ipmi_password=$5
    while true; do
        echo -n "."
        ping -c 1 $host_ip && break
        sleep 4
        i=$[i+1]
        if [[ $i -ge $TIMEOUT_ITERATION ]]; then
	    echo "ping timeout on $host_name..."
	    return 1
        fi
    done
    echo "Node $host_name is alive !"
    ipmitool -I lanplus -H $ipmi_ip -U $ipmi_user -P $ipmi_password bmc reset cold
    return 0
}

wait_for_shutdown() {
    local host_ip=$1

    while ping -c 1 $host_ip; do
	sleep 10
    done
}

# be sure to stop dnsmasq on any script exit
cleanup() {
    service dnsmasq stop
}

set -x

# we clean the result dir to be able to count the number of results to
# check if everything is right
rm -rf /var/lib/edeploy/health/install

trap cleanup 0
service dnsmasq stop
service dnsmasq start

JOBS=
tmpfile=$(mktemp)
declare -a assoc
count=0

for node in $NODES; do
    grep "^$node " $HOSTS > $tmpfile
    lines=$(wc -l < $tmpfile)
    count=$(($count + $lines))
    while read hostname ip mac ipmi user pass; do
        (
	    echo "Rebooting $hostname"
            poweroff_node $ipmi $user $pass
            configure_pxe $hostname health-check
            reboot_node $ipmi $user $pass
	    sleep 120
            test_connectivity $ip $hostname $ipmi $user $pass || exit 1
	    wait_for_shutdown $ip
	) > $LOGDIR/edeploy-$hostname.log 2>&1 &
	JOBS="$JOBS $!"
	assoc[$!]=$hostname
    done < $tmpfile
done

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

if [ $count != $(ls /var/lib/edeploy/health/install/*/*.hw|wc -l) ]; then
    rc=1
fi

cp /var/lib/edeploy/health/install/*/*.hw $LOGDIR/

if [ -n "$SUDO_USER" ]; then
    chown $SUDO_USER $LOGDIR/*
fi

exit $rc

# health-check.sh ends here
