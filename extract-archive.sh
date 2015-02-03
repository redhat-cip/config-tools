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

set -e
set -x

ORIG=$(cd $(dirname $0); pwd)
. $ORIG/functions

TARBALL_ARCHIVE="/tmp/archive.tar"
SUDO_USER=${SUDO_USER:=root}

if [ -r /etc/redhat-release ]; then
    USER=apache
else
    USER=www-data
fi


if [ -f $TARBALL_ARCHIVE ]; then
    rm -rf /etc/edeploy/*
    tar xf /tmp/archive.tar --no-same-owner -C /
fi

chown -R $SUDO_USER /etc/serverspec
chown -R $SUDO_USER /opt/tempest-scripts

if [ ${SUDO_USER} != root ]; then
    mkdir -p /root/.ssh
    cp $(getent passwd $SUDO_USER | cut -d: -f6)/.ssh/authorized_keys /root/.ssh/
fi

if [ -d /etc/jenkins_jobs/jobs ]; then
    service jenkins restart
    # Wait Jenkins is up and running, it may take a long time.
    if ! timeout 1000 sh -c "while ! curl -s http://localhost:8282 | grep 'No builds in the queue.' >/dev/null 2>&1; do sleep 10; done"; then
        echo "Jenkins is not up and running after long time."
        exit 1
    fi

    # Required to upgrade from I.1.1.0 to I.1.2.0
    # Change in JJB: http://goo.gl/1dDhye
    iniset /etc/jenkins_jobs/jenkins_jobs.ini job_builder allow_duplicates True
    if [ -x /opt/jenkins-job-builder/jenkins_jobs/cmd.py ]; then
        jjb=/opt/jenkins-job-builder/jenkins_jobs/cmd.py
    else
        jjb=jenkins-jobs
    fi
    $jjb update --delete-old /etc/jenkins_jobs/jobs
fi

if [ -r /etc/edeploy/state ]; then
    # After I.1.2.0 release, drop the "always True" statement
    # Here because we had no pxemngr before.
    chown -h $USER:$USER /etc/edeploy/*.cmdb /etc/edeploy/state /var/lib/pxemngr/pxemngr.sqlite3 /var/lib/tftpboot/pxelinux.cfg/* || :
    chown -R jenkins:jenkins ~jenkins/ || :
fi

# fix permissions for ssh keys
for user in root jenkins; do
    user_ssh_dir=$(eval echo ~${user}/.ssh)
    find ${user_ssh_dir} -type f -exec chmod 0600 {} \;
done

# extract eDeploy roles for rsync
mkdir -p /var/lib/debootstrap/install
cd /var/www/install
for version in $(ls -d *-*); do
    for path in $(ls $version/*.edeploy); do
        filename=$(basename $path)
        base=$(echo $filename|sed "s/-$version.edeploy//")
        mkdir -p /var/lib/debootstrap/install/$version/$base
        tar xf $path -C /var/lib/debootstrap/install/$version/$base
    done
done

# allow to boot over http
ln -f /var/lib/tftpboot/{vmlinuz,initrd.pxe,health.pxe} /var/www/install/ || \
  cp -f /var/lib/tftpboot/{vmlinuz,initrd.pxe,health.pxe} /var/www/install/ || :

# for RHEL www hierarchy compatibility
if [ -d /var/www/html ]; then
    ln -sf /var/www/install /var/www/html/
fi

# extract-archive.sh ends here
