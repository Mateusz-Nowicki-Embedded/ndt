#!/bin/bash
# Build the kernel from third_party/linux-fork using configs/linux-<flavor>.config.
# Output goes to build/linux/.
#
# Env overrides:
#   FLAVOR=debug|perf  pick config flavor (default: debug)

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)
KSRC=$NDT/third_party/linux-fork
BUILD=$NDT/build/linux
BZIMAGE_DST=$NDT/initramfs/bzImage
TARGETS="bzImage modules scripts_gdb"
FLAVOR=${FLAVOR:-debug}

case "$FLAVOR" in
    debug|perf) ;;
    *) echo "[build-kernel] bad FLAVOR=$FLAVOR (use debug|perf)" >&2; exit 2 ;;
esac

CFG=$NDT/configs/linux-${FLAVOR}.config
if [[ ! -f "$CFG" ]]; then
    echo "[build-kernel] error: config not found: $CFG" >&2
    exit 1
fi

echo "[build-kernel] flavor:  $FLAVOR"
echo "[build-kernel] config:  ${CFG#$NDT/}"
echo "[build-kernel] output:  ${BUILD#$NDT/}"
echo "[build-kernel] targets: $TARGETS"

mkdir -p "$BUILD"
cp "$CFG" "$BUILD/.config"
make -C "$KSRC" O="$BUILD" olddefconfig
# shellcheck disable=SC2086
make -C "$KSRC" O="$BUILD" -j"$(nproc)" $TARGETS

# Publish bzImage into initramfs/ so ndt.sh can boot a checked-in kernel
# without a build tree (see initramfs/initramfs.cpio.gz, shipped the same way).
cp "$BUILD/arch/x86/boot/bzImage" "$BZIMAGE_DST"

echo "[build-kernel] done: $BUILD/arch/x86/boot/bzImage"
echo "[build-kernel] published: ${BZIMAGE_DST#$NDT/}"
