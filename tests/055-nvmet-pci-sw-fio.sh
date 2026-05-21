#!/bin/bash
# ndt-expected: pass
#
# Run fio against /dev/nvme0n1 (software NVMe endpoint, nvmet-pci-sw).
# Uses a small LBA range so we stay well within null_blk's reported size
# and don't trip partition-scan's out-of-range reads.

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

# init has already loaded nvmet-pci-sw and brought /dev/nvme0n1 up.
rc=$(exec_in_guest "[ -e /dev/nvme0n1 ]")
[[ "$rc" != "0" ]] && scenario_fail "/dev/nvme0n1 missing"

# fio: small size so we stay clear of partition-scan's end-of-disk reads.
# libaio with iodepth=4 exercises the I/O queue + per-CQ MSI-X mock IRQ.
FIO_CMD="fio --name=swnvme --filename=/dev/nvme0n1 --direct=1 --ioengine=libaio --rw=randrw --bs=4k --size=4M --iodepth=4 --runtime=5 --time_based --group_reporting --output-format=normal"

rc=$(exec_in_guest "$FIO_CMD >/tmp/fio.out 2>&1")
[[ "$rc" != "0" ]] && {
    exec_in_guest "cat /tmp/fio.out" >/dev/null
    scenario_fail "fio failed (rc=$rc)"
}

rc=$(exec_in_guest "grep -qE 'read:|write:' /tmp/fio.out")
[[ "$rc" != "0" ]] && {
    exec_in_guest "cat /tmp/fio.out" >/dev/null
    scenario_fail "fio output has no read/write summary"
}

exec_in_guest "echo '===== fio summary ====='; grep -E 'read:|write:|IO depths|cpu|Disk stats' /tmp/fio.out; echo; echo '===== irq_counts ====='; cat /sys/kernel/debug/nvmet-pci-sw/queues/irq_counts 2>/dev/null | head -4" >/dev/null

dmesg_dump
scenario_pass
