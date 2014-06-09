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

SSHOPTS="-oBatchMode=yes -oCheckHostIP=no -oHashKnownHosts=no \
      -oStrictHostKeyChecking=no -oPreferredAuthentications=publickey \
      -oChallengeResponseAuthentication=no -oKbdInteractiveDevices=no \
      -oConnectTimeout=3 -oUserKnownHostsFile=/dev/null"

ORIG=$(cd $(dirname $0); pwd)

if [ $# -lt 2 ]; then
    echo "Usage: $0 <tag> <deployment yaml> [<key>=<value>...]" 1>&2
    exit 1
fi

set -e
set -x

tag="$1"
puppetgit=$($ORIG/extract.py module "$2")
serverspecgit=$($ORIG/extract.py serverspec "$2")
envgit=$($ORIG/extract.py environment.repository "$2")
envyml=$($ORIG/extract.py environment.name "$2")
infragit=$($ORIG/extract.py infrastructure "$2")

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

# infra and env

update_or_clone "$infragit" infra
update_or_clone "$envgit" env

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

# hosts

if [ -r $ORIG/infra/hosts.tmpl ]; then
    $ORIG/generate.py 0 $ORIG/global.yml $ORIG/infra/hosts.tmpl > $ORIG/hosts
    HOSTS=$ORIG/hosts
else
    HOSTS=
fi

cat > site.pp <<EOF
Exec {
  path => '/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin'
}

hiera_include('classes')
EOF

# Copy files and put them at the right places on $MASTER

scp $SSHOPTS $HOSTS site.pp serverspec.tgz modules.tgz data.tgz $ORIG/config.tmpl $ORIG/configure.sh $ORIG/global.yml $ORIG/verify-servers.sh $ORIG/generate.py $ORIG/extract.py $USER@$MASTER:/tmp/
rsync -e "ssh $SSHOPTS" -a infra env $USER@$MASTER:/tmp/

ssh $SSHOPTS $USER@$MASTER sudo rm -rf /etc/serverspec /etc/puppet/modules /etc/puppet/data
ssh $SSHOPTS $USER@$MASTER sudo mkdir -p /etc/config-tools
ssh $SSHOPTS $USER@$MASTER sudo tar xf /tmp/serverspec.tgz -C /etc
ssh $SSHOPTS $USER@$MASTER sudo tar xf /tmp/modules.tgz -C /etc/puppet
ssh $SSHOPTS $USER@$MASTER sudo tar xf /tmp/data.tgz -C /etc/puppet
ssh $SSHOPTS $USER@$MASTER sudo mv /tmp/site.pp /etc/puppet/manifests
if [ -n "$HOSTS" ]; then
    ssh $SSHOPTS $USER@$MASTER sudo cp /tmp/hosts /etc/
fi
ssh $SSHOPTS $USER@$MASTER sudo cp /tmp/config.tmpl /tmp/global.yml /etc/config-tools/
ssh $SSHOPTS $USER@$MASTER sudo rsync -a --delete /tmp/infra /tmp/env /etc/config-tools/
ssh $SSHOPTS $USER@$MASTER sudo cp /tmp/configure.sh /tmp/verify-servers.sh /tmp/generate.py /tmp/extract.py /usr/sbin/
ssh $SSHOPTS $USER@$MASTER sudo mkdir -p /root/.ssh
ssh $SSHOPTS $USER@$MASTER sudo cp \~/.ssh/authorized_keys /root/.ssh/
scp $SSHOPTS $HOME/.ssh/id_rsa root@$MASTER:.ssh/

if [ -n "$VIP_NODE" ]; then
    $ORIG/configure-vip.sh $USER $VIP_NODE eth0 $PREFIX.253 || :
fi

# provision.sh ends here
