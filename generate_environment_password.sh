#!/bin/bash
#
# Copyright (C) 2014 eNovance SAS <licensing@enovance.com>
#
# Author: Nicolas Hicher <nicolas.hicher@enovance.com>
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


yaml_file=$1

usage() {
  cat << EOF
  This script will modify password and ssh key in a env yaml file
  usage: $0 filename
EOF
  exit
}

if [ -z $yaml_file ]; then
  usage
fi

strings="swift_hash_suffix|password|secret_key|heat_auth_encryption_key|ks_admin_token|neutron_metadata_proxy_shared_secret"

for value in $(grep -E "$strings" $yaml_file | grep -Ev "\<root_password\>" |  awk -F':' '{print $1}'); do
  password=$(pwgen -s -c -n 30 1)
  sed -i "s/\([[:space:]]*$value\).*/\1: $password/" $yaml_file 
done

# root password
password=$(pwgen 30 1)
encrypted_password=$(openssl passwd -1 $password)
sed -i "/\<root_password\>/i # root password $password" $yaml_file
sed -i "s|\([[:space:]]*\<root_password\>\).*|\1: $encrypted_password|" $yaml_file 

# haproxy_auth
password=$(pwgen 30 1)
sed -i "s|\([[:space:]]*\<haproxy_auth\>\).*|\1: root:$password|" $yaml_file 

# gen ssh
dir=$(mktemp -d)

ssh-keygen -q -N '' -C 'nova@openstack' -f $dir/nova
sed -i '/-----BEGIN RSA PRIVATE KEY-----/,/-----END RSA PRIVATE KEY-----/d' $yaml_file
sed -i 's/^/    /' $dir/nova
sed -i "/nova_ssh_private_key/r $dir/nova" $yaml_file

nova_ssh_public_key=$(cat $dir/nova.pub)
sed -i "s|\([[:space:]]*nova_ssh_public_key\).*|\1: $nova_ssh_public_key|" $yaml_file 

rm $dir/nova*
rmdir $dir

