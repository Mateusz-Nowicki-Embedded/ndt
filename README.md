# ndt — NVMe Driver Tester

A test harness for the Linux NVMe driver.

NDT boots a locally built kernel under QEMU, brings up the
[`nvmet-pci-sw`](third_party/nvmet-pci-sw/) software NVMe endpoint inside
the guest (no QEMU-emulated NVMe device), and drives blktests +
scenario scripts against the resulting `/dev/nvme0n1`.

## Layout

- `third_party/` — submodules:
  - `linux-fork` — Linux kernel fork, pinned at the tested version.
  - `nvmet-pci-sw` — software NVMe PCIe endpoint built as an
    out-of-tree module against `linux-fork`; provides the
    `/dev/nvme0n1` the tests run against.
  - `qemu-nvme` — fork of QEMU.  Carries custom HMP NVMe knobs from
    the old QEMU-emul era; today NDT uses it as a plain
    `qemu-system-x86_64` (no `-device nvme`).
  - `nvme-cli-fork` — `nvme-cli` used inside the guest to issue admin
    / I/O commands.
  - `blktests-fork` — `blktests` checkout with NDT-specific test
    cases (e.g. `nvme/068`, `nvme/069`).
  - `pcimem` — `mmap`-based BAR poke tool used by some tests to
    manipulate MSI-X mask bits directly.
- `initramfs/` — guest root filesystem source (`rootfs/`) and the
  prebuilt `initramfs.cpio.gz`.  PID 1 is `rootfs/init`: brings up
  `null_blk + nvmet + nvmet-pci-sw`, then sits on a `ttyS1` command
  loop (RUN / EXEC / GO / DMESG / EXIT) driven by the host.
- `build-all.sh` — top-level wrapper: kernel → nvmet-pci-sw → QEMU
  → blktests → nvme-cli → pcimem → initramfs.
- `configs/` — per-kernel-version `.config` files
  (`linux-v7.0.config` debug, `linux-v7.0-perf.config` perf).
- `scripts/`
  - `build-*.sh` — per-component builds invoked by `build-all.sh`.
  - `run-qemu.sh` — boots kernel + initramfs in QEMU with two
    server sockets: `ttyS0` (`/tmp/qemu-serial.sock`) and `ttyS1`
    (`/tmp/qemu-ctrl.sock`).
  - `qemu-ctrl.sh` — pushes a line into `ttyS1` (releases the
    `ready-for-cmd` gate, sends RUN / EXEC commands).
  - `refresh-nvme-mod.sh` — narrow loop: rebuild just the NVMe
    modules and repack the cpio.
- `tests/` — host-side scenario scripts (`NNN-name.sh`) driven by
  `ndt.sh`.  Sourced helper library: `tests/lib/scenario.sh`.
- `build/` *(gitignored)* — populated by the build scripts.

## Getting the sources

```sh
git clone --recurse-submodules git@github.com:Mateusz-Nowicki-Embedded/ndt.git
```

If you already cloned without `--recurse-submodules`:

```sh
git submodule update --init --recursive
```

## What ndt does

`ndt.sh` runs scenario scripts from `tests/NNN-name.sh` under QEMU.
Each (test × iteration) gets its own fresh QEMU session and a dedicated
artifact directory under `/tmp/ndt/<run-id>/`.

For each iteration:

1. boots a fresh QEMU,
2. `rootfs/init` modprobes `null_blk + nvmet + nvmet-pci-sw`, opens
   the configfs subsystem + port, waits for `/dev/nvme0n1`, then
   emits `NDT_PHASE ready-for-cmd`,
3. the host scenario script drives the guest via `ttyS1`
   (`run_blktest`, `exec_in_guest`, `dmesg_dump`, ...),
4. scenario writes its verdict (`scenario_pass` / `scenario_fail`),
5. the runner shuts the guest down and records `PASS` / `FAIL`.

Usage:

```sh
./ndt.sh --test=1                       # single scenario, 1 iter
./ndt.sh --test=40,55 --iteration=10    # batched: each test 10× back-to-back
./ndt.sh --test=1 -i 10 --stop-at-fail  # abort whole run on first FAIL
```
