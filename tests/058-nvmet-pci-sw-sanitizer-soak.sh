#!/bin/bash
# ndt-expected: pass
#
# Sanitizer soak: run nvmet-pci-sw under fio + a rescan cycle, then
# grep dmesg for KASAN / KCSAN / UBSAN / lockdep / DMA debug / SLUB
# corruption / kmemleak splats.  Any hit → FAIL with the offending
# lines in the verdict.
#
# Exercises the paths most likely to misbehave:
#   - SQ poller hot path under fio (per-CPU iod pool, inline SG, IRQ fire)
#   - Admin queue create/destroy (SHN teardown + L3 shadow clear)
#   - PCI rescan (BUS_NOTIFY ADD/DEL, fake_pdev get/put ordering — L1/R3)
#   - configfs port up/down (nps_admin_lock unlock paths — R2)

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

BDF="0000:ff:00.0"   # endpoint pdev, behind 0xfe downstream port

# init has already loaded nvmet-pci-sw + brought /dev/nvme0n1 up.
rc=$(exec_in_guest "[ -e /dev/nvme0n1 ]")
[[ "$rc" != "0" ]] && scenario_fail "/dev/nvme0n1 missing"

# 3. fio: 10s mixed workload to keep the SQ poller busy + cycle the
# per-CPU iod pool.  libaio + iodepth=8 + 4 jobs ≈ 32 in-flight.
FIO_CMD="fio --name=soak --filename=/dev/nvme0n1 --direct=1 --ioengine=libaio --rw=randrw --bs=4k --size=4M --iodepth=8 --numjobs=4 --runtime=10 --time_based --group_reporting --output-format=normal"
rc=$(exec_in_guest "$FIO_CMD >/tmp/fio.out 2>&1")
[[ "$rc" != "0" ]] && {
    exec_in_guest "cat /tmp/fio.out" >/dev/null
    scenario_fail "fio failed (rc=$rc)"
}

# 4. PCI rescan cycle — exercises BUS_NOTIFY DEL_DEVICE → ADD_DEVICE
# paths (L1 fake_pdev WRITE_ONCE + R3 ADD ordering).  After SHN the
# admin queue is torn down (L3); fresh enable rebuilds it.
exec_in_guest "echo 1 > /sys/bus/pci/devices/$BDF/remove" >/dev/null
exec_in_guest "sleep 1; echo 1 > /sys/bus/pci/rescan" >/dev/null
exec_in_guest "for i in \$(seq 1 30); do [ -e /dev/nvme0n1 ] && break; sleep 1; done" >/dev/null

# 5. Second small fio after rescan to drive a few more cycles.
exec_in_guest "$FIO_CMD --runtime=3 >/tmp/fio2.out 2>&1" >/dev/null

# 6. Trigger kmemleak scan (gives the leak detector a chance to walk
# the heap before we tear down — late free is preferred over rmmod
# free for clean reports).
exec_in_guest "echo scan > /sys/kernel/debug/kmemleak 2>/dev/null; sleep 2; echo scan > /sys/kernel/debug/kmemleak 2>/dev/null; sleep 2" >/dev/null

# 7. Teardown — configfs unlink + module unload exercise the
# nvmet_wq teardown path (R2 mutex_unlock fix on add_port retry).
exec_in_guest "rm /sys/kernel/config/nvmet/ports/1/subsystems/nqn.test; rmdir /sys/kernel/config/nvmet/ports/1; echo 0 > /sys/kernel/config/nvmet/subsystems/nqn.test/namespaces/1/enable; rmdir /sys/kernel/config/nvmet/subsystems/nqn.test/namespaces/1; rmdir /sys/kernel/config/nvmet/subsystems/nqn.test" >/dev/null
exec_in_guest "rmmod nvmet-pci-sw" >/dev/null

# 8. Sanitizer dmesg grep.  Any of these strings appearing post-test
# means the soak hit something.  We dump matching lines to the test
# console so the verdict has full context.
PATTERNS='BUG:|WARNING:|KASAN:|KCSAN:|UBSAN:|kmemleak|stack-out-of-bounds|use-after-free|wild-memory-access|slab-out-of-bounds|sleeping function called from invalid context|deadlock|lockdep|circular locking|inconsistent lock state|softirq-safe|softirq-unsafe|kernel BUG at|Oops:|Call Trace:|RIP:|DMA-API:|DMA-API debug|task hung|hardlockup|softlockup'

exec_in_guest "dmesg | grep -E '$PATTERNS' > /tmp/splat.txt 2>&1; wc -l /tmp/splat.txt" >/dev/null
hits=$(exec_in_guest "wc -l < /tmp/splat.txt")
hits=${hits//[^0-9]/}

# Dump everything to console for artifact capture.
exec_in_guest "echo; echo '===== sanitizer hits ($hits lines) ====='; cat /tmp/splat.txt; echo; echo '===== fio summary ====='; grep -E 'read:|write:|IOPS' /tmp/fio.out | head; echo; echo '===== irq_counts ====='; cat /sys/kernel/debug/nvmet-pci-sw/queues/irq_counts 2>/dev/null | head -4" >/dev/null

dmesg_dump
if [[ "$hits" != "0" && -n "$hits" ]]; then
    scenario_fail "sanitizer hits in dmesg ($hits lines) — see console.log"
fi
scenario_pass
