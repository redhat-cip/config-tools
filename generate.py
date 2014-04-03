#!/usr/bin/env python
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

'''
'''

from jinja2 import Template
from yaml import load, Loader


def expand(templ_string, variables):
    template = Template(templ_string)
    return template.render(variables)


def get_vars(yaml_string):
    # load entries yaml
    return load(yaml_string, Loader=Loader)


def reinject(variables):
    for pname in variables['profiles']:
        if not variables['profiles'][pname]:
            variables['profiles'][pname] = {}
        if 'steps' in variables['profiles'][pname] and \
                variables['profiles'][pname]['steps']:
            min_step = min([x['step'] for x in variables['profiles'][pname]['steps']])
            variables['profiles'][pname]['min_step'] = min_step
        variables['profiles'][pname]['hosts'] = [x for x in variables['hosts'] if x['profile'] == pname]


def validate(variables):
    if not variables or 'hosts' not in variables or 'profiles' not in variables:
        return False, 'No hosts or profiles section'

    for host in variables['hosts']:
        if 'name' not in host:
            return False, 'host with no name'
        if 'profile' not in host:
            return False, 'host %s has no profile section' % host['name']

    return (True, '')

if __name__ == "__main__":
    import sys
    #import pprint

    if len(sys.argv) != 4:
        sys.stderr.write('Usage: %s <step> <yaml file> <template file>\n' % sys.argv[0])
        sys.exit(1)

    variables = get_vars(open(sys.argv[2]).read())
    if not validate(variables)[0]:
        print validate(variables)[1]
        sys.exit(1)
    variables['step'] = int(sys.argv[1])
    reinject(variables)
    #pprint.pprint(variables['profiles'])
    print(expand(open(sys.argv[3]).read(),
                 variables))

# generate.py ends here
