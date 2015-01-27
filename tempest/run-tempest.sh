#!/bin/bash
#---------------------------------------------------------------
# Project         : Run Tempest
# File            : run-tempest.sh
# Copyright       : (C) 2013 by
# Author          : Emilien Macchi
# Created On      : Thu Jan 24 18:26:30 2013
# Purpose         : Install and run Tempest
#---------------------------------------------------------------

set -e
set -x

here=$(dirname $(readlink -m $0))

tests_to_run=""
while getopts "v:p:" opt; do
    case $opt in
        v ) VERSION=$OPTARG;;
        p ) PROJECT=$OPTARG;;
        * ) echo "Bad parameter" ; exit 1 ;;
    esac
done

shift $(( OPTIND-1 ))

if [ "$@" ]; then
    custom_tests_to_run="$@"
fi

# Project param is used to exclude some tests in tempest, specific to the project
# that we want to test.
if [ ! "$PROJECT" ]; then
  PROJECT="default"
fi

if [ "$VERSION" ]; then
    if [ -f $here/nose_exclude_${PROJECT}_${VERSION} ] ; then
        grep -v -e '^#' -e '^$' $here/nose_exclude_${PROJECT}_${VERSION} > nose_exclude
        EXCLUDE="$(printf  "%s|" $(<nose_exclude))"
        NOSE_EXCLUDE="(${EXCLUDE::-1})"
        testr_exclude='(?!.*('"${EXCLUDE::-1}"'))'
        export NOSE_EXCLUDE
    fi
fi

export PYTHONUNBUFFERED=true
export NOSE_WITH_OPENSTACK=1
export NOSE_OPENSTACK_COLOR=1
export NOSE_OPENSTACK_RED=15
export NOSE_OPENSTACK_YELLOW=3
export NOSE_OPENSTACK_SHOW_ELAPSED=1
export NOSE_OPENSTACK_STDOUT=1
export NOSE_NOCAPTURE=1
export NOSE_LOGFORMAT='%(asctime)-15s %(message)s'
export NOSE_WITH_XUNIT=1
export NOSE_XUNIT_FILE=tempest_xunit.xml

cd /usr/share/openstack-tempest-juno/
if [ ! "$custom_tests_to_run" ]; then
  TESTRARGS='(?!.*\[.*\bslow\b.*\])(^tempest\.(api|cli)'$testr_exclude')'
else
   TESTRARGS="$custom_tests_to_run"
fi

[ ! -d .testrepository ] && testr init
testr run --subunit $TESTRARGS | subunit2junitxml -o tempest_xunit.xml  -f --no-passthrough | subunit2pyunit --no-passthrough
