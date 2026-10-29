# dash 内核缺口补齐需求说明

> **历史交接输入（2026-10-29），不是当前状态。** 文中的“当前 6.6.144/只生成
> Image”和包内 `project/dash/versions.env` 都是交接时状态；接收方后来已完成
> 6.6.118 构建、真机启动和部分 stock parity 修复。当前状态以
> [kernel/TEST_REPORT.md](../kernel/TEST_REPORT.md)、
> [kernel/OPEN_ISSUES.md](../kernel/OPEN_ISSUES.md) 和
> [handoff/PACKAGE.md](PACKAGE.md) 为准。本文保留原文用于追溯需求，不再按它
> 重新执行或覆盖当前实现。

本包是 dash 内核工作的完整交接材料。目标、设备事实、输入、原厂资产、模块、配置、boot 镜像、UFS/memfd 源码和外部 pin 都在包内或链接中。

**实现路径不限**：原厂源码恢复、等价重写、兼容 shim、行为级实现、上游 backport、二进制接口适配、重新设计或其他能达到目标的方案都可以。请在报告中说明所选方案、与 stock 行为的差异、验证结果和性能/能效影响；鼓励采用比现状更完整、更稳健的实现。

## 0. 执行环境默认（避免阻塞）

- 接收方可能**没有真机**，也**不能向用户提问**。不需要等待设备或询问确认。
- 无真机时：完成源码、补丁、配置、构建、静态 ABI/KCFI/符号检查和 boot 镜像生成；不做 fastboot、不写分区。实机启动可由设备所有者后续执行，不阻塞本任务。
- 网络可用时：按 `links/SOURCES.md` 获取 AOSP 6.6.118、BakaSU、SUSFS、clang r510928；网络不可用时：先用包内资产完成源码分析、补丁设计、配置/构建脚本和静态验证；如果因此无法实际编译，直接交付补丁/设计/分析并在报告中标记“构建未执行”，不因此中止。
- 默认决策（除非有更强证据）：AOSP `android15-6.6-2026-01_r1`（6.6.118）、设备 `device/stock.config`、BakaSU `d5e9e025b8b4`、SUSFS `0606e19afae9`、clang `r510928`；第一版不把 lz4kd 作为阻塞项；UFS/memfd 优先用包内源码。
- 遇到私有源码缺失、设备不可用、网络失败或测试环境缺失时，选择最合理的等价/替代路径继续交付，并在 `DESIGN.md`、`TEST_REPORT.md` 或 `OPEN_ISSUES.md` 说明边界；不要因此中止。
- 交付物可以在“仅构建/静态验证”的情况下完成；实机结果作为加分项，不作为唯一验收条件。

## 1. 交付目标

在 **AOSP `android15-6.6-2026-01_r1`（6.6.118）** 基线上，交付一套可应用的内核改动和可测试 boot 镜像，使 dash 的 stock 厂商模块（尤其 `node_cache.ko`、`os_cpu_qi.ko`）能够加载并工作，同时尽可能补齐缺失的 Xiaomi F2FS/EROFS/hybrid 功能；保留 BakaSU（内建）+ SUSFS + 厂商 `.ko` 兼容能力。

优先级：

1. **构建与镜像交付**：6.6.118 构建、boot 镜像、静态可验证性。
2. **厂商模块兼容**：638 个 stock 模块可加载；`node_cache`、`os_cpu_qi` 可 probe/工作；KCFI/ABI/vermagic/CRC/namespace/签名/符号问题被处理。
3. **BakaSU + SUSFS**：内建 KSU、SUSFS inline、BakaSU 读 hook 适配。
4. **Xiaomi F2FS/EROFS/hybrid 功能**：按 stock 行为实现或给出等价方案。
5. **可选**：UFS 官方源码替换、lz4kd/zram 研究。

## 2. 设备/原厂事实（实测）

| 项 | 值 |
|---|---|
| 设备 | `dash` / 2602BRT18C / REDMI Turbo 5 Max / MT6991 |
| 系统 | Android 17 / SDK 37；`ro.product.first_api_level=36` |
| stock 内核 | `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k` |
| KMI | `android15-6.6` / generation 8 |
| 页大小 | 4K；`CONFIG_ARM64_4K_PAGES=y` |
| boot | header v4；`boot_b` 64MB，kernel 17,317,780B，ramdisk_size=0 |
| init_boot | 8MB，ramdisk 3,301,406B |
| vendor_boot | 64MB，vendor ramdisk 63,506,233B + DTB 536,161B |
| dtbo/vbmeta | 各 8MB |
| zram | stock 当前 `lz4`，16GB disksize；`ZRAM=m`，默认 `lzo-rle` |
| 当前 root | stock 上 `kernelsu` LKM；`su` 上下文 `u:r:ksu:s0` |
| bootloader | 属性显示 locked/green，但设备所有者说明是隐藏解锁；`lk` 不在本次操作范围 |

安全配置：`CFI_CLANG=y`、`SHADOW_CALL_STACK=y`、`MODVERSIONS=y`、`MODULE_SIG_PROTECT=y`、`LTO_NONE=y`。

## 3. 当前工作状态与输入

- 已有 6.6.144 自编内核：BakaSU 内建 + SUSFS inline + `CONFIG_VENDOR_KO_COMPAT`；0 error/0 warning；只生成 Image，未生成 boot，未实机验证。
- `project/dash/`：当前补丁、脚本、配置、6.6.144 artifact config/BUILD_INFO。
- 当前补丁：
  - `0001-vendor-ko-compat.patch`：模块加载兼容；
  - `0002-bakasu-integration.patch`：BakaSU 接入；
  - `0003-susfs-gki-android15-6.6.patch`：SUSFS；
  - `0004-susfs-bakasu-hooks.patch`：BakaSU `ksu_handle_sys_read` 适配。
- 模块符号核对：把 vendor ramdisk 的 275 个模块纳入后，638 个 stock 模块没有硬缺失符号；`leds-mtk-disp.ko` 对 `mtk_drm_gateic_set_backlight` 只有 weak 引用。CFI/ABI 尚未实机验证。
- `node_cache`/`os_cpu_qi` 的运行时行为见 `docs/DEVICE_MODULES.md`；二进制在 `modules/`。

## 4. 需要补齐的功能

### A. Xiaomi F2FS/EROFS/hybrid

目标配置和行为：

- `CONFIG_XIAOMI_ENHANCED_IOSTAT=y`：F2FS iostat 增强；`en_iostat_enable`、`iostat_window_period_s`、`iostat_latency_threshold_ms`、iostat daily/window latency sysfs；`f2fs_iostat`/`f2fs_iostat_latency` tracepoints。
- `CONFIG_XIAOMI_EROFS_IOSTAT=y`：EROFS iostat/sysfs；`erofs_iostat_*`。
- `CONFIG_F2FS_VIP_FILE=y`：F2FS VIP file；`f2fs_vip_bsearch/insert/remove`、`vip_file_enable`。
- `CONFIG_F2FS_FS_HYBRID_UFS=y` + `CONFIG_BLOCK_HYBRID_UFS=y`：F2FS/block hybrid UFS；`f2fs_hw_support_hybrid`、`f2fs_disable_hybrid`、`f2fs_hw_hybrid_get_avail`、`device_hybrid_capable`、`hybrid_*` sysfs。

公开源码没有找到；可通过原厂源码恢复、等价实现、兼容层、行为级实现或其他方案完成。报告中请说明：

- 选择了什么实现路径；
- 与 stock sysfs/统计/策略的对应关系；
- 数据正确性、性能、能效和失败回退；
- 与原厂行为的差异和未覆盖部分。

### B. `node_cache.ko` / `os_cpu_qi.ko`

目标：

- 让 stock 模块可加载、probe 和工作；
- 13 个 `android_vh_*` tracepoint 的定义、导出、KMI 白名单和调用点正确；
- KCFI 原型 hash 匹配；
- `node_cache` 需要 LZ4 和 4 个新 hook；`os_cpu_qi` 需要 9 个新 hook + 已有 binder/futex 等 hook；
- 运行时按 `docs/DEVICE_MODULES.md` 核对 sysfs/行为。

可使用 `third_party/dash-droidspaces/patches/os4-vendor-hooks` 作为参考。该系列作者报告 full call site 会 bootloop；可以采用分组调用点、替代 hook 方案、等价实现或重新设计调用点。请报告方案和验证结果。

### C. `MEMFD_ASHMEM_SHIM`

包内 `source/memfd-ashmem-shim/` 是 MiCode 6.6.89 实现；移植到 6.6.118，启用配置，并验证对现有 memfd 无回归。也可采用更新的等价实现。

### D. UFS

包内 `source/ufs/` 是 MiCode `MTK_kernel_device_modules/dash-w-oss` 的官方 UFS 源（37 文件）。可将其作为官方 UFS 实现使用；也可选择其他经过验证的 UFS 方案。CC 的 UFS 实现是逆向重实现，可作为参考，使用时请标注来源和验证状态。

### E. 可选

- lz4kd/zram：可研究普通 lz4kd 或真正的 delta zram；在报告中区分“算法注册”和“delta 实际调用”。
- 性能/能效 A/B：建议覆盖 zram、F2FS node cache、QoS 继承和启动时延。

## 5. 交付物

1. `patches/`：相对 clean AOSP `android15-6.6-2026-01_r1` 的 unified diff 系列，按顺序可应用；包含 6.6.118 适配、BakaSU/SUSFS/vendor-ko 兼容、memfd、F2FS/EROFS/hybrid、vendor hooks。
2. `configs/`：基于 `device/stock.config` 的 config fragment 或脚本。
3. `build/`：使用 AOSP clang `r510928` 的构建脚本/命令，能生成 `Image`/`Image.lz4`。
4. `boot.img`：从 `boot/boot_b.img` 继承 header/DTB/ramdisk/cmdline，仅替换 kernel；`init_boot_b`/`vendor_boot_b`/`dtbo_b`/`vbmeta_b` 保持不动；附 `SHA256SUMS`。
5. `TEST_REPORT.md`：构建配置、命令、启动、模块加载、KCFI、sysfs、F2FS/EROFS、性能/功耗 A/B、失败日志。
6. `DESIGN.md`（建议）：每个缺口的实现路径、与 stock 的差异、风险、回退。
7. `OPEN_ISSUES.md`（建议）：未覆盖项、替代方案和后续建议。

## 6. 验收目标

- 补丁应用到 clean AOSP 6.6.118；build 0 error。
- 生成 Image/boot；boot 镜像结构正确（header v4、页大小 4096、DTB/ramdisk 保留），附 `SHA256SUMS`。
- **无真机环境**：以 clean apply + build + 静态 ABI/KCFI/符号检查 + boot 镜像结构检查为验收；实机启动不是阻塞条件。
- 有真机/设备访问时：优先 `fastboot boot`；启动后 `/proc/version` 为 6.6.118 基线。
- 有真机时：stock 638 个模块加载；重点 `node_cache`、`os_cpu_qi` 加载；无 KCFI `brk`/panic/未知符号/vermagic/CRC 拒载。
- 有真机时：`node_cache` sysfs 出现 `max_bytes/cur_cnt/cur_bytes/...`；`os_cpu_qi` 的 `qos_inherit/qos_sched` 可读。
- F2FS/EROFS 可正常挂载；实现的功能 sysfs 可读；数据不损坏（有设备时实测，无设备时做代码/静态验证）。
- BakaSU manager 可识别 root；SUSFS 工作；内建 KSU 与旧 `kernelsu` LKM 冲突被处理（有设备时验证）。
- 报告中明确区分“编译通过”“离线/静态验证”“实机验证”和“性能/功耗结果”。

## 7. 设备与操作约束

- 本次工作环境可能没有真机；不需要设备即可完成源码、补丁、构建和静态验证。
- `lk` 分区不在本次操作范围；不执行 fastboot/flash/分区写入。
- 如设备所有者后续测试，优先 `fastboot boot`；不要在无授权时写 `boot`/`boot_a`/`lk`/`super`。
- 测试文件放在 `/data/local/tmp`，结束清理。
- 包内 `boot_b`/`vbmeta_b` 等是备份/参考，不是写入指令。

## 8. 构建路径参考

```bash
git clone --depth=1 --single-branch -b android15-6.6 \
  https://android.googlesource.com/kernel/common aosp-6.6.118
git -C aosp-6.6.118 fetch --depth=1 origin \
  refs/tags/android15-6.6-2026-01_r1
git -C aosp-6.6.118 checkout --detach FETCH_HEAD
cp device/stock.config out/.config
# 应用补丁；目标为 6.6.118，不是 6.6.144
# 使用 AOSP clang r510928、ARCH=arm64、LLVM=1、LLVM_IAS=1
# 生成 Image；再用 stock boot_b 继承式替换 kernel 生成 boot.img
```

`dash/scripts` 当前按 6.6.144 的组织方式编写，可按需要改造或替换。

## 9. 包内文件

```text
TASK_BRIEF.md
docs/{NAVIGATION,GAP_RESEARCH,DEVICE_MODULES}.md
project/dash/{README,versions.env,Makefile,configs,patches,scripts,artifacts}
device/{stock.config,config.diff,stock.kallsyms.gz,getprop,lsmod,cmdline,bootconfig,dmesg,
        module-list,module_manifest.tsv,module_hook_deps.tsv,stock_exports,our_exports,PHONE_DUMP.sha256}
boot/{boot_b,init_boot_b,vendor_boot_b,dtbo_b,vbmeta_b}.img
modules/{vendor_ramdisk,vendor_dlkm,system_dlkm,node_cache.ko,os_cpu_qi.ko}
source/ufs/ (37 个官方 MTK UFS 文件)
source/memfd-ashmem-shim/
links/SOURCES.md
MANIFEST.sha256
```

## 10. 关键背景与参考

- AOSP tag：`android15-6.6-2026-01_r1`（6.6.118）
- Re-s/Mi15-Droidspaces-Kernel：同 stock `b9cc6ec16bc8` 的 6.6.118 参考
- MiCode `mist-w-oss`：6.6.118 公开源（其他设备，无 Xiaomi F2FS 特性）
- MiCode `dash-w-oss`：6.6.89
- `oss-dash/poco_dash_dump`：dash 6.6.118 完整 dump（链接记录，未下载；可补 boot_a/stock kernel/DTB/kallsyms）
- CC dash：6.6.144 LineageOS 参考，逆向模块请标注来源
- `dash-droidspaces`：os4 vendor hooks 参考，作者报告 full call site bootloop
- SUSFS/BakaSU/SukiSU：见 `links/SOURCES.md` 的 pin

## 11. 已记录的注意点（供方案设计参考）

- KCFI 原型/调用点与 stock 模块的匹配决定运行时是否触发 `brk`；如采用不同原型，请同步提供匹配的 hook 适配和验证。
- `SHADOW_CALL_STACK`/`CFI_CLANG`/`MODVERSIONS`/`MODULE_SIG_PROTECT` 保持 stock 行为更利于厂商模块。
- 内建 KSU 需要与设备当前 `kernelsu` LKM 协调，避免重复 root。
- `node_cache` 是 F2FS node 页压缩缓存（zsmalloc/LZ4），当前 35k 条目/13MB 压缩数据；会消耗 CPU 换内存。
- `os_cpu_qi` 是 QoS 继承引擎（binder/mutex/rwsem/percpu-rwsem/futex/fuse/RCU + UI/render RT 98）；会提升延迟表现，也有 boost 功耗。
- 公开源码未找到不等于唯一路径；可以用等价实现、行为级实现或重新设计，只需在报告中说明差异和验证。
