#!/bin/bash

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)
SRC=$NDT/third_party/vnvme
KBUILD=$NDT/build/linux

if [[ ! -f "$SRC/Makefile" ]]; then
    echo "[build-vnvme] !!ERROR!!: $SRC/Makefile not found" >&2
    echo "[build-vnvme] hint: git submodule update --init third_party/fake-pcie-nvme-drive" >&2
    exit 1
fi

if [[ ! -f "$KBUILD/include/config/kernel.release" ]]; then
    echo "[build-vnvme] !!ERROR!!: kernel not built ($KBUILD)" >&2
    echo "[build-vnvme] hint: run scripts/build-kernel.sh first" >&2
    exit 1
fi

echo "[build-vnvme] source: ${SRC#$NDT/}"
echo "[build-vnvme] kbuild: ${KBUILD#$NDT/}"

make -C "$SRC" KDIR="$KBUILD"

echo "[build-vnvme] done: $SRC/vnvme.ko"
