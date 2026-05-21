#!/bin/bash
# ndt-expected: pass
#
# Full driver-bind flow on the software NVMe endpoint, after BAR-carve
# + BAR-pin quirks landed.  Order:
#   1. modprobe nvmet + null_blk
#   2. configfs subsys + port (trtype=pci) + namespace
#   3. modprobe nvmet-pci-sw  -- bridge + scan + driver bind
#   4. observe driver progress (BAR map, CC.EN/CSTS.RDY, Identify, /dev/nvmeXn1)
#
# We don't *require* /dev/nvme0n1 to exist — the test reports what the
# driver actually managed.  Used to pinpoint the next blocker (MSI-X,
# polled mode fallback, multi-page PRP).

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

# Init already loaded nvmet-pci-sw and brought the configfs port up,
# so by ready-for-cmd the driver should already be bound and the
# block device exposed.  We just verify the bind happened.
rc=$(exec_in_guest "[ -L /sys/bus/pci/devices/0000:ff:00.0/driver ]")
[[ "$rc" != "0" ]] && scenario_fail "driver not bound on bus 0xff endpoint"

rc=$(exec_in_guest "[ -e /dev/nvme0n1 ]")
[[ "$rc" != "0" ]] && scenario_fail "/dev/nvme0n1 missing"

# Dump driver inventory + IRQ counters to console for artifact capture.
exec_in_guest "echo '===== inventory ====='; ls /sys/bus/pci/devices/0000:ff:00.0/ 2>/dev/null | head -10; echo; echo '===== /proc/interrupts (nvme) ====='; head -1 /proc/interrupts; grep nvme /proc/interrupts; echo; echo '===== dmesg ====='; dmesg | grep -E 'nvme nvme1|nvmet-pci-sw|nvmet:' | tail -20; echo; echo '===== irq_counts ====='; cat /sys/kernel/debug/nvmet-pci-sw/queues/irq_counts 2>/dev/null | head -4" >/dev/null

dmesg_dump
scenario_pass
