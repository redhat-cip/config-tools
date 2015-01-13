#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# Copyright (C) 2015 eNovance SAS <licensing@enovance.com>
#
# Author: Yassine Lamgarchal <yassine.lamgarchal@enovance.com>
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

import os
import sys
import unittest

import collector

_MODULE_DIR = os.path.dirname(sys.modules[__name__].__file__)
_CONFIG_PATH = "%s/datas/etc" % _MODULE_DIR

specs = [
    ('disk', '$disk1', 'size', '100'),
    ('disk', '$disk1', 'slot', '$slot1'),
    ('disk', '$disk2', 'size', '200'),
    ('disk', '$disk2', 'slot', '$slot2'),
    ('disk', '$disk3', 'size', '300'),
    ('disk', '$disk3', 'slot', '$slot3'),
    ('disk', '$disk4', 'size', '400'),
    ('disk', '$disk4', 'slot', '$slot4'),
    ('cpu', 'logical', 'number', "$nbcpu"),
    ('system', 'ipmi', 'channel', "$ipmi-channel"),
    ('system', 'product', 'name', 'ProLiant DL360p Gen8 (654081-B21)'),
    ('network', '$eth', 'serial', '$$mac'),
    ('network', '$eth1', 'serial', '$$mac1'),
    ('system', 'product', 'serial', 'CZ3340P75T')
]


class TestCollector(unittest.TestCase):

    def test_get_disks(self):
        actual = collector._get_disks(list(specs))
        expected = [{"size": "100G"}, {"size": "200G"},
                    {"size": "300G"}, {"size": "400G"}]
        self.assertEqual(actual, expected)

    @unittest.skip("Skipping, need a copy of the data")
    def test_collect(self):
        virt_platform = collector.collect(_CONFIG_PATH)
        self.assertTrue("hosts" in virt_platform)
        self.assertEqual(len(virt_platform["hosts"]), 4)

        for host in ['os-ci-test10', 'os-ci-test11', 'os-ci-test12']:
            self.assertTrue("disks" in virt_platform["hosts"][host])
            self.assertTrue("nics" in virt_platform["hosts"][host])

if __name__ == "__main__":
    unittest.main()
