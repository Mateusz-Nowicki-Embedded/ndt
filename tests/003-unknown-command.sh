#!/bin/bash
# ndt-expected: pass
#
# Sends an unknown command on ctrl.  Initramfs must emit
# NDT_CMD_DONE cmd='?' rc=127 and abort the session.  We pass if we see
# the error sentinel within a short window.

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "ready-for-cmd never appeared"

ctrl "BOGUS_COMMAND with some args"
if ! wait_for "NDT_CMD_DONE cmd='\\?' rc=127" 10; then
    scenario_fail "init did not emit cmd='?' rc=127 for unknown command"
fi

scenario_pass
