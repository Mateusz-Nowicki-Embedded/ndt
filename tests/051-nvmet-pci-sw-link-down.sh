#!/bin/bash
# ndt-expected: pass
#
# Task #61 nvmet-pci-sw — DLLLA flip + link-down injection.
#
# Verifies the debugfs link_state knob flips PCI_EXP_LNKSTA_DLLLA in
# cfg space (visible to lspci / sysfs), and that link-up restores it.

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

rc=$(exec_in_guest "modprobe nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "modprobe failed"

L=/sys/kernel/debug/nvmet-pci-sw/link_state
BDF_CMD="BDF=\$(ls /sys/bus/pci/devices/ | grep ':fe:00.0\$' | head -1)"

# Initial: link up (DLLLA set).
rc=$(exec_in_guest "[ \"\$(cat $L)\" = 'up' ]")
[[ "$rc" != "0" ]] && scenario_fail "initial link_state != up"

# LinkSta (0xa2) hi byte = 0x20 (bit 13 DLLLA).
rc=$(exec_in_guest "$BDF_CMD; HI=\$(xxd -s 0xa3 -l 1 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$HI\" = '20' ]")
[[ "$rc" != "0" ]] && scenario_fail "LNKSTA DLLLA bit not set initially"

# Inject link down.
rc=$(exec_in_guest "echo down > $L")
[[ "$rc" != "0" ]] && scenario_fail "write 'down' failed"

rc=$(exec_in_guest "[ \"\$(cat $L)\" = 'down' ]")
[[ "$rc" != "0" ]] && scenario_fail "link_state != down after injection"

# DLLLA bit must be clear; LABS bit (15) may be set.
rc=$(exec_in_guest "$BDF_CMD; HI=\$(xxd -s 0xa3 -l 1 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$HI\" = '80' ] || [ \"\$HI\" = '00' ]")
[[ "$rc" != "0" ]] && scenario_fail "DLLLA didn't clear after link down"

# Bring link back up.
rc=$(exec_in_guest "echo up > $L")
[[ "$rc" != "0" ]] && scenario_fail "write 'up' failed"

rc=$(exec_in_guest "[ \"\$(cat $L)\" = 'up' ]")
[[ "$rc" != "0" ]] && scenario_fail "link_state != up after restore"

# Bogus input rejected.
rc=$(exec_in_guest "echo wobble > $L 2>/dev/null"); [[ "$rc" = "0" ]] && scenario_fail "bogus input accepted"

rc=$(exec_in_guest "rmmod nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "rmmod failed"

dmesg_dump
scenario_pass
