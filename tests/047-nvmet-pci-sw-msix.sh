#!/bin/bash
# ndt-expected: pass
#
# Etap 6 nvmet-pci-sw — MSI-X capability + IRQ trigger mock.
#
# Verifies:
#   1. MSI-X capability (id 0x11) is advertised in cfg space
#   2. PCI_STATUS bit 4 (CAP_LIST) is set
#   3. After a command completes on the admin queue, the IRQ fire
#      counter for vector 0 increments — but only once the MSI-X
#      Enable bit in Message Control is on
#
# Real IRQ delivery (generic_handle_irq -> request_irq handler) is
# deferred to stage 7 with a working driver bind.

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

rc=$(exec_in_guest "modprobe nvmet && modprobe nvmet-pci-sw && modprobe null_blk nr_devices=1")
[[ "$rc" != "0" ]] && scenario_fail "modprobe chain failed (rc=$rc)"

NQN="nqn.test"
CFG=/sys/kernel/config/nvmet
SUB="$CFG/subsystems/$NQN"
PORT="$CFG/ports/1"

rc=$(exec_in_guest "mkdir -p /sys/kernel/config && mount -t configfs configfs /sys/kernel/config")
[[ "$rc" != "0" ]] && scenario_fail "configfs mount failed"

rc=$(exec_in_guest "mkdir -p $SUB && echo 1 > $SUB/attr_allow_any_host && mkdir $SUB/namespaces/1 && echo /dev/nullb0 > $SUB/namespaces/1/device_path && echo 1 > $SUB/namespaces/1/enable && mkdir $PORT && echo pci > $PORT/addr_trtype && ln -s $SUB $PORT/subsystems/$NQN")
[[ "$rc" != "0" ]] && scenario_fail "configfs setup failed (rc=$rc)"

# Find our device — :fe:00.0 suffix because PCI domain is auto-allocated.
BDF_CMD="BDF=\$(ls /sys/bus/pci/devices/ | grep ':fe:00.0\$' | head -1)"

# PCI_STATUS bit 4 (cap list present) — byte at config offset 0x06 must
# have 0x10 set.
rc=$(exec_in_guest "$BDF_CMD; xxd -s 0x06 -l 1 -p /sys/bus/pci/devices/\$BDF/config | grep -qi 1")
[[ "$rc" != "0" ]] && scenario_fail "PCI_STATUS CAP_LIST bit not set"

# Capability pointer (0x34) should chain to MSI-X cap.
rc=$(exec_in_guest "$BDF_CMD; CAPOFF=\$(xxd -s 0x34 -l 1 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$CAPOFF\" = '80' ]")
[[ "$rc" != "0" ]] && scenario_fail "PCI_CAPABILITY_LIST not pointing at 0x80"

# Cap ID at 0x80 must be 0x11 (MSI-X).
rc=$(exec_in_guest "$BDF_CMD; CAPID=\$(xxd -s 0x80 -l 1 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$CAPID\" = '11' ]")
[[ "$rc" != "0" ]] && scenario_fail "MSI-X cap id mismatch"

# Run an admin command to drive a CQE — counter should still be 0
# because the driver hasn't enabled MSI-X (bit 15 of Message Control).
rc=$(exec_in_guest "echo 1 > /sys/kernel/debug/nvmet-pci-sw/queues/selftest_admin")
[[ "$rc" != "0" ]] && scenario_fail "selftest_admin trigger failed"

rc=$(exec_in_guest "[ \"\$(cat /sys/kernel/debug/nvmet-pci-sw/queues/selftest_admin)\" = '1' ]")
[[ "$rc" != "0" ]] && scenario_fail "selftest_admin verdict != PASS"

# Before enabling MSI-X — counter for vec 0 should be 0.
rc=$(exec_in_guest "[ \"\$(awk '\$1==0{print \$2}' /sys/kernel/debug/nvmet-pci-sw/queues/irq_counts)\" = '0' ]")
[[ "$rc" != "0" ]] && scenario_fail "irq_counts[0] != 0 with MSI-X disabled"

# Enable MSI-X by writing Message Control (cfg offset 0x82) with bit 15
# set.  Driver-side it's pci_msix_enable() — we emulate by writing the
# bit through the config file (our nps_pci_write accepts u16 there).
# Value: keep table size bits, set bit 15 → 0x800f.
rc=$(exec_in_guest "$BDF_CMD; printf '\\x0f\\x80' | dd of=/sys/bus/pci/devices/\$BDF/config bs=1 count=2 seek=130 conv=notrunc 2>/dev/null")
[[ "$rc" != "0" ]] && scenario_fail "MSI-X enable write failed"

# Sanity: re-read MC and check bit 15.
rc=$(exec_in_guest "$BDF_CMD; MC=\$(xxd -s 0x82 -l 2 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$MC\" = '0f80' ]")
[[ "$rc" != "0" ]] && scenario_fail "MSI-X MC readback != 0x800f"

# Now run the admin selftest again — counter must increment.
rc=$(exec_in_guest "echo 1 > /sys/kernel/debug/nvmet-pci-sw/queues/selftest_admin")
[[ "$rc" != "0" ]] && scenario_fail "selftest_admin (2nd) trigger failed"

rc=$(exec_in_guest "[ \"\$(cat /sys/kernel/debug/nvmet-pci-sw/queues/selftest_admin)\" = '1' ]")
[[ "$rc" != "0" ]] && scenario_fail "selftest_admin (2nd) verdict != PASS"

rc=$(exec_in_guest "[ \"\$(awk '\$1==0{print \$2}' /sys/kernel/debug/nvmet-pci-sw/queues/irq_counts)\" -ge 1 ]")
[[ "$rc" != "0" ]] && scenario_fail "irq_counts[0] did not increment after MSI-X enable"

# Teardown.
rc=$(exec_in_guest "rm $PORT/subsystems/$NQN && rmdir $PORT && echo 0 > $SUB/namespaces/1/enable && rmdir $SUB/namespaces/1 && rmdir $SUB")
[[ "$rc" != "0" ]] && scenario_fail "teardown failed"

rc=$(exec_in_guest "rmmod nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "rmmod failed (rc=$rc)"

dmesg_dump
scenario_pass
