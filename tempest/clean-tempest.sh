#!/bin/bash
#
# Copyright (C) 2014 eNovance SAS <licensing@enovance.com>
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
#
# Cleanup all OpenStack resources after Tempest run.
# Note: Do not remove Keystone users/roles/tenants
#

set -e
set -x

source /etc/config-tools/openrc.sh

# Cleanup all resources except keystone users/tenants/roles
for tenant_name in $(keystone tenant-list | egrep -o -i "[_a-z0-9\-]*((tenant[_a-z0-9\-]*)|(-[0-9]{8,}))"); do ospurge --verbose --cleanup-project $tenant_name; done

case "$?" in
  "0")
    echo "Cleanup-process exited sucessfully";;
  "1")
    echo "Unknown error";;
  "2")
    echo "Project does not exist";;
  "3")
    echo "Authentication failed (e.g. Bad username or password)";;
  "4")
    echo "Resource deletion failed";;
  "5")
    echo "Connection error while deleting a resource (e.g. Service not available)";;
  "6")
    echo "Connection to endpoint failed (e.g. authentication url)";;
esac

# clean-tempest.sh ends here
