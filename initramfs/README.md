# initramfs

This directory holds the guest-side root filesystem used by `run-qemu.sh`.

- `rootfs/` — source tree of the initramfs: `init`, `/etc`, `/usr/local/bin`,
  busybox install layout, staged NVMe `.ko` modules.  Edit this when you
  want to add tools or change boot behaviour.
- `initramfs.cpio.gz` — prebuilt binary image consumed by QEMU.  Tracked
  in git so the test environment boots without a rebuild.

Rebuild the image after editing `rootfs/`:

```sh
../scripts/build-initramfs.sh
```

Rebuilding only the NVMe kernel modules and repacking the cpio:

```sh
../scripts/refresh-nvme-mod.sh
```
