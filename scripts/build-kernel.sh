#!/bin/bash
# Build the kernel from third_party/linux-fork using the matching
# config from configs/linux-v<tag>.config.  Output goes to build/linux/.
#
# Env overrides:
#   JOBS=8         override -j (default: nproc)
#   CFG=<path>     override config (default: configs/linux-v<tag>.config)

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)
KSRC=$NDT/third_party/linux-fork
BUILD=$NDT/build/linux
JOBS=${JOBS:-$(nproc)}
TARGETS="bzImage modules scripts_gdb"
# GCC 15 defaults to C23 where false/true/bool are keywords; kernels <=v6.9
# define them as enum/typedef and won't build.  Wrap CC to force gnu17 in
# every sub-Makefile (KCFLAGS alone misses subdirs with custom CFLAGS).
CC=$HERE/gcc-c17

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

echo "[build-kernel] cc:      $CC"

mkdir -p "$BUILD"
cp "$CFG" "$BUILD/.config"
make -C "$KSRC" O="$BUILD" CC="$CC" olddefconfig
# shellcheck disable=SC2086
make -C "$KSRC" O="$BUILD" CC="$CC" -j"$JOBS" $TARGETS

echo "[build-kernel] done: $BUILD/arch/x86/boot/bzImage"
