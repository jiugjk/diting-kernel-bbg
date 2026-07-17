# diting Kernel + Baseband-guard (GitHub Actions)

为 **Xiaomi diting**（Redmi K60 / POCO F5 Pro）基于官方开源分支
`bsp-diting-s-oss`（Android 12 / Linux 5.10 GKI 世代）构建可刷写内核产物，
并在树内集成 [Baseband-guard](https://github.com/vc-teahouse/Baseband-guard)。

> 用户态 ROM 可以不是 Android 12（例如 HyperOS 2），但该设备内核基线仍是
> **android12-5.10**。本仓库按官方 OSS 的 Android12 内核构建。

---

## 重要说明

| 组件 | 集成方式 | 说明 |
|------|----------|------|
| **Baseband-guard** | **树内 LSM** | 官方 `setup.sh` → `security/baseband-guard`，`CONFIG_BBG=y` |
| **panda-hide** | **树内 kprobe+LSM 移植** | 源码在 `panda-hide-in-tree/`，集成到 `security/panda-hide/`（**不再依赖 KernelPatch**） |
| **panda-hide.kpm**（可选） | 独立 KPM job | 仅当你仍要在 APatch/KernelPatch 上热加载时使用 |

### panda-hide 树内移植（核心）

上游 KPM 不能直接编进 `vmlinux`。本仓库按符号一一对应移植：

| 上游 hook | 树内机制 |
|-----------|----------|
| `seq_put_decimal_ull` / `seq_puts` | kprobe pre |
| `proc_pid_wchan` / `do_task_stat` | kretprobe |
| `show_map_vma` / `__get_task_comm` | kretprobe |
| `access_remote_vm` | kretprobe |
| `openat` / `faccessat` | kprobe 早退 `-ENOENT` + LSM `file_open` |
| `connect` | LSM `socket_connect` |

详情：`docs/PANDA_HIDE_INTREE.md`、`panda-hide-in-tree/HOOK_MAP.md`

---

## 官方构建事实（来自 OSS，非臆测）

来源：`MiCode/Xiaomi_Kernel_OpenSource` @ `bsp-diting-s-oss`

| 项 | 值 |
|----|-----|
| Tip commit（拉取时以实际 `git rev-parse` 为准） | `cb7a356ae138e77992ae199eebb86559d825a673`（历史 tip，CI 会记录实际 SHA） |
| 官方说明 defconfig | commit message 写 `diting_user_defconfig`；树内实际为 **fragment 合并** |
| BUILD_CONFIG | `build.config.msm.diting` |
| Variants | `consolidate`（默认）、`gki` |
| DEFCONFIG 基座 | `gki_defconfig` + `vendor/diting_GKI.config`（+ consolidate 时再叠 fragment） |
| 工具链 | **LLVM + clang-r416183b**（`build.config.common`） |
| ARCH | `arm64` |
| BRANCH / KMI | `android12-5.10` / `KMI_GENERATION=9` |
| 产物 | `Image`、`modules`、`dtbs`、可选 `dtbo.img` |

与你提供的设备信息对齐：

- 设备内核：`5.10.236-android12-9-...` → **android12 / KMI 9**
- 设备 config：`Android clang 12.0.5` → **r416183b** 一代
- `cmdline` 指纹：`diting:12/OS2.0.209.0.VLFCNXM:user`

---

## 已启用的 Baseband-guard 配置

| 配置项 | 取值 | 含义 |
|--------|------|------|
| `CONFIG_SECURITY` | `y` | LSM 框架 |
| `CONFIG_BBG` | `y` | 启用 Baseband-guard |
| `CONFIG_BBG_BLOCK_BOOT` | `y` | 保护 boot 分区写（系统内刷内核可能失败，需 recovery/fastboot） |
| `CONFIG_BBG_BLOCK_RECOVERY` | `y` | 保护 recovery 分区写 |
| `CONFIG_LSM` | 原列表 + `,baseband_guard` | 把 BBG 加入 LSM 启动列表 |

fragment 文件：`config/bbg.fragment`  
应用逻辑：`scripts/apply-bbg-config.sh`（不覆盖原始 vendor defconfig 文件）

---

## 在 GitHub Actions 上编译

1. 把本目录推到你的 GitHub 仓库。
2. Actions → **Build diting kernel + Baseband-guard** → **Run workflow**。
3. 参数：
   - `variant`: 建议 `consolidate`（完整设备向）
   - `bbg_ref`: 默认 `main`
   - `kernel_branch`: 默认 `bsp-diting-s-oss`
   - `build_kpm`: 是否额外编 panda-hide KPM
4. 结束后下载 Artifact：
   - `diting-kernel-bbg-<variant>-<run>`
   - （可选）`panda-hide-kpm-<run>`

### 本地复现同一套命令

```bash
# 需要：git curl make python3 clang 下载权限；建议 ≥64GB 磁盘 / 16GB RAM
chmod +x scripts/*.sh
export WORK_DIR=$PWD/work
export VARIANT=consolidate
export BBG_REF=main
export KERNEL_BRANCH=bsp-diting-s-oss
export JOBS=$(nproc)
./scripts/build-kernel.sh
./scripts/verify.sh work/dist work/out
```

可选 KPM：

```bash
./scripts/build-kpm-panda-hide.sh
```

---

## 脚本职责

| 脚本 | 作用 |
|------|------|
| `scripts/integrate-bbg.sh` | clone BBG + 运行官方 setup / 接线 Makefile&Kconfig |
| `scripts/apply-bbg-config.sh` | merge fragment + 规范化 `CONFIG_LSM` |
| `scripts/build-kernel.sh` | 拉内核、下 clang-r416183b、配置、编译、打包 |
| `scripts/verify.sh` | 镜像魔数 / BBG 配置 / 校验和 等基础检查 |
| `scripts/build-kpm-panda-hide.sh` | 按项目要求编 KPM |

---

## 产物布局（成功后）

```
work/dist/
  boot/Image
  boot/Image.gz
  dtb/*.dtb[o]          # 若源码生成
  modules/modules.tar.gz
  config/final.config
  patches/
    bbg.fragment
    0001-security-bbg-wiring.diff   # 若可生成
    INTEGRATION_FILES.txt
  meta/build-info.txt
  meta/bbg-integration.txt
  SHA256SUMS.txt
  kpm/panda-hide.kpm    # 仅 KPM job
```

CI 不会伪造不存在的 `boot.img` / `AnyKernel3` zip。  
**可刷写 boot.img** 需要你本机的 stock `boot.img` + `magiskboot`/`unpack_bootimg` 替换 kernel，
或 AnyKernel3 包装——脚本刻意不编造打包参数。

---

## 刷写前注意（必读）

1. **未在真机启动验证**（无本仓库的 Actions 只做编译期验证）。
2. **OSS tip（2023）与当前在用 HyperOS 内核 5.10.236（2025）存在版本差**：
   - 模块 ABI/KMI 与 vendor_dlkm **很可能不兼容**
   - 更稳妥做法：只替换 `boot` 内核 Image，并尽量禁用/避开不匹配的 vendor_dlkm 变更
3. `CONFIG_BBG_BLOCK_BOOT=y`：系统内刷写 boot 可能被拒绝，请用 **fastboot/recovery**。
4. 刷写前备份：`boot`、`dtbo`、`vendor_boot`（如有）、EFS/modem 相关分区。
5. 建议先 `fastboot boot` 临时启动（若设备/引导链支持），确认后再 `flash`。
6. 解锁 Bootloader；注意 AVB/vbmeta（部分设备需 `vbmeta` disable flags）。
7. panda-hide 需要设备已具备 **KernelPatch / APatch** 环境，与 BBG 内核集成相互独立。

---

## 已知风险

- 单树构建（非完整 mixed GKI + prebuilt GKI Image）与厂商完整 CI 仍有差距。
- 缺少设备专属 DTBO 选择时，可能需继续使用 stock dtbo。
- 开启 boot/recovery 写保护后，救砖路径依赖 fastboot。
- 官方 `build.config.msm.diting` 的 mixed build 依赖 `common/` GKI 树与 prebuilts；
  本脚本采用 OSS 单树 + 官方 fragment，以便在 GitHub Actions 可独立复现。

---

## 许可证

- 构建脚本：与仓库相同（建议 MIT/Apache，可自定）
- 内核源码：GPL-2.0（小米/高通/AOSP）
- Baseband-guard：GPL-2.0
- kpm-panda-hide：遵循其仓库许可证 + KernelPatch 约束
