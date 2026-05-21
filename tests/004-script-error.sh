#!/bin/bash
# ndt-expected: fail
#
# Scenario exits non-zero without writing verdict.txt.  Runner must detect
# missing verdict + non-zero rc and synthesize "FAIL: script error (rc=N)".

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "ready-for-cmd never appeared"

# Deliberately reference a function that doesn't exist; bash errors out
# with rc=127 and no scenario_pass/scenario_fail is called.
this_function_does_not_exist_xyzzy
