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

    def test_generate_ips(self):
        model = '192.168.1.10-12'
        self.assertEqual(list(generate._generate_values(model)),
                         ['192.168.1.10',
                          '192.168.1.11',
                          '192.168.1.12'])

    def test_generate_names(self):
        model = 'host10-12'
        self.assertEqual(list(generate._generate_values(model)),
                         ['host10', 'host11', 'host12'])

    def test_generate_nothing(self):
        model = 'host'
        result = generate._generate_values(model)
        self.assertEqual(result.next(),
                         'host')

    def test_generate_range(self):
        self.assertEqual(list(generate._generate_range('10-12')),
                         ['10', '11', '12'])

    def test_generate_range_zero(self):
        self.assertEqual(list(generate._generate_range('001-003')),
                         ['001', '002', '003'])

    def test_generate_range_colon(self):
        self.assertEqual(list(generate._generate_range('1-3:10-12')),
                         ['1', '2', '3', '10', '11', '12'])

    def test_generate_range_colon_reverse(self):
        self.assertEqual(list(generate._generate_range('100-100:94-90')),
                         ['100', '94', '93', '92', '91', '90'])

    def test_generate_range_invalid(self):
        self.assertEqual(list(generate._generate_range('D7-H.1.0.0')),
                         ['D7-H.1.0.0'])

    def test_generate(self):
        model = {'gw': '192.168.1.1',
                 '=ip': '192.168.1.10-12',
                 '=hostname': 'host10-12'}
        self.assertEqual(
            generate.generate_list(model),
            [{'gw': '192.168.1.1', 'ip': '192.168.1.10', 'hostname': 'host10'},
             {'gw': '192.168.1.1', 'ip': '192.168.1.11', 'hostname': 'host11'},
             {'gw': '192.168.1.1', 'ip': '192.168.1.12', 'hostname': 'host12'}]
            )

    def test_generate_with_zeros(self):
        model = {'gw': '192.168.1.1',
                 '=ip': '192.168.1.1-6',
                 '=hostname': 'ceph001-006'}
        self.assertEqual(
            generate.generate_list(model),
            [{'gw': '192.168.1.1', 'ip': '192.168.1.1', 'hostname': 'ceph001'},
             {'gw': '192.168.1.1', 'ip': '192.168.1.2', 'hostname': 'ceph002'},
             {'gw': '192.168.1.1', 'ip': '192.168.1.3', 'hostname': 'ceph003'},
             {'gw': '192.168.1.1', 'ip': '192.168.1.4', 'hostname': 'ceph004'},
             {'gw': '192.168.1.1', 'ip': '192.168.1.5', 'hostname': 'ceph005'},
             {'gw': '192.168.1.1', 'ip': '192.168.1.6', 'hostname': 'ceph006'},
             ]
            )

    def test_generate_253(self):
        result = generate.generate_list({'=hostname': '10.0.1-2.2-254'})
        self.assertEqual(
            len(result),
            2 * 253,
            result)

    def test_generate_invalid(self):
        result = generate.generate_list({'=hostname': '10.0.1-2.2-254',
                                         'version': 'D7-H.1.0.0'})
        self.assertEqual(
            len(result),
            2 * 253,
            result)

    def test_generate_list(self):
        result = generate.generate_list({'=hostname':
                                         ('hosta', 'hostb', 'hostc')})
        self.assertEqual(
            result,
            [{'hostname': 'hosta'},
             {'hostname': 'hostb'},
             {'hostname': 'hostc'}]
            )

    def test_generate_none(self):
        model = {'gateway': '10.66.6.1',
                 'ip': '10.66.6.100',
                 'netmask': '255.255.255.0',
                 'gateway-ipmi': '10.66.6.1',
                 'ip-ipmi': '10.66.6.110',
                 'netmask-ipmi': '255.255.255.0',
                 'hostname': 'hp-grid'
                 }
        result = generate.generate_list(model)
        self.assertEqual(result, [model])

    def test_generate_deeper(self):
        model = {'=cmdb':
                 {'gw': False,
                  '=ip': '192.168.1.10-12',
                  '=hostname': 'host10-12'}}
        self.assertEqual(
            generate.generate_list(model),
            [{'cmdb':
              {'gw': False,
               'ip': '192.168.1.10',
               'hostname': 'host10'}},
             {'cmdb':
              {'gw': False,
               'ip': '192.168.1.11',
               'hostname': 'host11'}},
             {'cmdb':
              {'gw': False,
               'ip': '192.168.1.12',
               'hostname': 'host12'}}]
            )

    def test_generate_hosts(self):
        model = {'=host10-12':
                 {'=cmdb':
                  {'gw': ['192.168.1.1',  '192.168.1.2'],
                   '=ip': '192.168.1.10-12'}}}
        self.assertEqual(
            generate.generate_dict(model),
            {'host10':
             {'cmdb':
              {'gw': ['192.168.1.1',  '192.168.1.2'],
               'ip': '192.168.1.10'}},
             'host11':
             {'cmdb':
              {'gw': ['192.168.1.1',  '192.168.1.2'],
               'ip': '192.168.1.11'}},
             'host12':
             {'cmdb':
              {'gw': ['192.168.1.1',  '192.168.1.2'],
               'ip': '192.168.1.12'}}}
            )

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
