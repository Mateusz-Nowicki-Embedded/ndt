#!/bin/bash
# ndt-expected: pass
#
# Task #62 nvmet-pci-sw — Slot capability + presence detect injection.
#
# Verifies:
#   * Slot Implemented bit in PCIe Caps Reg
#   * Slot Caps advertises HPC + HPS + ABP + PCP
#   * Slot Status initial PDS=1
#   * debugfs slot_state toggles PDS + latches PDC

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

rc=$(exec_in_guest "modprobe nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "modprobe failed"

S=/sys/kernel/debug/nvmet-pci-sw/slot_state
BDF_CMD="BDF=\$(ls /sys/bus/pci/devices/ | grep ':fe:00.0\$' | head -1)"

# PCIe Flags @ 0x92, hi byte bit 0 = Slot Implemented (bit 8 overall) -> 0x01.
rc=$(exec_in_guest "$BDF_CMD; HI=\$(xxd -s 0x93 -l 1 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$HI\" = '01' ]")
[[ "$rc" != "0" ]] && scenario_fail "Slot Implemented bit not set"

# Slot Caps low byte @ 0xa4 must have HPC(0x40) | HPS(0x20) | PCP(0x02) | ABP(0x01) = 0x63.
rc=$(exec_in_guest "$BDF_CMD; LO=\$(xxd -s 0xa4 -l 1 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$LO\" = '63' ]")
[[ "$rc" != "0" ]] && scenario_fail "Slot Caps low byte != 0x63 (got \$LO)"

# Slot Status @ 0xaa: PDS bit 6 = 0x40 hi byte? sltsta is u16 at 0xaa.
# LE: PDS bit 6 -> low byte 0x40.
rc=$(exec_in_guest "$BDF_CMD; LO=\$(xxd -s 0xaa -l 1 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$LO\" = '40' ]")
[[ "$rc" != "0" ]] && scenario_fail "Slot Status PDS not set initially"

rc=$(exec_in_guest "[ \"\$(cat $S)\" = 'present' ]")
[[ "$rc" != "0" ]] && scenario_fail "slot_state != present initially"

# Inject absent: PDS=0, PDC=1 -> 0x08.
rc=$(exec_in_guest "echo absent > $S")
[[ "$rc" != "0" ]] && scenario_fail "write 'absent' failed"

rc=$(exec_in_guest "[ \"\$(cat $S)\" = 'absent' ]")
[[ "$rc" != "0" ]] && scenario_fail "slot_state != absent after injection"

rc=$(exec_in_guest "$BDF_CMD; LO=\$(xxd -s 0xaa -l 1 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$LO\" = '08' ]")
[[ "$rc" != "0" ]] && scenario_fail "Slot Status after absent != 0x08 (got \$LO)"

# Restore present: PDS=1, PDC=1 -> 0x48.
rc=$(exec_in_guest "echo present > $S")
[[ "$rc" != "0" ]] && scenario_fail "write 'present' failed"

rc=$(exec_in_guest "$BDF_CMD; LO=\$(xxd -s 0xaa -l 1 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$LO\" = '48' ]")
[[ "$rc" != "0" ]] && scenario_fail "Slot Status after present != 0x48 (got \$LO)"

rc=$(exec_in_guest "rmmod nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "rmmod failed"

dmesg_dump
scenario_pass
