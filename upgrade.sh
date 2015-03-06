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
for p in $PROFILES; do
  # upgrade host by host (serial)
  for host in $($ORIG/extract.py -a "$p.*" /etc/ansible/profiles.yml); do
    # respect snippets tags to have correct order
    for tag in {1..9}; do
      ansible-playbook -s -M /srv/edeploy/ansible/library /etc/ansible/site.yml -v --tags $tag -l $host
    done
  done
done

for step in 0 5; do
  echo $step | sudo tee /etc/config-tools/step
  configure.sh $step
done

# upgrade.sh ends here
