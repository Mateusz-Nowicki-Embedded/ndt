#!/bin/bash
# Build pcimem from third_party/pcimem into build/pcimem/pcimem.
#
# Single C file, no deps beyond libc.  Used by the in-guest tests to
# read/write PCI BAR memory directly — e.g. set/clear the MSI-X mask
# bit in the controller's MSI-X table without driver cooperation.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)
SRC=$NDT/third_party/pcimem
BUILD=$NDT/build/pcimem

if [[ ! -f "$SRC/pcimem.c" ]]; then
    echo "[build-pcimem] error: $SRC/pcimem.c not found" >&2
    echo "[build-pcimem] hint: git submodule update --init third_party/pcimem" >&2
    exit 1
fi

echo "[build-pcimem] source: ${SRC#$NDT/}"
echo "[build-pcimem] output: ${BUILD#$NDT/}"

mkdir -p "$BUILD"
gcc -Wall -O2 "$SRC/pcimem.c" -o "$BUILD/pcimem"

echo "[build-pcimem] done: $BUILD/pcimem"
