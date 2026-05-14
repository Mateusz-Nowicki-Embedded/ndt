#!/bin/bash
# Build the kernel from third_party/linux-fork using the matching
# config from configs/linux-v<tag>.config.  Output goes to build/linux/.
#
# Env overrides:
#   JOBS=8         override -j (default: nproc)
#   CFG=<path>     override config (default: configs/linux-v<tag>.config)
#   TARGETS=...    override make targets (default: "bzImage modules")

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)
KSRC=$NDT/third_party/linux-fork
BUILD=$NDT/build/linux
JOBS=${JOBS:-$(nproc)}
TARGETS=${TARGETS:-bzImage modules}

if ! tag=$(git -C "$KSRC" describe --tags --exact-match HEAD 2>/dev/null); then
    echo "[build-kernel] error: third_party/linux-fork is not at a tagged commit" >&2
    echo "[build-kernel] HEAD: $(git -C "$KSRC" rev-parse --short HEAD)" >&2
    echo "[build-kernel] hint: pass CFG=<path> to use a custom config" >&2
    [[ -z "${CFG:-}" ]] && exit 1
fi

CFG=${CFG:-$NDT/configs/linux-${tag}.config}
if [[ ! -f "$CFG" ]]; then
    echo "[build-kernel] error: config not found: $CFG" >&2
    echo "[build-kernel] hint: see configs/README.md to seed a new version" >&2
    exit 1
fi

echo "[build-kernel] kernel:  ${tag:-untagged} ($(git -C "$KSRC" rev-parse --short HEAD))"
echo "[build-kernel] config:  ${CFG#$NDT/}"
echo "[build-kernel] output:  ${BUILD#$NDT/}"
echo "[build-kernel] jobs:    $JOBS"
echo "[build-kernel] targets: $TARGETS"

mkdir -p "$BUILD"
cp "$CFG" "$BUILD/.config"
make -C "$KSRC" O="$BUILD" olddefconfig
# shellcheck disable=SC2086
make -C "$KSRC" O="$BUILD" -j"$JOBS" $TARGETS

echo "[build-kernel] done: $BUILD/arch/x86/boot/bzImage"
