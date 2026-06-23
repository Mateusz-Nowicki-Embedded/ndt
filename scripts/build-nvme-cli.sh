#!/bin/bash
# Build nvme-cli (with bundled libnvme) from third_party/nvme-cli-fork
# into build/nvme-cli/.  Output binary: build/nvme-cli/nvme.
#
# nvme-cli uses meson + ninja and vendors libnvme as a subdirectory,
# so a single meson run produces both the libnvme.so and the nvme tool.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)
SRC=$NDT/third_party/nvme-cli-fork
BUILD=$NDT/build/nvme-cli

if [[ ! -f "$SRC/meson.build" ]]; then
    echo "[build-nvme-cli] error: $SRC/meson.build not found" >&2
    echo "[build-nvme-cli] hint: git submodule update --init third_party/nvme-cli-fork" >&2
    exit 1
fi

echo "[build-nvme-cli] source: ${SRC#$NDT/}"
echo "[build-nvme-cli] output: ${BUILD#$NDT/}"

# JSON output (`nvme ... -o json`) needs json-c.  Force the meson feature to
# 'enabled' so the build fails loudly if it is missing instead of silently
# dropping JSON support (the upstream default is 'auto').
if ! pkg-config --exists json-c; then
    echo "[build-nvme-cli] error: json-c not found (required for JSON output)" >&2
    echo "[build-nvme-cli] hint: install libjson-c-dev (apt) / dev-libs/json-c (emerge)" >&2
    exit 1
fi

# -Djson-c=enabled must be applied even to an already-configured tree, hence
# --reconfigure on the second run.
meson_opts=( --buildtype=release -Djson-c=enabled )
if [[ ! -f "$BUILD/build.ninja" ]]; then
    meson setup "$BUILD" "$SRC" "${meson_opts[@]}"
else
    meson setup --reconfigure "$BUILD" "$SRC" "${meson_opts[@]}"
fi

meson compile -C "$BUILD" -j "$(nproc)"

echo "[build-nvme-cli] done: $BUILD/nvme"
