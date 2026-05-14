#!/bin/bash
# Build QEMU from third_party/qemu-nvme into build/qemu-host/.
# Output binary: build/qemu-host/qemu-system-x86_64
#
# Env overrides:
#   JOBS=8                 override -j (default: nproc)
#   EXTRA_CONFIGURE=...    extra args passed to QEMU's ./configure
#   RECONFIGURE=1          force a re-run of ./configure before make

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)
QSRC=$NDT/third_party/qemu-nvme
BUILD=$NDT/build/qemu-host
JOBS=${JOBS:-$(nproc)}

if [[ ! -f "$QSRC/configure" ]]; then
    echo "[build-qemu] error: $QSRC/configure not found" >&2
    echo "[build-qemu] hint: git submodule update --init third_party/qemu-nvme" >&2
    exit 1
fi

echo "[build-qemu] source: ${QSRC#$NDT/}"
echo "[build-qemu] output: ${BUILD#$NDT/}"
echo "[build-qemu] jobs:   $JOBS"

mkdir -p "$BUILD"

if [[ ! -f "$BUILD/build.ninja" || "${RECONFIGURE:-0}" == "1" ]]; then
    echo "[build-qemu] configuring..."
    (
        cd "$BUILD"
        "$QSRC/configure" \
            --target-list=x86_64-softmmu \
            --enable-kvm \
            --disable-docs \
            --disable-werror \
            ${EXTRA_CONFIGURE:-}
    )
fi

echo "[build-qemu] building..."
make -C "$BUILD" -j"$JOBS"

echo "[build-qemu] done: $BUILD/qemu-system-x86_64"
