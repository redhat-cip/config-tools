#!/bin/bash
#
# Copyright (C) 2015 eNovance SAS <licensing@enovance.com>
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

if [ $# != 6 ]; then
    echo "Usage: $0 <tag> <deployement git url> <release> <OS version> <libvirt host> <install server hostname>"
    echo
    echo "ex: $0 I.1.3.1 file:///home/fred/testenv/virt-RH7.0.yml I.1.3.0 RH7.0 192.168.100.12 os-ci-test4"
    exit 1
fi

tag=$1
deployment=$2
stable=$3
version=$4-$stable
installserver=$5

$ORIG/download.sh $tag $deployment version=$version stable=$stable
$ORIG/virtualization/collector.py --sps-version $version --config-dir top/etc
