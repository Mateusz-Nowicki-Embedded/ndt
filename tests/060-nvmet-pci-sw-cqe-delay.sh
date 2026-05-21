#!/bin/bash
# ndt-expected: pass
#
# Verify per-SQ cqe_delay_ms debugfs knob defers CQE posting + IRQ
# fire by the requested millisecond count.  Mirror of QEMU HMP
# `nvme_completion_delay` semantic for the software endpoint.
#
# Strategy: set a 500 ms delay on the admin SQ (sqid=0), issue an
# identify, time the round trip.  Without delay it returns in <1 ms;
# with delay it must take ≥450 ms (allow some scheduler slack).
#
# All verification is done inside the guest as a single command —
# exec_in_guest only returns exit code, not stdout, so we have to
# self-assert and rely on rc.

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

# init has already loaded nvmet-pci-sw and bound the driver.
rc=$(exec_in_guest "[ -e /dev/nvme0n1 ]")
[[ "$rc" != "0" ]] && scenario_fail "/dev/nvme0n1 missing"

# Verification script — all in one guest invocation.  Returns 0 on
# success, non-zero on any check failure.  Echoes diagnostics to
# the console for artifact capture.
# exec_in_guest sends one line per ttyS1 read; chain everything with
# `;` / `&&` to stay on one line.
SCRIPT='CQD=/sys/kernel/debug/nvmet-pci-sw/queues/cqe_delay_ms;'
SCRIPT+='T0=$(date +%s%N); nvme id-ctrl /dev/nvme0 >/dev/null; T1=$(date +%s%N);'
SCRIPT+='BMS=$(( (T1-T0)/1000000 )); echo baseline=${BMS}ms;'
SCRIPT+='echo "0 500" > $CQD;'
SCRIPT+='GOT=$(grep "^0 " $CQD | head -1 | cut -d" " -f2);'
SCRIPT+='[ "$GOT" = "500" ] || { echo "FAIL readback=$GOT"; exit 1; };'
SCRIPT+='T0=$(date +%s%N); nvme id-ctrl /dev/nvme0 >/dev/null; T1=$(date +%s%N);'
SCRIPT+='DMS=$(( (T1-T0)/1000000 )); echo delayed=${DMS}ms;'
SCRIPT+='[ $DMS -ge 450 ] && [ $DMS -le 2000 ] || { echo "FAIL delay=$DMS"; exit 2; };'
SCRIPT+='echo "0 0" > $CQD;'
SCRIPT+='T0=$(date +%s%N); nvme id-ctrl /dev/nvme0 >/dev/null; T1=$(date +%s%N);'
SCRIPT+='RMS=$(( (T1-T0)/1000000 )); echo restored=${RMS}ms;'
SCRIPT+='[ $RMS -le 100 ] || { echo "FAIL not released=$RMS"; exit 3; };'
SCRIPT+='echo PASS'
rc=$(exec_in_guest "$SCRIPT")
[[ "$rc" != "0" ]] && scenario_fail "in-guest verification failed (rc=$rc)"

dmesg_dump
scenario_pass
