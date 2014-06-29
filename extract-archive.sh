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

tar xf /tmp/archive.tgz --no-same-owner -C /
mkdir -p /root/.ssh
cp $(getent passwd $SUDO_USER | cut -d: -f6)/.ssh/authorized_keys /root/.ssh/
/opt/jenkins-job-builder/jenkins_jobs/cmd.py update --delete-old /etc/jenkins_jobs/jobs

if [ -r /etc/edeploy/state ]; then
    chown www-data /etc/edeploy/*.cmdb /etc/edeploy/state
fi

# extract-archive.sh ends here
