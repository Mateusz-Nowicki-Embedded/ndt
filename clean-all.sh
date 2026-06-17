#!/bin/bash
# Remove all build outputs produced by build-all.sh.
#
# Removes:
#   build/                    everything built by build-all.sh
#
# Leaves alone:
#   initramfs/                tracked in git (source of truth)
#   third_party/              submodules
#
# Idempotent: safe to re-run.

set -euo pipefail
NDT=$(cd "$(dirname "$0")" && pwd)
export NDT

for arg in "$@"; do
    case "$arg" in
    -h | --help)
        awk 'NR==1{next} /^#/{sub(/^#[ \t]?/,""); print; next} {exit}' "$0"
        exit 0
        ;;
    *)
        echo "[clean-all] unknown arg: $arg" >&2
        exit 2
        ;;
    esac
done

# Out-of-tree module artefacts (.ko/.o) live inside the submodule tree,
# not under build/.  Wipe them via the module's own clean target.
VNVME_SRC=$NDT/third_party/vnvme
if [[ -f "$VNVME_SRC/Makefile" && -f "$NDT/build/linux/include/config/kernel.release" ]]; then
    echo "[clean-all] make -C ${VNVME_SRC/} clean"
    make -C "$VNVME_SRC" KDIR="$NDT/build/linux" clean >/dev/null
elif [[ -f "$VNVME_SRC/vnvme.ko" ]]; then
    # KDIR is gone - make clean would fail.  Wipe
    # the obvious *.ko/*.o/*.mod* trail by hand.
    echo "[clean-all] wiping ${VNVME_SRC} build artefacts"
    find "$VNVME_SRC" -maxdepth 1 \
        \( -name '*.ko' -o -name '*.o' -o -name '*.mod' -o -name '*.mod.c' \
        -o -name 'modules.order' -o -name 'Module.symvers' \) -delete
fi

if [[ -d "$NDT/build" ]]; then
    echo "[clean-all] removing $NDT/build/"
    rm -rf "$NDT/build"
fi

echo "[clean-all] done"
