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

from merge import merge

from itertools import izip
from jinja2 import Template
import os
import re
import types
from yaml import dump, load, Loader


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


def _generate_range(num_range):
    'Generate number for range specified like 10-12:20-30.'
    for rang in num_range.split(':'):
        boundaries = rang.split('-')
        if len(boundaries) == 2:
            try:
                if boundaries[0][0] == '0':
                    fmt = '%%0%dd' % len(boundaries[0])
                else:
                    fmt = '%d'
                start = int(boundaries[0])
                stop = int(boundaries[1]) + 1
                if stop > start:
                    step = 1
                else:
                    step = -1
                    stop = stop - 2
                for res in range(start, stop, step):
                    yield fmt % res
            except ValueError:
                yield num_range
        else:
            yield num_range


_RANGE_REGEXP = re.compile(r'^(.*?)([0-9]+-[0-9]+(:([0-9]+-[0-9]+))*)(.*)$')
_IPV4_RANGE_REGEXP = re.compile(r'^[0-9:\-.]+$')


def _generate_values(pattern):
    '''Create a generator for ranges of IPv4 or names with ranges
defined like 10-12:15-18 or from a list of entries.'''
    if isinstance(pattern, list) or isinstance(pattern, tuple):
        for elt in pattern:
            yield elt
    elif isinstance(pattern, dict):
        for key, entry in pattern.items():
            if key[0] == '=':
                pattern[key[1:]] = _generate_values(entry)
                del pattern[key]
            else:
                pattern[key] = entry
        while True:
            yield pattern
    elif isinstance(pattern, str):
        parts = pattern.split('.')
        if _IPV4_RANGE_REGEXP.search(pattern) and \
                len(parts) == 4 and (pattern.find(':') != -1 or
                                     pattern.find('-') != -1):
            gens = [_generate_range(part) for part in parts]
            for part0 in gens[0]:
                for part1 in gens[1]:
                    for part2 in gens[2]:
                        for part3 in gens[3]:
                            yield '.'.join((part0, part1, part2, part3))
                        gens[3] = _generate_range(parts[3])
                    gens[2] = _generate_range(parts[2])
                gens[1] = _generate_range(parts[1])
        else:
            res = _RANGE_REGEXP.search(pattern)
            if res:
                head = res.group(1)
                foot = res.group(res.lastindex)
                for num in _generate_range(res.group(2)):
                    yield head + num + foot
            else:
                for _ in xrange(16387064):
                    yield pattern
    else:
        for _ in xrange(16387064):
            yield pattern


STRING_TYPE = type('')
GENERATOR_TYPE = types.GeneratorType


def _call_nexts(model):
    'Walk through the model to call next() on all generators.'
    entry = {}
    generated = False
    for key in model.keys():
        if isinstance(model[key], GENERATOR_TYPE):
            entry[key] = model[key].next()
            generated = True
        elif isinstance(model[key], dict):
            entry[key] = _call_nexts(model[key])
        else:
            entry[key] = model[key]
    # We can have nested generators so call again
    if generated:
        return _call_nexts(entry)
    else:
        return entry


def generate_list(model):
    '''Generate a list of dict according to a model with ranges in
values like host10-12 or 192.168.2.10-12:14-20.'''
    # Safe guard for models without ranges
    for value in model.values():
        if type(value) != STRING_TYPE:
            break
        elif _RANGE_REGEXP.search(value):
            break
    else:
        return [model]
    # The model has a range starting from here
    result = []
    yielded = {}
    yielded.update(model)
    for key, value in yielded.items():
        if key[0] == '=':
            yielded[key[1:]] = _generate_values(value)
            del yielded[key]
        else:
            yielded[key] = value
    while True:
        try:
            result.append(_call_nexts(yielded))
        except StopIteration:
            break
    return result


def generate_dict(model):
    '''Generate a dict with ranges in keys and values.'''
    result = {}
    for thekey in model.keys():
        if thekey[0] == '=':
            key = thekey[1:]
            for newkey, val in izip(list(_generate_values(key)),
                                    generate_list(model[thekey])):
                try:
                    result[newkey] = merge(result[key], val)
                except KeyError:
                    result[newkey] = val
        else:
            key = thekey
            try:
                result[key] = merge(result[key], model[key])
            except KeyError:
                result[key] = model[key]
    return result


def expand_template(step, yamlstr, tmpl, ovrwt={}):
    '''Expand a template string according to the yaml variables augmented with
information with steps.'''
    variables = get_vars(yamlstr)
    variables.update(ovrwt)
    if 'hosts' in variables:
        variables['hosts'] = generate_dict(variables['hosts'])
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
        print excpt
        sys.exit(1)

# generate.py ends here
