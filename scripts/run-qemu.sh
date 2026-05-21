#!/bin/bash
# Boot the locally-built kernel + initramfs in QEMU.  No QEMU-emulated NVMe
# device — the test target is `nvmet-pci-sw`, which lives entirely inside
# the guest kernel.  null_blk backs the controller's namespaces.
#
# Two host-side sockets (server, nowait):
#   /tmp/qemu-serial.sock   ttyS0 console (kernel + init log, NDT sentinels)
#   /tmp/qemu-ctrl.sock     ttyS1 control channel (host -> guest "GO" gate)
#
# No HMP monitor — there's nothing to control on the QEMU side any more.
# Anything the old QEMU HMP knobs did (nvme_completion_delay, hotplug)
# is now exposed by the module itself via /sys/kernel/debug/nvmet-pci-sw/.
#
# Override defaults via env:
#   QEMU_EXTRA="-s -S" ./run-qemu.sh    # gdbstub + stop-at-start
#   QEMU_BIN=...    ./run-qemu.sh       # alternate qemu binary
#   BZIMAGE / INITRAMFS / APPEND        # override artifacts

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
# memmap=64K$0x100000000 — carve 64 KiB out of System RAM at the start of
# the high-RAM e820 block (0x100000000-0x27fffffff on -m 8G).  Reserved
# range backs BAR0 for the nvmet-pci-sw module (see modules/nvmet-pci-sw/
# bar.c: bar_phys default 0x100000000).  Literal '$' escaped so the shell
# doesn't expand $0.  nvme.poll_queues=4 enables io_uring --hipri path.
APPEND=${APPEND:-"console=ttyS0 panic=-1 memmap=64K\$0x100000000 nvme.poll_queues=4"}

for f in "$BZIMAGE" "$INITRAMFS"; do
    if [[ ! -f "$f" ]]; then
        echo "[run-qemu.sh] missing artifact: $f" >&2
        echo "[run-qemu.sh] hint: run ndt/build-all.sh first" >&2
        exit 1
    fi
done

# Q35 keeps the PCIe root complex (the module's virtual bridge lives
# under bus 0xfe inside the guest — no QEMU PCIe device is plugged here).
exec "$QEMU_BIN" \
    -machine q35 \
    -kernel "$BZIMAGE" \
    -initrd "$INITRAMFS" \
    -append "$APPEND" \
    -nographic \
    -m 8G \
    -smp 16 \
    -serial unix:/tmp/qemu-serial.sock,server,nowait \
    -serial unix:/tmp/qemu-ctrl.sock,server,nowait \
    -display none \
    -no-reboot \
    -cpu host -enable-kvm \
    ${QEMU_EXTRA:-} \
    "$@"
