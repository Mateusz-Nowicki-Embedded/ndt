# configs

Kernel configs consumed by `scripts/build-kernel.sh`.

- `linux-debug.config` — `DEBUG_INFO_DWARF5`, `GDB_SCRIPTS`, frame pointers,
  `LOCKDEP` + `PROVE_LOCKING`, `KASAN`, `KMEMLEAK`, `DEBUG_OBJECTS`,
  `SLUB_DEBUG`, `FUNCTION_TRACER` + `DYNAMIC_FTRACE`.  Slow, verbose,
  catches bugs.

- `linux-perf.config` — all of the above off.  `FTRACE` infra + tracepoints
  stay (blktrace, `nvme:` tracepoints still work), only specific expensive
  tracers are disabled.  `PREEMPT_NONE` for throughput.

Both share the same minimal base: no USB stack, no DRM/FB, no sound,
no wireless/bluetooth/infiniband, no virtio, no filesystems beyond
ext4 + tmpfs/proc/sysfs/configfs/devtmpfs.  Just enough to boot in
QEMU/KVM, run nvmet-pci-sw + null_blk under nvmet, and execute blktests.

## Selecting at build time

```
./scripts/build-kernel.sh                  # FLAVOR=debug (default)
FLAVOR=perf ./scripts/build-kernel.sh
```
