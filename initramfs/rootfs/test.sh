#!/bin/bash

echo 5000 > /sys/kernel/config/vnvme/drain_delay_ms
echo 1 > /sys/bus/pci/devices/12345\:01\:00.0/nvme/nvme0/reset_controller &
sleep 1
echo 1 > /sys/kernel/config/vnvme/hotremove

