#!/bin/bash
# ndt-expected: pass
#
# Verify our teardown drops pending delayed CQEs (QEMU-style) instead
# of waiting for them to fire.  We exercise the configfs port-unlink
# path because driver-side `reset_controller` ALSO waits for admin
# command timeout (60 s) before its sysfs write returns — a separate
# concern unrelated to our drop semantics.
#
# Strategy:
#   1. Set 30 s CQE delay on admin SQ
#   2. Spawn `nvme id-ctrl` in background — hangs on deferred CQE
#   3. configfs port unlink → triggers our teardown_work →
#      nps_admin_queue_destroy → nps_sq_drop_pending_iods
#   4. Unlink MUST complete in < 5 s (we cancel, don't wait)
#   5. Background id-ctrl exits with error (driver sees device gone)

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

rc=$(exec_in_guest "[ -e /dev/nvme0n1 ]")
[[ "$rc" != "0" ]] && scenario_fail "/dev/nvme0n1 missing"

# Single-shot in-guest verification.  Exit codes:
#   1 — couldn't set delay
#   2 — reset took too long (> 5 s); means we waited on the 30 s delay
#   3 — controller didn't come back after reset
# exec_in_guest is one-line; chain with ; and &&.
SCRIPT='CQD=/sys/kernel/debug/nvmet-pci-sw/queues/cqe_delay_ms;'
SCRIPT+='LINK=/sys/kernel/config/nvmet/ports/1/subsystems/nqn.test;'
SCRIPT+='[ -L $LINK ] || { echo "FAIL no link"; exit 10; };'
SCRIPT+='echo "0 30000" > $CQD || { echo "FAIL set delay"; exit 1; };'
SCRIPT+='( nvme id-ctrl /dev/nvme0 >/dev/null 2>/tmp/iderr; echo $? > /tmp/idrc ) &'
SCRIPT+=' IDPID=$!; sleep 1;'
SCRIPT+='T0=$(date +%s%N); rm $LINK; T1=$(date +%s%N);'
SCRIPT+='UMS=$(( (T1-T0)/1000000 )); echo unlink_ms=$UMS;'
SCRIPT+='[ $UMS -le 5000 ] || { echo "FAIL unlink_blocked=$UMS"; exit 2; };'
SCRIPT+='wait $IDPID 2>/dev/null; IDRC=$(cat /tmp/idrc 2>/dev/null);'
SCRIPT+='echo "background rc=$IDRC (nonzero expected)";'
SCRIPT+='echo PASS'
rc=$(exec_in_guest "$SCRIPT")
[[ "$rc" != "0" ]] && scenario_fail "in-guest delay-reset failed (rc=$rc)"

dmesg_dump
scenario_pass
