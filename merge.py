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

'''Utility to merge 2 YAML files.
'''

import sys
from yaml import dump, load


def merge(user, default):
    'Merge 2 data structures'
    for key, val in default.iteritems():
        if key not in user:
            user[key] = val
        else:
            if isinstance(user[key], dict) and isinstance(val, dict):
                user[key] = merge(user[key], val)
            elif isinstance(user[key], list) and isinstance(val, list):
                user[key] = user[key] + val
            else:
                user[key] = val
    return user


def main():
    'SCript entry point'
    vars_ = {}
    for fname in sys.argv[1:]:
        current = load(open(fname).read())
        merge(vars_, current)
    sys.stdout.write(dump(vars_))

if __name__ == "__main__":
    main()

# merge.py ends here
