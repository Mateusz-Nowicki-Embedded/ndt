#!/bin/bash
# Stage build/ artifacts into initramfs/rootfs and repack the cpio.gz.
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
BLKTESTS=$NDT/build/blktests
ROOTFS=$NDT/initramfs/rootfs
CPIO=$NDT/initramfs/initramfs.cpio.gz

for d in "$KBUILD" "$NVMECLI" "$BLKTESTS"; do
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
echo "[build-initramfs] stage kernel modules"
rm -rf "$ROOTFS/lib/modules"
mkdir -p "$ROOTFS/lib/modules/$KVER/kernel/drivers/nvme/host"
cp "$KBUILD/drivers/nvme/host/nvme-core.ko" \
   "$KBUILD/drivers/nvme/host/nvme.ko" \
   "$ROOTFS/lib/modules/$KVER/kernel/drivers/nvme/host/"
for f in modules.order modules.builtin modules.builtin.modinfo; do
    [[ -f "$KBUILD/$f" ]] && cp "$KBUILD/$f" "$ROOTFS/lib/modules/$KVER/"
done
depmod -b "$ROOTFS" "$KVER"

# blktests' _have_kernel_options runs zgrep on /proc/config.gz (exposed by
# CONFIG_IKCONFIG_PROC) — ship the wrapper so it can do that.
install -D -m 755 /usr/bin/zgrep "$ROOTFS/usr/bin/zgrep"

# 2. nvme-cli binary + libnvme
echo "[build-initramfs] stage nvme-cli"
install -D -m 755 "$NVMECLI/nvme" "$ROOTFS/usr/local/bin/nvme"
mkdir -p "$ROOTFS/usr/lib64"
rm -f "$ROOTFS/usr/lib64/libnvme.so"*
install -m 755 "$NVMECLI/libnvme/src/libnvme.so.3.0.0" "$ROOTFS/usr/lib64/"
ln -s libnvme.so.3.0.0 "$ROOTFS/usr/lib64/libnvme.so.3"

# 3. blktests source + helpers
echo "[build-initramfs] stage blktests"
rm -rf "$ROOTFS/opt/blktests"
mkdir -p "$ROOTFS/opt"
rsync -a --exclude='.git*' "$BLKTESTS/" "$ROOTFS/opt/blktests/"
cat > "$ROOTFS/opt/blktests/config" <<'EOF'
# nvme0n2: 256 MiB, no metadata (default test target for most tests).
# nvme0n3: 256 MiB, ms=8 mset=0 (metadata-formatted, exercises nvme/064).
TEST_DEVS=(/dev/nvme0n2 /dev/nvme0n3)
# Unprivileged user used by tests like nvme/046; see initramfs/rootfs/etc/passwd.
NORMAL_USER=nobody
EOF

# 4. Repack
echo "[build-initramfs] pack cpio.gz"
( cd "$ROOTFS" && \
  find . -print0 | cpio --null --create --format=newc 2>/dev/null | \
  gzip -9 > "$CPIO" )

sz=$(du -h "$CPIO" | cut -f1)
echo "[build-initramfs] done: ${CPIO#$NDT/} ($sz)"
