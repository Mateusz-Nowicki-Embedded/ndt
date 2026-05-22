#!/bin/bash
# Mirror third_party/blktests-fork into build/blktests/ and compile the
# C/C++ helpers in src/.  The mirror keeps the submodule working tree
# clean; build-initramfs.sh later stages build/blktests/ into the guest
# at /opt/blktests.
#
# Env overrides:
#   JOBS=8         override -j (default: nproc)

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)
SRC=$NDT/third_party/blktests-fork
BUILD=$NDT/build/blktests
JOBS=${JOBS:-$(nproc)}
CC=$HERE/gcc-c17

if [[ ! -x "$SRC/check" ]]; then
    echo "[build-blktests] error: $SRC/check not found" >&2
    echo "[build-blktests] hint: git submodule update --init third_party/blktests-fork" >&2
    exit 1
fi

echo "[build-blktests] source: ${SRC#$NDT/}"
echo "[build-blktests] output: ${BUILD#$NDT/}"
echo "[build-blktests] jobs:   $JOBS"
echo "[build-blktests] cc:     $CC"

mkdir -p "$BUILD"
rsync -a --delete \
    --exclude='.git' \
    --exclude='.github' \
    --exclude='results/' \
    "$SRC/" "$BUILD/"

make -C "$BUILD" -j"$JOBS" CC="$CC"

echo "[build-blktests] done: $BUILD/"
