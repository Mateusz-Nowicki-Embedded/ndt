#!/bin/bash
# ndt-expected: pass
#
# Etap 5e/5f nvmet-pci-sw — Identify Controller flow with data plane.
#
# Selftest allocates a 4 KiB data buffer, plants its phys into SQE.PRP1
# and submits Admin Identify (CNS=1).  Our queue_response posts the CQE
# back into host CQ memory after nvmet writes the controller record
# into the data buffer through our PRP→SGL conversion (single page).
#
# Pass: cqe.status == 0 and the response buffer starts with sane nvmet
# defaults (model name contains "Linux").

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

rc=$(exec_in_guest "modprobe nvmet && modprobe nvmet-pci-sw && modprobe null_blk nr_devices=1")
[[ "$rc" != "0" ]] && scenario_fail "modprobe chain failed (rc=$rc)"

NQN="nqn.test"
CFG=/sys/kernel/config/nvmet
SUB="$CFG/subsystems/$NQN"
PORT="$CFG/ports/1"

rc=$(exec_in_guest "mkdir -p /sys/kernel/config && mount -t configfs configfs /sys/kernel/config")
[[ "$rc" != "0" ]] && scenario_fail "configfs mount failed (rc=$rc)"

rc=$(exec_in_guest "mkdir -p $SUB && echo 1 > $SUB/attr_allow_any_host && mkdir $SUB/namespaces/1 && echo /dev/nullb0 > $SUB/namespaces/1/device_path && echo 1 > $SUB/namespaces/1/enable && mkdir $PORT && echo pci > $PORT/addr_trtype && ln -s $SUB $PORT/subsystems/$NQN")
[[ "$rc" != "0" ]] && scenario_fail "configfs setup failed (rc=$rc)"

rc=$(exec_in_guest "dmesg | grep -q 'nvmet-pci-sw: port 1 enabled'")
[[ "$rc" != "0" ]] && scenario_fail "add_port hook missed"

S=/sys/kernel/debug/nvmet-pci-sw/queues/selftest_identify
rc=$(exec_in_guest "echo 1 > $S")
[[ "$rc" != "0" ]] && scenario_fail "selftest_identify trigger failed (rc=$rc)"

rc=$(exec_in_guest "[ \"\$(cat $S)\" = '1' ]")
[[ "$rc" != "0" ]] && scenario_fail "identify verdict != PASS"

rc=$(exec_in_guest "dmesg | grep -q 'identify PASS'")
[[ "$rc" != "0" ]] && scenario_fail "identify PASS log missing"

# Teardown.
rc=$(exec_in_guest "rm $PORT/subsystems/$NQN && rmdir $PORT && echo 0 > $SUB/namespaces/1/enable && rmdir $SUB/namespaces/1 && rmdir $SUB")
[[ "$rc" != "0" ]] && scenario_fail "teardown failed"

rc=$(exec_in_guest "rmmod nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "rmmod failed (rc=$rc)"

dmesg_dump
scenario_pass
