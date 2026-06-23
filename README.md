------ early POC stage ------

Goal: create framework for running blktests on qemu with virtual nvme drive.

Virtual NVMe drive: it's based on kernel module not a qemu native nvme emulation

vnvme: https://github.com/Mateusz-Nowicki-Embedded/vnvme



Run test:
./ndt.sh 069

Manual interactive session:

```
./ndt.sh - starts NVMe driver tester interactiver session
```

```
bash-5.3# ./vnvme_load.sh
[    6.225162] nvmet: adding nsid 1 to subsystem vnvme-ss
[    6.226957] vnvme: loading out-of-tree module taints kernel.
[    6.227657] vnvme: init
[    6.227816] vnvme: vnvme_dev_init()
[    6.228220] [switch]: device succesfully registered
[    6.228412] [switch]: .start=0x100000000, .end=0x1000fffff
[    6.228584] [switch]: got domain nr: 0x12345
[    6.228739] platform vnvme: PCI host bridge to bus 12345:00
[    6.228912] pci_bus 12345:00: root bus resource [bus 00-ff]
[    6.229123] pci_bus 12345:00: root bus resource [mem 0x100000000-0x1000fffff 64bit pref]
[    6.229375] pci 12345:00:00.0: [1af4:10f0] type 01 class 0x060400 PCIe Root Port
[    6.229602] pci 12345:00:00.0: PCI bridge to [bus 00]
[    6.229759] pci 12345:00:00.0:   bridge window [mem 0x100000000-0x1000fffff 64bit pref]
[    6.230044] pci 12345:00:00.0: bridge configuration invalid ([bus 00-00]), reconfiguring
[    6.230308] pci 12345:00:00.0: PCI bridge to [bus 01-ff]
[    6.230471] pci_bus 12345:01: busn_res: [bus 01-ff] end is updated to 01
[    6.230676] pci 12345:00:00.0: bridge window [mem size 0x00200000]: can't assign; no space
[    6.230922] pci 12345:00:00.0: bridge window [mem size 0x00200000]: failed to assign
[    6.231170] pci 12345:00:00.0: bridge window [mem size 0x00200000 64bit pref]: can't assign; no space
[    6.231440] pci 12345:00:00.0: bridge window [mem size 0x00200000 64bit pref]: failed to assign
[    6.231723] pci 12345:00:00.0: bridge window [mem size 0x00200000]: can't assign; no space
[    6.231972] pci 12345:00:00.0: bridge window [mem size 0x00200000]: failed to assign
[    6.232255] pci 12345:00:00.0: bridge window [mem size 0x00200000 64bit pref]: can't assign; no space
[    6.232787] pci 12345:00:00.0: bridge window [mem size 0x00200000 64bit pref]: failed to assign
[    6.233548] pci 12345:00:00.0: PCI bridge to [bus 01]
[    6.234159] pcieport 12345:00:00.0: AER: enabled with IRQ 24
[    6.234722] pcieport 12345:00:00.0: pciehp: Slot #1 AttnBtn- PwrCtrl+ MRL- AttnInd+ PwrInd+ HotPlug+ Surprise- Interlock- NoCompl+ IbPresDis- LLActRep+
[    6.236460] [target]: registered nvmet PCI transport
[    6.238224] [target]: nvmet add_port portid=1

bash-5.3# lspci
0000:00:00.0 Host bridge: Intel Corporation 82G33/G31/P35/P31 Express DRAM Controller
0000:00:01.0 VGA compatible controller: Device 1234:1111 (rev 02)
0000:00:02.0 Ethernet controller: Intel Corporation 82574L Gigabit Network Connection
0000:00:1f.0 ISA bridge: Intel Corporation 82801IB (ICH9) LPC Interface Controller (rev 02)
0000:00:1f.2 SATA controller: Intel Corporation 82801IR/IO/IH (ICH9R/DO/DH) 6 port SATA Controller [AHCI mode] (rev 02)
0000:00:1f.3 SMBus: Intel Corporation 82801I (ICH9 Family) SMBus Controller (rev 02)
12345:00:00.0 PCI bridge: Red Hat, Inc. Device 10f0 (rev 01)
```



```
Hotplug:
bash-5.3# ./hotplug.sh
[    9.062132] configfs: hotplug requested
[    9.062407] vnvme: hotplug detected!
[    9.062576] [SM]: PowerOn
[    9.062699] [SM]: new event : 10 accepted
bash-5.3# [    9.062977] [SM]: active event updated: [NO-OP] -> [POWER_ON]
[    9.063234] pci 12345:01:00.0: [1af4:10f1] type 00 class 0x010802 PCIe Endpoint
[    9.063545] pci 12345:01:00.0: BAR 0 [mem 0x00000000-0x0000ffff 64bit pref]
[    9.063890] pcieport 12345:00:00.0: bridge window [mem size 0x00000000 64bit pref] to [bus 01] add_size 200000 add_align 100000
[    9.064451] pcieport 12345:00:00.0: bridge window [mem size 0x00000000] to [bus 01] add_size 200000 add_align 100000
[    9.064902] pcieport 12345:00:00.0: bridge window [mem size 0x00200000]: can't assign; no space
[    9.065279] pcieport 12345:00:00.0: bridge window [mem size 0x00200000]: failed to assign
[    9.065619] pcieport 12345:00:00.0: bridge window [mem size 0x00200000 64bit pref]: can't assign; no space
[    9.066021] pcieport 12345:00:00.0: bridge window [mem size 0x00200000 64bit pref]: failed to assign
[    9.066430] pcieport 12345:00:00.0: bridge window [mem size 0x00200000]: can't assign; no space
[    9.066818] pcieport 12345:00:00.0: bridge window [mem size 0x00200000]: failed to assign
[    9.067161] pcieport 12345:00:00.0: bridge window [mem size 0x00200000 64bit pref]: can't assign; no space
[    9.067564] pcieport 12345:00:00.0: bridge window [mem size 0x00200000 64bit pref]: failed to assign
[    9.068000] [switch]: triggering HotPlug IRQ...
[    9.068146] nvme nvme0: pci function 12345:01:00.0
[    9.068230] [SM]: state updated: [OFF] -> [DISABLED]
[    9.068298] pcieport 12345:00:00.0: pciehp: Slot(1): Card present
[    9.068300] pcieport 12345:00:00.0: pciehp: Slot(1): Link Up
[    9.068494] nvme 12345:01:00.0: enabling device (0000 -> 0002)
[    9.068713] [SM]: active event updated: [POWER_ON] -> [NO-OP]
[    9.069028] [SM]: MSE=1
[    9.070037] [SM]: BME=1
[    9.070308] [SM]: CC.EN = 1
[    9.070441] [SM]: new event : 1 accepted
[    9.070622] [SM]: active event updated: [NO-OP] -> [CNT_ENABLE]
[    9.071096] nvmet: Created nvm controller 1 for subsystem vnvme-ss for NQN nqn.2014-08.org.nvmexpress:uuid:0931c80b-b230-450e-8de9-5b9b64a685c8.
[    9.071680] [target]: nvmet create_cq cqid=0 depth=32 vector=0 db=0x1004
[    9.071995] [target]: nvmet create_sq sqid=0 cqid=0 depth=32 db=0x1000
[    9.072611] [target]: controller enabled "vnvme-ss", 17 queues, csts=0x1
[    9.072895] [SM]: state updated: [DISABLED] -> [WAIT_FOR_READY]
[    9.073353] [SM]: state updated: [WAIT_FOR_READY] -> [ENABLED]
[    9.073600] [SM]: active event updated: [CNT_ENABLE] -> [NO-OP]
[    9.074763] [target]: nvmet create_cq cqid=1 depth=1024 vector=1 db=0x100c
[    9.075135] [target]: nvmet create_sq sqid=1 cqid=1 depth=1024 db=0x1008
[    9.075503] [target]: nvmet create_cq cqid=2 depth=1024 vector=2 db=0x1014
[    9.075879] [target]: nvmet create_sq sqid=2 cqid=2 depth=1024 db=0x1010
[    9.076188] [target]: nvmet create_cq cqid=3 depth=1024 vector=3 db=0x101c
[    9.076536] [target]: nvmet create_sq sqid=3 cqid=3 depth=1024 db=0x1018
[    9.076849] [target]: nvmet create_cq cqid=4 depth=1024 vector=4 db=0x1024
[    9.077183] [target]: nvmet create_sq sqid=4 cqid=4 depth=1024 db=0x1020
[    9.077493] [target]: nvmet create_cq cqid=5 depth=1024 vector=5 db=0x102c
[    9.077809] [target]: nvmet create_sq sqid=5 cqid=5 depth=1024 db=0x1028
[    9.078120] [target]: nvmet create_cq cqid=6 depth=1024 vector=6 db=0x1034
[    9.078435] [target]: nvmet create_sq sqid=6 cqid=6 depth=1024 db=0x1030
[    9.078749] [target]: nvmet create_cq cqid=7 depth=1024 vector=7 db=0x103c
[    9.079066] [target]: nvmet create_sq sqid=7 cqid=7 depth=1024 db=0x1038
[    9.079379] [target]: nvmet create_cq cqid=8 depth=1024 vector=8 db=0x1044
[    9.079697] [target]: nvmet create_sq sqid=8 cqid=8 depth=1024 db=0x1040
[    9.080007] [target]: nvmet create_cq cqid=9 depth=1024 vector=9 db=0x104c
[    9.080346] [target]: nvmet create_sq sqid=9 cqid=9 depth=1024 db=0x1048
[    9.080656] [target]: nvmet create_cq cqid=10 depth=1024 vector=10 db=0x1054
[    9.081001] [target]: nvmet create_sq sqid=10 cqid=10 depth=1024 db=0x1050
[    9.081364] [target]: nvmet create_cq cqid=11 depth=1024 vector=11 db=0x105c
[    9.082021] [target]: nvmet create_sq sqid=11 cqid=11 depth=1024 db=0x1058
[    9.082687] [target]: nvmet create_cq cqid=12 depth=1024 vector=12 db=0x1064
[    9.083350] [target]: nvmet create_sq sqid=12 cqid=12 depth=1024 db=0x1060
[    9.084002] [target]: nvmet create_cq cqid=13 depth=1024 vector=13 db=0x106c
[    9.084664] [target]: nvmet create_sq sqid=13 cqid=13 depth=1024 db=0x1068
[    9.085016] [target]: nvmet create_cq cqid=14 depth=1024 vector=14 db=0x1074
[    9.085351] [target]: nvmet create_sq sqid=14 cqid=14 depth=1024 db=0x1070
[    9.085674] [target]: nvmet create_cq cqid=15 depth=1024 vector=15 db=0x107c
[    9.086018] [target]: nvmet create_sq sqid=15 cqid=15 depth=1024 db=0x1078
[    9.086350] [target]: nvmet create_cq cqid=16 depth=1024 vector=16 db=0x1084
[    9.086686] [target]: nvmet create_sq sqid=16 cqid=16 depth=1024 db=0x1080
[    9.087000] nvme nvme0: 16/0/0 default/read/poll queues

bash-5.3# lspci
0000:00:00.0 Host bridge: Intel Corporation 82G33/G31/P35/P31 Express DRAM Controller
0000:00:01.0 VGA compatible controller: Device 1234:1111 (rev 02)
0000:00:02.0 Ethernet controller: Intel Corporation 82574L Gigabit Network Connection
0000:00:1f.0 ISA bridge: Intel Corporation 82801IB (ICH9) LPC Interface Controller (rev 02)
0000:00:1f.2 SATA controller: Intel Corporation 82801IR/IO/IH (ICH9R/DO/DH) 6 port SATA Controller [AHCI mode] (rev 02)
0000:00:1f.3 SMBus: Intel Corporation 82801I (ICH9 Family) SMBus Controller (rev 02)
12345:00:00.0 PCI bridge: Red Hat, Inc. Device 10f0 (rev 01)
12345:01:00.0 Non-Volatile memory controller: Red Hat, Inc. Device 10f1 (rev 01)

```



```
./fio.sh
vnvme-write: (g=0): rw=write, bs=(R) 4096B-4096B, (W) 4096B-4096B, (T) 4096B-4096B, ioengine=libaio, iodepth=32
...
fio-3.42
Starting 8 processes
Jobs: 8 (f=8): [W(8)][100.0%][w=8021MiB/s][w=2053k IOPS][eta 00m:00s]
vnvme-write: (groupid=0, jobs=8): err= 0: pid=244: Tue Jun 16 21:43:14 2026
  write: IOPS=2130k, BW=8321MiB/s (8725MB/s)(244GiB/30001msec)
    slat (nsec): min=633, max=4097.1k, avg=1740.73, stdev=6616.44
    clat (nsec): min=240, max=5578.9k, avg=118184.36, stdev=101474.02
     lat (usec): min=5, max=5580, avg=119.93, stdev=101.95
    clat percentiles (usec):
     |  1.00th=[   46],  5.00th=[   56], 10.00th=[   60], 20.00th=[   69],
     | 30.00th=[   73], 40.00th=[   77], 50.00th=[   87], 60.00th=[  103],
     | 70.00th=[  123], 80.00th=[  149], 90.00th=[  202], 95.00th=[  265],
     | 99.00th=[  498], 99.50th=[  660], 99.90th=[ 1188], 99.95th=[ 1532],
     | 99.99th=[ 2573]
   bw (  MiB/s): min= 7167, max= 9334, per=99.97%, avg=8318.25, stdev=52.44, samples=480
   iops        : min=1834800, max=2389520, avg=2129470.88, stdev=13424.04, samples=480
  lat (nsec)   : 250=0.01%, 500=0.01%, 750=0.01%, 1000=0.01%
  lat (usec)   : 2=0.01%, 4=0.01%, 10=0.01%, 20=0.10%, 50=1.62%
  lat (usec)   : 100=56.80%, 250=35.66%, 500=4.82%, 750=0.64%, 1000=0.19%
  lat (msec)   : 2=0.13%, 4=0.02%, 10=0.01%
  cpu          : usr=19.37%, sys=39.62%, ctx=3684641, majf=0, minf=82
  IO depths    : 1=0.1%, 2=0.1%, 4=0.1%, 8=0.1%, 16=0.1%, 32=100.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.1%, 64=0.0%, >=64=0.0%
     issued rwts: total=0,63903709,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0.00ns, window=0.00ns, percentile=100.00%, depth=32

Run status group 0 (all jobs):
  WRITE: bw=8321MiB/s (8725MB/s), 8321MiB/s-8321MiB/s (8725MB/s-8725MB/s), io=244GiB (262GB), run=30001-30001msec

Disk stats (read/write):
  nvme0n1: ios=85/63711156, sectors=2616/509689248, merge=0/0, ticks=0/5366572, in_queue=5366572, util=99.75%

```
