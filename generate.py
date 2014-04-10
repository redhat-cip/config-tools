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

'''Module to generate templates according to yaml variables.
'''

from jinja2 import Template
from yaml import load, Loader


class Invalid(Exception):
    'Exception raised when a yaml is invalid'
    pass


def expand(templ_string, variables):
    'Expand a Jinja2 templates using variables.'
    template = Template(templ_string)
    return template.render(variables)


def get_vars(yaml_string):
    'Transform a syaml string in a python dict.'
    return load(yaml_string, Loader=Loader)


def reinject(variables):
    'Inject variables according to step and hosts.'
    for pname in variables['profiles']:
        if not variables['profiles'][pname]:
            variables['profiles'][pname] = {}
        if 'steps' in variables['profiles'][pname] and \
                variables['profiles'][pname]['steps']:
            min_step = min([x['step'] \
                                for x in variables['profiles'][pname]['steps']])
            variables['profiles'][pname]['min_step'] = min_step
        variables['profiles'][pname]['hosts'] = [x for x \
                                                     in variables['hosts'] \
                                                     if x['profile'] == pname]


def validate(variables):
    'Validate variables.'
    if not variables or 'hosts' not in variables or 'profiles' not in variables:
        raise(Invalid('No hosts or profiles section'))

    for host in variables['hosts']:
        if 'name' not in host:
            raise(Invalid('host with no name'))
        if 'profile' not in host:
            raise(Invalid('host %s has no profile section' % host['name']))

    return True


def expand_template(step, yamlstr, tmpl):
    '''Expand a template string according to the yaml variables augmented with
information with steps.'''
    variables = get_vars(yamlstr)
    validate(variables)
    variables['step'] = step
    reinject(variables)
    #pprint.pprint(variables['profiles'])
    return expand(tmpl, variables)

if __name__ == "__main__":
    import sys
    #import pprint

    if len(sys.argv) != 4:
        sys.stderr.write('Usage: %s <step> <yaml file> <template file>\n'
                         % sys.argv[0])
        sys.exit(1)

    try:
        print expand_template(int(sys.argv[1]),
                              open(sys.argv[2]).read(),
                              open(sys.argv[3]).read())
    except Invalid, excpt:
        print excpt
        sys.exit(1)
        
# generate.py ends here
