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

ORIG=$(cd $(dirname $0); pwd)

if [ $(id -u) != 0 ]; then
    exec sudo -i WORKSPACE=$WORKSPACE JOB_NAME=$JOB_NAME BUILD_ID=$BUILD_ID JENKINS_HOME=$JENKINS_HOME "$ORIG/$(basename $0)" "$@"
fi

if [ $# -gt 2 ]; then
    echo "Usage: $0 [<last step>]" 1>&2
    exit 1
fi

set -e
set -x

LAST=$1

CDIR=/etc/config-tools
CFG=$CDIR/global.yml

LOGDIR=$WORKSPACE

if [ ! -d "$LOGDIR" ]; then
    LOGDIR=$(mktemp -d)
fi

TRY=5
PARALLELSTEPS='none'

SSHOPTS="-oBatchMode=yes -oCheckHostIP=no -oHashKnownHosts=no \
      -oStrictHostKeyChecking=no -oPreferredAuthentications=publickey \
      -oChallengeResponseAuthentication=no -oKbdInteractiveDevices=no \
      -oConnectTimeout=3 -oUserKnownHostsFile=/dev/null"

if [ -r $JENKINS_HOME/.ssh/id_rsa ]; then
    SSHOPTS="$SSHOPTS -i $JENKINS_HOME/.ssh/id_rsa"
fi

PUPPETOPTS="--onetime --verbose --no-daemonize --no-usecacheonfailure \
    --no-splay --show_diff"

PUPPETOPTS2="--ignorecache --waitforcert 240"

PATH=/usr/share/config-tools:$PATH
export PATH

generate() {
    step=$1
    file=$2
    shift 2
    args="$@"

    generate.py $step $CFG ${file}.tmpl $args|grep -v '^$' > $file
    chmod 0644 $file
}

for f in /etc/serverspec/arch.yml.tmpl /etc/puppet/data/common.yaml.tmpl /etc/puppet/data/fqdn.yaml.tmpl /etc/puppet/data/type.yaml.tmpl $CFG $CDIR/config.tmpl; do
    if [ ! -r $f ]; then
        echo "$f doesn't exist" 1>&2
        exit 1
    fi
done

generate 0 $CDIR/config

. $CDIR/config

# use extglob form to have a variable in a case clause
PARALLELSTEPS="@(${PARALLELSTEPS})"

shopt -s extglob

if [ -r $CDIR/step ]; then
    STEP=$(cat $CDIR/step)
else
    STEP=0
fi

if [ -z "$LAST" ]; then
    LAST=$(egrep '^\s*[0-9]+:' $CFG|cut -d ':' -f 1|sort -rn|head -1)
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
            echo "$ipaddress    $SHORT" >> /etc/hosts
        fi

        FQDN=$SHORT
    fi
}

detect_os() {
    OS=$(lsb_release -i -s)
    case $OS in
        Debian|Ubuntu)
            WEB_SERVER="apache2"
            PUPPET_VHOST="/etc/apache2/sites-available/puppetmaster"
            ;;
        CentOS|RedHatEnterpriseServer)
            WEB_SERVER="httpd"
            PUPPET_VHOST="/etc/httpd/conf.d/puppetmaster.conf"
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
configtimeout=10m
pluginsync=true

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

    cat > /etc/puppet/hiera.yaml <<EOF
---
:backends:
  - yaml
:yaml:
  :datadir: /etc/puppet/data
:hierarchy:
  - "%{::type}/%{::fqdn}"
  - "%{::type}/common"
  - common
EOF
chown puppet:puppet /etc/puppet/hiera.yaml

    cat > /etc/puppet/routes.yaml <<EOF
---
master:
  facts:
    terminus: puppetdb
    cache: yaml
EOF
chown puppet:puppet /etc/puppet/routes.yaml

    cat > /etc/puppetdb/conf.d/jetty.ini <<EOF
[jetty]
host = ${FQDN}
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
chown puppet:puppet /etc/puppet/puppetdb.conf

    if [ -f /etc/httpd/conf.d/puppetmaster.conf.disabled ]; then
        mv /etc/httpd/conf.d/puppetmaster.conf.disabled /etc/httpd/conf.d/puppetmaster.conf
    fi

    sed -i -e "s!SSLCertificateFile.*!SSLCertificateFile /var/lib/puppet/ssl/certs/${FQDN}.pem!" -e "s!SSLCertificateKeyFile.*!SSLCertificateKeyFile /var/lib/puppet/ssl/private_keys/${FQDN}.pem!" $PUPPET_VHOST

    rm -rf /var/lib/puppet/ssl && puppet cert generate ${FQDN}

    mkdir -p /etc/puppetdb/ssl
    cp /var/lib/puppet/ssl/private_keys/$(hostname -f).pem /etc/puppetdb/ssl/key.pem && chown puppetdb:puppetdb /etc/puppetdb/ssl/key.pem
    cp /var/lib/puppet/ssl/certs/$(hostname -f).pem /etc/puppetdb/ssl/cert.pem && chown puppetdb:puppetdb /etc/puppetdb/ssl/cert.pem
    cp /var/lib/puppet/ssl/certs/ca.pem /etc/puppetdb/ssl/ca.pem && chown puppetdb:puppetdb /etc/puppetdb/ssl/ca.pem

    # Bug Puppet: https://tickets.puppetlabs.com/browse/PUP-1386
    if [ $OS == "Debian" ] || [ $OS == "Ubuntu" ]; then
        echo '. /etc/default/locale' | tee --append /etc/apache2/envvars
        # Bug Debian: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=736849
        echo 'umask 022' | tee --append /etc/apache2/envvars
    else
        sed -i "s/^\(LANG\s*=\s*\).*\$/\1en_US.UTF-8/" /etc/sysconfig/httpd
    fi

    tee -a /etc/puppet/autosign.conf <<< '*'
    chown puppet:puppet /etc/puppet/autosign.conf

    puppet resource service puppetmaster ensure=stopped enable=false
    service puppetdb restart
    puppet resource service puppetdb ensure=running enable=true

    if [ "$WEB_SERVER" = "apache2" ]; then
        a2ensite puppetmaster

        # if puppetboard is present, enable it
        if [ -r /var/www/puppetboard/wsgi.py ]; then
            a2ensite puppetboard
        fi
    fi

    service $WEB_SERVER restart
    puppet resource service $WEB_SERVER ensure=running enable=true

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
    # check puppet result
    if [ $RC = 1 ]; then
        exit 1
    fi
    # Some issues have been found when running puppet the first time.
    # It seems that restarting web server solves the issue.
    service $WEB_SERVER restart
}

    for h in $HOSTS; do
        if [ $h = $(hostname -s) ]; then
            (echo "Configure Puppet environment on ${h} node:"
             mkdir -p /etc/facter/facts.d
             cat > /etc/facter/facts.d/environment.txt <<EOF
type=${PROF_BY_HOST[$h]}
EOF
             n=$(($n + 1)))
        else
            (echo "Configure Puppet environment on ${h} node:"
             tee /tmp/environment.txt.$h <<EOF
type=${PROF_BY_HOST[$h]}
EOF
             scp $SSHOPTS /tmp/environment.txt.$h $USER@$h.$DOMAIN:/tmp/environment.txt
             ssh $SSHOPTS $USER@$h.$DOMAIN sudo mkdir -p /etc/facter/facts.d
             ssh $SSHOPTS $USER@$h.$DOMAIN sudo cp /tmp/environment.txt /etc/facter/facts.d
             n=$(($n + 1)))
        fi
    done

######################################################################
# Step 0: provision the puppet master and the certificates on the nodes
######################################################################

detect_os

if [ $STEP -eq 0 ]; then
    configure_hostname
    generate 0 /etc/puppet/data/common.yaml
    configure_puppet | tee $LOGDIR/puppet-master.step0.log
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        STEP=1
        echo $STEP > $CDIR/step
    else
        exit 1
    fi

    # clean known_hosts
    for h in $HOSTS; do
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R ${h} || :
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R ${h}.$DOMAIN || :
    done

    n=0
    for h in $HOSTS; do
        if [ $h = $(hostname -s) ]; then
            (echo "Provisioning Puppet agent on ${h} node:"
             cp /tmp/hosts /etc
             augtool << EOT
set /files/etc/puppet/puppet.conf/agent/pluginsync true
set /files/etc/puppet/puppet.conf/agent/certname $h
set /files/etc/puppet/puppet.conf/agent/server $MASTER
rm /files/etc/puppet/puppet.conf/main/templatedir
save
EOT

             if [[ ! $h.$DOMAIN == $FQDN ]]; then
               rm -rf /var/lib/puppet/ssl/* || :
             fi

             service ntp stop || :
             ntpdate 0.europe.pool.ntp.org || :
             service ntp start || :

             puppet agent $PUPPETOPTS $PUPPETOPTS2) > $LOGDIR/$h.step0.log 2>&1 &
            n=$(($n + 1))
        else
            (echo "Provisioning Puppet agent on ${h} node:"
             scp $SSHOPTS /etc/hosts /etc/resolv.conf $USER@$h.$DOMAIN:/tmp/
             ssh $SSHOPTS $USER@$h.$DOMAIN sudo mv /tmp/resolv.conf /tmp/hosts /etc
             ssh $SSHOPTS $USER@$h.$DOMAIN sudo augtool << EOT
set /files/etc/puppet/puppet.conf/agent/pluginsync true
set /files/etc/puppet/puppet.conf/agent/certname $h
set /files/etc/puppet/puppet.conf/agent/server $MASTER
rm /files/etc/puppet/puppet.conf/main/templatedir
save
EOT

             if [[ ! $h.$DOMAIN == $FQDN ]]; then
               ssh $SSHOPTS $USER@$h.$DOMAIN sudo rm -rf /var/lib/puppet/ssl/* || :
             fi

             ssh $SSHOPTS $USER@$h.$DOMAIN sudo service ntp stop || :
             ssh $SSHOPTS $USER@$h.$DOMAIN sudo ntpdate 0.europe.pool.ntp.org || :
             ssh $SSHOPTS $USER@$h.$DOMAIN sudo service ntp start || :

             ssh $SSHOPTS $USER@$h.$DOMAIN sudo puppet agent $PUPPETOPTS $PUPPETOPTS2) > $LOGDIR/$h.step0.log 2>&1 &
            n=$(($n + 1))
        fi
    done

    while [ $n -ne 0 ]; do
        wait
        if [ $? -ne 0 ]; then
            RC=1
        fi
        n=$(($n - 1))
    done
    # check remote puppet result
    if [ $RC = 1 ]; then
        exit 1
    fi
fi

######################################################################
# Step 1+: regular puppet runs (without certificate creation)
######################################################################

# useful after an upgrade
service $WEB_SERVER restart

for (( step=$STEP; step<=$LAST; step++)); do # Yep, this is a bashism
    start=$(date '+%s')
    echo $step > $CDIR/step
    generate $step /etc/puppet/data/common.yaml
    for h in $HOSTS; do
        generate $step /etc/puppet/data/fqdn.yaml host=$h
        mkdir -p /etc/puppet/data/${PROF_BY_HOST[$h]}
        # hack to fix %{hiera} without ""
        sed -e 's/: \(%{hiera.*\)/: "\1"/' < /etc/puppet/data/fqdn.yaml > /etc/puppet/data/${PROF_BY_HOST[$h]}/$h.$DOMAIN.yaml
        rm /etc/puppet/data/fqdn.yaml
    done
    for p in $PROFILES; do
        generate $step /etc/puppet/data/type.yaml profile=$p
        mkdir -p /etc/puppet/data/$p
        mv /etc/puppet/data/type.yaml /etc/puppet/data/$p/common.yaml
    done

    for (( loop=1; loop<=$TRY; loop++)); do # Yep, this is a bashism
        n=0
        for h in $HOSTS; do
            n=$(($n + 1))
            echo "Run Puppet on $h node (step ${step}, try $loop):"
            if run_parallel $step; then
                if [ $h = $(hostname -s) ]; then
                    puppet agent $PUPPETOPTS > $LOGDIR/$h.step${step}.try${loop}.log 2>&1 &
                else
                    ssh $SSHOPTS $USER@$h sudo -i puppet agent $PUPPETOPTS > $LOGDIR/$h.step${step}.try${loop}.log 2>&1 &
                fi
            else
                if [ $h = $(hostname -s) ]; then
                    puppet agent $PUPPETOPTS 2>&1 | tee $LOGDIR/$h.step${step}.try${loop}.log
                else
                    ssh $SSHOPTS $USER@$h sudo -i puppet agent $PUPPETOPTS 2>&1 | tee $LOGDIR/$h.step${step}.try${loop}.log
                fi
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

verify-servers.sh -x $LOGDIR

exit $RC

# configure.sh ends here
