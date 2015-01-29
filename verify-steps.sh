#!/bin/bash
#
# Copyright (C) 2014 eNovance SAS <licensing@enovance.com>
#
# Author: Emilien Macchi <emilien.macchi@enovance.com>
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

ORIG=$(cd $(dirname $0); pwd)

if [ $(id -u) != 0 ]; then
    exec sudo -i WORKSPACE=$WORKSPACE "$ORIG/$(basename $0)" "$@"
fi

if ! type -p puppet > /dev/null; then
    PATH=/usr/local/bin:$PATH
    export PATH
fi

CDIR=/etc/config-tools
CFG=$CDIR/global.yml

. $CDIR/config

step=$1

TMPDIR=$(mktemp -d)

if [ ! -d "$TMPDIR" ]; then
    echo "Unable to create temp dir." 1>&2
    exit 1
fi

cleanup() {
    rm -rf $TMPDIR
}

trap cleanup 0

if [ -z "$step" ]; then
    step=$(cat $CDIR/step)
fi

if [ -z "$step" ]; then
    step=100
fi

generate.py $step $CFG /etc/puppet/steps.yml.tmpl|grep -v '^$' > /etc/puppet/steps.yml

RET=0

# need to find a way to consume YAML file to list hosts
for host in hosts;
do
  # need to find a way to consume YAML file to list classes
  for class in classes;
  do
    # need to find a way to consume YAML file to get anchor name
    if ! puppet query nodes "(Anchor['Create ${anchor} anchor'] and hostname='${host}')"; then
        echo "${anchor} service is not running on ${host}."
    fi
  done
done

RET=$?
exit $RET

# verify-steps.sh ends here
