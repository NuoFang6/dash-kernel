# mikernel / dash 资源导航

本文件是 `mikernel` 的仓库资源导航；文档总入口见
[docs/README.md](../README.md)。详细构建步骤见
[docs/kernel/README.md](../kernel/README.md)，版本锁定见
[dash/versions.env](../../dash/versions.env)。缺口的逐项搜索结果见
[GAP_RESEARCH.md](GAP_RESEARCH.md)，两个厂商模块的实测行为见
[DEVICE_MODULES.md](DEVICE_MODULES.md)。

目标设备：`dash` / REDMI Turbo 5 Max（MT6991），stock `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`，GKI 分支 `android15-6.6`，KMI 字符串 `android15-8`，4K 页。本页只维护资源、pin 和资产位置；当前版本/产物/实机状态见 [docs/STATUS.md](../STATUS.md)，缺口见 [OPEN_ISSUES.md](../kernel/OPEN_ISSUES.md)。部分章节保留早期调研痕迹，遇到冲突不要沿用旧状态。

> 大源码树（AOSP common、MiCode、CC 主内核）故意没有做成子模块，避免把几 GB 历史带进仓库；它们的浅克隆位置和上游地址在下文单独记录。

## 1. 子模块

以下子模块已加入 `.gitmodules` 和 git 索引。当前 clone 使用 `--depth 1`，但没有把 depth 写进 `.gitmodules`；新机器请用 `git clone --recurse-submodules --shallow-submodules` 或 `git submodule update --init --recursive --depth 1`。

| 路径 | 上游 | 分支 | 当前 pin | 用途 |
|---|---|---|---|---|
| [BakaSU](../../BakaSU) | https://github.com/Baka-SU/BakaSU.git | main | `d5e9e025b8b4` | BakaSU/KSU 内核源码（`BakaSU/kernel`），当前内建 + SUSFS |
| [third_party/sukisu-patch](../../third_party/sukisu-patch) | https://github.com/SukiSU-Ultra/SukiSU_patch.git | main | `eec45788c9a1` | SukiSU 补丁集合；`other/zram` 下有 lz4k/lz4k_oplus/lz4kd 参考 |
| [third_party/susfs4ksu](../../third_party/susfs4ksu) | https://gitlab.com/simonpunk/susfs4ksu.git | gki-android15-6.6 | `0606e19afae9` | SUSFS kernel patches；内核侧 SUSFS hook 调用点在 `dash/patches/010-bakasu-susfs/`，susfs.c/h 由本子模块安装 |
| [third_party/dash-droidspaces](../../third_party/dash-droidspaces) | https://github.com/lakitu12/kernel_dash_droidspaces.git | main | `6039943a9c15` | dash 的 DroidSpaces/SukiSU 参考项目；`patches/os4-vendor-hooks` 在这里；实验性，README 已报告 call site bootloop |
| [third_party/hyperos-lz4kd](../../third_party/hyperos-lz4kd) | https://github.com/2108282/hyperos-lz4kd.git | main | `e58761a19874` | 小米 14 的 LZ4KD/自动切换参考；非 delta zram 实现 |
| [third_party/tcp-brutal](../../third_party/tcp-brutal) | https://github.com/HyNetworks/tcp-brutal.git | master | `d2397ff8bca0` | TCP Brutal v2.0.1 外部内核模块；`make brutal` 构建，GPL-3.0，按需 insmod |
| [third_party/nomount](../../third_party/nomount) | https://github.com/maxsteeel/nomount.git | v2.3.1 | `dcd77d03e991` | NoMount VFS 路径重定向子系统；apply 时符号链接进 `fs/nomount`，`CONFIG_NOMOUNT=y` 内建（编译级验证，未实机验证） |
| [third_party/cc-dash-build](../../third_party/cc-dash-build) | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_build.git | dash-w-oss | `627ef9ba0d31` | CC dash 的 repo manifest / Kleaf 构建脚本 |
| [third_party/cc-dash-device-modules](../../third_party/cc-dash-device-modules) | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_device_modules.git | dash-w-oss | `94914f6bc83f` | dash DTS、`kernel/configs/dash*.config`、重实现的触摸/热管理/millet/mi_memory/UFS 模块源码 |
| [third_party/cc-dash-mtk-modules](../../third_party/cc-dash-mtk-modules) | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_mtk_modules.git | dash-w-oss | `d3e32dcf9f67` | MediaTek camera/connectivity/GPU/等模块源码 |
| [third_party/cc-dash-bazel-rules](../../third_party/cc-dash-bazel-rules) | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_bazel_mgk_rules.git | lineage-23.2 | `1573a08b7d6b` | CC dash Kleaf/MGK 构建规则 |
| [third_party/xiaomi-dada-closed-modules](../../third_party/xiaomi-dada-closed-modules) | https://github.com/klarnet2009/dada-closed-modules.git | main | `3c6328d3485a` | Xiaomi 15/SM8750 约 630 个闭源模块的**逆向重建源码**（146 模块，EQUIVALENT 103/PARTIAL 43，每模块带 `STATUS.md`）；`mi_wmark`/`mi_reclaim`/`dynamic_readahead`/`fault_report`/`vip_sched` 等接口与判定参考；大量模块标 DO NOT LOAD，仅读不刷（见 [FEATURES_SURVEY](../kernel/FEATURES_SURVEY.md) 2026-11-28 节） |
| [third_party/xiaomi-opt_gki_kernel_android13-5.15](../../third_party/xiaomi-opt_gki_kernel_android13-5.15) | https://github.com/donothavename/opt_gki_kernel_android13-5.15.git | main | `4662b82f6205` | 5.15 GKI 的 OS4 内存/调度移植（`sew_mi_reclaim`/`sew_unfairmem`/`sew_scene_swappiness`/`sew_dynamic_readahead`/`kshrink_slabd`/`mi_rmap_efficiency`/`unionpower`/`ssg`）；本树已导出其所需 vendor hook |
| [third_party/xiaomi-chirunoneko-gki-5.15-modules](../../third_party/xiaomi-chirunoneko-gki-5.15-modules) | https://github.com/NikoRurQwQRuaaMeow/chirunoneko_gki_android13-5.15_kernel_module_opensource.git | chirunoneko_5.15-lts_vendor_modules_opensource | `96dd2f7849a8` | 小米特性**清单/命名情报**（Kconfig/defconfig 为主，源码被挖空，README 仅“滚木”）；用于按特性名反查真源码 |
| [third_party/mtk-device-modules-hikari](../../third_party/mtk-device-modules-hikari) | https://github.com/Project-Hikari-Liella/MTK_kernel_device_modules-50da8b3c19a331c676dcaa1334fa3b49e4b1a531.git | main | `430688007431` | **dash 实际的厂商 zram/内存后端源码（XRING）**：`drivers/block/zram/{zgroup,zgroup_wb,mctrl,xswapd,smart_cache}.c`，是 `zgroup_enable`/`memory.mctrl.*`/`memory.xswapd.*` 的真源码；`kernel/configs/dash.config` 也在此（`XRING_ZRAM_MEMCG(_WRITEBACK)/XSWAPD=y`，`MI_MEMORY_FREEZE=n`） |
| [third_party/xiaomi-venus-memcg](../../third_party/xiaomi-venus-memcg) | https://github.com/hushangda/android_kernel_xiaomi_sm8350_venus.git | main | `412a1fcc196a` | 小米 memcg 策略参考实现 + **官方 `Documentation/admin-guide/mm/xiaomi-memcg.rst` 协议文档**，精确解释 `mctrl.*` 与 `xswapd.*` 的取值/单位/协议（`mm/mi_memcg*.c`、`mm/mi_smart_cache.c`） |

> 小米官方 6.6 开源（`MiCode` bixi-v-oss，~30 GB）与 OneFeiFan pad6max（~200 MB）
> **不做子模块**，按需用 GitHub API 取单文件（MFZ/ExtM/mi_wmark 权威来源），pin 见
> `dash/versions.env` 末段。

### 1.1 按需取码来源（不入子模块，2026-11-28 最后一轮搜索新增）

| 仓库 | 用途 | 规模 |
|---|---|---|
| [Pzqqt/android_kernel_xiaomi_marble](https://github.com/Pzqqt/android_kernel_xiaomi_marble) | **唯一公开的 XRING 补全源码**：`lib/lz4p/`（12 文件，含 NEON `.S`）+ `drivers/staging/kshrink_slabd/`；`lz4p.h` 头注明 X-Ring technologies | 2.4 GB，只取单文件 |
| [ShriHari33/mt6991-ufs-gear-lane](https://github.com/ShriHari33/mt6991-ufs-gear-lane) | MT6991 UFS `power_mode`/gear-lane 运行时切档 + W-LUN 唤醒修复 + G5 时钟分析（源码副本/PDF） | 4.7 MB，可取 `proposed/*.patch` |
| [OnePlusOSS/android_kernel_oneplus_mt6991](https://github.com/OnePlusOSS/android_kernel_oneplus_mt6991) | **官方 MT6991 6.6.118**（`mt6991_b_16.0.0_oneplus_ace5_ultra`），AOSP-vs-厂商对照；证明 XRING 非 MTK 通用 | 2.3 GB，按文件比对 |
| [oppo-source/android_kernel_oppo_mt6991](https://github.com/oppo-source/android_kernel_oppo_mt6991) | 官方 MT6991 6.6.30（Find X8 Pro），同上 | 2.2 GB，按文件比对 |
| [bocchi810/mt6991-kernel-ci](https://github.com/bocchi810/mt6991-kernel-ci) | MT6991 6.6.118 CI；`hybridswap_lpc` NULL-deref 的 kprobe 守卫思路（OPLUS 后端，dash 不适用） | 19 KB |
| [dongyanchen-dev/android_kernel_xiaomi_sm8850](https://github.com/dongyanchen-dev/android_kernel_xiaomi_sm8850) | 小米 17/K90 Pro Max GKI 构建器 + 约 60 个 f2fs/ufs/fscrypt/erofs/mglru 安全 backport | 1.2 MB |
| [liudaoziwa/mainline-mt6991](https://github.com/liudaoziwa/mainline-mt6991) | Linux 7.3 主线 MT6991 支持（观察） | 382 GB 量级源码，不克隆 |
| [localhosts-A/UniXNU-MT6991-Common](https://github.com/localhosts-A/UniXNU-MT6991-Common) | MT6991 硬件输入整理 `docs/hardware-inputs.md` + `dts/mt6991.dtsi`（XNU 方向） | 10 KB |
| [SHuiTU68/android_kernel_oplus_common](https://github.com/SHuiTU68/android_kernel_oplus_common) | OPLUS F2FS 移植（`F2FS_FS_DEDUP`/`COMPRESS_FIXED_OUTPUT`/`lz4armv8` NEON），6.6.114 | 255 GB 量级，按文件比对 |

> 详见 [FEATURES_SURVEY.md](../kernel/FEATURES_SURVEY.md) 末节与
> [UPSTREAM_NOTES_REVIEW.md](../kernel/UPSTREAM_NOTES_REVIEW.md) §7.5。

注意：CC 的 device modules 中很多厂商模块是**反汇编/逆向重实现**，不是原厂源码；README 明确写“it compiles doesn't mean it works”，且**不要直接刷到 HyperOS 上**。只作为接口/实现参考。

> **2026-11-21：Content-Creation-Club 全部仓库（4 个子模块 + 主内核树）已
> 404/私有化，无法重新获取。** 上表 pin 的 commit 与本地浅克隆是唯一副本，
> `scripts/upstream-check.sh` 会持续报告 (unreachable)。如需异地备份，对
> `third_party/cc-dash-*` 子模块做 git bundle。

## 2. 大源码树（非子模块，浅克隆/本地）

| 路径 | 上游 | pin / 分支 | 用途 |
|---|---|---|---|
| [dash/src/aosp/common](../../dash/src/aosp/common) | https://android.googlesource.com/kernel/common | 跟随 `android15-6.6` 分支，pin `a5c942b8c5be461264ec25e7893e53fda4144a3a`（6.6.144-r01） | 当前自编内核源码；`dash/versions.env` 固定 commit，`AOSP_UPDATE=1 make source` 刷新 |
| [dash/src/micode-kernel](../../dash/src/micode-kernel) | https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git | `2d28e280ea36` / `dash-w-oss`（6.6.89） | 官方公开 dash 参考源码；`mm/memfd-ashmem-shim*` 来源 |
| [dash/src/MTK_kernel_device_modules](../../dash/src/MTK_kernel_device_modules) | https://github.com/MiCode/MTK_kernel_device_modules.git | `9c62564` / `dash-w-oss` | 官方公开 dash DTS/device modules 参考 |
| [dash/src/MTK_kernel_modules](../../dash/src/MTK_kernel_modules) | https://github.com/MiCode/MTK_kernel_modules.git | `8c88cf7` / `dash-w-oss` | 官方公开 MTK camera/WiFi 等模块参考 |
| [dash/toolchains/clang-prebuilt](../../dash/toolchains/clang-prebuilt) | https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 | `main-kernel` @ `74fa19d5` | AOSP clang r614150（23.0.1，2026-11-23 快照），当前构建链；`CLANG_UPDATE=1 make toolchain` 刷新 |
| `/tmp/cc_dash_tree`（临时） | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash.git | `86b65f8476c7` / `dash-w-oss`（6.6.144） | CC 主内核参考；2.8GB。**上游已 404（2026-11-21），无法再取** |

大源码树的更新方式：

```bash
# AOSP common（脚本）
cd dash
bash scripts/sync-aosp.sh
# 或手工
git -C src/aosp/common fetch --depth=1 origin android15-6.6
git -C src/aosp/common checkout --detach <commit>

# MiCode 参考树（不要拉完整历史）
git clone --depth=1 --filter=blob:none --no-checkout \
  -b dash-w-oss https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git dash/src/micode-kernel

# CC 主内核：上游已 404（2026-11-21），无法再克隆；本地浅克隆若已丢失，
# 参考价值只能靠 third_party/cc-dash-* 子模块的 bundle 备份。
```

## 3. 原厂设备审计资产

全部在 [dash/out/device-audit](../../dash/out/device-audit)。手机侧只在 `/data/local/tmp/dash-audit` 写文件；分区只读 `dd`，没有写分区。

| 路径 | 内容 |
|---|---|
| [phone-dump](../../dash/out/device-audit/phone-dump) | 201MB 原厂审计包：`boot_b.img`、`init_boot_b.img`、`vendor_boot_b.img`、`dtbo_b.img`、`vbmeta_b.img`、`stock.config.gz`、`stock.kallsyms`、`getprop.txt`、`lsmod.txt`、`dmesg.txt`、模块 tar；[SHA256SUMS](../../dash/out/device-audit/phone-dump/SHA256SUMS) |
| [stock.config](../../dash/out/device-audit/stock.config) | 原厂完整 config（2259 项） |
| [config.diff](../../dash/out/device-audit/config.diff) | 原厂 config 与当前产物 config 的差异 |
| [stock.kallsyms](../../dash/out/device-audit/stock.kallsyms) | 原厂符号/导出名（地址被 kptr 限制为 0） |
| [vendor_ramdisk_root](../../dash/out/device-audit/vendor_ramdisk_root) | `vendor_boot` 解包：275 个厂商模块 + DTB 等 |
| [vendor_modules](../../dash/out/device-audit/vendor_modules) | `vendor_dlkm` 的 289 个模块 |
| [system_modules](../../dash/out/device-audit/system_modules) | `system_dlkm` 的 78 个模块 |
| [micode-memfd](../../dash/out/device-audit/micode-memfd) | MiCode `memfd-ashmem-shim` 源码副本 |

当前原厂 boot 布局（`_b`）：`boot_b` 64MB/header v4/kernel 17,317,780B；`init_boot_b` ramdisk 3,301,406B；`vendor_boot_b` vendor ramdisk 63,506,233B + DTB 536,161B。只备份了 active `_b`；`boot_a`/`init_boot_a`/`vendor_boot_a`/`dtbo_a`/`vbmeta_a` 及 `vbmeta_system/vendor` 尚未收集。

## 4. 构建、补丁、产物

| 路径 | 用途 |
|---|---|
| [docs/kernel/README.md](../kernel/README.md) | dash 构建/更新流程 |
| [docs/kernel/DEV_NOTES.md](../kernel/DEV_NOTES.md) | 仓库开发笔记合并版（自动生成，给 LLM 的避坑包；`make notes` 重新生成） |
| [dash/versions.env](../../dash/versions.env) | AOSP / BakaSU / SUSFS / clang 版本锁定 |
| [dash/Makefile](../../dash/Makefile) | `deps/toolchain/source/patches/config/build` 入口 |
| [dash/scripts](../../dash/scripts) | 源码同步、补丁、配置、构建脚本 |
| [dash/patches](../../dash/patches) | 按特性分目录的补丁系列（`series` 是唯一应用顺序；bakasu-susfs / vendor-ko-compat / vendor-hooks-os4 / memfd-shim / lz4kd-zram / f2fs / erofs / dash-misc）；SUSFS 文件 apply 时从 `third_party/susfs4ksu` 安装，仓库不存副本 |
| [dash/out/artifacts](../../dash/out/artifacts) | 构建产物目录（本地生成，gitignored）：`Image`、`Image.lz4`、`boot.img`、`vmlinux`、`System.map`、`config`、`brutal.ko`、`BUILD_INFO`、`SHA256SUMS`；当前实际版本/哈希见 [docs/STATUS.md](../STATUS.md)，本页不固定版本 |

当前产物版本、哈希和验证结论见 [docs/STATUS.md](../STATUS.md)；证据见
[docs/kernel/TEST_REPORT.md](../kernel/TEST_REPORT.md)，本页不重复。

## 5. 按任务导航

- 想让 agent/LLM 接手：先读根目录 [AGENTS.md](../../AGENTS.md) 和 [docs/STATUS.md](../STATUS.md)；`DEV_NOTES.md` 是生成物，不是当前状态的权威来源。
- 想构建/更新内核：从 [docs/kernel/README.md](../kernel/README.md) 开始，版本改 [dash/versions.env](../../dash/versions.env)。
- 想恢复原厂 boot/kernel：用 [phone-dump](../../dash/out/device-audit/phone-dump) 里的 `boot_b.img` 等；不要碰 `lk`。
- 想改 BakaSU/KSU：看 [BakaSU/kernel](../../BakaSU/kernel)；6.6.118 时代的拆分补丁已删（git 历史保留）。
- 想改 SUSFS：看 [third_party/susfs4ksu](../../third_party/susfs4ksu)（`kernel_patches/`，apply 时直接安装）；BakaSU 三参数 `ksu_handle_sys_read` 的适配在 `dash/patches/010-bakasu-susfs/`。
- 想研究 lz4kd/zram：看 [third_party/sukisu-patch/other/zram](../../third_party/sukisu-patch/other/zram)、[third_party/hyperos-lz4kd](../../third_party/hyperos-lz4kd)；当前结论是 delta 未真正接入 zram。
- 想找 dash DTS / 原厂模块接口：看 [third_party/cc-dash-device-modules](../../third_party/cc-dash-device-modules)，尤其是 `arch/arm64/boot/dts/mediatek/dash*`、`kernel/configs/dash*.config`、`drivers/ufs/`、`drivers/input/touchscreen/`、`drivers/misc/xiaomi/`。这些是逆向重实现，不是 stock 源码。
- 想找 OS4 vendor hooks：看 [third_party/dash-droidspaces/patches/os4-vendor-hooks](../../third_party/dash-droidspaces/patches/os4-vendor-hooks)；上游 README 报告过 full call site bootloop，但本仓库完整 13-hook + 全调用点镜像已实机启动，冲突时以 [docs/kernel/TEST_REPORT.md](../kernel/TEST_REPORT.md) 为准。
- 想走 CC 的 Kleaf 构建：看 [third_party/cc-dash-build/default.xml](../../third_party/cc-dash-build/default.xml) 和 [third_party/cc-dash-bazel-rules](../../third_party/cc-dash-bazel-rules)。

## 6. 更新与 clone 规则

```bash
# 新机器拉本项目 + 子模块（浅）
git clone --recurse-submodules --shallow-submodules <mikernel-url>
# 或已有仓库
git submodule update --init --recursive --depth 1

# 只更新某个子模块到其分支（会移动 pin，需手动 review）
git submodule update --remote --merge third_party/susfs4ksu
```

- 子模块 pin 以 `git submodule status` 为准；不要在生产构建里随意 `--remote`。
- AOSP、MiCode、CC 主内核等大源码树用浅克隆，不放进子模块；只保留路径和 pin。
- `dash/src`、`dash/toolchains`、`dash/out` 已在 `dash/.gitignore` 中忽略。

## 7. 缺口与安全边界

- 当前缺口、风险和性能排序只在 [OPEN_ISSUES.md](../kernel/OPEN_ISSUES.md) 维护；本页不复制状态。
- 原厂精确源码不存在：stock `6.6.118` commit `b9cc6ec16bc8` 不是 AOSP tag；MiCode 公开分支是 `6.6.89`，CC 树是 LineageOS 方向的逆向重实现。不要把它们当 stock 等价源码，也不要把 CC 产物直接刷到 HyperOS。
- 只备份了 active `_b` boot 链；全机救砖资产（`lk`、`super`、system/vendor 等）没有收集；不要写 `lk`/`super`/用户数据。
- `node_cache` 的 6.12 API 重实现不是 stock 原始源码，当前不参与构建；详见 [NODE_CACHE_SOURCE.md](../kernel/NODE_CACHE_SOURCE.md)。

## 8. 上游参考

- AOSP kernel common：https://android.googlesource.com/kernel/common
- AOSP 6.6.118 tag：https://android.googlesource.com/kernel/common/+/refs/tags/android15-6.6-2026-01_r1
- BakaSU：https://github.com/Baka-SU/BakaSU
- SUSFS4KSU：https://gitlab.com/simonpunk/susfs4ksu
- SukiSU patches：https://github.com/SukiSU-Ultra/SukiSU_patch
- dash DroidSpaces 参考：https://github.com/lakitu12/kernel_dash_droidspaces
- HyperOS LZ4KD 参考：https://github.com/2108282/hyperos-lz4kd
- CC dash 主内核：https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash （已 404，2026-11-21）
- MiCode dash：https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/dash-w-oss
- MiCode 6.6.118（其他设备）：https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/mist-w-oss
- Mi15 6.6.118 参考（含 stock config/构建脚本）：https://github.com/Re-s/Mi15-Droidspaces-Kernel
- dash 6.6.118 完整 dump（参考，不下载）：https://github.com/oss-dash/poco_dash_dump
- AOSP clang prebuilt：https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86
