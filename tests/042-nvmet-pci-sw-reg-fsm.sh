#!/bin/bash
# ndt-expected: pass
#
# Etap 3 nvmet-pci-sw — register FSM driven by the poller kthread.
#
# Plan called for KMMIO-watched registers but KMMIO arms the driver's
# ioremap vaddr (which we don't have a clean hook to), so we use a
# polling kthread instead.  This test exercises CC/CSTS/CAP/VS through
# the debugfs mirror exported by registers.c — no nvme PCI driver
# involved, since the BAR is in System RAM and the driver's
# pci_request_mem_regions() refuses it (sorted in stage 5).

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

rc=$(exec_in_guest "modprobe nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "modprobe failed (rc=$rc)"

R=/sys/kernel/debug/nvmet-pci-sw
rc=$(exec_in_guest "[ -d $R ]")
[[ "$rc" != "0" ]] && scenario_fail "debugfs dir missing"

# CAP low: MQES=63, CQR=1, TO=10 -> 0x0a01003f.
rc=$(exec_in_guest "[ \"\$(cat $R/cap_lo)\" = '0x0a01003f' ]")
[[ "$rc" != "0" ]] && scenario_fail "CAP low mismatch"

# CAP high: NSSRS (=bit 36 of CAP, task #59) + CSS NVM (=bit 37) -> 0x30.
rc=$(exec_in_guest "[ \"\$(cat $R/cap_hi)\" = '0x00000030' ]")
[[ "$rc" != "0" ]] && scenario_fail "CAP high mismatch"

# VS = NVMe 1.4.
rc=$(exec_in_guest "[ \"\$(cat $R/vs)\" = '0x00010400' ]")
[[ "$rc" != "0" ]] && scenario_fail "VS mismatch"

# Initial state: controller disabled, not ready.
rc=$(exec_in_guest "[ \"\$(cat $R/cc)\" = '0x00000000' ] && [ \"\$(cat $R/csts)\" = '0x00000000' ]")
[[ "$rc" != "0" ]] && scenario_fail "initial CC/CSTS not zero"

# Enable controller, expect CSTS.RDY to flip to 1 within poll interval.
rc=$(exec_in_guest "echo 0x1 > $R/cc; sleep 0.2; [ \"\$(cat $R/csts)\" = '0x00000001' ]")
[[ "$rc" != "0" ]] && scenario_fail "CSTS.RDY didn't assert after CC.EN=1"

# Disable: CSTS.RDY drops back.
rc=$(exec_in_guest "echo 0x0 > $R/cc; sleep 0.2; [ \"\$(cat $R/csts)\" = '0x00000000' ]")
[[ "$rc" != "0" ]] && scenario_fail "CSTS.RDY didn't deassert after CC.EN=0"

rc=$(exec_in_guest "rmmod nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "rmmod failed (rc=$rc)"

dmesg_dump
scenario_pass
