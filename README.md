# ndt — NVMe Driver Tester

A test harness for the Linux NVMe driver.

`ndt` is a wrapper repository that ties together the three components used
to exercise and validate the kernel's NVMe driver:

- [`third_party/qemu-nvme`](third_party/qemu-nvme) — fork of QEMU with
  NVMe-focused monitor commands and fault-injection hooks used to drive
  the virtual controller from the host side.
- [`third_party/nvme-cli-fork`](third_party/nvme-cli-fork) — fork of
  `nvme-cli` used inside the guest to issue admin / I/O commands and
  read controller state.
- [`third_party/blktests-fork`](third_party/blktests-fork) — fork of
  `blktests` carrying the NVMe driver test cases run inside the guest.


## Getting the sources

```sh
git clone --recurse-submodules git@github.com:Mateusz-Nowicki-Embedded/ndt.git
```

If you already cloned without `--recurse-submodules`:

```sh
git submodule update --init --recursive
```
