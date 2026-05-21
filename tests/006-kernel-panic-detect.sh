#!/bin/bash
# ndt-expected: fail
#
# Triggers a kernel panic in the guest via sysrq.  Watcher must spot it
# through PANIC_RE on console.log, capture-forensics fires
# dump-guest-memory + lx-dmesg, and the verdict ends with "FAIL: kernel
# panic".

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "ready-for-cmd never appeared"

# Enable all sysrq triggers, then fire 'c' to crash the kernel.  We use
# raw ctrl (not exec_in_guest) because the kernel will panic before init
# can emit CMD_DONE.
ctrl "EXEC echo 1 > /proc/sys/kernel/sysrq && echo c > /proc/sysrq-trigger"

# Block; watcher will SIGTERM us once it grep's panic on console.
sleep 60
scenario_fail "watcher never killed us — panic detection broken?"
