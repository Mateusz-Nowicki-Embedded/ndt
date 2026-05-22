#!/bin/bash
# Build every component NDT needs to run a test, in dependency order.
#
# Output trees live under ndt/build/:
#   build/linux/                 -> out-of-tree kernel build (bzImage + modules)
#   build/qemu-host/             -> qemu-system-x86_64 binary
#   build/nvme-cli/              -> nvme binary (copied into initramfs)
#   build/blktests/              -> blktests checkout (copied into initramfs)
#
# After all builds finish, build-initramfs.sh repacks initramfs/rootfs +
# the freshly built binaries into initramfs/initramfs.cpio.gz.
#
# NVMe namespaces are provided by the in-guest nvmet-pci-sw + null_blk
# stack (see initramfs/rootfs/init), so there is no per-NS disk image
# to materialise here any more.

set -euo pipefail
NDT=$(cd "$(dirname "$0")" && pwd)
export NDT

"$NDT/scripts/build-kernel.sh"
"$NDT/scripts/build-nvmet-pci-sw.sh"
"$NDT/scripts/build-qemu.sh"
"$NDT/scripts/build-blktests.sh"
"$NDT/scripts/build-nvme-cli.sh"
"$NDT/scripts/build-pcimem.sh"
"$NDT/scripts/build-initramfs.sh"
