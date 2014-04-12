Config Tools
============

Config Tools are a set of tools to use puppet to configure a set of
nodes with complex configuration using a step by step approach. Each
step is validated by serverspec tests before going to the next
step. If the tests of a step fail, puppet is called again on all the
nodes.

Pre-requesites
++++++++++++++

You need puppet already installed on all the nodes and on the puppet
master. All the nodes must be reachable using ssh from the puppet
master without interaction.

On the puppet master, you need to have the following installed:

- make
- python with the jinja2 and yaml modules
- rake
- serverspec

Config files
++++++++++++

Serverspec tests must be under ``/etc/serverspec``.

Puppet files are under ``/etc/puppet``.

The puppet manifests and the YAML file describing the tests must be
Jinja2 templates in ``/etc/puppet/manifest/site.pp.tmpl``,
``/etc/puppet/manifest/params.pp.tmpl`` and
``/etc/serverspec/arch.yml.tmpl``.

Configuration is centralized in ``/etc/config-tools/global.yaml``.
