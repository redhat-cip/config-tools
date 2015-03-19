#!/bin/bash
#
# Copyright (C) 2015 eNovance SAS <licensing@enovance.com>
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

set -e
set -x

ORIG=$(cd $(dirname $0); pwd)

if [ $(id -u) != 0 ]; then
  SUDO=sudo
fi

source /etc/config-tools/config
export ANSIBLE_HOST_KEY_CHECKING=false
CFG='/etc/config-tools/global.yml'

for template in profiles.yml site.yml hosts group_vars/all; do
  generate.py 0 /etc/config-tools/global.yml /etc/ansible/$template.tmpl|grep -v '^$' |sudo tee /etc/ansible/$template > /dev/null
  sudo chmod 0644 /etc/ansible/$template
done

# respect 'ordered_profiles' order to upgrade
# this loop is idempotent. It will iterate each host of each profile
# and try to start or resume the upgrade process.
for p in $PROFILES; do
  $SUDO mkdir -p /etc/ansible/steps/$p
  $SUDO chown -R jenkins:jenkins /etc/ansible/steps
  mkdir -p /etc/ansible/steps/$p
  # upgrade host by host (serial)
  for host in $($ORIG/extract.py -a "$p.*" /etc/ansible/profiles.yml); do
    # host is an array returned by extract.py, we need to sanitize it
    host=$(echo $host | sed 's/\[//g' | sed 's/\]//g' | sed -e "s/\'//g" |sed -e "s/\,//g" | sed -e "s/'//g")
    # this is the first run, we start at step 1
    if [ ! -f /etc/ansible/steps/$p/$host ]; then
      step=1
    # if the file does not exist, we continue from the latest successful step
    else
      step=$(cat /etc/ansible/steps/$p/$host)
    fi
    # we don't want to repeat last step if already done
    if [ "$step" = "9" ];then
      continue
    fi
    # respect snippets tags to have correct order
    for tag in $(seq $step 9); do
      echo $tag > /etc/ansible/steps/$p/$host
      ansible-playbook -s -M /srv/edeploy/ansible/library /etc/ansible/site.yml -v --tags $tag -l $host
    done
  done
done

for step in 0 5; do
  echo $step | sudo tee /etc/config-tools/step
  configure.sh $step
done

# cleanup
$SUDO rm -rf /etc/ansible/steps

# upgrade.sh ends here
