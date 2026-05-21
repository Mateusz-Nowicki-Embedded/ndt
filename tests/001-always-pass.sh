#!/bin/bash
# ndt-expected: pass
#
# Smoke test: boot, source scenario lib, scenario_pass.  If this fails the
# whole framework is broken; every later test relies on it.

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "ready-for-cmd never appeared"

scenario_pass
