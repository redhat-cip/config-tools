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

# Copy files and put them at the right places on $MASTER

SSHOPTS="-oBatchMode=yes -oCheckHostIP=no -oHashKnownHosts=no \
      -oStrictHostKeyChecking=no -oPreferredAuthentications=publickey \
      -oChallengeResponseAuthentication=no -oKbdInteractiveDevices=no \
      -oConnectTimeout=3 -oUserKnownHostsFile=/dev/null"

set -e
set -x

ORIG=$(cd $(dirname $0); pwd)

if [ ! -r $ORIG/config ]; then
    echo "No config file found. Aborting."
    exit 1
fi

cd $ORIG
. config

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

scp $SSHOPTS $HOSTS openrc.sh site.pp serverspec.tgz modules.tgz data.tgz $ORIG/config.tmpl $ORIG/configure.sh $ORIG/global.yml $ORIG/verify-servers.sh $ORIG/generate.py $ORIG/extract.py $USER@$MASTER:/tmp/
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
ssh $SSHOPTS $USER@$MASTER sudo cp /tmp/openrc.sh /etc/config-tools/
ssh $SSHOPTS $USER@$MASTER sudo rsync -a --delete /tmp/infra /tmp/env /etc/config-tools/
ssh $SSHOPTS $USER@$MASTER sudo cp /tmp/configure.sh /tmp/verify-servers.sh /tmp/generate.py /tmp/extract.py /usr/sbin/
ssh $SSHOPTS $USER@$MASTER sudo mkdir -p /root/.ssh
ssh $SSHOPTS $USER@$MASTER sudo cp \~/.ssh/authorized_keys /root/.ssh/
scp $SSHOPTS $HOME/.ssh/id_rsa root@$MASTER:.ssh/

# send.sh ends here
