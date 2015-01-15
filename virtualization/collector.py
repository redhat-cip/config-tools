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

"""Collector.

Usage:
  collector (--config-dir=<path>) [--output-dir=<path>]
  collector (-h | --help)
  collector --version

Options:
  --config-dir=<path>   The config directory absolute path
                        [default: ./top/etc].
  --output-dir=<path>   The output dir of the virtual configuration
                        [default: ./].
  -h --help             Show this screen.
  --version             Show version.
"""

from hardware.generate import generate # noqa
from hardware import matcher

import copy
import netaddr
import os
import sys

import docopt
import yaml

_VERSION = "0.0.1"


def _get_content(path):
    try:
        with open(path, "r") as f:
            return f.read()
    except (OSError, IOError) as e:
        print("Error: cannot open or read file '%s': %s" % (path, e))
        sys.exit(1)


def _eval_python_file(path):
    file_content = _get_content(path)

    return eval(file_content)


def _get_default_network(cmdb_machines):
    first_machine = cmdb_machines[0]
    netmask = first_machine["netmask"]
    net_address = netaddr.IPNetwork("%s/%s" % (first_machine["ip"], netmask))
    net_address = str(net_address.network)

    return {"name": "default",
            "address": net_address,
            "netmask": netmask}


def _get_disks(specs):
    disks = []
    info = {}
    while matcher.match_spec(('disk', '$disk', 'size', '$gb'),
                             specs, info):
        disks_size = "%sG" % info['gb']
        disks.append({"size": disks_size})
        info = {}
    return disks


def _get_nics(configuration):
    all_macs = [configuration[mac] for mac in configuration
                if mac.startswith("mac")]
    nics = []
    for i in xrange(len(all_macs)):
        eth_name = "eth%s" % i
        nics.append({"name": eth_name,
                     "mac": all_macs[i],
                     "network": "default"})

    return nics


def collect(config_path):
    # check config directory path
    if not os.path.exists(config_path):
        print("Error: --config-dir='%s' does not exist." % config_path)
        sys.exit(1)

    # get state file
    state_profiles = _eval_python_file("%s/edeploy/state" % config_path)

    # the virtual configuration of each host
    virt_platform = {"hosts": {}}

    for profile in state_profiles:
        profile_name = profile[0]
        number_of_profile = profile[1]

        # source the cmdb file
        cmdb_file_path = "%s/edeploy/%s.cmdb" % (config_path, profile_name)
        cmdb_machines = _eval_python_file(cmdb_file_path)

        # source the specs file
        spec_file_path = "%s/edeploy/%s.specs" % (config_path, profile_name)
        specs = _eval_python_file(spec_file_path)

        # get the default network address from the cmdb
        virt_platform["networks"] = [_get_default_network(cmdb_machines)]

        # get the number of disk and their size from the specs file
        disks = _get_disks(specs)

        # loop over the number of profile
        for _ in xrange(number_of_profile):
            # retrieve one configuration not yet assigned
            for configuration in cmdb_machines:
                hostname = configuration["hostname"]
                if hostname in virt_platform["hosts"]:
                    continue
                # construct the host virtual configuration
                virt_platform["hosts"][hostname] = {}
                # add the disks
                virt_platform["hosts"][hostname]["disks"] = \
                    copy.deepcopy(disks)
                # add the nics
                virt_platform["hosts"][hostname]["nics"] = _get_nics(
                    configuration)
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


def main(args=None):
    cli_arguments = docopt.docopt(__doc__,
                                  argv=args or sys.argv[1:],
                                  version="Collector %s" % _VERSION)
    virt_platform = collect(cli_arguments["--config-dir"])
    save_virt_platform(virt_platform, cli_arguments["--output-dir"])


if __name__ == '__main__':
    main(sys.argv[1:])
