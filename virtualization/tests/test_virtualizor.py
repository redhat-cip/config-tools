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
    mock.Mock(**{'name.return_value': 'default_sps'})]
libvirt_conn.listAllDomains.return_value = [
    mock.Mock(**{'name.return_value': 'default_os-ci-test11'})]
libvirt_conn.lookupByName.return_value = mock.Mock(**{
    'info.return_value': [1], 'create.return_value': True})


class FakeLibvirt(object):
    VIR_DOMAIN_NOSTATE = 0
    VIR_DOMAIN_RUNNING = 1
    VIR_DOMAIN_BLOCKED = 2
    VIR_DOMAIN_PAUSED = 3
    VIR_DOMAIN_SHUTDOWN = 4
    VIR_DOMAIN_SHUTOFF = 5
    VIR_DOMAIN_CRASHED = 6
    VIR_DOMAIN_PMSUSPENDED = 7

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
        virtualizor.Hypervisor.wait_for_install_server = mock.Mock(
            return_value='1.2.3.4')
        virtualizor.main(['virt_platform.yml.sample', 'bar',
                          '--pub-key-file', 'virt_platform.yml.sample'])
        sub_call.assert_has_calls([
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/default_os-ci-test10-000.qcow2',
                  '10000000000']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/default_os-ci-test10-001.qcow2',
                  '10000000000']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/default_os-ci-test10-002.qcow2',
                  '10000000000']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/default_os-ci-test10-003.qcow2',
                  '10000000000']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/default_os-ci-test12-000.qcow2',
                  '10000000000']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/default_os-ci-test12-001.qcow2',
                  '10000000000']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/default_os-ci-test12-002.qcow2',
                  '10000000000']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-q', '-f', 'qcow2',
                  img_dir + '/default_os-ci-test12-003.qcow2',
                  '10000000000']),
            call(['ssh', 'root@bar', 'mkdir', '-p', '/tmp/mydata']),
            call(['scp', '-r', mock.ANY, 'root@bar:/tmp/mydata/meta-data']),
            call(['scp', '-r', mock.ANY, 'root@bar:/tmp/mydata/user-data']),
            call(['ssh', 'root@bar', 'genisoimage', '-quiet', '-output',
                  img_dir + '/cloud-init.iso', '-volid', 'cidata', '-joliet',
                  '-rock', '/tmp/mydata/user-data', '/tmp/mydata/meta-data']),
            call(['ssh', 'root@bar', 'qemu-img', 'create', '-f', 'qcow2',
                  '-b', img_dir + '/install-server-RH7.0-I.1.3.0.img.qcow2',
                  img_dir + '/default_os-ci-test4-000.qcow2',
                  '30G']),
            call(['ssh', 'root@bar', 'qemu-img', 'resize', '-q',
                  img_dir + '/default_os-ci-test4-000.qcow2',
                  '30G'])
        ])
        self.assertEqual(sub_call.call_count, 14)
        self.assertEqual(libvirt_conn.networkCreateXML.call_count, 0)
        self.assertEqual(libvirt_conn.defineXML.call_count, 3)

    @mock.patch('virtualizor.subprocess.call')
    def test_main_with_replace(self, sub_call):
        import virtualizor
        libvirt_conn.reset_mock()
        virtualizor.Hypervisor.wait_for_install_server = mock.Mock(
            return_value='1.2.3.4')
        virtualizor.main(['--replace', 'virt_platform.yml.sample', 'bar',
                          '--pub-key-file', 'virt_platform.yml.sample'])
        self.assertEqual(sub_call.call_count, 18)
        self.assertEqual(libvirt_conn.networkCreateXML.call_count, 1)
        self.assertEqual(libvirt_conn.defineXML.call_count, 4)

if __name__ == '__main__':
    unittest.main()
