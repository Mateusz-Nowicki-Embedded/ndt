#!/bin/bash
# Copy build/ artifacts into initramfs/rootfs and repack the cpio.gz.
#
# Pulls in:
#   build/linux/drivers/nvme/host/{nvme-core,nvme}.ko  -> /lib/modules/$KVER/
#   build/nvme-cli/nvme                                -> /usr/local/bin/
#   build/nvme-cli/libnvme/src/libnvme.so.3.0.0        -> /usr/lib64/
#   build/blktests/                                    -> /opt/blktests/
#
# Then repacks initramfs/rootfs into initramfs/initramfs.cpio.gz.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)
KBUILD=$NDT/build/linux
NVMECLI=$NDT/build/nvme-cli
BLKTESTS_SRC=$NDT/third_party/blktests-fork
BLKTESTS_BIN=$NDT/build/blktests
PCIMEM=$NDT/build/pcimem
ROOTFS=$NDT/initramfs/rootfs
CPIO=$NDT/initramfs/initramfs.cpio.gz

for d in "$KBUILD" "$NVMECLI" "$BLKTESTS_SRC" "$BLKTESTS_BIN" "$PCIMEM"; do
    if [[ ! -d "$d" ]]; then
        echo "[build-initramfs] missing: $d" >&2
        echo "[build-initramfs] hint: run ./build-all.sh first" >&2
        exit 1
    fi
done

if [[ ! -f "$KBUILD/include/config/kernel.release" ]]; then
    echo "[build-initramfs] kernel not built (no include/config/kernel.release)" >&2
    exit 1
fi
KVER=$(cat "$KBUILD/include/config/kernel.release")

echo "[build-initramfs] rootfs: ${ROOTFS#$NDT/}"
echo "[build-initramfs] kver:   $KVER"

# 1. Kernel modules (drop stale tree first)
echo "[build-initramfs] copy kernel modules"
rm -rf "$ROOTFS/lib/modules"
mkdir -p "$ROOTFS/lib/modules/$KVER/kernel/drivers/nvme/host"
cp "$KBUILD/drivers/nvme/host/nvme-core.ko" \
    "$KBUILD/drivers/nvme/host/nvme.ko" \
    "$ROOTFS/lib/modules/$KVER/kernel/drivers/nvme/host/"

# nvmet target stack (only copy what's actually built).
NVMET_KO=$KBUILD/drivers/nvme/target/nvmet.ko
if [[ -f "$NVMET_KO" ]]; then
    mkdir -p "$ROOTFS/lib/modules/$KVER/kernel/drivers/nvme/target"
    cp "$NVMET_KO" "$ROOTFS/lib/modules/$KVER/kernel/drivers/nvme/target/"
    for opt in nvme-loop.ko nvmet-tcp.ko nvmet-rdma.ko nvmet-fc.ko; do
        [[ -f "$KBUILD/drivers/nvme/target/$opt" ]] &&
            cp "$KBUILD/drivers/nvme/target/$opt" \
                "$ROOTFS/lib/modules/$KVER/kernel/drivers/nvme/target/"
    done
fi

# null_blk backing for nvmet namespaces.
NULL_BLK_KO=$KBUILD/drivers/block/null_blk/null_blk.ko
[[ -f "$NULL_BLK_KO" ]] || NULL_BLK_KO=$KBUILD/drivers/block/null_blk.ko
if [[ -f "$NULL_BLK_KO" ]]; then
    mkdir -p "$ROOTFS/lib/modules/$KVER/kernel/drivers/block"
    cp "$NULL_BLK_KO" "$ROOTFS/lib/modules/$KVER/kernel/drivers/block/"
fi

# configfs (nvmet's port/subsys/namespace API is configfs-only).
CONFIGFS_KO=$KBUILD/fs/configfs/configfs.ko
if [[ -f "$CONFIGFS_KO" ]]; then
    mkdir -p "$ROOTFS/lib/modules/$KVER/kernel/fs/configfs"
    cp "$CONFIGFS_KO" "$ROOTFS/lib/modules/$KVER/kernel/fs/configfs/"
fi
for f in modules.order modules.builtin modules.builtin.modinfo; do
    [[ -f "$KBUILD/$f" ]] && cp "$KBUILD/$f" "$ROOTFS/lib/modules/$KVER/"
done

# Out-of-tree nvmet-pci-sw module — software NVMe PCIe endpoint.
NPS_KO=$NDT/third_party/nvmet-pci-sw/nvmet-pci-sw.ko
if [[ -f "$NPS_KO" ]]; then
    mkdir -p "$ROOTFS/lib/modules/$KVER/extra"
    cp "$NPS_KO" "$ROOTFS/lib/modules/$KVER/extra/"
    echo "[build-initramfs] copy out-of-tree: nvmet-pci-sw.ko"
else
    echo "[build-initramfs] warn: $NPS_KO not built, skipping" >&2
fi

depmod -b "$ROOTFS" "$KVER"

# 2. nvme-cli binary + libnvme
echo "[build-initramfs] copy nvme-cli"
install -D -m 755 "$NVMECLI/nvme" "$ROOTFS/usr/local/bin/nvme"
mkdir -p "$ROOTFS/usr/lib64"
rm -f "$ROOTFS/usr/lib64/libnvme.so"*
install -m 755 "$NVMECLI/libnvme/src/libnvme.so.3.0.0" "$ROOTFS/usr/lib64/"
ln -s libnvme.so.3.0.0 "$ROOTFS/usr/lib64/libnvme.so.3"

# 2b. pcimem — direct mmap-based BAR poke (MSI-X mask manipulation etc.)
echo "[build-initramfs] copy pcimem"
install -D -m 755 "$PCIMEM/pcimem" "$ROOTFS/usr/local/bin/pcimem"

# 3. blktests: source tree from third_party + out-of-tree binaries on top
echo "[build-initramfs] copy blktests"
rm -rf "$ROOTFS/opt/blktests"
mkdir -p "$ROOTFS/opt"
rsync -a --exclude='.git*' --exclude='.github' "$BLKTESTS_SRC/" "$ROOTFS/opt/blktests/"
rsync -a "$BLKTESTS_BIN/" "$ROOTFS/opt/blktests/src/"
cat >"$ROOTFS/opt/blktests/config" <<'EOF'
TEST_DEVS=(/dev/nvme0n1)
NORMAL_USER=nobody
EOF

# 4. Repack
echo "[build-initramfs] pack cpio.gz"
(cd "$ROOTFS" &&
    find . -print0 | cpio --null --create --format=newc 2>/dev/null |
    gzip -9 >"$CPIO")

sz=$(du -h "$CPIO" | cut -f1)
echo "[build-initramfs] done: ${CPIO#$NDT/} ($sz)"
