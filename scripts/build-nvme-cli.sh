#!/bin/bash
# Build nvme-cli (with bundled libnvme) from third_party/nvme-cli-fork
# into build/nvme-cli/.  Output binary: build/nvme-cli/nvme.
#
# nvme-cli uses meson + ninja and vendors libnvme as a subdirectory,
# so a single meson run produces both the libnvme.so and the nvme tool.
#
# Env overrides:
#   JOBS=8           override -j (default: nproc)
#   RECONFIGURE=1    force meson setup --reconfigure before compile

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)
SRC=$NDT/third_party/nvme-cli-fork
BUILD=$NDT/build/nvme-cli
JOBS=${JOBS:-$(nproc)}

if [[ ! -f "$SRC/meson.build" ]]; then
    echo "[build-nvme-cli] error: $SRC/meson.build not found" >&2
    echo "[build-nvme-cli] hint: git submodule update --init third_party/nvme-cli-fork" >&2
    exit 1
fi

echo "[build-nvme-cli] source: ${SRC#$NDT/}"
echo "[build-nvme-cli] output: ${BUILD#$NDT/}"
echo "[build-nvme-cli] jobs:   $JOBS"

if [[ ! -f "$BUILD/build.ninja" ]]; then
    meson setup "$BUILD" "$SRC" --buildtype=release
elif [[ "${RECONFIGURE:-0}" == "1" ]]; then
    meson setup --reconfigure "$BUILD" "$SRC" --buildtype=release
fi

meson compile -C "$BUILD" -j "$JOBS"

echo "[build-nvme-cli] done: $BUILD/nvme"
