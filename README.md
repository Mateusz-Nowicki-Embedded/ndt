# ndt — NVMe Driver Tester

A test harness for the Linux NVMe driver.

`ndt` is a wrapper repository that ties together the components used to
exercise and validate the kernel's NVMe driver.

## Layout

- `third_party/` — submodules pointing at the moving pieces:
  - `linux-fork` — Linux kernel fork, pinned at the tested version.
  - `qemu-nvme` — fork of QEMU with NVMe-focused monitor commands and
    fault-injection hooks used to drive the virtual controller.
  - `nvme-cli-fork` — fork of `nvme-cli` used inside the guest to issue
    admin / I/O commands and read controller state.
  - `blktests-fork` — fork of `blktests` carrying the NVMe driver test
    cases run inside the guest.
- `initramfs/` — guest root filesystem source (`rootfs/`) and the
  prebuilt `initramfs.cpio.gz` shipped in git.  Contents are stable
  across most runs and do not need to be rebuilt for every test.
- `build-all.sh` — top-level wrapper that rebuilds kernel, QEMU,
  blktests, nvme-cli, and finally the initramfs image.
- `configs/` — per-kernel-version `.config` files
  (`linux-v6.9.config`, `linux-v7.0.config`, ...) consumed by
  `build-kernel.sh`.
- `scripts/`
  - `build-kernel.sh`, `build-qemu.sh`, `build-blktests.sh`,
    `build-nvme-cli.sh`, `build-initramfs.sh` — per-component builds
    invoked by `build-all.sh`.
  - `run-qemu.sh` — boots the locally built kernel + initramfs in QEMU.
    Opens three host-side sockets: serial console (`ttyS0`), guest
    control channel (`ttyS1`), and HMP monitor.
  - `qemu-hmp.sh` — one-shot HMP command sender (writes to the monitor
    socket, prints the reply).  Used by `ndt.sh` to program e.g.
    `nvme_completion_delay`.
  - `qemu-ctrl.sh` — pushes a line into the guest's `ttyS1` control
    channel; releases the init script's "ready-for-cmd" gate.
  - `refresh-nvme-mod.sh` — narrow loop: rebuild just the NVMe modules
    and repack the cpio.
- `build/` *(gitignored)* — populated by the build scripts.
- `disks/` *(gitignored)* — NVMe namespace images for the QEMU device.


## Getting the sources

```sh
git clone --recurse-submodules git@github.com:Mateusz-Nowicki-Embedded/ndt.git
```

If you already cloned without `--recurse-submodules`:

```sh
git submodule update --init --recursive
```

## What NDT does

NDT drives a single blktests case end-to-end against the NVMe driver
running inside QEMU.  The entry point is a bash script that takes a
test identifier (e.g. `nvme/068`) and:

1. boots `qemu-nvme` with an emulated NVMe controller,
2. waits for the guest's `NDT_PHASE ready-for-cmd` sentinel
   (driver loaded, I/O queues created),
3. programs anything requested via the HMP monitor — currently
   per-SQ `nvme_completion_delay`,
4. releases the guest gate (`GO` on `ttyS1`) so the test starts,
5. captures the test's exit status and output,
6. shuts the guest down cleanly,
7. prints a single `PASS` / `FAIL` line plus the captured log.

Usage sketch:

```sh
./ndt.sh nvme/068
./ndt.sh 32 cq-delay=1:1000           # delay SQ 1 by 1 s before the test
./ndt.sh t=32,50 i=4 --stop-at-fail   # multi-test loop, abort on first fail
```

The intent is that CI and local "did I break the driver?" loops both
go through the same one-liner.
