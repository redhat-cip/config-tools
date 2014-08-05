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

import unittest

import extract


class TestExtract(unittest.TestCase):

    def test_extract(self):
        self.assertEquals(extract.extract_from_yaml('key', YAML), 'value')

    def test_extract2(self):
        self.assertEquals(extract.extract_from_yaml('key2.subkey', YAML),
                          'value')

    def test_extract3(self):
        self.assertIn(extract.extract_from_yaml('*.subkey', YAML),
                      ['value', 'value2'])

    def test_extract_all(self):
        res = extract.extract_from_yaml('*.subkey', YAML, True)
        self.assertEquals(len(res), 2)
        self.assertIn(res[0], ['value', 'value2'])
        self.assertIn(res[1], ['value', 'value2'])

YAML = '''
key: value
key2:
  subkey: value
key3:
  subkey: value2
'''

if __name__ == "__main__":
    unittest.main()

# test_extract.py ends here
