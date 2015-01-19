# Virtualization


The virtualization directory contains the tools which aims to standardize the way
we test an architecture in a virtual environment.

## Pre-requesites

```sh
$ pip install -r requirements.txt
```

### Collector

```sh
$ ./collector.py --help
usage: collector.py [-h] [--config-dir CONFIG_DIR] [--output-dir OUTPUT_DIR]
                    --sps-version SPS_VERSION

Generate virtual infrastructure description.

optional arguments:
  -h, --help            show this help message and exit
  --config-dir CONFIG_DIR
                        The config directory absolute path
  --output-dir OUTPUT_DIR
                        The output directory of the virtual configuration.
  --sps-version SPS_VERSION
                        The SpinalStack version.
```

### Virtualizor

```sh
usage: virtualizor.py [-h] [--replace] [--pub-key-file PUB_KEY_FILE] input_file target_host

Deploy a virtual infrastructure for Spinal Stack as described by collector.py output.

positional arguments:
  input_file            the input file.
  target_host           the libvirt server.

optional arguments:
  -h, --help            show this help message and exit
  --replace             Existing resources will be recreated.
  --pub-key-file PUB_KEY_FILE
                        SSH public key file.
```

### Example

```sh
$ ./config-tools/download.sh I.1.3.0 deployment-3nodes-D7.yml version=D7-I.1.3.0
```

It generates a directory 'top/' in the current directory.

```sh
$ ./collector.py --config-dir ./top/etc --sps-version D7-I.1.3.0
Virtual platform generated successfully at 'virt_platform.yml' !
```

It will generate a file 'virt_platform.yml' which describe the corresponding virtual
platform. You may take a look at a sample in the virtualization directory.

```sh
$ ./virtualizor.py virt_platform.yml my-hypervisor-node --replace --pub-key-file ~/.ssh/boa.pub
```
