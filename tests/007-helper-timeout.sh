#!/bin/bash
# ndt-expected: fail
#
# wait_for with a short timeout against a pattern that never appears.
# Exercises the timeout-fallout path in scenario helpers.

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "ready-for-cmd never appeared"

wait_for "PATTERN_THAT_WILL_NEVER_APPEAR_12345" 5 \
    || scenario_fail "wait_for timed out as expected"

scenario_fail "wait_for did not time out — bug in scenario helpers"
