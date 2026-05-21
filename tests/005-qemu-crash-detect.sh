#!/bin/bash
# ndt-expected: fail
#
# Kills the QEMU process from the host side mid-scenario.  Watcher must
# detect "qemu-died", SIGTERM this scenario, and write "FAIL: qemu died".

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "ready-for-cmd never appeared"

# Background a delayed SIGKILL on QEMU.  `disown` so the subshell isn't
# reaped when the parent dies on SIGTERM from the watcher.
( sleep 3; kill -9 "$NDT_QEMU_PID" 2>/dev/null ) &
disown

# Block long enough for the watcher to fire.  The watcher will SIGTERM us
# before this returns naturally.
sleep 60
scenario_fail "watcher never killed us — qemu-crash detection broken?"
