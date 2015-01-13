# -*- coding: utf-8 -*-
#
# Copyright 2015 eNovance SAS <licensing@enovance.com>
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

import mock
import unittest
import testtools

import virtualizor


class TestVirtualizor(testtools.TestCase):

    def _get_mocked_libvirt_conn(self):
        libvirt_conn = mock.Mock()
        libvirt_conn.listAllNetworks.return_value = [
            mock.Mock(**{'name.return_value': 'default'})]
        libvirt_conn.listAllDomains.return_value = [
            mock.Mock(**{'name.return_value': 'os-ci-test12'})]
        return libvirt_conn

    def test_random_mac(self):
        self.assertRegex(virtualizor.random_mac(),
                         '^([0-9a-fA-F]{2}:){5}([0-9a-fA-F]{2})$')

    @mock.patch('libvirt.open')
    @mock.patch('virtualizor.Host._call')
    def test_main(self, Host_call, libvirt_open):
        img_dir = '/var/lib/libvirt/images'
        libvirt_conn = self._get_mocked_libvirt_conn()
        libvirt_open.return_value = libvirt_conn
        virtualizor.main(['virt_platform.yml.sample', 'bar'])
        Host_call.assert_has_calls(
            [mock.call('qemu-img', 'create', '-q', '-f', 'qcow2',
                       img_dir + '/os-ci-test11-000.qcow2', '100G'),
             mock.call('qemu-img', 'create', '-q', '-f', 'qcow2',
                       img_dir + '/os-ci-test11-001.qcow2', '2000G'),
             mock.call('qemu-img', 'create', '-q', '-f', 'qcow2',
                       img_dir + '/os-ci-test11-002.qcow2', '2000G'),
             mock.call('qemu-img', 'create', '-q', '-f', 'qcow2',
                       img_dir + '/os-ci-test11-003.qcow2', '2000G'),
             mock.call('qemu-img', 'create', '-q', '-f', 'qcow2',
                       img_dir + '/os-ci-test10-000.qcow2', '300G'),
             mock.call('qemu-img', 'create', '-q', '-f', 'qcow2',
                       img_dir + '/os-ci-test10-001.qcow2', '300G'),
             mock.call('qemu-img', 'create', '-q', '-f', 'qcow2',
                       img_dir + '/os-ci-test10-002.qcow2', '300G'),
             mock.call('qemu-img', 'create', '-q', '-f', 'qcow2',
                       img_dir + '/os-ci-test10-003.qcow2', '300G')])
        libvirt_open.assert_called_once_with('qemu+ssh://root@bar/system')
        self.assertEqual(libvirt_conn.networkCreateXML.call_count, 0)
        self.assertEqual(libvirt_conn.createXML.call_count, 2)

    @mock.patch('libvirt.open')
    @mock.patch('virtualizor.Host._call')
    def test_main_with_replace(self, Host_call, libvirt_open):
        libvirt_conn = self._get_mocked_libvirt_conn()
        libvirt_open.return_value = libvirt_conn
        virtualizor.main(['--replace', 'virt_platform.yml.sample', 'bar'])

        self.assertEqual(Host_call.call_count, 12)
        self.assertEqual(libvirt_conn.networkCreateXML.call_count, 1)
        self.assertEqual(libvirt_conn.createXML.call_count, 3)

if __name__ == '__main__':
    unittest.main()
