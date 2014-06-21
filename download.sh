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

if [ $# -lt 2 ]; then
    echo "Usage: $0 <tag> <deployment yaml> [<key>=<value>...]" 1>&2
    exit 1
fi

set -e
set -x

tag="$1"
yaml="$2"

checkout_tag() {
    cd $1
    if [ -n "$tag" ] && (git tag; git branch -r) | grep $tag; then
	git checkout $tag
	tagged=1
    else
	tagged=0
    fi
    git log -1
    cd ..
}

update_or_clone() {
    giturl=$1
    dir=$2

    if [ -r $dir/.git/config ]; then
        if ! grep -q "url = $giturl\$" $dir/.git/config; then
            rm -rf $dir
        fi
    fi

    if [ -d $dir ]; then
	cd $dir
	git reset --hard
	git clean -xfdq
	git checkout master
	git checkout .
	git pull
	cd ..
    else
	git clone $giturl $dir
    fi

    checkout_tag $dir
}

envgit=$(dirname $yaml)
yamlfile=env/$(basename $yaml)

update_or_clone "$envgit" env

puppetgit=$($ORIG/extract.py module "$yamlfile")
serverspecgit=$($ORIG/extract.py serverspec "$yamlfile")
envyml=$($ORIG/extract.py environment "$yamlfile")
infragit=$($ORIG/extract.py infrastructure "$yamlfile")

# infra and env

update_or_clone "$infragit" infra

if [ ! -f infra/infra.yml ]; then
    echo "infra.yml not found in $infragit" 1>&2
    exit 1
fi

if [ ! -f env/$envyml ]; then
    echo "$envyml not found in $envgit" 1>&2
    exit 1
fi

cat infra/infra.yml env/$envyml > global.yml

$ORIG/generate.py 0 global.yml $ORIG/config.tmpl > config
. config

if [ -z "$USER" ]; then
    echo "USER not defined in env/env.yml" 1>&2
    exit 1
fi

if [ -z "$MASTER" ]; then
    echo "MASTER not defined in env/env.yml" 1>&2
    exit 1
fi

# /etc/puppet/data

for f in infra/data/common.yaml.tmpl infra/data/fqdn.yaml.tmpl infra/data/type.yaml.tmpl; do
    if [ ! -f  ]; then
	echo "$f not found in $infragit" 1>&2
	exit 1
    fi
done

rm -rf data.tgz data
mkdir data
tar zcf data.tgz -C infra data

# Serverspec

update_or_clone "$serverspecgit" serverspec

git --git-dir=serverspec/.git rev-parse HEAD > serverspec-rev

cp infra/arch.yml.tmpl serverspec/
sed -i "s/root/$USER/" serverspec/spec/spec_helper.rb

rm -f serverspec.tgz
tar zcf serverspec.tgz --exclude=".git*" serverspec

# Puppet modules

update_or_clone "$puppetgit" puppet-module

git --git-dir=puppet-module/.git rev-parse HEAD > puppet-module-rev

if [ -n "$tag" -a "$tagged" = 1 ]; then
    sed -i -e "s/master/$(cat puppet-module-rev)/" ./puppet-module/Puppetfile
fi

rm -rf modules
PUPPETFILE=./puppet-module/Puppetfile PUPPETFILE_DIR=./modules r10k --verbose 3 puppetfile install

rm -f modules.tgz
tar zcf modules.tgz --exclude=".git*" modules

# download.sh ends here
