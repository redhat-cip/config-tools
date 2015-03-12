#!/usr/bin/env python
#
# Copyright (C) 2015 eNovance SAS <licensing@enovance.com>
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

'''Utils to parse the output of 'puppet parser dump <module>' to find
useful info like which services anb which files are manipulated by
puppet modules.

'''

import os
import subprocess
import sys

import sexp


def require(_, name):
    '(require => name)'
    if name not in _ENV['REQS']:
        _ENV['REQS'].append(name)
        return parse_and_eval(dump_puppet_module(puppet_filename(name)))
    else:
        return name


def invoke(action, *args):
    "(invoke include '::module::submodule')"
    if action == 'include':
        return require(action, args[0])
    else:
        return ['invoke', action] + list(args)


def resource(res_type, desc, *args):
    "(resource service <service>)"
    sys.stderr.write('Resource %s %s\n' % (res_type, desc[0]))
    if res_type == 'service':
        if desc[0] not in _ENV['SERVICES']:
            _ENV['SERVICES'].append(desc[0])
        return desc[0]
    elif res_type == 'file':
        if desc[0] not in _ENV['FILES']:
            _ENV['FILES'].append(desc[0])
        return desc[0]
    elif res_type == 'class':
        require('resource', desc[0])
    else:
        return ['resource', res_type, desc]


def slice_(_, *names):
    '(slice class name)'
    #print 'slice', names
    return names[0]


def cat(*args):
    return ''.join([str(arg) for arg in args])


def str_(arg):
    return str(arg)


def puppet_env():
    'Define the functions we want to call during eval_sexp'
    env = dict()
    env.update({
        'FILES': [],
        'REQS': [],
        'SERVICES': [],
        'invoke': invoke,
        'resource': resource,
        'slice': slice_,
        'cat': cat,
        'str': str_,
    })
    return env

_ENV = puppet_env()


def puppet_filename(name, prefix='/etc/puppet/modules'):
    'Return a filename according to puppet module name'
    components = name.split('::')
    if components[0] == '':
        components = components[1:]
    if len(components) == 1:
        return os.path.join(prefix,
                            components[0],
                            'manifests',
                            'init') + '.pp'
    else:
        return os.path.join(prefix,
                            components[0],
                            'manifests',
                            *components[1:]) + '.pp'


def dump_puppet_module(filename):
    'Call puppet to parse a filename'
    sys.stderr.write('Parsing %s\n' % filename)
    res = subprocess.check_output(['puppet', 'parser', 'dump', filename])
    # ignore chars up to the first parenthesis as puppet is writting
    # the filename prefixed by --- before.
    #print res[res.find('('):]
    return res[res.find('('):]


def parse_and_eval(srt_):
    'Parse and evaluate the string in the puppet env.'
    return sexp.eval_sexp(sexp.parse_sexp(srt_), _ENV)


def main():
    'Script entry point'
    for arg in sys.argv[1:]:
        parse_and_eval(dump_puppet_module(puppet_filename(arg)))

    print _ENV['REQS']
    print _ENV['FILES']
    print _ENV['SERVICES']

if __name__ == "__main__":
    main()

# extract_puppet_info.py ends here
