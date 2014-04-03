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

ORIG=$(cd $(dirname $0); pwd)

SERVERSPECJOBS=10

PATH=/usr/share/config-tools:$PATH
export PATH

CDIR=/etc/config-tools
CFG=$CDIR/global.yaml

. $CDIR/config

if [ "$1" = -x ]; then
    XMLOUTPUT=1
    shift
else
    XMLOUTPUT=0
fi

step=$1

if [ -z "$step" ]; then
    step=$(cat $CDIR/step)
fi

if [ -z "$step" ]; then
    step=100
fi

generate.py $step $CFG /etc/serverspec/arch.yml.tmpl|grep -v '^$' > /etc/serverspec/arch.yml

cd /etc/serverspec

rm -f /tmp/*.xml

RET=0
targets="$(rake -T spec|cut -f2 -d' '|grep -v '^spec'|sed 's/serverspec://')"

echo -n "all:" > Makefile
for target in $targets; do
    echo -n " $target" >> Makefile
done
echo >> Makefile

for target in $targets; do
    echo "$target:" >> Makefile
    if [ $XMLOUTPUT -eq 1 ]; then
	echo "	rake serverspec:$target SPEC_OPTS=\"-r rspec-extra-formatters -f JUnitFormatter -o /tmp/$target.xml\" > $target.log 2>&1" >> Makefile
    else
	echo "	rake serverspec:$target SPEC_OPTS='--profile' > $target.log 2>&1" >> Makefile
    fi
    echo >> Makefile
done

make -j$SERVERSPECJOBS

RET=$?

for target in $targets; do
    echo "$target:"
    cat $target.log
    echo "=============================="
done

exit $RET

# verify-servers.sh ends here
