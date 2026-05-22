#!/bin/bash
# Build blktests in build/blktests/.
# build-initramfs.sh later copies the result into the guest at /opt/blktests.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)
SRC=$NDT/third_party/blktests-fork
BUILD=$NDT/build/blktests

if [[ ! -x "$SRC/check" ]]; then
    echo "[build-blktests] error: $SRC/check not found" >&2
    echo "[build-blktests] hint: git submodule update --init third_party/blktests-fork" >&2
    exit 1
fi

echo "[build-blktests] source: ${SRC#$NDT/}"
echo "[build-blktests] output: ${BUILD#$NDT/}"

mkdir -p "$BUILD"
make -C "$SRC/src" -j"$(nproc)" O="$BUILD"

echo "[build-blktests] done: $BUILD/"
