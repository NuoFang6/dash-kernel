# mikernel / dash 资源导航

本文件是 `mikernel` 的仓库资源导航；文档总入口见
[docs/README.md](../README.md)。详细构建步骤见
[docs/kernel/README.md](../kernel/README.md)，版本锁定见
[dash/versions.env](../../dash/versions.env)。缺口的逐项搜索结果见
[GAP_RESEARCH.md](GAP_RESEARCH.md)，两个厂商模块的实测行为见
[DEVICE_MODULES.md](DEVICE_MODULES.md)。

目标设备：`dash` / REDMI Turbo 5 Max（MT6991），stock `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`，GKI 分支 `android15-6.6`，KMI 字符串 `android15-8`，4K 页。当前自编产物为 **6.6.143 #8**，并已在真机 `boot_b`（`0dc871a5…`）启动验证；准确状态以 [docs/kernel/TEST_REPORT.md](../kernel/TEST_REPORT.md) 和 [dash/out/artifacts/BUILD_INFO](../../dash/out/artifacts/BUILD_INFO) 为准。本页部分章节保留了早期 6.6.144 调研痕迹，遇到冲突不要沿用旧状态。

> 大源码树（AOSP common、MiCode、CC 主内核）故意没有做成子模块，避免把几 GB 历史带进仓库；它们的浅克隆位置和上游地址在下文单独记录。

## 1. 子模块

以下子模块已加入 `.gitmodules` 和 git 索引。当前 clone 使用 `--depth 1`，但没有把 depth 写进 `.gitmodules`；新机器请用 `git clone --recurse-submodules --shallow-submodules` 或 `git submodule update --init --recursive --depth 1`。

| 路径 | 上游 | 分支 | 当前 pin | 用途 |
|---|---|---|---|---|
| [BakaSU](../../BakaSU) | https://github.com/Baka-SU/BakaSU.git | main | `d5e9e025b8b4` | BakaSU/KSU 内核源码（`BakaSU/kernel`），当前内建 + SUSFS |
| [third_party/sukisu-patch](../../third_party/sukisu-patch) | https://github.com/SukiSU-Ultra/SukiSU_patch.git | main | `eec45788c9a1` | SukiSU 补丁集合；`other/zram` 下有 lz4k/lz4k_oplus/lz4kd 参考 |
| [third_party/susfs4ksu](../../third_party/susfs4ksu) | https://gitlab.com/simonpunk/susfs4ksu.git | gki-android15-6.6 | `0606e19afae9` | SUSFS kernel patches；`dash/patches/legacy-6.6.118/0003` 的来源（当前 6.6.143 已并入 `0000-6.6.143-dash-integration.patch`） |
| [third_party/dash-droidspaces](../../third_party/dash-droidspaces) | https://github.com/lakitu12/kernel_dash_droidspaces.git | main | `6039943a9c15` | dash 的 DroidSpaces/SukiSU 参考项目；`patches/os4-vendor-hooks` 在这里；实验性，README 已报告 call site bootloop |
| [third_party/hyperos-lz4kd](../../third_party/hyperos-lz4kd) | https://github.com/2108282/hyperos-lz4kd.git | main | `e58761a19874` | 小米 14 的 LZ4KD/自动切换参考；非 delta zram 实现 |
| [third_party/tcp-brutal](../../third_party/tcp-brutal) | https://github.com/HyNetworks/tcp-brutal.git | master | `d2397ff8bca0` | TCP Brutal v2.0.1 外部内核模块；`make brutal` 构建，GPL-3.0，按需 insmod |
| [third_party/cc-dash-build](../../third_party/cc-dash-build) | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_build.git | dash-w-oss | `627ef9ba0d31` | CC dash 的 repo manifest / Kleaf 构建脚本 |
| [third_party/cc-dash-device-modules](../../third_party/cc-dash-device-modules) | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_device_modules.git | dash-w-oss | `94914f6bc83f` | dash DTS、`kernel/configs/dash*.config`、重实现的触摸/热管理/millet/mi_memory/UFS 模块源码 |
| [third_party/cc-dash-mtk-modules](../../third_party/cc-dash-mtk-modules) | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_mtk_modules.git | dash-w-oss | `d3e32dcf9f67` | MediaTek camera/connectivity/GPU/等模块源码 |
| [third_party/cc-dash-bazel-rules](../../third_party/cc-dash-bazel-rules) | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_bazel_mgk_rules.git | lineage-23.2 | `1573a08b7d6b` | CC dash Kleaf/MGK 构建规则 |

注意：CC 的 device modules 中很多厂商模块是**反汇编/逆向重实现**，不是原厂源码；README 明确写“it compiles doesn't mean it works”，且**不要直接刷到 HyperOS 上**。只作为接口/实现参考。

## 2. 大源码树（非子模块，浅克隆/本地）

| 路径 | 上游 | pin / 分支 | 用途 |
|---|---|---|---|
| [dash/src/aosp/common](../../dash/src/aosp/common) | https://android.googlesource.com/kernel/common | tag `android15-6.6-2026-10_r2`，commit `bf768be0eed008588dc4e0db0b2f76c026a35818`（6.6.143） | 当前自编内核源码；由 `dash/versions.env` 固定 |
| [dash/src/micode-kernel](../../dash/src/micode-kernel) | https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git | `2d28e280ea36` / `dash-w-oss`（6.6.89） | 官方公开 dash 参考源码；`mm/memfd-ashmem-shim*` 来源 |
| [dash/src/MTK_kernel_device_modules](../../dash/src/MTK_kernel_device_modules) | https://github.com/MiCode/MTK_kernel_device_modules.git | `9c62564` / `dash-w-oss` | 官方公开 dash DTS/device modules 参考 |
| [dash/src/MTK_kernel_modules](../../dash/src/MTK_kernel_modules) | https://github.com/MiCode/MTK_kernel_modules.git | `8c88cf7` / `dash-w-oss` | 官方公开 MTK camera/WiFi 等模块参考 |
| [dash/toolchains/clang-prebuilt](../../dash/toolchains/clang-prebuilt) | https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 | `main-kernel` | AOSP clang r614150（23.0.1），当前构建链 |
| `/tmp/cc_dash_tree`（临时） | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash.git | `86b65f8476c7` / `dash-w-oss`（6.6.144） | CC 主内核参考；2.8GB，**故意不做子模块**，需要时按 shallow 方式取 |

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

# CC 主内核（只在需要时，2.8GB）
git clone --depth=1 --filter=blob:none \
  -b dash-w-oss https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash.git /tmp/cc_dash_tree
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
| [dash/patches/series](../../dash/patches/series) | 当前唯一补丁 `0000-6.6.143-dash-integration.patch`（整树 squash；含 vendor-ko 兼容、BakaSU、SUSFS、Xiaomi F2FS/EROFS、OS4 vendor hooks） |
| [dash/patches/legacy-6.6.118](../../dash/patches/legacy-6.6.118) | 旧 6.6.118 拆分系列，仅作历史参考，不再应用 |
| [dash/out/artifacts](../../dash/out/artifacts) | 当前 6.6.143 构建产物：`Image`、`Image.lz4`、`boot.img`、`vmlinux`、`System.map`、`config`、`brutal.ko`、`BUILD_INFO`、`SHA256SUMS` |

当前产物：`6.6.143-4k #8`（AOSP 2026-10_r2，clang r614150，ThinLTO），
BakaSU built-in + SUSFS inline Hook；64MB AVB 保留式 `boot.img`
`0dc871a5…` 已刷入 `boot_b` 并启动；586 个模块加载，KCFI 13/13，
mihomo TUN/addrtype/IPv6 NAT、TFO 持久化和 tcp-brutal 已实机验证。详见
[docs/kernel/TEST_REPORT.md](../kernel/TEST_REPORT.md) §15/§18。

## 5. 按任务导航

- 想快速避坑/让 LLM 接手：先读 [docs/kernel/DEV_NOTES.md](../kernel/DEV_NOTES.md)，再按其中的权威顺序读源文档。
- 想构建/更新内核：从 [docs/kernel/README.md](../kernel/README.md) 开始，版本改 [dash/versions.env](../../dash/versions.env)。
- 想恢复原厂 boot/kernel：用 [phone-dump](../../dash/out/device-audit/phone-dump) 里的 `boot_b.img` 等；不要碰 `lk`。
- 想改 BakaSU/KSU：看 [BakaSU/kernel](../../BakaSU/kernel) 和 [0002-bakasu-integration.patch](../../dash/patches/legacy-6.6.118/0002-bakasu-integration.patch)。
- 想改 SUSFS：看 [third_party/susfs4ksu](../../third_party/susfs4ksu)，对应 [0003](../../dash/patches/legacy-6.6.118/0003-susfs-gki-android15-6.6.patch)；注意 BakaSU 三参数 `ksu_handle_sys_read` 的 [0004](../../dash/patches/legacy-6.6.118/0004-susfs-bakasu-hooks.patch)。
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

## 7. 已知缺口与风险

- 原厂精确源码：stock `6.6.118` commit `b9cc6ec16bc8`（设备）/CC 文档里的 `c44b714366cc` 不是 AOSP tag；当前使用 AOSP `android15-6.6-2026-10_r2`（`bf768be0`，6.6.143）作为基线，MiCode 公开分支是 `6.6.89`。
- 仍缺 Xiaomi 私有内核特性**原厂源码**：`XIAOMI_ENHANCED_IOSTAT`、`XIAOMI_EROFS_IOSTAT`、`F2FS_VIP_FILE`、`F2FS_FS_HYBRID_UFS`、`BLOCK_HYBRID_UFS`。当前已有行为级实现；F2FS 单开关 iostat、`f2fs_fault_report`、lock/priority tracepoint 和 VIP 选择策略已补齐；hybrid、EROFS per-device 统计仍未复刻。
- 仍缺 `node_cache.ko` / `os_cpu_qi.ko` 的原厂源码；当前用 stock 二进制 + 13 个 hook，真机加载和 KCFI 静态匹配已通过。2026-11-03 收到一份面向 6.12 API 的 `node_cache.c` 重实现（[`dash/vendor-src/node_cache/node_cache.c`](../../dash/vendor-src/node_cache/node_cache.c)），已与 stock 6.6.118 二进制做差异核对，见 [NODE_CACHE_SOURCE.md](../kernel/NODE_CACHE_SOURCE.md)；它不是 stock 原始源码，当前不参与构建。
- `MEMFD_ASHMEM_SHIM` 在 AOSP 6.6.118 树内已自带实现，当前 6.6.118 构建只启用配置（`memfd_ashmem_shim_ioctl` 已编入）。
- 当前产物为 `6.6.143-4k #8`（AOSP 2026-10_r2 + ThinLTO + clang r614150，boot_b `0dc871a5…`），已在真机验证 CFI/厂商模块/BakaSU/zram ExtM/mihomo TUN/IPv6 NAT/TFO 持久化/tcp-brutal；详见 [docs/kernel/TEST_REPORT.md](../kernel/TEST_REPORT.md) §15/§18。
- 只备份 active `_b` boot 链；全机救砖资产（`lk`、`super`、system/vendor 等）没有收集；不要刷 `lk`。
- CC 仓库是 LineageOS 方向、逆向后重实现，**不要直接刷 HyperOS**，也不能当官方 stock 等价源码。
- 2026-10-30 已补 F2FS lock/priority tracepoint、VIP 选择策略（hook + 保守
  fallback）和 4 个 lock sysfs；真机已验证 uplift/restore、lock elapsed 和 VIP
  计数增删；stock 1860 个 core traceiter 全部存在（6.6.143 另有 46 个上游新增）、
  GKI dynamic task_struct 已补齐。仍缺的 stock-only 项：hybrid UFS、EROFS per-device 统计、
  SCSI fastdiscard、UFS 官方 37 文件源；详见
  [OPEN_ISSUES.md](../kernel/OPEN_ISSUES.md)。

## 8. 上游参考

- AOSP kernel common：https://android.googlesource.com/kernel/common
- AOSP 6.6.118 tag：https://android.googlesource.com/kernel/common/+/refs/tags/android15-6.6-2026-01_r1
- BakaSU：https://github.com/Baka-SU/BakaSU
- SUSFS4KSU：https://gitlab.com/simonpunk/susfs4ksu
- SukiSU patches：https://github.com/SukiSU-Ultra/SukiSU_patch
- dash DroidSpaces 参考：https://github.com/lakitu12/kernel_dash_droidspaces
- HyperOS LZ4KD 参考：https://github.com/2108282/hyperos-lz4kd
- CC dash 主内核：https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash
- MiCode dash：https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/dash-w-oss
- MiCode 6.6.118（其他设备）：https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/mist-w-oss
- Mi15 6.6.118 参考（含 stock config/构建脚本）：https://github.com/Re-s/Mi15-Droidspaces-Kernel
- dash 6.6.118 完整 dump（参考，不下载）：https://github.com/oss-dash/poco_dash_dump
- AOSP clang prebuilt：https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86
