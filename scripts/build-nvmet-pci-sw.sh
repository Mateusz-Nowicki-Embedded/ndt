#!/bin/bash
# Build the nvmet-pci-sw out-of-tree module against build/linux.
#
# Output: third_party/nvmet-pci-sw/nvmet-pci-sw.ko
# build-initramfs.sh picks it up and stages into rootfs/lib/modules/<KVER>/extra/.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)
SRC=$NDT/third_party/nvmet-pci-sw
KBUILD=$NDT/build/linux

if [[ ! -f "$SRC/Makefile" ]]; then
    echo "[build-nvmet-pci-sw] error: $SRC/Makefile not found" >&2
    echo "[build-nvmet-pci-sw] hint: git submodule update --init third_party/nvmet-pci-sw" >&2
    exit 1
fi

if [[ ! -f "$KBUILD/include/config/kernel.release" ]]; then
    echo "[build-nvmet-pci-sw] error: kernel not built ($KBUILD)" >&2
    echo "[build-nvmet-pci-sw] hint: run scripts/build-kernel.sh first" >&2
    exit 1
fi

echo "[build-nvmet-pci-sw] source: ${SRC#$NDT/}"
echo "[build-nvmet-pci-sw] kbuild: ${KBUILD#$NDT/}"

make -C "$SRC" KDIR="$KBUILD"

echo "[build-nvmet-pci-sw] done: $SRC/nvmet-pci-sw.ko"
