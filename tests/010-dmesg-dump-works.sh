#!/bin/bash
# ndt-expected: pass
#
# Calls dmesg_dump and verifies it produced a non-empty iter dmesg.txt
# containing at least one nvme0 line (sanity that the dmesg.txt content
# is real kernel output, not noise).

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "ready-for-cmd never appeared"

dmesg_dump

if [[ ! -s "$NDT_ITER_DIR/dmesg.txt" ]]; then
    scenario_fail "dmesg_dump produced empty $NDT_ITER_DIR/dmesg.txt"
fi
if ! grep -q "nvme0" "$NDT_ITER_DIR/dmesg.txt"; then
    scenario_fail "dmesg.txt missing expected 'nvme0' line"
fi

scenario_pass
