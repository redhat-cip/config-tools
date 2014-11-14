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
    echo "Usage: $0 [-l] <tag> <deployment yaml> [<key>=<value>...]" 1>&2
    echo "    -l: do not download files. Use the local copies." 1>&2
    exit 1
fi

set -e
set -x

if [ $1 = -l ]; then
    LOCAL=1
    shift
else
    LOCAL=
fi

tag="$1"
yaml="$2"
shift 2

branch=${tag%.*}

role=openstack-full
eval "$@"

checkout_tag() {
    cd $1
    if [ -n "$tag" ] && (git tag; git branch -r) | egrep "$tag|$branch"; then
	git checkout $tag || git checkout $branch
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
        if [ "$LOCAL" != 1 ]; then
	    cd $dir
	    git reset --hard
	    git clean -xfdq
	    git checkout $branch || git checkout master
	    git checkout .
	    git pull
	    cd ..
        fi
    else
	git clone $giturl $dir
	git checkout $branch || git checkout master
    fi

    checkout_tag $dir
}

clone() {
    giturl=$1
    dir=$2

    if [ -r $dir/.git/config ]; then
        if ! grep -q "url = $giturl\$" $dir/.git/config; then
            rm -rf $dir
        fi
    fi

    if [ -d $dir ]; then
        if [ "$LOCAL" != 1 ]; then
	    cd $dir
	    git reset --hard
	    git clean -xfdq
	    git checkout $branch || git checkout master
	    git checkout .
	    git pull
	    cd ..
        fi
    else
	git clone $giturl $dir
	git checkout $branch || git checkout master
    fi
}

check_and_download() {
    url=$1
    base=$(basename $url)

    if [ "$LOCAL" != 1 ]; then
        rm -f $base.md5
        wget -q $url.md5
        if ! md5sum -c $base.md5; then
            rm -f $base
            wget -q $url
            md5sum -c $base.md5
        fi
    fi
}

envgit=$(dirname $yaml)
yamlfile=env/$(basename $yaml)

update_or_clone "$envgit" env

puppetgit=$($ORIG/extract.py module "$yamlfile")
serverspecgit=$($ORIG/extract.py serverspec "$yamlfile")
env=$($ORIG/extract.py environment "$yamlfile")
envyml=${env}.yml
infragit=$($ORIG/extract.py infrastructure "$yamlfile")

# allow to have an empty fields (optional)

set +e

if [ -z "$version" ]; then
    version=$($ORIG/extract.py version "$yamlfile")
fi

ansiblegit=$($ORIG/extract.py ansible "$yamlfile")
kernel=$($ORIG/extract.py kernel "$yamlfile"|sed -e "s/@VERSION@/$version/")
pxe=$($ORIG/extract.py pxeramdisk "$yamlfile"|sed -e "s/@VERSION@/$version/")
health=$($ORIG/extract.py healthramdisk "$yamlfile"|sed -e "s/@VERSION@/$version/")
edeployurl=$($ORIG/extract.py edeploy "$yamlfile"|sed -e "s/@VERSION@/$version/")
jenkinsgit=$($ORIG/extract.py jenkins "$yamlfile")
scenario=$($ORIG/extract.py scenario "$yamlfile")

set -e

# infra and env
update_or_clone "$infragit" infra

if [ -n "$scenario" ]; then
    if [ ! -f "infra/scenarios/${scenario}/infra.yaml" ]; then
        echo "scenarios/${scenario}/infra.yaml not found in $infragit" 1>&2
        exit 1
    else
        infrayaml=infra/scenarios/${scenario}/infra.yaml
    fi
else
    if [ ! -f infra/infra.yaml ]; then
        echo "infra.yaml not found in $infragit" 1>&2
        exit 1
    else
        infrayaml=infra/infra.yaml
    fi
fi

if [ ! -f env/$envyml ]; then
    echo "$envyml not found in $envgit" 1>&2
    exit 1
fi

# create root of the tree

TOP=$(pwd)/top
rm -rf $TOP
mkdir -p $TOP/etc/config-tools $TOP/etc/puppet/manifests $TOP/usr/sbin $TOP/usr/bin

$ORIG/merge.py $infrayaml env/$envyml > $TOP/etc/config-tools/global.yml

$ORIG/generate.py 0 $TOP/etc/config-tools/global.yml $ORIG/config.tmpl version=$version role=$role > $TOP/etc/config-tools/config
. $TOP/etc/config-tools/config

if [ -z "$USER" ]; then
    echo "config.user not defined in env/$envyml" 1>&2
    exit 1
fi

if [ -z "$MASTER" ]; then
    echo "config.puppet_master not defined in env/$envyml" 1>&2
    exit 1
fi

# eDeploy

if [ -d env/$env ]; then
    if [ -z "$version" ]; then
        echo "pass version=<version> on the command line" 1>&1
        exit 1
    fi
    rsync -a env/$env/ $TOP/
    # use find to avoid breaking symlinks
    sed -i -e "s/@VERSION@/$version/" -e "s/@ROLE@/$role/" $(find $TOP/etc/edeploy/ -type f)

    mkdir -p $ORIG/cache/$version

    mkdir -p $TOP/var/lib/tftpboot
    for url in $kernel $pxe $health; do
        (cd $ORIG/cache/$version
         check_and_download $url
         cp $base $TOP/var/lib/tftpboot/
        )
    done

    mkdir -p $TOP/var/www/install/$version
    # TODO: make the list of roles generic
    for role in $($ORIG/extract.py -a 'profiles.*.edeploy' $TOP/etc/config-tools/global.yml|fgrep -v install-server|sort -u); do
        (cd $ORIG/cache/$version
         check_and_download $edeployurl/$role-$version.edeploy
         cp $role-$version.edeploy* $TOP/var/www/install/$version/
        )
    done
fi

# Jenkins jobs builder

if [ -n "$jenkinsgit" ]; then
    update_or_clone "$jenkinsgit" jenkins_jobs
    cp -a jenkins_jobs $TOP/etc/
fi

# Puppet

for f in infra/data/common.yaml.tmpl infra/data/fqdn.yaml.tmpl infra/data/type.yaml.tmpl; do
    if [ ! -f  ]; then
	echo "$f not found in $infragit" 1>&2
	exit 1
    fi
done

cp -r infra/data $TOP/etc/puppet/

cat > $TOP/etc/puppet/manifests/site.pp <<EOF
Exec {
  path => '/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin'
}

hiera_include('classes')
EOF

# Ansible

if [ -n "$ansiblegit" ]; then
    clone "$ansiblegit" ansible
    mkdir -p $TOP/etc/ansible
    cp -a ansible/upgrade/$tag/*/* $TOP/etc/ansible/
fi

# hosts

if [ -r $ORIG/infra/hosts.tmpl ]; then
    $ORIG/generate.py 0 $TOP/etc/config-tools/global.yml $ORIG/infra/hosts.tmpl > $TOP/etc/hosts
fi

# Puppet modules

update_or_clone "$puppetgit" puppet-module

git --git-dir=puppet-module/.git rev-parse HEAD > $TOP/etc/config-tools/puppet-module-rev

if [ -n "$tag" -a "$tagged" = 1 ]; then
    sed -i -e "s/master/$(cat ${TOP}/etc/config-tools/puppet-module-rev)/" ./puppet-module/Puppetfile
fi

if [ "$LOCAL" != 1 ]; then
    rm -rf modules

    PUPPETFILE=./puppet-module/Puppetfile PUPPETFILE_DIR=./modules r10k --verbose 3 puppetfile install
fi

cp -a modules $TOP/etc/puppet/

# Serverspec

update_or_clone "$serverspecgit" serverspec

git --git-dir=serverspec/.git rev-parse HEAD > $TOP/etc/config-tools/serverspec-rev

cp infra/arch.yml.tmpl serverspec/
sed -i "s/root/$USER/" serverspec/spec/spec_helper.rb

cp -a serverspec $TOP/etc/

# scripts

cp $ORIG/configure.sh $ORIG/verify-servers.sh $ORIG/generate.py $ORIG/merge.py $ORIG/extract.py $ORIG/edeploy-nodes.sh $ORIG/health-check.sh $TOP/usr/bin/

# config-tools

cp $ORIG/config.tmpl $TOP/etc/config-tools/

if [ -r infra/openrc.sh.tmpl ]; then
    $ORIG/generate.py 0 $TOP/etc/config-tools/global.yml infra/openrc.sh.tmpl > $TOP/etc/config-tools/openrc.sh
fi

# create the archive

tar cf archive.tar -C $TOP .

# download.sh ends here
