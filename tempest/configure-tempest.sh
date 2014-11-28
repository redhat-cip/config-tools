#!/bin/bash
#---------------------------------------------------------------
# Project         : Configure Tempest
# File            : configure-tempest.sh
# Copyright       : (C) 2013 by
# Author          : Emilien Macchi
# Created On      : Thu Jan 24 18:26:30 2013
# Purpose         : Install and run Tempest
#---------------------------------------------------------------

set -e
set -x

here=$(readlink -f $(dirname $0))
tempest_dir="/usr/share/openstack-tempest-icehouse"

cd $tempest_dir
source /etc/config-tools/openrc.sh

source $here/lib/functions
source $here/lib/keystone
source $here/lib/glance
source $here/lib/neutron
source $here/lib/swift

while getopts "akgnqcsmhz" opt ; do
    case $opt in
        a ) ALL=YES ;;
        k ) KEYSTONE=YES ;;
        g ) GLANCE=YES ;;
        n ) NOVA=YES ;;
        q ) NEUTRON=YES ;;
        c ) CINDER=YES ;;
        s ) SWIFT=YES ;;
        m ) CEILOMETER=YES ;;
        h ) HEAT=YES ;;
        z ) HORIZON=YES ;;
        * ) echo "Bad parameter"
            exit 1 ;;
    esac
done

# Basic Configuration of Tempest
cp $tempest_dir/etc/tempest.conf.sample $tempest_dir/etc/tempest.conf
mkdir -p /var/lib/tempest/state
chmod 755 /var/lib/tempest/state

iniset DEFAULT lock_path "/var/lib/tempest/state"
iniset auth allow_tenant_isolation true
iniset identity uri "$OS_AUTH_URL"
iniset identity uri_v3 "$OS_AUTH_V3_URL"
iniset identity admin_tenant_name "$OS_TENANT_NAME"
iniset identity admin_username "$OS_USERNAME"
iniset identity admin_password "$OS_PASSWORD"
iniset identity tenant_name "demo"
iniset identity username "demo"
iniset identity password "secret"
iniset identity alt_tenant_name "alt_demo"
iniset identity alt_username "alt_demo"
iniset identity alt_password "secret"
[[ ! -z "$OS_REGION_NAME" ]] && iniset identity region "$OS_REGION_NAME"
iniset client cli_dir "/usr/bin/" # havana
iniset cli cli_dir "/usr/bin/" # grizzly
iniset service_available horizon false
iniset service_available cinder false
iniset service_available ceilometer false
iniset service_available neutron false
iniset service_available glance false
iniset service_available swift false
iniset service_available nova false
iniset service_available heat false
iniset service_available ironic false
iniset service_available sahara false
iniset service_available trove false
iniset service_available zaqar false

if [[ $ALL = YES ]]; then
    KEYSTONE=YES
    GLANCE=YES
    NEUTRON=YES
    NOVA=YES
    CINDER=YES
    SWIFT=YES
    CEILOMETER=YES
    HEAT=YES
    HORIZON=YES
fi

if [[ $KEYSTONE == YES ]]; then
    setup_keystone_user_role
fi

if [[ $GLANCE == YES ]]; then
    iniset service_available glance True
    setup_glance
fi

if [[ $NEUTRON == YES ]]; then
    iniset service_available neutron True
    setup_neutron
fi

if [[ $NOVA == YES ]]; then
    iniset service_available nova True
    iniset compute change_password_available false
    iniset whitebox whitebox_enabled false
    iniset compute-admin username "$OS_USERNAME"
    iniset compute-admin tenant_name "$OS_TENANT_NAME"
    iniset compute-admin password "$OS_PASSWORD"

    # Enable Nova API v3
    if keystone service-list | grep "computev3"; then
      iniset compute-feature-enabled api_v3 True
    fi
fi

if [[ $CEILOMETER == YES ]]; then
    iniset service_available ceilometer True
fi

if [[ $HEAT == YES ]]; then
    iniset service_available heat True
    iniset orchestration endpoint_type internalURL
fi

if [[ $HORIZON == YES ]]; then
    iniset service_available horizon True
    iniset dashboard dashboard_url "$HORIZON_URL"
    iniset dashboard login_url "$HORIZON_LOGIN_URL"
fi

if [[ $CINDER == YES ]]; then
	echo -n ""
    iniset service_available cinder True
    # nothing to do here
fi

if [ "$SWIFT" == "YES" ]; then
    iniset service_available swift True
    iniset object-storage operator_role SwiftOperator
fi
if [ "$SWIFT" == "YES" -a "$NOVA" == "YES" ]; then
	setup_ec2_s3_creds
fi

if [ "$SWIFT" == "YES" -a "$GLANCE" == "YES" ]; then
	 create_s3_materials
fi
