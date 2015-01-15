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

import voluptuous

from virtualization import collector

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

cmdb_machines = [{'mac1': 'd8:9d:67:1a:8f:59',
                 'domainname': 'ring.enovance.com',
                 'ip': '10.151.68.54',
                 'hostname': 'os-ci-test10',
                 'netmask': '255.255.255.0',
                 'mac': 'd8:9d:67:1a:8f:58',
                 'gateway': '10.151.68.3'}]


def test_get_disks():
    actual = collector._get_disks(list(specs))
    expected = [{"size": "100G"}, {"size": "200G"},
                {"size": "300G"}, {"size": "400G"}]
    assert expected == actual


def test_get_default_network():
    actual = collector._get_default_network(cmdb_machines)
    expected = {'name': 'default',
                'address': '10.151.68.0',
                'netmask': '255.255.255.0'}
    assert expected == actual


def test_get_nics():
    nics = collector._get_nics(cmdb_machines[0])

    assert len(nics) == 2
    for nic in nics:
        assert "name" in nic
        assert "network" in nic
        assert "mac" in nic


def test_collect():
    virt_platform = collector.collect(_CONFIG_PATH)
    assert "networks" in virt_platform
    assert len(virt_platform["networks"]) == 1

    assert "hosts" in virt_platform
    assert len(virt_platform["hosts"]) == 3

    for host in ['os-ci-test10', 'os-ci-test11', 'os-ci-test12']:
        assert "disks" in virt_platform["hosts"][host]
        assert "nics" in virt_platform["hosts"][host]
