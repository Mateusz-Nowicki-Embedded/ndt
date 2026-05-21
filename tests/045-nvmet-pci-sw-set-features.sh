#!/bin/bash
# ndt-expected: pass
#
# Etap 5b-5d nvmet-pci-sw — admin queue routes Set Features through
# nvmet (not our dummy CQE generator).  Flow:
#   - host configures a nvmet subsystem + port (trtype=pci) via configfs
#   - selftest_admin enables the controller, submits Set Features
#     (Number of Queues), waits for the CQE
#   - nvmet handles the command in its workqueue, our queue_response
#     writes the CQE back into the host CQ memory
#
# Pass criterion: selftest returns 1 (PASS) and dmesg shows the result
# DW being echoed back by nvmet_set_feat_num_queues.

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

# Stack: nvmet core, our transport, null_blk for the namespace backing.
rc=$(exec_in_guest "modprobe nvmet")
[[ "$rc" != "0" ]] && scenario_fail "modprobe nvmet failed (rc=$rc)"

rc=$(exec_in_guest "modprobe nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "modprobe nvmet-pci-sw failed (rc=$rc)"

rc=$(exec_in_guest "modprobe null_blk nr_devices=1")
[[ "$rc" != "0" ]] && scenario_fail "modprobe null_blk failed (rc=$rc)"

# configfs setup.
NQN="nqn.test"
CFG=/sys/kernel/config/nvmet
SUB="$CFG/subsystems/$NQN"
PORT="$CFG/ports/1"

rc=$(exec_in_guest "mkdir -p /sys/kernel/config && mount -t configfs configfs /sys/kernel/config")
[[ "$rc" != "0" ]] && scenario_fail "configfs mount failed (rc=$rc)"

rc=$(exec_in_guest "mkdir -p $SUB && echo 1 > $SUB/attr_allow_any_host")
[[ "$rc" != "0" ]] && scenario_fail "configfs subsys create failed"

rc=$(exec_in_guest "mkdir $SUB/namespaces/1 && echo /dev/nullb0 > $SUB/namespaces/1/device_path && echo 1 > $SUB/namespaces/1/enable")
[[ "$rc" != "0" ]] && scenario_fail "configfs namespace setup failed"

rc=$(exec_in_guest "mkdir $PORT && echo pci > $PORT/addr_trtype")
[[ "$rc" != "0" ]] && scenario_fail "configfs port create failed"

rc=$(exec_in_guest "ln -s $SUB $PORT/subsystems/$NQN")
[[ "$rc" != "0" ]] && scenario_fail "configfs port-subsys link failed (rc=$rc)"

# Confirm transport got the add_port hook.
rc=$(exec_in_guest "dmesg | grep -q 'nvmet-pci-sw: port 1 enabled'")
[[ "$rc" != "0" ]] && scenario_fail "add_port hook missed"

# Trigger selftest — drives CC.EN, ctrl alloc, SQE submission.
S=/sys/kernel/debug/nvmet-pci-sw/queues/selftest_admin
rc=$(exec_in_guest "echo 1 > $S")
[[ "$rc" != "0" ]] && scenario_fail "selftest trigger failed (rc=$rc)"

rc=$(exec_in_guest "[ \"\$(cat $S)\" = '1' ]")
[[ "$rc" != "0" ]] && scenario_fail "selftest verdict != PASS"

# nvmet's set_feat_num_queues echoes dw11 into result — should see it.
rc=$(exec_in_guest "dmesg | grep -q 'selftest PASS (set-features-numq result'")
[[ "$rc" != "0" ]] && scenario_fail "set-features result log missing"

# Teardown: unlink port→subsys first (drops transport refcount),
# remove the port, then namespace + subsystem.  Each step is its own
# exec_in_guest so a failure is pinpointable.
rc=$(exec_in_guest "rm $PORT/subsystems/$NQN")
[[ "$rc" != "0" ]] && scenario_fail "teardown: unlink failed"

rc=$(exec_in_guest "rmdir $PORT")
[[ "$rc" != "0" ]] && scenario_fail "teardown: rmdir port failed"

rc=$(exec_in_guest "echo 0 > $SUB/namespaces/1/enable && rmdir $SUB/namespaces/1 && rmdir $SUB")
[[ "$rc" != "0" ]] && scenario_fail "teardown: subsys cleanup failed"

rc=$(exec_in_guest "rmmod nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "rmmod failed (rc=$rc)"

dmesg_dump
scenario_pass
