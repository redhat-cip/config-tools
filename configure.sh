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
      -oGSSAPIAuthentication=no \
      -oConnectTimeout=3 -oUserKnownHostsFile=/dev/null"

if [ -r $JENKINS_HOME/.ssh/id_rsa ]; then
    SSHOPTS="$SSHOPTS -i $JENKINS_HOME/.ssh/id_rsa"
fi

PUPPETOPTS="--verbose --no-usecacheonfailure --no-splay --show_diff"

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

erlang_cookie=$(${ORIG}/extract.py config.erlang_cookie $CFG)
if [ -z "$erlang_cookie" ]; then
  echo "erlang_cookie is a new required parameter in your environment."
  echo "Please read carefully http://spinalstack.enovance.com/en/latest/deploy/components/rabbitmq.html#upgrade-from-i-1-3-0-to-j-1-0-0"
fi

for f in /etc/serverspec/arch.yml.tmpl /etc/puppet/data/common.yaml.tmpl /etc/puppet/data/fqdn.yaml.tmpl /etc/puppet/data/type.yaml.tmpl $CFG $CDIR/config.tmpl; do
    if [ ! -r $f ]; then
        echo "$f doesn't exist" 1>&2
        exit 1
    fi
done

start=$(date '+%s')

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

#
# Set server type in each machine so hiera can
# provide them with the correct values during
# puppet run
#
n=0
for h in $HOSTS; do
    if [ $h = $(hostname -s) ]; then
        echo "Configure Puppet environment on ${h} node:"
        mkdir -p /etc/facter/facts.d
        cat > /etc/puppet/manifest.pp<<EOF
Exec {
  path => ['/bin', '/sbin', '/usr/bin', '/usr/sbin'],
}
hiera_include('classes')
EOF
         cat > /etc/facter/facts.d/environment.txt <<EOF
type=${PROF_BY_HOST[$h]}
EOF
    else
        echo "Configure Puppet environment on ${h} node:"
        (
        tee /tmp/manifest.pp <<EOF
Exec {
  path => ['/bin', '/sbin', '/usr/bin', '/usr/sbin'],
}
hiera_include('classes')
EOF
        tee /tmp/environment.txt.$h <<EOF
type=${PROF_BY_HOST[$h]}
EOF
        scp -r $SSHOPTS /tmp/environment.txt.$h /tmp/manifest.pp /etc/puppet/modules $USER@$h.$DOMAIN:/tmp
        ssh $SSHOPTS $USER@$h.$DOMAIN "
set -e
sudo rm -rf /etc/puppet/modules
sudo cp -r /tmp/modules /etc/puppet/modules
sudo mkdir -p /etc/facter/facts.d
sudo cp /tmp/environment.txt.$h /etc/facter/facts.d/environment.txt
sudo cp /tmp/manifest.pp /etc/puppet/manifest.pp
"
        ) > $LOGDIR/$h.init.log 2>&1 &
        n=$(($n + 1))
    fi
done

while [ $n -ne 0 ]; do
    wait
    n=$(($n - 1))
done

elapsed=$(($(date '+%s') - $start))

echo "step init took $(($elapsed / 60)) mn"

#######################################################################
# Step 0: provision the nodes for Puppet configuration & certificates #
#######################################################################

if [ $STEP -eq 0 ]; then
    start=$(date '+%s')
    configure_hostname
    generate 0 /etc/puppet/data/common.yaml
    for template in $(cat /etc/config-tools/templates); do
        generate 0 $template
    done
    for p in $PROFILES; do
        generate 0 /etc/puppet/data/type.yaml profile=$p
        mkdir -p /etc/puppet/data/$p
        mv /etc/puppet/data/type.yaml /etc/puppet/data/$p/common.yaml
    done
    for h in $HOSTS; do
        generate 0 /etc/puppet/data/fqdn.yaml host=$h
        mkdir -p /etc/puppet/data/${PROF_BY_HOST[$h]}
        chmod 751 /etc/puppet/data/${PROF_BY_HOST[$h]}
        # hack to fix %{hiera} without ""
        sed -e 's/: \(%{hiera.*\)/: "\1"/' < /etc/puppet/data/fqdn.yaml > /etc/puppet/data/${PROF_BY_HOST[$h]}/$h.$DOMAIN.yaml
        chmod 644 /etc/puppet/data/${PROF_BY_HOST[$h]}/$h.$DOMAIN.yaml
        rm /etc/puppet/data/fqdn.yaml
    done
    if ! test -f /etc/puppet/ssl/puppetdb.pem ; then
        echo "/etc/puppet/ssl/puppetdb.pem file is missing so PuppetDB cannot be configured."
        echo "More documentation about it: http://spinalstack.enovance.com/en/latest/deploy/components/puppetdb.html"
        exit 1
    fi
    puppet apply /etc/puppet/modules/cloud/scripts/bootstrap.pp | tee  $LOGDIR/puppet-master.step0.log
    puppet apply -e 'include ::cloud::install::puppetdb::server' | tee  $LOGDIR/puppet-master.step0.log
    puppet apply -e 'include ::cloud::install::puppetdb::config' | tee  $LOGDIR/puppet-master.step0.log
    # Last puppet apply restart PuppetDB service, which takes ~ 15 seconds to start.
    # let's wait 30 seconds to be sure PuppetDB is started and we can run Puppet on all the nodes
    sleep 30
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        STEP=1
        echo $STEP > $CDIR/step
    else
        exit 1
    fi

    n=0
    for h in $HOSTS; do
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R ${h} || :
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R ${h}.$DOMAIN || :
        if [ $h != $(hostname -s) ]; then
            n=$(($n + 1))
            echo "Provisioning Puppet agent on ${h} node"
            (
             ssh $SSHOPTS $USER@$h.$DOMAIN mkdir -p /tmp/data/${PROF_BY_HOST[$h]}
             scp $SSHOPTS /etc/puppet/data/common.yaml $USER@$h.$DOMAIN:/tmp/data/
             scp $SSHOPTS /etc/puppet/data/${PROF_BY_HOST[$h]}/common.yaml $USER@$h.$DOMAIN:/tmp/data/${PROF_BY_HOST[$h]}/
             scp $SSHOPTS /etc/puppet/data/${PROF_BY_HOST[$h]}/$h.$DOMAIN.yaml $USER@$h.$DOMAIN:/tmp/data/${PROF_BY_HOST[$h]}/
             scp $SSHOPTS /etc/puppet/hiera.yaml /etc/hosts /etc/resolv.conf $USER@$h.$DOMAIN:/tmp/
             ssh $SSHOPTS $USER@$h.$DOMAIN "
set -e
sudo rm -rf /etc/puppet/data
sudo cp -r /tmp/data /etc/puppet/data
sudo cp /tmp/hiera.yaml /etc/puppet/hiera.yaml
sudo cp /tmp/resolv.conf /tmp/hosts /etc
sudo -i puppet apply /etc/puppet/manifest.pp"
            ) > $LOGDIR/$h.step0.log 2>&1 &
        fi
    done

    while [ $n -ne 0 ]; do
        wait
        n=$(($n - 1))
    done

    elapsed=$(($(date '+%s') - $start))

    echo "step 0 took $(($elapsed / 60)) mn"
fi

######################################################################
# Step 1+: regular puppet runs (without certificate creation)
######################################################################

for (( step=$STEP; step<=$LAST; step++)); do # Yep, this is a bashism
    start=$(date '+%s')
    echo $step > $CDIR/step
    for template in $(cat /etc/config-tools/templates); do
        generate $step $template
    done
    for p in $PROFILES; do
        generate $step /etc/puppet/data/type.yaml profile=$p
        mkdir -p /etc/puppet/data/$p
        mv /etc/puppet/data/type.yaml /etc/puppet/data/$p/common.yaml
    done
    for h in $HOSTS; do
        generate $step /etc/puppet/data/fqdn.yaml host=$h
        mkdir -p /etc/puppet/data/${PROF_BY_HOST[$h]}
        chmod 751 /etc/puppet/data/${PROF_BY_HOST[$h]}
        # hack to fix %{hiera} without ""
        sed -e 's/: \(%{hiera.*\)/: "\1"/' < /etc/puppet/data/fqdn.yaml > /etc/puppet/data/${PROF_BY_HOST[$h]}/$h.$DOMAIN.yaml
        chmod 644 /etc/puppet/data/${PROF_BY_HOST[$h]}/$h.$DOMAIN.yaml
        rm /etc/puppet/data/fqdn.yaml
        if [ $h != $(hostname -s) ]; then
          ssh $SSHOPTS $USER@$h.$DOMAIN mkdir -p /tmp/data/${PROF_BY_HOST[$h]}
          scp $SSHOPTS /etc/puppet/data/common.yaml $USER@$h.$DOMAIN:/tmp/data/
          scp $SSHOPTS /etc/puppet/data/${PROF_BY_HOST[$h]}/common.yaml $USER@$h.$DOMAIN:/tmp/data/${PROF_BY_HOST[$h]}/
          scp $SSHOPTS /etc/puppet/data/${PROF_BY_HOST[$h]}/$h.$DOMAIN.yaml $USER@$h.$DOMAIN:/tmp/data/${PROF_BY_HOST[$h]}/
          ssh $SSHOPTS $USER@$h.$DOMAIN sudo rm -rf /etc/puppet/data
          ssh $SSHOPTS $USER@$h.$DOMAIN sudo cp -r /tmp/data /etc/puppet/data
        fi
    done

    for (( loop=1; loop<=$TRY; loop++)); do # Yep, this is a bashism
        n=0
        for h in $HOSTS; do
            n=$(($n + 1))
            echo "Run Puppet on $h node (step ${step}, try $loop):"
            if run_parallel $step; then
                if [ $h = $(hostname -s) ]; then
                    puppet apply /etc/puppet/manifest.pp > $LOGDIR/$h.step${step}.try${loop}.log 2>&1 &
                else
                    ssh $SSHOPTS $USER@$h sudo -i puppet apply /etc/puppet/manifest.pp > $LOGDIR/$h.step${step}.try${loop}.log 2>&1 &
                fi
            else
                if [ $h = $(hostname -s) ]; then
                    puppet apply /etc/puppet/manifest.pp 2>&1 | tee $LOGDIR/$h.step${step}.try${loop}.log
                else
                    ssh $SSHOPTS $USER@$h sudo -i puppet apply /etc/puppet/manifest.pp 2>&1 | tee $LOGDIR/$h.step${step}.try${loop}.log
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

last_step=$(cat $CDIR/step)
if [ $last_step -gt 1 ]; then
    # At this stage, verify-servers.sh (serverspec) has already been run successfuly
    # on all the nodes for the steps. Since we are using 'set -e', we would not be here if
    # an error occured on the tests, so there is no reason to fail here.
    # With XML output, it happens serverspecs timeout to connect on the nodes,
    # so as a temporary background until we upgrade to latest version, do not fail on
    # this command to avoid deployment issues.
    verify-servers.sh -x $LOGDIR || true
fi

# ensure logs are readable by Jenkins
chmod -R 644 $LOGDIR/*

exit $RC

# configure.sh ends here
