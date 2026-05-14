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
- `scripts/`
  - `build-all.sh` — wrapper that rebuilds kernel, QEMU, blktests,
    nvme-cli, and finally the initramfs image.
  - `build-kernel.sh`, `build-qemu.sh`, `build-blktests.sh`,
    `build-nvme-cli.sh`, `build-initramfs.sh` — per-component builds.
  - `run-qemu.sh` — boots the locally built kernel + initramfs in QEMU.
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
2. runs the requested blktests case inside the guest,
3. captures the test's exit status and output,
4. shuts the guest down cleanly,
5. prints a single `PASS` / `FAIL` line plus the captured log.

Usage sketch:

```sh
./ndt.sh nvme/068
```

The intent is that CI and local "did I break the driver?" loops both
go through the same one-liner.
