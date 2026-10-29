# dash 缺口调研台账

目标：逐个查清 stock 6.6.118 相关缺口，优先找可直接使用的源码；沾边但不精确的链接只记录，不下载。检索时间：2026-10-29；实现状态更新：2026-10-30（见文末）。

检索方式：WebSearch（多组中英文关键词）、GitHub repo/code/commit search、Sourcegraph、GitLab API、Gitee API、MiCode 分支扫描、本地源码树核对。

## 1. 原厂 6.6.118 精确源码

### 结论

**没有找到 dash 的精确厂商 6.6.118 源码。** 公开的最佳替代是 AOSP `android15-6.6-2026-01_r1`（6.6.118），再叠加原厂 config 和可获得的补丁。

### 找到的精确/近似基线

| 来源 | 内容 | 判断 |
|---|---|---|
| [AOSP android15-6.6-2026-01_r1](https://android.googlesource.com/kernel/common/+/refs/tags/android15-6.6-2026-01_r1) | 6.6.118 GKI 源基线 | 精确 6.6.118 上游，不是 dash 厂商树 |
| [Re-s/Mi15-Droidspaces-Kernel](https://github.com/Re-s/Mi15-Droidspaces-Kernel) | 明确写 stock `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`；含 stock config、boot 构建脚本、DroidSpaces 补丁 | **高价值参考**，不是 dash 源码 |
| [MiCode `mist-w-oss`](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/mist-w-oss) | Xiaomi 6.6.118 源，另一个设备（REDMI Note 17/POCO M8 Power 5G） | 6.6.118 源候选，但不是 dash，也没有 Xiaomi F2FS 特性 |
| [MiCode `dada-v-oss`](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/dada-v-oss) | 6.6.30，Xiaomi 15/15 Pro | 版本太旧，不适用 |
| [android-kernels/xiaomi-dash-w-oss](https://github.com/android-kernels/xiaomi-dash-w-oss) | MiCode `dash-w-oss` 的镜像，6.6.89 | 旧版本镜像，不是 6.6.118 |
| [MiCode `dash-w-oss`](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/dash-w-oss) | 6.6.89，dash 官方公开源 | 公开版本落后于设备实际 6.6.118 |

### 沾边线索（只记录，不下载）

- [ghostlock-app README_ZH](https://github.com/YuKongA/ghostlock-app/blob/main/README_ZH.md)：把 `6.6.118-android15-8-gc44b714366cc` 映射到 REDMI K80 Pro / Turbo 5 Max / POCO X8 Pro Max / Xiaomi Pad 7 Ultra；只是版本映射，不是源码。
- [CC dash 主内核](https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash)：6.6.144 LineageOS 方向，不是 stock 6.6.118。
- [donyanchen/android_kernel_xiaomi_sm8850](https://github.com/donyanchen/android_kernel_xiaomi_sm8850)：6.12 设备配置/补丁，不是 6.6.118 源。

## 2. Xiaomi F2FS/EROFS/hybrid 实现

### 结论

**没有找到公开源码。** 只找到配置项、符号和二进制，找不到 `XIAOMI_ENHANCED_IOSTAT`、`XIAOMI_EROFS_IOSTAT`、`F2FS_VIP_FILE`、`F2FS_FS_HYBRID_UFS`、`BLOCK_HYBRID_UFS` 的实现。

### 已确认的配置存在

- [Re-s stock 6.6.118 config](https://github.com/Re-s/Mi15-Droidspaces-Kernel/blob/main/docs/stock-6.6.118-android15-8.config)：全部包含上述选项。
- 我们设备 dump 的 [stock.config](../../dash/out/device-audit/stock.config) 同样包含。
- CC device modules 和 MiCode 分支的 Kconfig 里没有这些选项，说明实现不在这些公开树的当前分支。

### 检索结果

- GitHub code search：只命中 `ikconfig`/`*.config`、DroidSpaces 配置、CC 配置；没有源码。
- Sourcegraph（含 forks/archived）：`f2fs_hw_support_hybrid`、`f2fs_vip_bsearch`、`erofs_iostat_update`、`device_hybrid_capable` 均无匹配。
- GitHub code search 的 `erofs_iostat_update` 只命中 OnePlus/LineageOS 的 `vendor_hooks.c`、`fs/erofs/zdata.c`，不是 Xiaomi IOSTAT 实现。
- MiCode 全分支扫描：`dash-w-oss`、`dada-v-oss`、`mist-w-oss` 等都没有这些 Kconfig/源码；`mist-w-oss` 虽然 SUBLEVEL=118，但 F2FS/EROFS 特性为 0。
- 中文搜索只命中 F2FS/EROFS 通用介绍，没有 Xiaomi 私有实现。

### 沾边链接（只记录，不下载）

- [Re-s config](https://github.com/Re-s/Mi15-Droidspaces-Kernel/blob/main/docs/stock-6.6.118-android15-8.config)
- [donyanchen sm8850](https://github.com/donyanchen/android_kernel_xiaomi_sm8850)（6.12 配置/补丁）
- [klarnet2009/dada-closed-modules](https://github.com/klarnet2009/dada-closed-modules)（closed-module/struct-layout 文档）
- [hgn284/xiaomi_17pro_max_sm8850](https://github.com/hgn284/xiaomi_17pro_max_sm8850)、[Apr-YT/gg-rwproc33-driver](https://github.com/Apr-YT/gg-rwproc33-driver)、[wfqefwqf/share-poc-XRing-O1](https://github.com/wfqefwqf/share-poc-XRing-O1)：只有 stock config/日志。

## 3. node_cache.ko / os_cpu_qi.ko 源码

### 结论

**没有公开源码。** 只有 stock 二进制、符号依赖和 OS4 hooks 补丁；没有找到厂商实现或等价重写。

### 已确认

- 设备 stock 模块：`node_cache.ko`（F2FS node cache，依赖 5 个 tracepoint + LZ4）、`os_cpu_qi.ko`（QoS，依赖 40 个 tracepoint）。
- [dash-droidspaces os4-vendor-hooks](https://github.com/lakitu12/kernel_dash_droidspaces/tree/main/patches/os4-vendor-hooks) 只补 hook 注册/调用点，不含这两个模块源码；作者报告 full call site bootloop。
- MiCode/CC/DroidSpaces 源码树中没有 `node_cache`/`os_cpu_qi` 路径。

### 沾边链接（只记录，不下载）

- [lakitu 的 os4-vendor-hooks](https://github.com/lakitu12/kernel_dash_droidspaces/tree/main/patches/os4-vendor-hooks)
- [CC device_modules](https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_device_modules)：有 touch/thermal/millet/UFS 等重实现，没有这两个模块。
- 我们设备的 [node_cache.ko](../../dash/out/device-audit/vendor_ramdisk_root/lib/modules/node_cache.ko) 和 [os_cpu_qi.ko](../../dash/out/device-audit/vendor_modules/modules/os_cpu_qi.ko)：stock 二进制，仅用于 ABI/依赖分析。

## 4. UFS 与固件/设备 dump

### 4.1 UFS 官方源码：找到

[MiCode/MTK_kernel_device_modules `dash-w-oss`](https://github.com/MiCode/MTK_kernel_device_modules/tree/dash-w-oss) 的 `drivers/ufs/` 有 37 个文件，包括：

- `ufs-mediatek-ise.c/.h`
- `ufs-mediatek-dbg.c/.h`
- `ufs-mediatek-mbrain.c`
- `ufs-mediatek-mimic.c`
- `ufs-mediatek-perf.c`
- `ufs-mediatek-rpmb.c`
- `ufs-mediatek-sysfs.c`
- `ufs-mediatek.c/.h`
- `vendor/ufsfeature.c`、`ufshid.c`、`ufsringbuf.c`、`ufsshpb.c`、`ufstw.c` 等

这是**官方公开 UFS 源码**，可替代 CC device modules 里的逆向版 `ufs-mediatek-ise`。本地位置：[dash/src/MTK_kernel_device_modules](../../dash/src/MTK_kernel_device_modules) 下的 `drivers/ufs`（当前 blobless，按需 sparse checkout）。

### 4.2 dash 完整 dump：找到，未下载

以下是**同代号 dash 的完整设备 dump**，不是源码；可作为 boot_a、stock kernel、DTB、kallsyms、vendor/system 模块的补充。都只记录，不下载。

| 仓库 | 系统/内核 | 内容 |
|---|---|---|
| [oss-dash/poco_dash_dump](https://github.com/oss-dash/poco_dash_dump) | OS3.1 / **6.6.118** / POCO dash | `boot/kernel` 36.8MB、`boot.elf` 42MB、`boot/dtb`、`boot/dts`、`ikconfig`、`kallsyms.txt`、`boot.img.aa/.ab`、`init_boot`、`vendor_boot`、`system_dlkm`、`vendor_dlkm`、`aosp-device-tree` |
| [xiaomi-mt6991/poco_dash_dump](https://github.com/xiaomi-mt6991/poco_dash_dump) | OS3.1 / 6.6.118 | 同上结构（另一个 dump） |
| [HexaUnion/redmi_dash_dump](https://github.com/HexaUnion/redmi_dash_dump) | OS3.1 / 6.6.118 | boot/init_boot/vendor_boot/dtbo、ikconfig、kallsyms、system/vendor |
| [xiaomi-dash-dev/redmi_dash_dump](https://github.com/xiaomi-dash-dev/redmi_dash_dump) | OS3.0 / **6.6.89** | 旧版完整 dump；含 boot/vendor_boot 分卷、ikconfig、kallsyms |
| [ONFIX dash 教程/ROM](https://onfix.cn/course?bid=1&mid=30095) | OS3.0.x | boot/init_boot 资源索引；需付费下载 |

`oss-dash` 的 `aosp-device-tree/BoardConfig.mk` 还确认了 dash boot 布局：header v4、kernel base `0x7fff8000`、页大小 4096、boot 64MB、init_boot 8MB、vendor_boot 64MB、super 9.1GB；这和我们从手机读到的布局一致。

### 4.3 固件/完整 dump 的价值

- 可补 active `_b` 之外的 `boot_a`/`init_boot_a`/`vendor_boot_a` 等资产；
- `boot.elf`/`kallsyms.txt` 可补 stock ABI/符号分析（不提供源码）；
- `boot/dtb`、`boot/dts` 可补 dash 设备树；
- `vendor_dlkm`/`system_dlkm` 可补另一版 stock 模块；
- **不能**补 F2FS/EROFS/hybrid 源码或 `node_cache`/`os_cpu_qi` 源码。

## 5. 仍缺 / 下一步

仍然缺失：

- dash 精确 6.6.118 **厂商源码**（公开只有 AOSP tag、MiCode 6.6.89、mist 6.6.118 其他设备）。
- `XIAOMI_ENHANCED_IOSTAT`、`XIAOMI_EROFS_IOSTAT`、`F2FS_VIP_FILE`、`F2FS_FS_HYBRID_UFS`、`BLOCK_HYBRID_UFS` 实现源码。
- `node_cache.ko`、`os_cpu_qi.ko` 源码。
- boot_a/另一槽位、lk/super、完整固件（dump 仓库可补部分，但未下载）。

建议：

1. 以 AOSP `android15-6.6-2026-01_r1` + 设备 stock config 为主基线；`mist-w-oss` 可作为 6.6.118 源参考。
2. 从 MiCode `MTK_kernel_device_modules` sparse 取 `drivers/ufs`，替代 CC 逆向 UFS。
3. 如必须补 boot_a/stock kernel/DTB，优先只拉 `oss-dash/poco_dash_dump` 的 `boot/`、`boot/dtb`、`ikconfig`、`kallsyms.txt`，不要拉整个 6.8GB 仓库。
4. F2FS/EROFS/hybrid 和 `node_cache`/`os_cpu_qi` 没有公开源码；当前是行为级/接口级实现，不能声称与 stock 逐行等价。剩余差异需要原厂 6.6.118 源码、二进制反推或接受功能缺失。

### 2026-10-30 实现状态更新

- **已做**：AOSP 6.6.118 + stock config + BakaSU/SUSFS + 13 个 OS4 hooks；
  真机启动；F2FS 增强 iostat 单开关语义；`f2fs_fault_report`；
  `fs/f2fs/lock.c`、`f2fs_lock_elapsed_time`、`f2fs_priority_uplift/restore`
  和 4 个 lock sysfs；F2FS VIP 的 hook + 保守 fallback。真机已验证
  uplift/restore、lock elapsed、VIP 计数增删和开关清零。
- **已补**：stock core tracepoint 1860/1860 对齐（51 个 hook、44 个调用点、
  2 个 LZ4 事件）；GKI dynamic task_struct；F2FS `gc_lock` 全部调用点接入
  lock trace wrapper。
- **仍缺**：hybrid UFS、EROFS per-device iostat、SCSI fastdiscard、UFS
  官方 37 文件源。`/proc/iostat_enhance` 经复核不是 dash stock ABI。
- **仍无**：dash 精确 6.6.118 厂商源码；上述实现是行为级/等价路径，不是原厂
  源码逐行复刻。当前运行状态以 [TEST_REPORT](../kernel/TEST_REPORT.md) 和
  [OPEN_ISSUES](../kernel/OPEN_ISSUES.md) 为准。
