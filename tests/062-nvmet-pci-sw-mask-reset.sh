#!/bin/bash
# ndt-expected: pass
#
# Mirror of test 030 for the nvmet-pci-sw endpoint: mask every MSI-X
# vector via pcimem, run fio in background, trigger reset_controller,
# verify the controller comes back and no "Unbalanced enable for IRQ"
# splat fires.  Exercises our PBA-set + msix_poller-replay logic.

source "$NDT/tests/lib/scenario.sh"

ITER=${ITER:-3}

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "ready-for-cmd never appeared"

rc=$(exec_in_guest "[ -e /dev/nvme0n1 ]")
[[ "$rc" != "0" ]] && scenario_fail "/dev/nvme0n1 missing"

# Single-line script: N iters of (mask all vectors, fio 3s, reset
# burst).  Our MSI-X table is at BAR0+0x2000, 16 bytes per entry,
# DW3 mask bit is offset 0xC.  NPS_MSIX_NR_VECTORS=16.
SCRIPT="ITER=$ITER;"
SCRIPT+='RES0=/sys/bus/pci/devices/0000:ff:00.0/resource0;'
SCRIPT+='RESET=/sys/class/nvme/nvme0/reset_controller;'
SCRIPT+='[ -e $RES0 ] || { echo "FAIL no res0"; exit 10; };'
SCRIPT+='[ -e $RESET ] || { echo "FAIL no reset"; exit 11; };'
SCRIPT+='for it in $(seq 1 $ITER); do'
SCRIPT+=' echo "===== iter $it/$ITER =====";'
SCRIPT+=' fio --name=t --filename=/dev/nvme0n1 --direct=1 --ioengine=libaio --rw=randrw --bs=4k --size=4M --iodepth=4 --time_based --runtime=3 --group_reporting --output-format=normal >/tmp/fio.out 2>&1 &'
SCRIPT+=' FPID=$!; sleep 1;'
SCRIPT+=' for v in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do'
SCRIPT+='   off=$(printf "0x%x" $(( 0x2000 + 16*v + 0xC )));'
SCRIPT+='   pcimem $RES0 $off w 0x1 >/dev/null 2>&1;'
SCRIPT+=' done;'
SCRIPT+=' sleep 0.5;'
SCRIPT+=' echo 1 > $RESET 2>/dev/null;'
SCRIPT+=' for w in 1 2 3 4 5 6 7 8 9 10; do [ -e /dev/nvme0n1 ] && break; sleep 1; done;'
SCRIPT+=' [ -e /dev/nvme0n1 ] || { echo "FAIL: /dev/nvme0n1 missing after iter $it"; exit 1; };'
SCRIPT+=' nvme id-ctrl /dev/nvme0 >/dev/null 2>&1 || { echo "FAIL: id-ctrl iter $it"; exit 2; };'
SCRIPT+=' wait $FPID 2>/dev/null;'
SCRIPT+=' echo "iter $it OK";'
SCRIPT+='done;'
SCRIPT+='echo ALL_PASS'

rc=$(exec_in_guest "$SCRIPT")
[[ "$rc" != "0" ]] && scenario_fail "mask-reset failed (rc=$rc)"

# Scan dmesg for trouble.
exec_in_guest "dmesg | grep -E 'Unbalanced|BUG:|WARNING.*irq|UBSAN' > /tmp/splat.txt; wc -l /tmp/splat.txt" >/dev/null
rc=$(exec_in_guest "[ ! -s /tmp/splat.txt ]")
[[ "$rc" != "0" ]] && {
    exec_in_guest "cat /tmp/splat.txt" >/dev/null
    scenario_fail "MSI-X / IRQ splat detected in dmesg"
}

dmesg_dump
scenario_pass
