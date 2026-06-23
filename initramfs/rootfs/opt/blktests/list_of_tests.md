# list of tests added for NDT purpose
nvme/068 - NVMe reg read while endpoint has disabled MSE, expected to see 0xFFFFFFFF
nvme/069 - increase drain time via 'echo 5000 > /sys/kernel/config/vnvme/drain_delay_ms', run fio.sh for 30 secs, nvme reset, wait 1s, echo 1 > hotremove
nvme/070 - run fio for 30 secs + echo 1 > hotremove
