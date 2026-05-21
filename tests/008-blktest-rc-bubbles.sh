#!/bin/bash
# ndt-expected: pass
#
# Issues run_blktest against a nonexistent test id.  Verifies the rc from
# ./check inside init bubbles back up through CMD_DONE to scenario.

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "ready-for-cmd never appeared"

run_blktest nvme/999-this-test-does-not-exist
rc=$?
if (( rc == 0 )); then
    scenario_fail "run_blktest unexpectedly returned 0 for missing test"
fi

scenario_pass
