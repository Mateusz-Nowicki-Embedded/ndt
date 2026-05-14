# configs

Per-version kernel configs consumed by `scripts/build-kernel.sh`.

Naming: `linux-v<tag>.config`, matching tags of `third_party/linux-fork`
(e.g. `linux-v6.9.config`, `linux-v7.0.config`).  `build-kernel.sh` picks
the file that matches the submodule's current tag.

## Adding a config for a new kernel version

```sh
# 1. Point the submodule at the new tag (see top-level README).
# 2. Seed the new config from the closest existing one.
cp configs/linux-v7.0.config configs/linux-v6.9.config

# 3. Refresh against the new source so new/removed symbols are resolved.
make -C third_party/linux-fork \
     O=$PWD/build/linux \
     KCONFIG_CONFIG=$PWD/configs/linux-v6.9.config \
     olddefconfig

# 4. Commit the resolved config.
git add configs/linux-v6.9.config
git commit -m "Add v6.9 kernel config"
```
