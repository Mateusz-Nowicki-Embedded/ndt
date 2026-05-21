#!/bin/bash
# ndt-expected: pass
#
# exec_in_guest with a payload that exits 42 — verify the same rc reaches
# the scenario via NDT_CMD_DONE.

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "ready-for-cmd never appeared"

rc=$(exec_in_guest "exit 42")
if [[ "$rc" != "42" ]]; then
    scenario_fail "expected exec rc=42, got rc='$rc'"
fi

scenario_pass
