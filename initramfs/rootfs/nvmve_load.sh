#!/bin/bash

insmod /lib/modules/7.1.0-rc3/extra/vnvme.ko \
    bar0_phys=0x100000000 \
    bar0_size=0x10000 \
    s_vid=0x1AF4 \
    s_did=0x10F0 \
    e_vid=0x1AF4 \
    e_did=0x10F1
