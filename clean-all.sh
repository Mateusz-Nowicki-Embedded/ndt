#!/bin/bash
# Remove all build outputs produced by build-all.sh.
#
# Leaves alone:
#   initramfs/   tracked in git (source of truth)
#   third_party/ submodules
#   disks/       per-run NVMe namespace images (delete manually if needed)
#
# Idempotent: safe to run when build/ is already empty.

set -euo pipefail
NDT=$(cd "$(dirname "$0")" && pwd)

if [[ -d "$NDT/build" ]]; then
    echo "[clean-all] removing $NDT/build/"
    rm -rf "$NDT/build"
fi

echo "[clean-all] done"
