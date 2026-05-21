#!/bin/bash
# ndt-expected: pass
#
# Etap 1 nvmet-pci-sw — module load + virtual PCIe bus discovery.
#
# Goal: prove the module registers a host bridge that the kernel
# enumerates a fake NVMe device under.  No driver binding yet, just
# enumeration.

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

# Load module.
rc=$(exec_in_guest "modprobe nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "modprobe nvmet-pci-sw failed (rc=$rc)"

# Find our device — kernel auto-assigns a PCI domain number to our
# host bridge, so we can't hardcode `0000:fe:00.0`.  Match by the
# `:fe:00.0` suffix instead.  Side-effect: this also asserts the bus
# number we configured (0xfe) actually shows up.
rc=$(exec_in_guest "ls /sys/bus/pci/devices/ | grep -q ':fe:00.0\$'")
[[ "$rc" != "0" ]] && scenario_fail "no PCI device on bus 0xfe"

# Vendor / Device / Class — write to /tmp/nps-bdf in guest, then read
# its files individually.  Without stdout capture from exec_in_guest we
# can't easily slurp the BDF back, so iterate inside guest.
rc=$(exec_in_guest "BDF=\$(ls /sys/bus/pci/devices/ | grep ':fe:00.0\$' | head -1); grep -q 0xfffe /sys/bus/pci/devices/\$BDF/vendor")
[[ "$rc" != "0" ]] && scenario_fail "vendor != 0xfffe"

rc=$(exec_in_guest "BDF=\$(ls /sys/bus/pci/devices/ | grep ':fe:00.0\$' | head -1); grep -q 0x4e50 /sys/bus/pci/devices/\$BDF/device")
[[ "$rc" != "0" ]] && scenario_fail "device != 0x4e50"

rc=$(exec_in_guest "BDF=\$(ls /sys/bus/pci/devices/ | grep ':fe:00.0\$' | head -1); grep -q 0x010802 /sys/bus/pci/devices/\$BDF/class")
[[ "$rc" != "0" ]] && scenario_fail "class != 0x010802"

# Clean unload.
rc=$(exec_in_guest "rmmod nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "rmmod failed (rc=$rc)"

if [[ "$(exec_in_guest "ls /sys/bus/pci/devices/ | grep -q ':fe:00.0\$'")" == "0" ]]; then
    scenario_fail "device still present after rmmod"
fi

dmesg_dump
scenario_pass
