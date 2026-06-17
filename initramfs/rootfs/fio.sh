#!/bin/bash
fio --name=vnvme-write \
    --filename=/dev/nvme0n1 \
    --ioengine=libaio --direct=1 \
    --rw=write --bs=4k --iodepth=32 --numjobs=8 \
    --time_based --runtime=30 \
    --group_reporting
