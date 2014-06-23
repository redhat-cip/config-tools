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

import generate


class TestGenerate(unittest.TestCase):

    def test_expand(self):
        self.assertEqual(generate.expand('Hello {{ name }}!',
                                         {'name': 'John Doe'}),
                         'Hello John Doe!')

    def test_get_vars(self):
        self.assertEqual(generate.get_vars(YAML1),
                         {'key': 'value'})

    def test_invalid_profile(self):
        variables = generate.get_vars('')
        with self.assertRaises(generate.Invalid):
            generate.validate(variables)

    def test_validate(self):
        variables = generate.get_vars(YAML2)
        self.assertTrue(generate.validate(variables))

    def test_validate2(self):
        variables = generate.get_vars(YAML3)
        self.assertTrue(generate.validate(variables))

    def test_reinject(self):
        variables = generate.get_vars(YAML2)
        generate.reinject(variables)
        self.assertTrue(variables['profiles']['management'], variables)
        self.assertTrue(variables['profiles']['management']['hosts'],
                        variables)
        self.assertEqual(variables['profiles']['management']['min_step'], 1,
                         variables)

    def test_expand_template(self):
        self.assertEqual(generate.expand_template(
            1,
            YAML2,
            '{% if step >= 1 %}a{% endif %}'), 'a')

    def test_expand_template_overwrite(self):
        self.assertEqual(generate.expand_template(
            1,
            YAML2,
            '{{ key }}',
            {'key': 'other'}
        ), 'other')

    def test_validate_arity(self):
        self.assertTrue(generate.validate_arity('1', 1))

    def test_validate_arity2(self):
        self.assertFalse(generate.validate_arity('2', 1))

    def test_validate_arity3(self):
        self.assertFalse(generate.validate_arity(' 2 + n ', 1))

    def test_validate_arity4(self):
        self.assertTrue(generate.validate_arity(' 2 + 2n ', 8))

    def test_validate_arity5(self):
        self.assertTrue(generate.validate_arity('n', 0))

YAML1 = '''
key: value
'''

YAML2 = '''
name: 2
profiles:
  management2:
    arity: 0
  management:
    arity: 1
    steps:
      1:
        role:
          - role1
      3:
        role:
          - role3
infra: 2
hosts:
  master:
    profile: management
key: value
'''

YAML3 = '''
name: 3
profiles:
  management:
    arity: n
  management2:
    arity: 1+2n
infra: 3
hosts:
  master:
    profile: management2
key: value
'''

if __name__ == "__main__":
    unittest.main()

# test_generate.py ends here
