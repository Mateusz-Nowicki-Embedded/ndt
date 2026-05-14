#!/bin/bash
# Rebuild NVMe modules, stage them in initramfs, regenerate modules.dep,
# and repack initramfs.cpio.gz so that the next QEMU boot picks up the change.
#
# Usage:
#   ./refresh-nvme-mod.sh                # full cycle: build + stage + depmod + repack
#   NO_BUILD=1   ./refresh-nvme-mod.sh   # skip kernel build, only restage from existing .ko
#   NO_REPACK=1  ./refresh-nvme-mod.sh   # skip cpio repack (e.g. when staging more files)
#   JOBS=8       ./refresh-nvme-mod.sh   # override -j (default: nproc)

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)

BUILD_DIR=${BUILD_DIR:-$NDT/build/linux}
KSRC=${KSRC:-$NDT/third_party/linux-fork}
ROOTFS=${ROOTFS:-$NDT/initramfs/rootfs}
INITRAMFS=${INITRAMFS:-$NDT/initramfs/initramfs.cpio.gz}
JOBS=${JOBS:-$(nproc)}

KVER=$(make -s -C "$BUILD_DIR" kernelrelease)
NVME_HOST="$BUILD_DIR/drivers/nvme/host"
MOD_DST="$ROOTFS/lib/modules/$KVER/kernel/drivers/nvme/host"

echo "[refresh] kernel: $KVER"
echo "[refresh] build:  $BUILD_DIR"
echo "[refresh] rootfs: $ROOTFS"

if [[ "${NO_BUILD:-0}" != "1" ]]; then
    echo "[refresh] building modules (-j$JOBS)..."
    # In-tree narrow build: ask for the nvme/host directory targets directly.
    # 'M=' is reserved for *external* modules with their own Makefile, so don't use it here.
    make -C "$BUILD_DIR" -j"$JOBS" drivers/nvme/host/ >/dev/null
fi

echo "[refresh] staging .ko"
mkdir -p "$MOD_DST"
cp "$NVME_HOST/nvme-core.ko" "$NVME_HOST/nvme.ko" "$MOD_DST/"

# These come from the kernel build and are needed for clean depmod runs.
for f in modules.order modules.builtin modules.builtin.modinfo; do
    [[ -f "$BUILD_DIR/$f" ]] && cp "$BUILD_DIR/$f" "$ROOTFS/lib/modules/$KVER/"
done

echo "[refresh] depmod"
depmod -b "$ROOTFS" "$KVER"

if [[ "${NO_REPACK:-0}" != "1" ]]; then
    echo "[refresh] repacking $INITRAMFS"
    ( cd "$ROOTFS" && \
      find . -print0 | cpio --null --create --format=newc 2>/dev/null | \
      gzip -9 > "$INITRAMFS" )
    sz=$(du -h "$INITRAMFS" | cut -f1)
    echo "[refresh] done: $INITRAMFS ($sz)"
else
    echo "[refresh] skipping repack (NO_REPACK=1)"
fi
