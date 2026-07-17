# Delivery notes — diting + Baseband-guard (GHA)

Generated for: Xiaomi **diting**, kernel branch **bsp-diting-s-oss** (Android12-5.10).

## What this repository is

A **builder repository** (scripts + GitHub Actions), not a fork of the full kernel tree.
The CI job clones MiCode OSS at runtime, integrates Baseband-guard, builds, and uploads artifacts.

## Source commits (recorded at clone time in artifacts)

| Component | Repo | Ref | Note |
|-----------|------|-----|------|
| Kernel | MiCode/Xiaomi_Kernel_OpenSource | `bsp-diting-s-oss` | CI writes actual SHA to `meta/build-info.txt` |
| Baseband-guard | vc-teahouse/Baseband-guard | `main` (configurable) | SHA in `meta/bbg-integration.txt` |
| kpm-panda-hide | P4nda0s/kpm-panda-hide | `main` | Optional job; KPM only |
| KernelPatch | bmax121/KernelPatch | default branch | Only for KPM build |

Historical tip of `bsp-diting-s-oss` observed during research:

- `cb7a356ae138e77992ae199eebb86559d825a673`
- Message mentions `diting_user_defconfig` and qcom S vendor tag; tree uses fragment-based defconfigs.

## Toolchain

| Tool | Version / path |
|------|----------------|
| Clang/LLVM | **clang-r416183b** (Android prebuilt; Clang 12.0.5 family) |
| Assembler | LLVM IAS (`LLVM_IAS=1`) |
| Linker | `ld.lld` |
| Host | Ubuntu 22.04 (GHA) |

Matches official `build.config.common`:

```
CLANG_PREBUILT_BIN=prebuilts-master/clang/host/linux-x86/clang-r416183b/bin
LLVM=1
BRANCH=android12-5.10
KMI_GENERATION=9
```

## Repeatable build entrypoint

```bash
./scripts/build-kernel.sh
```

Key env vars: `VARIANT`, `BBG_REF`, `KERNEL_BRANCH`, `WORK_DIR`, `JOBS`.

GitHub Actions workflow: `.github/workflows/build.yml`.

## Baseband-guard options forced on

```
CONFIG_SECURITY=y
CONFIG_BBG=y
CONFIG_BBG_BLOCK_BOOT=y
CONFIG_BBG_BLOCK_RECOVERY=y
CONFIG_LSM="<existing>,baseband_guard"
```

## kpm-panda-hide

**Not** integrated into the kernel image. Built as `panda-hide.kpm` per upstream Makefile:

```
make TARGET_COMPILE=aarch64-none-elf- KP_DIR=/path/to/KernelPatch
```

## Validation performed by CI

- Build exit code
- `Image` presence + ARM64 magic when applicable
- BBG Kconfig keys in `final.config`
- SHA-256 manifest
- **Not** performed: on-device boot, modem, camera, fingerprint, OTA, full KMI diff vs stock 5.10.236

## Flash packaging (out of scope for automatic invent)

Replace kernel in stock `boot.img` using your device’s known layout (`magiskboot`, `unpack_bootimg`, or AnyKernel3). Do not flash random Image without packaging.
