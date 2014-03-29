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
- serverspec
- cpp (The C pre-processor)

Config files
++++++++++++

Serverspec tests must be under ``/etc/serverspec``.

Puppet files are under ``/etc/puppet``.

The puppet manifest and the YAML file describing the tests must be
augmented with C pre-processor blocks in
``/etc/puppet/manifest/site.cpp`` and
``/etc/serverspec/arch.cyml``. Steps are defined with pre-processor
blocks like this::

  # if STEP >= 2
    <my block>
  # endif

The steps must be in synchro between ``site.cpp`` and ``arch.cyml``.

A file defining the nodes and various config options needs to be put
in ``/etc/puppet/manifests/hosts.cpp``. For example::

  #define PUPPETMASTER 'master'
  #define LB 'lb'
  #define MGT1 'mgt1'
  #define MGT2 'mgt2'
  #define MGT3 'mgt3'
  #define COMPUTE1 'cmpt1'
  #define COMPUTE2 'cmpt2'
  #define COMPUTE3 'cmpt3'
  #define PREFIX '192.168.122'
  #define DOMAIN 'lab.net'
  #define USER 'jenkins'
  #define HOSTS LB MGT1 MGT2 MGT3 COMPUTE1 COMPUTE2 COMPUTE3
  #define PARALLELSTEPS "2|4|5"
