#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# Copyright (C) 2015 eNovance SAS <licensing@enovance.com>
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
import unittest

import collector

_MODULE_DIR = os.path.dirname(__file__)
_CONFIG_PATH = "%s/data" % _MODULE_DIR


class TestCollector(unittest.TestCase):

    def test_collect(self):
        virt_platform = collector.collect(_CONFIG_PATH)
        self.assertTrue("hosts" in virt_platform)
        self.assertEqual(len(virt_platform["hosts"]), 4)

        for host in ['node1', 'node2', 'node3']:
            self.assertTrue("disks" in virt_platform["hosts"][host])
            self.assertEqual(virt_platform["hosts"][host]["nics"][0]['mac'],
                             'dddd')

if __name__ == "__main__":
    unittest.main()
