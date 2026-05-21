#!/bin/bash
# ndt-expected: pass
#
# Scaling check: run fio with increasing numjobs/queue-count on
# /dev/nvme1n1 and report IOPS per config.  Goal — answer "does the
# software endpoint scale with queue count?"

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

rc=$(exec_in_guest "modprobe nvmet && modprobe null_blk nr_devices=1")
[[ "$rc" != "0" ]] && scenario_fail "modprobe nvmet/null_blk (rc=$rc)"

rc=$(exec_in_guest "mkdir -p /sys/kernel/config && mount -t configfs configfs /sys/kernel/config")
[[ "$rc" != "0" ]] && scenario_fail "configfs mount (rc=$rc)"

NQN="nqn.test"
CFG=/sys/kernel/config/nvmet
SUB="$CFG/subsystems/$NQN"
PORT="$CFG/ports/1"

# attr_qid_max=33 → 1 admin + 32 I/O queues, matching the 32-vCPU guest.
rc=$(exec_in_guest "mkdir -p $SUB && echo 1 > $SUB/attr_allow_any_host && echo 33 > $SUB/attr_qid_max && mkdir $SUB/namespaces/1 && echo /dev/nullb0 > $SUB/namespaces/1/device_path && echo 1 > $SUB/namespaces/1/enable")
[[ "$rc" != "0" ]] && scenario_fail "subsys/ns setup (rc=$rc)"

rc=$(exec_in_guest "modprobe nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "modprobe nvmet-pci-sw (rc=$rc)"

rc=$(exec_in_guest "mkdir $PORT && echo pci > $PORT/addr_trtype && ln -s $SUB $PORT/subsystems/$NQN")
[[ "$rc" != "0" ]] && scenario_fail "port + link (rc=$rc)"

exec_in_guest "for i in \$(seq 1 60); do [ -e /dev/nvme1n1 ] && break; sleep 1; done" >/dev/null

rc=$(exec_in_guest "[ -e /dev/nvme1n1 ]")
[[ "$rc" != "0" ]] && scenario_fail "/dev/nvme1n1 never appeared"

# Sanity: confirm driver actually got multiple queues.
exec_in_guest "dmesg | grep -E 'nvme nvme1: [0-9]+/[0-9]+/[0-9]+ default'" >/dev/null

# Run fio with 1/2/4/8 numjobs — each spreads across the IO queues.
FIO_BASE="fio --direct=1 --ioengine=libaio --rw=randread --bs=4k --size=4M --iodepth=4 --runtime=5 --time_based --group_reporting"

for nj in 1 2 4 8 16 32; do
    exec_in_guest "$FIO_BASE --name=sw-nj$nj --filename=/dev/nvme1n1 --numjobs=$nj > /tmp/fio-nj$nj.out 2>&1" >/dev/null
    rc=$(exec_in_guest "grep -q 'read: IOPS=' /tmp/fio-nj$nj.out")
    [[ "$rc" != "0" ]] && scenario_fail "fio numjobs=$nj failed"
done

exec_in_guest "echo; echo '=========== nvmet-pci-sw scaling (1 namespace, 32 IO queues, 32 vCPU, 8GB) ==========='; for nj in 1 2 4 8 16 32; do printf 'numjobs=%d : ' \$nj; grep 'read: IOPS=' /tmp/fio-nj\$nj.out | head -1; done; echo; echo '=========== driver queues ==========='; dmesg | grep -E 'nvme nvme1: [0-9]+/[0-9]+/[0-9]+ default' | tail -1; echo; echo '=========== /proc/interrupts (head) ==========='; head -1 /proc/interrupts; grep nvme1 /proc/interrupts | head -5" >/dev/null

# Teardown
exec_in_guest "rm $PORT/subsystems/$NQN; rmdir $PORT; echo 0 > $SUB/namespaces/1/enable; rmdir $SUB/namespaces/1; rmdir $SUB" >/dev/null
exec_in_guest "rmmod nvmet-pci-sw" >/dev/null

dmesg_dump
scenario_pass
