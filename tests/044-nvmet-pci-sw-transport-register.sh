#!/bin/bash
# ndt-expected: pass
#
# Etap 5a nvmet-pci-sw — register the transport with nvmet core.
# Just proves nvmet_register_transport(&nps_fabrics_ops) succeeded —
# port/subsystem wiring happens in 5b+.

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

# nvmet pulls in configfs automatically.
rc=$(exec_in_guest "modprobe nvmet")
[[ "$rc" != "0" ]] && scenario_fail "modprobe nvmet failed (rc=$rc)"

rc=$(exec_in_guest "modprobe nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "modprobe nvmet-pci-sw failed (rc=$rc)"

rc=$(exec_in_guest "dmesg | grep -q 'nvmet-pci-sw: registered as nvmet PCI transport'")
[[ "$rc" != "0" ]] && scenario_fail "transport registration log missing"

# Module must hold a ref on nvmet — verify via modules dependency.
rc=$(exec_in_guest "lsmod | awk '\$1==\"nvmet_pci_sw\"' | grep -q nvmet")
[[ "$rc" != "0" ]] && scenario_fail "nvmet_pci_sw doesn't show nvmet as dep"

rc=$(exec_in_guest "rmmod nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "rmmod nvmet-pci-sw failed (rc=$rc)"

dmesg_dump
scenario_pass
