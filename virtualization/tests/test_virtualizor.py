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
from mock import call
import testtools
import unittest

libvirt_conn = mock.Mock()
libvirt_conn.listAllNetworks.return_value = [
    mock.Mock(**{'name.return_value': 'sps_default'})]
libvirt_conn.listAllDomains.return_value = [
    mock.Mock(**{'name.return_value': 'os-ci-test11'})]


class FakeLibvirt(object):
    def open(a, b):
        return libvirt_conn


class TestVirtualizor(testtools.TestCase):

    def setUp(self):
        super(TestVirtualizor, self).setUp()
        self.module_patcher = mock.patch.dict(
            'sys.modules', {'libvirt': FakeLibvirt()})
        self.module_patcher.start()

    def test_random_mac(self):
        import virtualizor
        self.assertRegex(virtualizor.random_mac(),
                         '^([0-9a-fA-F]{2}:){5}([0-9a-fA-F]{2})$')

    @mock.patch('virtualizor.subprocess.call')
    def test_main(self, sub_call):
        import virtualizor
        img_dir = '/var/lib/libvirt/images'
        virtualizor.main(['virt_platform.yml.sample', 'bar',
                          '--pub-key-file', 'virt_platform.yml.sample'])
        sub_call.assert_has_calls([
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/os-ci-test10-000.qcow2',
                  '10485760K']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/os-ci-test10-001.qcow2',
                  '10485760K']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/os-ci-test10-002.qcow2',
                  '10485760K']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/os-ci-test10-003.qcow2',
                  '10485760K']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/os-ci-test12-000.qcow2',
                  '10485760K']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/os-ci-test12-001.qcow2',
                  '10485760K']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/os-ci-test12-002.qcow2',
                  '10485760K']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/os-ci-test12-003.qcow2',
                  '10485760K']),
            call(['ssh', 'root@bar', 'mkdir', '-p', '/tmp/mydata']),
            call(['scp', '-r', mock.ANY, 'root@bar:/tmp/mydata/meta-data']),
            call(['scp', '-r', mock.ANY, 'root@bar:/tmp/mydata/user-data']),
            call(['ssh', 'root@bar', 'genisoimage', '-quiet', '-output',
                  img_dir + '/cloud-init.iso', '-volid', 'cidata', '-joliet',
                  '-rock', '/tmp/mydata/user-data', '/tmp/mydata/meta-data']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-f', 'qcow2',
                  '-b', img_dir + '/install-server-RH7.0-I.1.3.0.img.qcow2',
                  img_dir + '/os-ci-test4-000.qcow2',
                  '30G']),
            call(['ssh', 'root@bar', 'qemu-img', 'resize', '-q',
                  img_dir + '/os-ci-test4-000.qcow2',
                  '30G'])
        ])
        self.assertEqual(sub_call.call_count, 14)
        self.assertEqual(libvirt_conn.networkCreateXML.call_count, 0)
        self.assertEqual(libvirt_conn.createXML.call_count, 3)

    @mock.patch('virtualizor.subprocess.call')
    def test_main_with_replace(self, sub_call):
        import virtualizor
        libvirt_conn.reset_mock()
        virtualizor.main(['--replace', 'virt_platform.yml.sample', 'bar',
                          '--pub-key-file', 'virt_platform.yml.sample'])
        self.assertEqual(sub_call.call_count, 18)
        self.assertEqual(libvirt_conn.networkCreateXML.call_count, 1)
        self.assertEqual(libvirt_conn.createXML.call_count, 4)

if __name__ == '__main__':
    unittest.main()
