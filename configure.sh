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

if [ $(id -u) != 0 ]; then
    exec sudo -i "$0" "$@"
fi

if [ $# -gt 2 ]; then
    echo "Usage: $0 [<last step>]" 1>&2
    exit 1
fi

LAST=$1

for f in /etc/serverspec/arch.yml.tmpl /etc/puppet/manifests/site.pp.tmpl /etc/puppet/config.yaml /etc/puppet/config.tmpl; do
    if [ ! -r $f ]; then
	echo "$f doesn't exist" 1>&2
	exit 1
    fi
done

TRY=3
PARALLELSTEPS='none'

ORIG=$(cd $(dirname $0); pwd)

SSHOPTS="-oBatchMode=yes -oCheckHostIP=no -oHashKnownHosts=no \
      -oStrictHostKeyChecking=no -oPreferredAuthentications=publickey \
      -oChallengeResponseAuthentication=no -oKbdInteractiveDevices=no \
      -oConnectTimeout=3 -oUserKnownHostsFile=/dev/null"

PUPPETOPTS="--onetime --verbose --no-daemonize --no-usecacheonfailure \
    --no-splay --show_diff"

PUPPETOPTS2="--ignorecache --waitforcert 240"

PATH=/usr/share/config-tools:$PATH
export PATH

generate.py 0 /etc/puppet/config.yaml /etc/puppet/config.tmpl|grep -v '^$' > /etc/puppet/config

. /etc/puppet/config

# exported for verify-servers.sh
export PREFIX
export DOMAIN

# use extglob form to have a variable in a case clause
PARALLELSTEPS="@(${PARALLELSTEPS})"

shopt -s extglob

if [ -r /etc/puppet/step ]; then
    STEP=$(cat /etc/puppet/step)
else
    STEP=0
fi

if [ -z "$LAST" ]; then
    LAST=$(fgrep 'step:' /etc/puppet/config.yaml|cut -d ':' -f 2|sort -rn|head -1)
fi

if [ -z "$LAST" ]; then
    LAST=10
fi

RC=0

run_parallel() {
    case $1 in
	$PARALLELSTEPS)
	    return 0
	    ;;
	*)
	    return 1
	    ;;
    esac
}

configure_hostname() {
    if hostname -f; then
	FQDN=$(hostname -f)
    else
	HOSTNAME=$(hostname)

	case $HOSTNAME in
	    *.*)
		SHORT=$(sed 's/\..*//' <<< $HOSTNAME)
		;;
	    *)
		SHORT=$HOSTNAME
		HOSTNAME=$HOSTNAME.local
		;;
	esac

	eval "$(facter |fgrep 'ipaddress =>' | sed 's/ => /=/')"

	if ! grep -q $ipaddress /etc/hosts; then
	    echo "$ipaddress	$SHORT" >> /etc/hosts
	fi

	FQDN=$SHORT
    fi
}

detect_os() {
    OS=$(lsb_release -i -s)
    case $OS in
	Debian|Ubuntu)
	    WEB_SERVER="apache2"
	    ;;
	CentOS|RedHatEnterpriseServer)
	    WEB_SERVER="httpd"
	    ;;
	*)
	    echo "Operating System not supported."
	    exit 1
	    ;;
    esac
    RELEASE=$(lsb_release -c -s)
    DIST_RELEASE=$(lsb_release -s -r)
}

configure_puppet() {
    service puppetmaster stop
    service puppetdb stop
    service $WEB_SERVER stop

    cat > /etc/puppet/puppet.conf <<EOF
[main]
logdir=/var/log/puppet
vardir=/var/lib/puppet
ssldir=/var/lib/puppet/ssl
rundir=/var/run/puppet
factpath=\$vardir/lib/facter
templatedir=\$confdir/templates
configtimeout=10m

[master]
ssl_client_header = SSL_CLIENT_S_DN
ssl_client_verify_header = SSL_CLIENT_VERIFY
storeconfigs=true
storeconfigs_backend=puppetdb
reports=store,puppetdb
pluginsync=true

[agent]
pluginsync=true
certname=${FQDN}
server=${FQDN}
EOF

    cat > /etc/puppet/routes.yaml <<EOF
---
master:
  facts:
    terminus: puppetdb
    cache: yaml
EOF

    cat > /etc/puppetdb/conf.d/jetty.ini <<EOF
[jetty]
port = 8080

ssl-host = ${FQDN}
ssl-port = 8081
ssl-key = /etc/puppetdb/ssl/key.pem
ssl-cert = /etc/puppetdb/ssl/cert.pem
ssl-ca-cert = /etc/puppetdb/ssl/ca.pem
EOF

    cat > /etc/puppet/puppetdb.conf <<EOF
[main]
server = ${FQDN}
port = 8081
EOF

    sed -i -e "s!SSLCertificateFile.*!SSLCertificateFile /var/lib/puppet/ssl/certs/${FQDN}.pem!" -e "s!SSLCertificateKeyFile.*!SSLCertificateKeyFile /var/lib/puppet/ssl/private_keys/${FQDN}.pem!" /etc/apache2/sites-available/puppetmaster

    rm -rf /var/lib/puppet/ssl && puppet cert generate ${FQDN}

    cp /var/lib/puppet/ssl/private_keys/$(hostname -f).pem /etc/puppetdb/ssl/key.pem && chown puppetdb:puppetdb /etc/puppetdb/ssl/key.pem
    cp /var/lib/puppet/ssl/certs/$(hostname -f).pem /etc/puppetdb/ssl/cert.pem && chown puppetdb:puppetdb /etc/puppetdb/ssl/cert.pem
    cp /var/lib/puppet/ssl/certs/ca.pem /etc/puppetdb/ssl/ca.pem && chown puppetdb:puppetdb /etc/puppetdb/ssl/ca.pem

    if [ $OS == "Debian" ] || [ $OS == "Ubuntu" ]; then
	echo '. /etc/default/locale' | tee --append /etc/apache2/envvars
    fi

    tee -a /etc/puppet/autosign.conf <<< '*'

    puppet resource service puppetmaster ensure=stopped enable=false
    service puppetdb start
    puppet resource service puppetdb ensure=running enable=true
    a2ensite puppetmaster
    service $WEB_SERVER start

    # puppetdb is slow to start so try multiple times to reach it
    NUM=10
    RC=1
    while [ $NUM -gt 0 ]; do
	if puppet agent $PUPPETOPTS  $PUPPETOPTS2; then
	    RC=0
	    echo "Puppet Server UP and RUNNING!"
	    break
	fi
	NUM=$(($NUM - 1))
	sleep 10
    done
    # Some issues have been found when running puppet the first time.
    # It seems that restarting web server solves the issue.
    service $WEB_SERVER restart
}

######################################################################
# Step 0: provision the puppet master and the certificates on the nodes
######################################################################
if [ $STEP -eq 0 ]; then
    generate.py 0 /etc/puppet/config.yaml /etc/puppet/manifests/site.pp.tmpl|grep -v '^$' > /etc/puppet/manifests/site.pp
    configure_hostname
    detect_os
    configure_puppet | tee /tmp/puppet-master.step0.log
    if [ $RC -eq 0 ]; then
	STEP=1
	echo $STEP > /etc/puppet/step
    else
	exit $RC
    fi

    # clean known_hosts
    for h in $HOSTS; do
	ssh-keygen -f "$HOME/.ssh/known_hosts" -R ${h} || :
	ssh-keygen -f "$HOME/.ssh/known_hosts" -R ${h}.$DOMAIN || :
    done

    n=0
    for h in $HOSTS; do
	(echo "Provisioning Puppet agent on ${h} node:"
	scp $SSHOPTS /etc/hosts /etc/resolv.conf $USER@$h:/tmp/
	ssh $SSHOPTS $USER@$h sudo cp /tmp/hosts /tmp/resolv.conf /etc/
	ssh $SSHOPTS $USER@$h sudo augtool << EOT
set /files/etc/puppet/puppet.conf/agent/pluginsync true
set /files/etc/puppet/puppet.conf/agent/certname $h
set /files/etc/puppet/puppet.conf/agent/server $MASTER
save
EOT
        ssh $SSHOPTS $USER@$h sudo rm -rf /var/lib/puppet/ssl/* || :

	ssh $SSHOPTS $USER@$h sudo /etc/init.d/ntp stop || :
	ssh $SSHOPTS $USER@$h sudo ntpdate 0.europe.pool.ntp.org || :
	ssh $SSHOPTS $USER@$h sudo /etc/init.d/ntp start || :

    ssh $SSHOPTS $USER@$h sudo puppet agent $PUPPETOPTS $PUPPETOPTS2) > /tmp/$h.step0.log 2>&1 &
	n=$(($n + 1))
    done

    while [ $n -ne 0 ]; do
	wait
	n=$(($n - 1))
    done
fi

######################################################################
# Step 1+: regular puppet runs (without certificate creation)
######################################################################
for (( step=$STEP; step<=$LAST; step++)); do # Yep, this is a bashism
    start=$(date '+%s')
    echo $step > /etc/puppet/step
    generate.py $step /etc/puppet/config.yaml /etc/puppet/manifests/site.pp.tmpl|grep -v '^$' > /etc/puppet/manifests/site.pp

    for (( loop=1; loop<=$TRY; loop++)); do # Yep, this is a bashism
	n=0
	for h in $HOSTS; do
	    n=$(($n + 1))
	    echo "Run Puppet on $h node (step ${step}, try $loop):"
	    if run_parallel $step; then
		ssh $SSHOPTS $USER@$h sudo -i puppet agent $PUPPETOPTS > /tmp/$h.step${step}.try${loop}.log 2>&1 &
	    else
		ssh $SSHOPTS $USER@$h sudo -i puppet agent $PUPPETOPTS 2>&1 | tee /tmp/$h.step${step}.try${loop}.log
	    fi
	done

	if run_parallel $step; then
	    while [ $n -ne 0 ]; do
		wait
		n=$(($n - 1))
	    done
	fi

	if verify-servers.sh $step; then
	    RC=0
	    break
	else
	    RC=1
	    echo "Still errors, launching puppet again (step $step, try $loop)..."
	fi
    done

    elapsed=$(($(date '+%s') - $start))

    echo "step $step took $(($elapsed / 60)) mn"

    if [ $RC -eq 1 ]; then
	break
    fi
done

verify-servers.sh -x

exit $RC

# configure.sh ends here
