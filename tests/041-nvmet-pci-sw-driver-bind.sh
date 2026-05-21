#!/bin/bash
# ndt-expected: pass
#
# Etap 2 nvmet-pci-sw — verify the mainline nvme PCI driver class-matches
# our fake device and binds to it.
#
# Stage 2 deliberately stops short of working register FSM: nvme_probe()
# is expected to fail when CSTS.RDY never asserts.  The pass criterion is
# *that the bind happened*, not that probe succeeded.

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

# Load module — triggers PCI enumeration and the nvme driver's
# class-match probe attempt.
rc=$(exec_in_guest "modprobe nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "modprobe failed (rc=$rc)"

# Device must be on bus 0xfe.
rc=$(exec_in_guest "ls /sys/bus/pci/devices/ | grep -q ':fe:00.0\$'")
[[ "$rc" != "0" ]] && scenario_fail "no PCI device on bus 0xfe"

# nvme driver should have at least attempted to claim it.  Stage 2 has
# no register FSM, so probe() bails with -ENODEV and the kernel
# auto-unbinds — i.e. the driver symlink won't survive past probe.
# What survives is the dmesg trace, which proves class-match + probe
# entry happened.
rc=$(exec_in_guest "dmesg | grep -qE 'nvme [0-9a-f]+:fe:00\\.0'")
[[ "$rc" != "0" ]] && scenario_fail "nvme driver never touched fake device"

# And specifically the expected stage-2 probe outcome.
rc=$(exec_in_guest "dmesg | grep -E 'nvme [0-9a-f]+:fe:00\\.0' | grep -q 'probe failed'")
[[ "$rc" != "0" ]] && scenario_fail "nvme probe didn't reach the expected -ENODEV path"

dmesg_dump
scenario_pass
