#!/bin/bash
# ndt-expected: pass
#
# Task #59 nvmet-pci-sw — NVMe Subsystem Reset (NSSR).
#
# Verifies:
#   * CAP.NSSRS bit 36 advertised
#   * Writing 0x4E564D65 ('NVMe') to NSSR (offset 0x20) tears the
#     controller down (CSTS.RDY clears, admin queue destroyed) and
#     latches CSTS.NSSRO bit 4
#   * CSTS.NSSRO clears on the next CC.EN 0→1

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

rc=$(exec_in_guest "modprobe nvmet && modprobe nvmet-pci-sw && modprobe null_blk nr_devices=1")
[[ "$rc" != "0" ]] && scenario_fail "modprobe chain failed"

R=/sys/kernel/debug/nvmet-pci-sw

# CAP high u32: bit 36 (NSSRS, = bit 4 of high u32) | bit 37 (CSS NVM, = bit 5).
# So cap_hi == 0x30.
rc=$(exec_in_guest "[ \"\$(cat $R/cap_hi)\" = '0x00000030' ]")
[[ "$rc" != "0" ]] && scenario_fail "CAP.NSSRS not advertised (cap_hi != 0x30)"

# Initial state: NSSRO clear.
rc=$(exec_in_guest "[ \"\$(cat $R/csts)\" = '0x00000000' ]")
[[ "$rc" != "0" ]] && scenario_fail "CSTS not zero initially"

# Enable controller minimally (no admin queue — just FSM, like test 042).
rc=$(exec_in_guest "echo 0x460001 > $R/cc; sleep 0.05; [ \"\$(cat $R/csts)\" = '0x00000001' ]")
[[ "$rc" != "0" ]] && scenario_fail "CSTS.RDY didn't assert after CC.EN=1"

# Write NSSR magic — controller resets, NSSRO latches, RDY clears, CC.EN clears.
rc=$(exec_in_guest "echo 0x4E564D65 > $R/nssr; sleep 0.05; [ \"\$(cat $R/csts)\" = '0x00000010' ]")
[[ "$rc" != "0" ]] && scenario_fail "CSTS.NSSRO not set or RDY not cleared after NSSR"

rc=$(exec_in_guest "[ \"\$(cat $R/cc)\" = '0x00000000' ]")
[[ "$rc" != "0" ]] && scenario_fail "CC.EN didn't clear after NSSR"

# Re-enable: NSSRO should clear, RDY set.
rc=$(exec_in_guest "echo 0x460001 > $R/cc; sleep 0.05; [ \"\$(cat $R/csts)\" = '0x00000001' ]")
[[ "$rc" != "0" ]] && scenario_fail "NSSRO didn't clear on re-enable"

# Quiesce.
rc=$(exec_in_guest "echo 0 > $R/cc; sleep 0.05")
[[ "$rc" != "0" ]] && scenario_fail "final disable failed"

rc=$(exec_in_guest "rmmod nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "rmmod failed"

dmesg_dump
scenario_pass
