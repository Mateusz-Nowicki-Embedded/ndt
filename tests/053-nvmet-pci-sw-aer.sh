#!/bin/bash
# ndt-expected: pass
#
# Task #63 nvmet-pci-sw — AER extended capability + error injection.
#
# Verifies:
#   * AER ext-cap header @ 0x100 (id 0x0001, version 2)
#   * AER Control advertises ECRC Generation/Check Capable
#   * aer_inject debugfs sets UE/CE status bits
#   * "clear" resets both status regs

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

rc=$(exec_in_guest "modprobe nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "modprobe failed"

A=/sys/kernel/debug/nvmet-pci-sw/aer_inject
BDF_CMD="BDF=\$(ls /sys/bus/pci/devices/ | grep ':fe:00.0\$' | head -1)"

# Ext cap header LE: 01 00 02 00 (id 0x0001, version 2, no next).
rc=$(exec_in_guest "$BDF_CMD; H=\$(xxd -s 0x100 -l 4 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$H\" = '01000200' ]")
[[ "$rc" != "0" ]] && scenario_fail "AER ext-cap header mismatch (got \$H)"

# AER Control @ 0x118 (= 0x100 + PCI_ERR_CAP=0x18): ECRC_GENC=bit5, ECRC_CHKC=bit7 -> 0xa0.
rc=$(exec_in_guest "$BDF_CMD; C=\$(xxd -s 0x118 -l 1 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$C\" = 'a0' ]")
[[ "$rc" != "0" ]] && scenario_fail "AER Control low byte != 0xa0 (got \$C)"

# Initial: both status zero.
rc=$(exec_in_guest "[ \"\$(cat $A)\" = 'ue=0x00000000 ce=0x00000000' ]")
[[ "$rc" != "0" ]] && scenario_fail "AER status not initially zero"

# Inject completion timeout: UE bit 14 -> 0x00004000.
rc=$(exec_in_guest "echo cto > $A")
[[ "$rc" != "0" ]] && scenario_fail "AER cto inject failed"

rc=$(exec_in_guest "grep -q 'ue=0x00004000' $A")
[[ "$rc" != "0" ]] && scenario_fail "UE status bit 14 (CTO) not set"

# Inject poisoned TLP: bit 12 -> additional 0x1000 -> total 0x00005000.
rc=$(exec_in_guest "echo poison > $A")
[[ "$rc" != "0" ]] && scenario_fail "AER poison inject failed"

rc=$(exec_in_guest "grep -q 'ue=0x00005000' $A")
[[ "$rc" != "0" ]] && scenario_fail "UE status accumulate failed"

# Correctable injection accumulates into ce side.
rc=$(exec_in_guest "echo bad-tlp > $A")
[[ "$rc" != "0" ]] && scenario_fail "AER bad-tlp inject failed"

rc=$(exec_in_guest "grep -q 'ce=0x00000040' $A")
[[ "$rc" != "0" ]] && scenario_fail "CE status BAD_TLP not set"

# Verify via raw cfg space — UE status at 0x104, bit 14 still latched.
rc=$(exec_in_guest "$BDF_CMD; HI=\$(xxd -s 0x105 -l 1 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$HI\" = '50' ]")
[[ "$rc" != "0" ]] && scenario_fail "raw UE status hi byte != 0x50 (got \$HI)"

# Clear.
rc=$(exec_in_guest "echo clear > $A")
[[ "$rc" != "0" ]] && scenario_fail "AER clear failed"

rc=$(exec_in_guest "[ \"\$(cat $A)\" = 'ue=0x00000000 ce=0x00000000' ]")
[[ "$rc" != "0" ]] && scenario_fail "AER status not zero after clear"

# Bogus rejected.
rc=$(exec_in_guest "echo wobble > $A 2>/dev/null")
[[ "$rc" = "0" ]] && scenario_fail "bogus AER input accepted"

rc=$(exec_in_guest "rmmod nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "rmmod failed"

dmesg_dump
scenario_pass
