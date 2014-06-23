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

import merge


class TestMerge(unittest.TestCase):

    def test_merge(self):
        dic1 = {'a': 1}
        dic2 = {'b': 2}
        merge.merge(dic1, dic2)
        self.assertEqual(dic1['b'], 2)

    def test_merge_identical(self):
        dic1 = {'a': 1}
        dic2 = {'a': 2}
        merge.merge(dic1, dic2)
        self.assertEqual(dic1['a'], 2)

    def test_merge_subdict(self):
        dic1 = {'a': {'b': 2}}
        dic2 = {'a': {'c': 3}}
        merge.merge(dic1, dic2)
        self.assertEqual(dic1['a']["c"], 3)

    def test_merge_lists(self):
        dic1 = {'a': [1, 2]}
        dic2 = {'a': [3, 4]}
        merge.merge(dic1, dic2)
        self.assertEqual(dic1['a'], [1, 2, 3, 4])

if __name__ == "__main__":
    unittest.main()

# test_merge.py ends here
