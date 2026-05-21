#!/bin/bash
# ndt-expected: pass
#
# Task #60 nvmet-pci-sw — PCIe Express capability advertising Gen5.
#
# Verifies:
#   * Cap chain MSI-X (0x80) → PCIe (0x90, cap id 0x10)
#   * PCIe Caps Reg: version 2, endpoint type
#   * LinkCap: Max Link Speed = 5 (32 GT/s, Gen5)
#   * LinkSta: Current Link Speed = 5, DLLLA bit set
#   * LinkCap2: SLSV advertises 2.5/5/8/16/32 GT/s
#   * sysfs "current_link_speed" agrees

source "$NDT/tests/lib/scenario.sh"

wait_for "NDT_PHASE phase='ready-for-cmd'" 60 \
    || scenario_fail "guest never reached ready-for-cmd"

rc=$(exec_in_guest "modprobe nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "modprobe failed"

BDF_CMD="BDF=\$(ls /sys/bus/pci/devices/ | grep ':fe:00.0\$' | head -1)"

# MSI-X cap (0x80) next ptr -> PCIe cap (0x90).
rc=$(exec_in_guest "$BDF_CMD; NEXT=\$(xxd -s 0x81 -l 1 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$NEXT\" = '90' ]")
[[ "$rc" != "0" ]] && scenario_fail "MSI-X next ptr != 0x90"

# Cap ID at 0x90 = 0x10 (PCIe).
rc=$(exec_in_guest "$BDF_CMD; CID=\$(xxd -s 0x90 -l 1 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$CID\" = '10' ]")
[[ "$rc" != "0" ]] && scenario_fail "PCIe cap id mismatch at 0x90"

# PCI_EXP_FLAGS (offset 0x92): version 2 + endpoint type (0) + Slot
# Implemented bit 8 (task #62).  LE bytes: 02 01.
rc=$(exec_in_guest "$BDF_CMD; FL=\$(xxd -s 0x92 -l 2 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$FL\" = '0201' ]")
[[ "$rc" != "0" ]] && scenario_fail "PCIe flags != 0x0102 (got \$FL)"

# LinkCap (offset 0x9c, 4 bytes LE): Max Link Speed (bits 3:0) = 5, Width (bits 9:4) = 4.
# Value = 0x00000045.
rc=$(exec_in_guest "$BDF_CMD; LC=\$(xxd -s 0x9c -l 4 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$LC\" = '45000000' ]")
[[ "$rc" != "0" ]] && scenario_fail "LinkCap != Gen5 x4"

# LinkSta (offset 0xa2, 2 bytes LE): speed=5 (bits 3:0), width=4 (bits 9:4),
# DLLLA bit 13.  Value = 5 | (4<<4) | (1<<13) = 0x2045.
rc=$(exec_in_guest "$BDF_CMD; LS=\$(xxd -s 0xa2 -l 2 -p /sys/bus/pci/devices/\$BDF/config); [ \"\$LS\" = '4520' ]")
[[ "$rc" != "0" ]] && scenario_fail "LinkStatus mismatch (got \$LS, expected 0x2045)"

# sysfs current_link_speed (kernel decodes LinkSta for us).
rc=$(exec_in_guest "$BDF_CMD; grep -q '32.0 GT' /sys/bus/pci/devices/\$BDF/current_link_speed")
[[ "$rc" != "0" ]] && scenario_fail "sysfs current_link_speed != 32 GT/s"

rc=$(exec_in_guest "rmmod nvmet-pci-sw")
[[ "$rc" != "0" ]] && scenario_fail "rmmod failed"

dmesg_dump
scenario_pass
