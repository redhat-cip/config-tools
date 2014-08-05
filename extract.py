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

'''Module to extract information from a YAML file according to a key.
'''

from yaml import load, Loader


def _lookup_keys(keys, data, lookup_all):
    '''Axuliary function for extract_from_yaml.'''
    if len(keys) == 0:
        return data
    res = None
    if keys[0] == '*':
        for subkey in data.keys():
            ret = _lookup_keys(keys[1:], data[subkey], lookup_all)
            if ret is not None:
                if lookup_all:
                    if not res:
                        res = []
                    res.append(ret)
                else:
                    return ret
        return res
    else:
        try:
            return _lookup_keys(keys[1:], data[keys[0]], lookup_all)
        except (KeyError, TypeError):
            return None


def extract_from_yaml(key, yamlstr, lookup_all=False):
    '''Extract a value from a YAML string according to a key. If
lookup_all is True find all the values.

The key can describe a hierarchical structure using '.' as separator
and use * as a wildcard.'''
    variables = load(yamlstr, Loader=Loader)
    keys = key.split('.')
    return _lookup_keys(keys, variables, lookup_all)

if __name__ == "__main__":
    import sys

    if len(sys.argv) not in (3, 4) or len(sys.argv) == 4 and sys.argv[1] != '-a':
        sys.stderr.write('Usage: %s [-a] <key> <yaml file>\n' % sys.argv[0])
        sys.exit(1)

    if len(sys.argv) == 3:
        key = sys.argv[1]
        filename = sys.argv[2]
        find_all = False
    else:
        key = sys.argv[2]
        filename = sys.argv[3]
        find_all = True

    ret = extract_from_yaml(key, open(filename).read(), find_all)

    if ret:
        if isinstance(ret, (list, tuple)):
            for elt in ret:
                print elt
        else:
            print(ret)
    else:
        sys.stderr.write('Key "%s" not found in %s\n' % (key, filename))
        sys.exit(1)

# extract-from-yaml.py ends here
