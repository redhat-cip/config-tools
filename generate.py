#!/usr/bin/env python
#
# Copyright (C) 2014-2015 eNovance SAS <licensing@enovance.com>
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
import os
from yaml import dump, load, Loader

from hardware import generate


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
            min_step = min([x
                            for x in variables['profiles'][pname]['steps']])
            variables['profiles'][pname]['min_step'] = min_step
        variables['profiles'][pname]['hosts'] = \
            [x for x
             in variables['hosts']
             if variables['hosts'][x]['profile'] == pname]


def validate_arity(arity_def, value):
    '''Validate a value against an arity definition of a profile entry.

The arity field can have these forms:

    arity: 2                    # only 2 instances
    arity: 3n                   # only instances by group of 3
    arity: 1+2n                 # only odd number of instances

    '''
    # strict number
    try:
        arity = int(arity_def)
        return arity == value
    except ValueError:
        pass
    # remove spaces
    arity_def = arity_def.replace(' ', '')
    # pattern like 1+2n
    if '+' in arity_def:
        num, pattern = arity_def.split('+')
        num = int(num)
    # pattern like 2n
    else:
        pattern = arity_def
        num = 0
    if not 'n' in pattern:
        raise(Invalid('Invalid arity pattern %s' % arity_def))
    pattern = pattern[:-1]
    if len(pattern) == 0:
        time = 1
    else:
        time = int(pattern)
    if value < num:
        return False
    return (value - num) % time == 0


def validate(variables):
    'Validate variables.'
    if not variables or 'hosts' not in variables or \
       'profiles' not in variables:
        raise(Invalid('No hosts or profiles section'))

    if not 'infra' in variables or not 'name' in variables:
        raise(Invalid('No infra or name field'))

    if variables['infra'] != variables['name']:
        raise(Invalid('Incoherent infra(%s) and env(%s)' %
                      (variables['name'], variables['infra'])))

    for host in variables['hosts']:
        if 'profile' not in variables['hosts'][host]:
            raise(Invalid('host %s has no profile section' % host))

    for profile_name in variables['profiles']:
        profile = variables['profiles'][profile_name]
        if profile and not 'arity' in profile:
            if 'name' in profile:
                raise(Invalid('No arity field in profile %s' %
                              profile['name']))
            else:
                raise(Invalid('No arity field in profile'))
        count = 0
        for host in variables['hosts']:
            if variables['hosts'][host]['profile'] == profile_name:
                count += 1
        if not profile:
            raise(Invalid('Profile %s has no arity definition' %
                          profile_name))
        if not validate_arity(profile['arity'], count):
            raise(Invalid('Not the expected arity (%s) for %s: %d' %
                          (profile['arity'], profile_name, count)))

    return True


def expand_template(step, yamlstr, tmpl, ovrwt={}):
    '''Expand a template string according to the yaml variables augmented with
information with steps.'''

    variables = get_vars(yamlstr)
    variables.update(ovrwt)
    if 'hosts' in variables:
        variables['hosts'] = generate.generate_dict(variables['hosts'], '=')
    validate(variables)
    variables['step'] = step
    reinject(variables)

    # for debugging purpose
    if os.getenv('CONFIGTOOL_GENERATED_YAML'):
        generated = open(os.getenv('CONFIGTOOL_GENERATED_YAML'), 'w')
        generated.write(dump(variables))
        generated.close()

    return expand(tmpl, variables)

if __name__ == "__main__":
    import sys
    #import pprint

    if len(sys.argv) < 4:
        sys.stderr.write('Usage: %s <step> <yaml file> <template file>'
                         ' [var=val...]\n'
                         % sys.argv[0])
        sys.exit(1)

    overwrite = {}
    for arg in sys.argv[4:]:
        key, value = arg.split('=')
        overwrite[key] = value

    try:
        print expand_template(int(sys.argv[1]),
                              open(sys.argv[2]).read(),
                              open(sys.argv[3]).read(),
                              overwrite)
    except Invalid, excpt:
        sys.stderr.write('%s\n' % excpt)
        sys.exit(1)

# generate.py ends here
