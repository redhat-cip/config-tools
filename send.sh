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

. top/etc/config-tools/config

if tty -s; then
    ROPTS=-vP
fi

if [ $USER != root ]; then
    SUDO=sudo
fi

if [ "${PROF_BY_HOST[$HOSTNAME]}" == "install-server" ]; then
    cp -a archive.tar functions extract-archive.sh /tmp/
    $SUDO /tmp/extract-archive.sh
else
    rsync -e "ssh $SSHOPTS" -az $ROPTS archive.tar functions extract-archive.sh $USER@$MASTER:/tmp/
    ssh $SSHOPTS $USER@$MASTER $SUDO /tmp/extract-archive.sh
fi

# send.sh ends here
