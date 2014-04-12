#!/bin/sh
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

set -e
set -x

SSHOPTS="-oBatchMode=yes -oCheckHostIP=no -oHashKnownHosts=no \
      -oStrictHostKeyChecking=no -oPreferredAuthentications=publickey \
      -oChallengeResponseAuthentication=no -oKbdInteractiveDevices=no \
      -oConnectTimeout=3 -oUserKnownHostsFile=/dev/null"

ORIG=$(cd $(dirname $0); pwd)

if [ $# != 5 ]; then
    echo "Usage: $0 <tag> <puppet module git> <serverspec git> <env git> <infra git>" 1>&2
    exit 1
fi

tag="$1"
puppetgit="$2"
serverspecgit="$3"
envgit="$4"
infragit="$5"

checkout_tag() {
    cd $1
    if [ -n "$tag" ] && git tag | grep $tag; then
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

cat infra/infra.yml env/env.yml > global.yml

./generate.py 0 global.yml config.tmpl > config
. config

if [ -z "$USER" ]; then
    echo "USER not defined in env/env.yml" 1>&2
    exit 1
fi

if [ -z "$MASTER" ]; then
    echo "MASTER not defined in env/env.yml" 1>&2
    exit 1
fi

# Manifests

rm -rf manifests.tgz manifests
mkdir manifests
cp -p infra/*.pp.tmpl manifests/
tar zcf manifests.tgz --exclude=".git*" manifests

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

if [ -r $ORIG/hosts ]; then
    HOSTS=$ORIG/hosts
else
    HOSTS=
fi

# Copy files and put them at the right places on $MASTER

scp $SSHOPTS $HOSTS serverspec.tgz modules.tgz manifests.tgz $ORIG/config $ORIG/configure.sh $ORIG/verify-servers.sh $ORIG/generate.py $USER@$MASTER:/tmp/
ssh $SSHOPTS $USER@$MASTER sudo rm -rf /etc/serverspec /etc/puppet/modules /etc/puppet/manifests
ssh $SSHOPTS $USER@$MASTER sudo tar xf /tmp/serverspec.tgz -C /etc
ssh $SSHOPTS $USER@$MASTER sudo tar xf /tmp/modules.tgz -C /etc/puppet
ssh $SSHOPTS $USER@$MASTER sudo tar xf /tmp/manifests.tgz -C /etc/puppet
if [ -n "$HOSTS" ]; then
    ssh $SSHOPTS $USER@$MASTER sudo cp /tmp/hosts /etc/
fi
ssh $SSHOPTS $USER@$MASTER sudo cp /tmp/config /etc/puppet/
ssh $SSHOPTS $USER@$MASTER sudo cp /tmp/configure.sh /tmp/verify-servers.sh /tmp/generate.py /usr/sbin/
ssh $SSHOPTS $USER@$MASTER sudo mkdir -p /root/.ssh
ssh $SSHOPTS $USER@$MASTER sudo cp \~/.ssh/authorized_keys /root/.ssh/
scp $SSHOPTS $HOME/.ssh/id_rsa root@$MASTER:.ssh/

if [ -n "$VIP_NODE" ]; then
    $ORIG/configure-vip.sh $USER $VIP_NODE eth0 $PREFIX.253 || :
fi

# provision.sh ends here
