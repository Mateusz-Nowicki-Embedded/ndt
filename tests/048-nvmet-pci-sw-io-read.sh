#!/bin/bash
# ndt-expected: pass
#
# Etap 7 nvmet-pci-sw — I/O queue end-to-end read.
#
# Selftest:
#   - sets up admin queue (CC.EN flip with full CC including IOSQES/IOCQES)
#   - issues Create I/O CQ (cqid=1, irq_vector=1, IRQ enabled)
#   - issues Create I/O SQ (sqid=1, cqid=1)
#   - submits nvme_cmd_read on SQ1, LBA=0, NLB=0 (1 block)
#   - asserts CQE status=0 and the 4 KiB data buffer is all-zero
#     (null_blk default)
#
# Exercises:
#   * transport.c .create_cq/.create_sq dispatch into nps_io_cq_create/sq_create
#   * per-SQ poller for SQ1
#   * PRP1→SGL on Read command with 4 KiB transfer
#   * nvmet read execution path through null_blk
#   * CQE posting on a non-admin CQ
#   * MSI-X fire counter on vector 1 (driver-side IRQ delivery still TBD)

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
[[ "$rc" != "0" ]] && scenario_fail "configfs mount failed"

rc=$(exec_in_guest "mkdir -p $SUB && echo 1 > $SUB/attr_allow_any_host && mkdir $SUB/namespaces/1 && echo /dev/nullb0 > $SUB/namespaces/1/device_path && echo 1 > $SUB/namespaces/1/enable && mkdir $PORT && echo pci > $PORT/addr_trtype && ln -s $SUB $PORT/subsystems/$NQN")
[[ "$rc" != "0" ]] && scenario_fail "configfs setup failed (rc=$rc)"

rc=$(exec_in_guest "dmesg | grep -q 'nvmet-pci-sw: port 1 enabled'")
[[ "$rc" != "0" ]] && scenario_fail "add_port hook missed"

S=/sys/kernel/debug/nvmet-pci-sw/queues/selftest_io
rc=$(exec_in_guest "echo 1 > $S")
[[ "$rc" != "0" ]] && scenario_fail "selftest_io trigger failed (rc=$rc)"

rc=$(exec_in_guest "[ \"\$(cat $S)\" = '1' ]")
[[ "$rc" != "0" ]] && scenario_fail "selftest_io verdict != PASS"

rc=$(exec_in_guest "dmesg | grep -q 'io selftest PASS'")
[[ "$rc" != "0" ]] && scenario_fail "PASS log missing"

# I/O CQ uses vector 1.  Counter for vec 1 starts at 0 (MSI-X enable
# only flipped if a host wrote it).  We don't enable MSI-X in this test;
# instead assert the per-vector counter stayed 0 — that's the
# documented stage-6 behavior (no IRQ when MSI-X disabled).
rc=$(exec_in_guest "[ \"\$(awk '\$1==1{print \$2}' /sys/kernel/debug/nvmet-pci-sw/queues/irq_counts)\" = '0' ]")
[[ "$rc" != "0" ]] && scenario_fail "vec 1 fired despite MSI-X disabled"

# Teardown.
rc=$(exec_in_guest "rm $PORT/subsystems/$NQN && rmdir $PORT && echo 0 > $SUB/namespaces/1/enable && rmdir $SUB/namespaces/1 && rmdir $SUB")
[[ "$rc" != "0" ]] && scenario_fail "teardown failed"

rc=$(exec_in_guest "rmmod nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "rmmod failed (rc=$rc)"

dmesg_dump
scenario_pass
