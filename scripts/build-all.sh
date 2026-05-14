#!/bin/bash
# Build every component NDT needs to run a test, in dependency order.
#
# Output trees live under ndt/build/:
#   build/linux/                 -> out-of-tree kernel build (bzImage + modules)
#   build/qemu-host/             -> qemu-system-x86_64 binary
#   build/nvme-cli/              -> nvme binary (staged into initramfs)
#   build/blktests/              -> blktests checkout (staged into initramfs)
#
# After all builds finish, build-initramfs.sh repacks initramfs/rootfs +
# the freshly built binaries into initramfs/initramfs.cpio.gz.

set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

# TODO: implement individual build scripts and wire them up here.
"$HERE/build-kernel.sh"
"$HERE/build-qemu.sh"
"$HERE/build-blktests.sh"
"$HERE/build-nvme-cli.sh"
"$HERE/build-initramfs.sh"
