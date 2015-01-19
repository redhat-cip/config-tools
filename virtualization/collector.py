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

from hardware.generate import generate  # noqa
from hardware.generate import generate_dict  # noqa
from hardware import matcher

import copy
import netaddr
import os
import sys

import argparse
import yaml

_VERSION = "0.0.1"


def _get_content(path):
    try:
        with open(path, "r") as f:
            return f.read()
    except (OSError, IOError) as e:
        print("Error: cannot open or read file '%s'" % path)
        sys.exit(1)


def _eval_python_file(path):
    file_content = _get_content(path)

    return eval(file_content)


def _get_yaml_content(path):
    try:
        with open(path, "r") as f:
            return yaml.load(f)
    except (OSError, IOError) as e:
        print("Error: cannot open or read file '%s': %s" % (path, e))
        sys.exit(1)


def _get_disks(specs):
    disks = []
    info = {}
    while matcher.match_spec(('disk', '$disk', 'size', '$gb'), specs, info):
        disks_size = "%sG" % info['gb']
        disks.append({"size": disks_size})
        info = {}
    return disks


def _get_nics(global_host):

    nics = []
    for mac in global_host["cmdb"]:
        if mac.startswith("mac"):
            nics.append({"mac": global_host["cmdb"][mac]})
    return nics


def _is_in_cmdb(hostname, cmdb_machines):
    for machine in cmdb_machines:
        if machine["hostname"] == hostname:
            return True
    return False


def collect(config_path):
    # check config directory path
    if not os.path.exists(config_path):
        print("Error: --config-dir='%s' does not exist." % config_path)
        sys.exit(1)

    # get state file
    state_profiles = _eval_python_file("%s/edeploy/state" % config_path)

    # get global conf
    global_conf = _get_yaml_content("%s/config-tools/global.yml" % config_path)
    # expand keys prefixed by "="
    global_conf["hosts"] = generate_dict(global_conf["hosts"], "=")

    # the virtual configuration of each host
    virt_platform = {"hosts": {}}

    for profile_name, _ in state_profiles:

        # source the cmdb file
        cmdb_file_path = "%s/edeploy/%s.cmdb" % (config_path, profile_name)
        cmdb_machines = _eval_python_file(cmdb_file_path)

        # source the specs file
        spec_file_path = "%s/edeploy/%s.specs" % (config_path, profile_name)
        specs = _eval_python_file(spec_file_path)

        # get the number of disk and their size from the specs file
        disks = _get_disks(specs)

        # loop over the number of profile
        for _ in xrange(len(global_conf["hosts"])):
            # retrieve one configuration not yet assigned
            for hostname in global_conf["hosts"]:
                if hostname in virt_platform["hosts"]:
                    continue
                if not _is_in_cmdb(hostname, cmdb_machines):
                    continue
                # construct the host virtual configuration
                virt_platform["hosts"][hostname] = {}
                # add the disks
                virt_platform["hosts"][hostname]["disks"] = \
                    copy.deepcopy(disks)
                # add the profile
                virt_platform["hosts"][hostname]["profile"] = \
                    global_conf["hosts"][hostname]["profile"]

                if virt_platform["hosts"][hostname]["profile"] == \
                        "install-server":
                    break
                # add the nics
                virt_platform["hosts"][hostname]["nics"] = \
                    _get_nics(global_conf["hosts"][hostname])
                break

    # so far, the nodes are described excepted the install-server
    # the code below adds the install-server from the global conf.
    for hostname in global_conf["hosts"]:
        if global_conf["hosts"][hostname]["profile"] == "install-server":
            # add the admin_network config
            admin_network = global_conf["config"]["admin_network"]
            admin_network = netaddr.IPNetwork(admin_network)
            nics = [{"name": "eth0",
                     "ip": global_conf["hosts"][hostname]["ip"],
                     "network": str(admin_network.network),
                     "netmask": str(admin_network.netmask)}]
            virt_platform["hosts"][hostname]["nics"] = nics
            break

    return virt_platform


def save_virt_platform(virt_platform, output_path):
    output_file_path = os.path.normpath("%s/virt_platform.yml" % output_path)

    try:
        with open(output_file_path, 'w') as outfile:
            outfile.write(yaml.dump(virt_platform, default_flow_style=False))
        print "Virtual platform generated successfully at '%s' !" % \
              output_file_path
    except (OSError, IOError) as e:
        print("Error: cannot write file '%s': %s" % (output_file_path, e))
        sys.exit(1)


def main():
    cli_parser = argparse.ArgumentParser(
        description='Collect architecture information from the edeploy '
        'directory as generated by config-tools/download.sh.')
    cli_parser.add_argument('--config-dir',
                            default="./top/etc",
                            help='The config directory absolute path.')
    cli_parser.add_argument('--output-dir',
                            default="./",
                            help='The output directory of the virtual'
                                 ' configuration.')
    cli_parser.add_argument('--sps-version',
                            required=True,
                            help='The SpinalStack version.')
    cli_arguments = cli_parser.parse_args()

    virt_platform = collect(cli_arguments.config_dir)
    virt_platform["version"] = cli_arguments.sps_version
    save_virt_platform(virt_platform,
                       cli_arguments.output_dir)


if __name__ == '__main__':
    main()
