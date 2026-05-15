#!/bin/bash
# Boot the locally-built kernel + initramfs in QEMU with a virtual NVMe controller.
# Console is wired to stdio (serial). Exit with: poweroff -f  (or Ctrl+A x).
#
# Three host-side sockets are created (server, nowait — host connects later):
#   /tmp/qemu-serial.sock   ttyS0 console (kernel + init log, NDT sentinels)
#   /tmp/qemu-ctrl.sock     ttyS1 control channel (host -> guest "GO" gate)
#   /tmp/qemu-monitor.sock  HMP monitor (host -> QEMU: nvme_completion_delay, ...)
#
# Paths (relative to the NDT repo root):
#   build/linux/arch/x86/boot/bzImage  -> kernel image
#   initramfs/initramfs.cpio.gz        -> busybox initramfs (tracked binary)
#   disks/nvme-ns1.img                 -> 1 GiB raw, exposed as nsid=1
#   disks/nvme-ns2.img                 -> 256 MiB raw, exposed as nsid=2
#
# NVMe controller options:
#   max_ioqpairs=8   - 8 IO queue pairs (in addition to admin)
#   cmb_size_mb=16   - Controller Memory Buffer (16 MiB)
#   serial=...       - required by spec; arbitrary string
#
# Override defaults via env, e.g.:
#   NVME=0 ./run-qemu.sh                         # boot without NVMe (for A/B)
#   QEMU_EXTRA="-s -S" ./run-qemu.sh             # gdbstub + stop-at-start
#   QEMU_BIN=/usr/bin/qemu-system-x86_64 ./run-qemu.sh   # use system QEMU

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)

LOCAL_QEMU="$NDT/build/qemu-host/qemu-system-x86_64"
QEMU_BIN=${QEMU_BIN:-${LOCAL_QEMU}}
if [[ ! -x "$QEMU_BIN" ]]; then
    echo "[run-qemu.sh] $QEMU_BIN not found, falling back to system qemu-system-x86_64" >&2
    QEMU_BIN=qemu-system-x86_64
fi

BZIMAGE=${BZIMAGE:-"$NDT/build/linux/arch/x86/boot/bzImage"}
INITRAMFS=${INITRAMFS:-"$NDT/initramfs/initramfs.cpio.gz"}
APPEND=${APPEND:-"console=ttyS0 panic=-1"}

for f in "$BZIMAGE" "$INITRAMFS"; do
    if [[ ! -f "$f" ]]; then
        echo "[run-qemu.sh] missing artifact: $f" >&2
        echo "[run-qemu.sh] hint: run ndt/build-all.sh first" >&2
        exit 1
    fi
done

NVME=${NVME:-1}
NVME_NS1="$NDT/disks/nvme-ns1.img"
NVME_NS2="$NDT/disks/nvme-ns2.img"
NVME_NS3="$NDT/disks/nvme-ns3.img"

nvme_args=()
if [[ "$NVME" == "1" ]]; then
    # Plug NVMe behind a pcie-root-port so SBR-based hot reset and FLR work
    # end-to-end (the root port is the upstream bridge that emulates Hot Reset
    # on Secondary Bus Reset).
    # nsid=3 is formatted with 8-byte metadata (mset=0, separate buffer) for
    # nvme/064 and related metadata tests.
    nvme_args+=(
        -device "pcie-root-port,id=rp0,chassis=1,slot=1,bus=pcie.0"
        -drive "file=$NVME_NS1,format=raw,if=none,id=nvm0"
        -drive "file=$NVME_NS2,format=raw,if=none,id=nvm1"
        -drive "file=$NVME_NS3,format=raw,if=none,id=nvm2"
        -device "nvme,id=nvme0,bus=rp0,serial=NVME0001,max_ioqpairs=8,cmb_size_mb=16"
        -device "nvme-ns,drive=nvm0,bus=nvme0,nsid=1"
        -device "nvme-ns,drive=nvm1,bus=nvme0,nsid=2"
        -device "nvme-ns,drive=nvm2,bus=nvme0,nsid=3,ms=8,mset=0"
    )
fi

# Q35 gives us a PCIe root complex (i440FX is conventional PCI only); needed
# for FLR, AER and the SBR-driven Hot Reset path on the NVMe device.
exec "$QEMU_BIN" \
    -machine q35 \
    -kernel "$BZIMAGE" \
    -initrd "$INITRAMFS" \
    -append "$APPEND" \
    -nographic \
    -m 1G \
    -smp 8 \
    -serial unix:/tmp/qemu-serial.sock,server,nowait \
    -serial unix:/tmp/qemu-ctrl.sock,server,nowait \
    -monitor unix:/tmp/qemu-monitor.sock,server,nowait \
    -display none \
    -no-reboot \
    -cpu host -enable-kvm \
    "${nvme_args[@]}" \
    ${QEMU_EXTRA:-} \
    "$@"
