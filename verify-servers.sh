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

if [ $(id -u) != 0 ]; then
    exec sudo -i WORKSPACE=$WORKSPACE "$ORIG/$(basename $0)" "$@"
fi

SERVERSPECJOBS=10

if ! type -p rspec > /dev/null; then
    PATH=/usr/local/bin:$PATH
    export PATH
fi

CDIR=/etc/config-tools
CFG=$CDIR/global.yml

. $CDIR/config

if [ "$1" = -x ]; then
    XMLOUTPUT="$2"
    shift 2
else
    XMLOUTPUT=
fi

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

generate.py $step $CFG /etc/serverspec/arch.yml.tmpl|grep -v '^$' > /etc/serverspec/arch.yml

cd /etc/serverspec

RET=0
targets="$(rake -T spec|cut -f2 -d' '|grep -v '^spec'|sed 's/serverspec://')"

echo -n "all:" > $TMPDIR/Makefile
for target in $targets; do
    echo -n " $target" >> $TMPDIR/Makefile
done
echo >> $TMPDIR/Makefile

for target in $targets; do
    echo "$target:" >> $TMPDIR/Makefile
    if [ -n "$XMLOUTPUT" ]; then
        rm -f "$XMLOUTPUT/$target.xml"
	echo "	cd /etc/serverspec; rake serverspec:$target SPEC_OPTS=\"-r rspec-extra-formatters -f JUnitFormatter -o $XMLOUTPUT/$target.xml\" > $TMPDIR/$target.log 2>&1" >> $TMPDIR/Makefile
    else
	echo "	cd /etc/serverspec; rake serverspec:$target SPEC_OPTS='--profile' > $TMPDIR/$target.log 2>&1" >> $TMPDIR/Makefile
    fi
    echo >> $TMPDIR/Makefile
done

make -j$SERVERSPECJOBS -f $TMPDIR/Makefile

RET=$?

for target in $targets; do
    echo "$target:"
    cat $TMPDIR/$target.log
    echo "=============================="
done

exit $RET

# verify-servers.sh ends here
