#!/usr/bin/env python
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

import argparse
import random
import os.path
import string
import subprocess
import sys
import tempfile
import uuid

import ipaddress
import jinja2
import libvirt
import six
import yaml

# from pprint import pprint


def random_mac():
    return "52:54:00:%02x:%02x:%02x" % (
        random.randint(0, 255),
        random.randint(0, 255),
        random.randint(0, 255))


def get_conf(argv=sys.argv):
    parser = argparse.ArgumentParser(
        description='Deploy a virtual infrastructure.')
    parser.add_argument('--replace', action='store_true',
                        help='existing resources will be recreated.')
    parser.add_argument('input_file', type=str,
                        help='the input file.')
    parser.add_argument('target_host', type=str,
                        help='the libvirt server.')
    parser.add_argument('--pub-key-file', type=str,
                        default=os.path.expanduser(
                            '~/.ssh/id_rsa.pub'),
                        help='SSH public key file.')
    conf = parser.parse_args(argv)
    return conf


class Host(object):
    host_template_string = """
<domain type='kvm'>
  <name>{{ hostname }}</name>
  <uuid>{{ uuid }}</uuid>
  <memory unit='KiB'>{{ memory }}</memory>
  <currentmemory unit='KiB'>{{ memory }}</currentmemory>
  <os>
    <type arch='x86_64' machine='pc'>hvm</type>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>/usr/bin/qemu-kvm</emulator>
{% for disk in disks %}
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='{{ disk.path }}'/>
      <target dev='{{ disk.name }}' bus='sata'/>
{% if disk.boot_order is defined %}
      <boot order='{{ disk.boot_order }}'/>
{% endif %}
    </disk>
{% endfor %}
{% if use_cloud_init is defined %}
    <disk type='file' device='disk'>
      <driver name='qemu' type='raw'/>
      <source file='/var/lib/libvirt/images/cloud-init.iso'/>
      <target dev='vda' bus='virtio'/>
    </disk>
{% endif %}
{% for nic in nics %}
{% if nic.network_name is defined %}
    <interface type='network'>
      <mac address='{{ nic.mac }}'/>
      <source network='{{ nic.network_name }}'/>
      <model type='virtio'/>
{% if nic.boot_order is defined %}
      <boot order='{{ nic.boot_order }}'/>
{% endif %}
    </interface>
{% endif %}
{% endfor %}
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <input type='mouse' bus='ps2'/>
    <graphics type='vnc' port='-1' autoport='yes'/>
    <video>
      <model type='cirrus' vram='9216' heads='1'/>
    </video>
  </devices>
</domain>
    """
    host_libvirt_image_dir = "/var/lib/libvirt/images"

    def __init__(self, conf, hostname, definition):
        self.conf = conf
        self.hostname = hostname
        self.meta = {'hostname': hostname, 'uuid': str(uuid.uuid1()),
                     'memory': 4194304,
                     'cpus': [], 'disks': [], 'nics': []}

        for k in ('uuid', 'serial', 'product_name',
                  'memory', 'use_cloud_init'):
            if k not in definition:
                continue
            self.meta[k] = definition[k]

        if 'use_cloud_init' in definition:
            self.prepare_cloud_init()

        env = jinja2.Environment(undefined=jinja2.StrictUndefined)
        self.template = env.from_string(Host.host_template_string)

        definition['nics'][0]['boot_order'] = 1
        definition['disks'][0]['boot_order'] = 2

        self.register_disks(definition)
        self.register_nics(definition)

    def _push(self, source, dest):
        subprocess.call(['scp', '-r', source,
                         'root@%s' % self.conf.target_host + ':' + dest])

    def _call(self, *kargs):
        subprocess.call(['ssh', 'root@%s' % self.conf.target_host] +
                        list(kargs))

    def prepare_cloud_init(self):

        ssh_key_file = self.conf.pub_key_file
        ssh_keys = open(ssh_key_file).readlines()
        contents = {
            'user-data': '#cloud-config\nusers:\n' +
                         ' - default\n' +
                         ' - name: root\n' +
                         '   ssh-authorized-keys:\n' +
                         '    - ' + ('    - '.join(ssh_keys)) +
                         'runcmd:\n' +
                         ' - sed -i -e "s/^Defaults\s\+requiretty/# \\0/" ' +
                         '/etc/sudoers\n',
            'meta-data': 'instance-id: id-install-server\n' +
                         'local-hostname: install-server\n'}
        # TODO(Gonéri): use mktemp
        self._call("mkdir", "-p", "/tmp/mydata")
        for name, content in six.iteritems(contents):
            fd = tempfile.NamedTemporaryFile()
            fd.write(content)
            fd.seek(0)
            fd.flush()
            self._push(fd.name, '/tmp/mydata/' + name)

        self._call('genisoimage', '-quiet', '-output',
                   Host.host_libvirt_image_dir + '/cloud-init.iso',
                   '-volid', 'cidata', '-joliet', '-rock',
                   '/tmp/mydata/user-data', '/tmp/mydata/meta-data')

    def register_disks(self, definition):
        cpt = 0
        for info in definition['disks']:
            filename = "%s-%03d.qcow2" % (self.hostname, cpt)
            if 'clone_from' in info:
                self._call('qemu-img', 'create', '-f', 'qcow2',
                           '-b', info['clone_from'],
                           Host.host_libvirt_image_dir +
                           '/' + filename, info['size'])
                self._call('qemu-img', 'resize', '-q',
                           Host.host_libvirt_image_dir + '/' + filename,
                           info['size'])
            else:
                self._call('qemu-img', 'create', '-q', '-f', 'qcow2',
                           Host.host_libvirt_image_dir + '/' + filename,
                           info['size'])

            info.update({
                'name': 'sd' + string.ascii_lowercase[cpt],
                'path': Host.host_libvirt_image_dir + '/' + filename})
            self.meta['disks'].append(info)
            cpt += 1

    def register_nics(self, definition):
        i = 0
        for info in definition['nics']:
            info.update({
                'mac': info.get('mac', random_mac()),
                'name': info.get('name', 'noname%i' % i),
                'network_name': 'sps_default'
            })
            self.meta['nics'].append(info)
            i += 1

    def dump_libvirt_xml(self):
        return self.template.render(self.meta)


class Network(object):
    network_template_string = """
<network>
  <name>{{ name }}</name>
  <uuid>{{ uuid }}</uuid>
  <bridge name='{{ bridge_name }}' stp='on' delay='0'/>
  <mac address='{{ mac }}'/>
{% if dhcp is defined %}
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <ip address='{{ dhcp.address }}' netmask='{{ dhcp.netmask }}'>
    <dhcp>
{% for host in dhcp.hosts %}
      <range start='{{ host.ip }}' end='{{ host.ip }}' />
      <host mac='{{ host.mac }}' name='{{ host.name }}' ip='{{ host.ip }}'/>
{% endfor %}
    </dhcp>
  </ip>
{% endif %}
</network>
    """

    default_network_settings = {}

    def __init__(self, name, definition):
        self.name = name
        self.meta = {
            'name': name,
            'uuid': str(uuid.uuid1()),
            'mac': random_mac(),
            'bridge_name': 'virbr%d' % random.randrange(0, 0xffffffff)}

        for k in ('uuid', 'mac', 'ips', 'dhcp'):
            if k not in definition:
                continue
            self.meta[k] = definition[k]

        env = jinja2.Environment(undefined=jinja2.StrictUndefined)
        self.template = env.from_string(Network.network_template_string)

    def dump_libvirt_xml(self):
        return self.template.render(self.meta)


def main(argv=sys.argv[1:]):
    conf = get_conf(argv)

    hosts_definition = yaml.load(open(conf.input_file, 'r'))
    conn = libvirt.open('qemu+ssh://root@%s/system' % conf.target_host)
    networks = hosts_definition.get('networks', {})
    networks['sps_default'] = Network.default_network_settings
    install_server_mac_addr = None

    for hostname, definition in six.iteritems(hosts_definition['hosts']):
        if 'profile' not in definition:
            continue
        if definition['profile'] != 'install-server':
            continue
        print("install-server (%s)" % (hostname))
        admin_nic_info = definition['nics'][0]
        if 'mac' in admin_nic_info:
            install_server_mac_addr
        else:
            install_server_mac_addr = random_mac()
        network = ipaddress.ip_network(
            unicode(
                admin_nic_info['network'] + '/' + admin_nic_info['netmask']))
        networks['sps_default'] = {'dhcp': {
            'address': str(network.network_address + 1),
            'netmask': str(network.netmask),
            'hosts': [{'mac': install_server_mac_addr,
                       'name': hostname,
                       'ip': admin_nic_info['ip']}]}}

    existing_networks = ([n.name() for n in conn.listAllNetworks()])
    for netname, definition in six.iteritems(networks):
        if netname in existing_networks:
            if conf.replace:
                conn.networkLookupByName(netname).destroy()
                print("Recreating network %s." % netname)
            else:
                print("Network %s already exist." % netname)
                continue
        network = Network(netname, definition)
        conn.networkCreateXML(network.dump_libvirt_xml())

    hosts = hosts_definition['hosts']
    existing_hosts = ([n.name() for n in conn.listAllDomains()])
    for hostname, definition in six.iteritems(hosts):

        if definition['profile'] == 'install-server':
            definition['use_cloud_init'] = True
            definition['disks'] = [
                {'name': 'sda',
                 'size': '30G',
                 'clone_from':
                     '/var/lib/libvirt/images/install-server_original.qcow2'}
            ]
            if 'nics' not in definition:
                definition['nics'] = [{'mac': install_server_mac_addr,
                                       'name': 'eth0'}]

        if hostname in existing_hosts:
            if conf.replace:
                conn.lookupByName(hostname).destroy()
                # TODO(Gonéri): remove the storages too
                print("Recreating host %s." % hostname)
            else:
                print("Host %s already exist." % hostname)
                continue
        host = Host(conf, hostname, definition)
        conn.createXML(host.dump_libvirt_xml())


if __name__ == '__main__':
    main()
