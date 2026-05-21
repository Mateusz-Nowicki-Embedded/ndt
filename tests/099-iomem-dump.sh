#!/bin/bash
# ndt-expected: pass

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

exec_in_guest "modprobe nvmet-pci-sw" >/dev/null

exec_in_guest "echo; echo '===== /proc/iomem ====='; cat /proc/iomem" >/dev/null

exec_in_guest "echo; echo '===== dmesg: BAR + carve ====='; dmesg | grep -E 'BAR0 backing|carve|adjust_resource|insert_resource' | head" >/dev/null

exec_in_guest "rmmod nvmet-pci-sw" >/dev/null
scenario_pass
