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


def extract_from_yaml(key, yamlstr):
    '''Extract a value from a YAML string according to a key.

The key can describe a hierarchical structure using '.' as separator.
'''
    variables = load(yamlstr, Loader=Loader)
    keys = key.split('.')
    try:
        for k in keys:
            variables = variables[k]
        return variables
    except KeyError:
        return None

if __name__ == "__main__":
    import sys

    if len(sys.argv) != 3:
        sys.stderr.write('Usage: %s <key> <yaml file>\n' % sys.argv[0])
        sys.exit(1)

    ret = extract_from_yaml(sys.argv[1], open(sys.argv[2]).read())

    if ret:
        print(ret)
    else:
        sys.stderr.write('Key "%s" not found in %s\n' % (sys.argv[1],
                                                         sys.argv[2]))
        sys.exit(1)

# extract-from-yaml.py ends here
