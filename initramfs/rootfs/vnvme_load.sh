#!/bin/bash

set -uo pipefail

mkdir -p /sys/kernel/config/nvmet/subsystems/vnvme-ss
echo 1 > /sys/kernel/config/nvmet/subsystems/vnvme-ss/attr_allow_any_host
mkdir /sys/kernel/config/nvmet/subsystems/vnvme-ss/namespaces/1
echo /dev/nullb0 > /sys/kernel/config/nvmet/subsystems/vnvme-ss/namespaces/1/device_path
echo 1 > /sys/kernel/config/nvmet/subsystems/vnvme-ss/namespaces/1/enable

insmod /lib/modules/extra/vnvme.ko \
    bar0_phys=0x100000000 \
    bar0_size=0x10000 \
    s_vid=0x1AF4 \
    s_did=0x10F0 \
    e_vid=0x1AF4 \
    e_did=0x10F1

# configure settings from vnvme side
echo -n vnvme-ss > /sys/kernel/config/vnvme/subsysnqn
echo 1 > /sys/kernel/config/vnvme/portid

# connect vnvme with nvmet
mkdir /sys/kernel/config/nvmet/ports/1
echo -n pci > /sys/kernel/config/nvmet/ports/1/addr_trtype
ln -s /sys/kernel/config/nvmet/subsystems/vnvme-ss /sys/kernel/config/nvmet/ports/1/subsystems/vnvme-ss
