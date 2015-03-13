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

import unittest

import extract_puppet_info as epi


class TestExtractPuppetInfo(unittest.TestCase):

    def test_puppet_filename(self):
        self.assertEqual(epi.puppet_filename('cloud::messaging'),
                         '/etc/puppet/modules/cloud/manifests/messaging.pp')

    def test_puppet_filename_short(self):
        self.assertEqual(epi.puppet_filename('rabbitmq'),
                         '/etc/puppet/modules/rabbitmq/manifests/init.pp')

    def test_eval_cat(self):
        self.assertEqual(epi.parse_and_eval(
            '(cat ::apache::mod:: (str $mpm_module) \'\')'),
                         '::apache::mod::$mpm_module')

    def test_eval_case(self):
        self.assertEqual(epi.parse_and_eval('''
 (case 2
   (when (2 4) (then (block 2)))
   (when (5) (then (block 4)))
)
'''),
                         2)

if __name__ == "__main__":
    unittest.main()

# test_extract_puppet_info.py ends here
