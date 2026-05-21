#!/bin/bash
# ndt-expected: fail
#
# Calls scenario_fail to exercise the FAIL-reporting path: verdict.txt gets
# "FAIL: <reason>", runner records actual=FAIL, with expected=fail this
# yields result=OK.

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "ready-for-cmd never appeared"

scenario_fail "intentional failure for framework smoke test"
