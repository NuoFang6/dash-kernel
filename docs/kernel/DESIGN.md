# dash 6.6.118 内核设计说明

## 1. 基线与交付边界

- 设备：`dash` / REDMI Turbo 5 Max / MT6991，stock
  `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`。
- AOSP 基线：`android15-6.6-2026-01_r1`，peeled commit
  `f9c84f40b6ba6152b6f51daba0193c9564af4172`（`SUBLEVEL=118`）。
- 工具链：AOSP `clang-r510928`。
- 配置起点：[stock.config](../../dash/configs/stock.config)，不是 `gki_defconfig`。
- 页面大小 4K；保留 `CFI_CLANG`、`SHADOW_CALL_STACK`、`MODVERSIONS`、
  `MODULE_SIG_PROTECT`、`LTO_NONE` 和 `TRIM_UNUSED_KSYMS`。
- 交付物不写 `lk`、`super` 或用户数据；实机测试只使用 `boot_b`，并在写入前备份
  完整 boot/vbmeta 分区。默认仍应优先无写入验证，任何刷机由设备所有者决定。

## 2. 补丁系列

[patches/series](../../dash/patches/series) 是唯一应用顺序：

| 补丁 | 内容 |
|---|---|
| `0000-tools-libbpf-const-strchr.patch` | 6.6.118 host `libbpf` 与 r510928 的 `const` 诊断修复，只影响构建主机 |
| `0001-vendor-ko-compat.patch` | 跳过厂商 `.ko` 的签名、vermagic、CRC、namespace 和 GKI protected-export 检查 |
| `0002-bakasu-integration.patch` | BakaSU 内建接入 |
| `0003-susfs-gki-android15-6.6.patch` | SUSFS inline 支持，已适配 6.6.118 |
| `0004-susfs-bakasu-hooks.patch` | BakaSU `ksu_handle_sys_read` 三参数适配 |
| `0005-xiaomi-f2fs-features.patch` | 增强 iostat、fault report、lock/priority、VIP manager、hybrid UFS 接口、block Kconfig |
| `0006-xiaomi-erofs-iostat.patch` | EROFS 每 CPU iostat 与 sysfs |
| `0007-stock-parity-hooks.patch` | 51 个 stock-only hook、44 个调用点、2 个 LZ4 事件、GKI dynamic task_struct |
| `0008-mmc-dma-hook-callsites.patch` | MMC attach/reset/cd、sdhci get_cd、dma-heap alloc latency 调用点 |
| `0009-lazy-resched-hooks.patch` | `restore_curr_resched` 的 arm64 lazy-resched 调用点 |
| `vendor-hooks/0001..0010` | node_cache/os_cpu_qi 需要的 13 个 `android_vh_*` hooks、导出和调用点 |

`susfs.c`、`susfs.h`、`susfs_def.h` 由 `scripts/apply-patches.sh` 从
`patches/susfs/` 安装；BakaSU 以固定提交的本地符号链接接入，不复制上游历史。

## 3. 厂商模块与 trace hooks

stock 的 638 个模块作为一个整体检查。它们需要 13 个 AOSP 6.6 基线没有的
tracepoint：

- `node_cache`：`remove_mapping`、`remove_mapping_failed`、
  `filemap_get_folio_end`、`put_super`；另使用基线已有的
  `android_vh_do_new_mount_fc`。
- `os_cpu_qi`：`fuse_request_end_ext`、`fuse_request_fetch`、
  `mmap_lock_init`、`mmap_lock_free`、`percpu_rwsem_init`、
  `rcu_boost_start`、`rcu_boost_end`、`sync_rcu_wait_start`、
  `sync_rcu_wait_end`。

实现采用 `include/trace/hooks/dash_os4_stub.h` 的 `DECLARE_HOOK`，在
`vendor_hooks.c` 中定义并导出。`mmap_lock_init/free` 的 `EXPORT_TRACEPOINT_SYMBOL_GPL`
单独放在只声明、不定义 tracepoint 的
`drivers/android/dash_os4_decl_exports.c`，以复现 stock 的 modversion CRC。
13 个原型均写入编译期 extern 原型 pin，构建后用
`scripts/verify-os4-kcfi.py` 对 `__traceiter_*` 的实际 KCFI 立即数逐项核对。

调用点参考 `dash-droidspaces` 的 OS4 hooks 系列（固定到本地 submodule 的
`6039943`）。本次完整调用点系列已随最终镜像实机启动成功，`os_cpu_qi` 整条 QoS
依赖链和 `node_cache` 均加载，启动日志无 KCFI `brk`、未知符号或 CRC/vermagic
拒载。参考仓库记录的历史 bootloop 未在本机构建中复现；如未来改动调用点后异常，
仍按 [OPEN_ISSUES.md](OPEN_ISSUES.md) 的分组方式回退。

### stock core tracepoint / dynamic task_struct

`0007-stock-parity-hooks.patch` 以 AOSP `android15-6.6-2026-10_r2` 为参考，
回移 stock 6.6.118 有、2026-01 AOSP 没有的 51 个 hook，并回移其中 44 个的
调用点。`dma_heap_buffer_alloc_lat_*`、`mmc_*`/`sdhci_get_cd`、
`restore_curr_resched` 在上游只有声明/导出，保持相同的“事件可用、无内核调用点”
状态。`lz4_decompress_start/end` 没有公开源码，按 stock BTF 的
`inputsize/outputsize/ret/bypass` 字段在 EROFS LZ4 解压路径实现；它记录的是
EROFS 解压，不宣称覆盖所有 LZ4 使用点。

GKI dynamic task_struct 按 AOSP/OnePlus 公开实现接入：
`CONFIG_GKI_DYNAMIC_TASK_STRUCT_SIZE` 选择
`ARCH_WANTS_DYNAMIC_TASK_STRUCT`，`arch_task_struct_size` 默认等于
`sizeof(struct task_struct)`，`android_arch_task_struct_size=` early param
可把 slab 分配扩大到 `GKI_TASK_STRUCT_VENDOR_SIZE_MAX=1024`，并导出
`vendor_data_pad`。不传参数时 `task_struct` 布局与 stock 相同（4800B）。

## 4. BakaSU 与 SUSFS

- 内建 `CONFIG_KSU=y`、`CONFIG_KSU_MULTI_MANAGER_SUPPORT=y`。
- `CONFIG_KSU_SUSFS=y`，关闭 tracepoint/manual hook，使用 inline hook。
- `0001` 的 `CONFIG_VENDOR_KO_COMPAT` 只放宽模块加载校验，不伪造缺失符号；
  未知符号仍会导致加载失败。
- 安全影响：模块签名/CRC/vermagic/protected-export 检查被关闭，仅适用于已解锁的
  自有设备。`MODULE_SIG_PROTECT=y` 本身保留，以便随时关闭兼容开关回到严格模式。

## 5. memfd ashmem shim

交接说明假设需要从 MiCode 6.6.89 移植，但 AOSP 6.6.118 树已经包含：

- `mm/memfd-ashmem-shim.c`
- `mm/memfd-ashmem-shim.h`
- `mm/memfd-ashmem-shim-internal.h`
- `mm/shmem.c` 中的两个 hook
- `mm/Kconfig`、`mm/Makefile` 和 arm64 GKI defconfig 的配置

因此没有新增重复实现，只启用 `CONFIG_MEMFD_ASHMEM_SHIM=y`。这避免双份 ioctl
和 shmem 逻辑，兼容性风险低于强行移植 6.6.89 版本。

## 6. Xiaomi F2FS 功能

公开源中没有找到与 stock 二进制逐行一致的原厂实现，因此采用行为级等价实现，
并在 sysfs 名称上保持 stock ABI 可发现性。代码在
`fs/f2fs/xiaomi.c`、`fs/f2fs/xiaomi.h`。

### 增强 iostat

- `CONFIG_XIAOMI_ENHANCED_IOSTAT=y`，依赖现有 `CONFIG_F2FS_IOSTAT=y`。
- 复用已有 `f2fs_iostat` / `f2fs_iostat_latency` tracepoints；不重复定义事件。
- 在 `iostat.c` 的 bio 完成延迟路径追加聚合，按 read / write_sync /
  write_async / meta 分类统计 window、daily、超阈值次数。
- 新增 sysfs：`en_iostat_enable`、`iostat_config`、
  `iostat_window_period_s`、`iostat_latency_threshold_ms`、
  `iostat_window_latency`、`iostat_daily_latency`。
- 和 stock 的差异：stock 有 20 槽窗口和按 10 档粒度/设备 percpu 的布局；本实现
  按文件系统做 5 类聚合，输出值语义一致但不保证逐字节输出格式相同。没有原厂
  percpu 内存开销，统计精度和窗口语义略有差异。
- 实测开关语义（2026-10-30 修正）：`__update_iostat_latency()` 现在分别判断
  `iostat_enable` 和 `en_iostat_enable`。stock MIUI init 的
  `iostat_enable=0, en_iostat_enable=1` 组合已实测能记录
  read/write_sync/write_async/meta；stock `io_lat` 仍只在 `iostat_enable=1`
  时更新。剩余差异仍是 5 类聚合 vs stock 20 槽/per-CPU 布局。

### F2FS fault report

- 新增 `include/trace/events/f2fs.h` 中的 `f2fs_fault_report` tracepoint，原型
  与 stock BTF 一致：`(struct super_block *sb, unsigned int err_code,
  const char *function, unsigned int line)`。
- 在同步错误路径 `f2fs_handle_error()` 触发；没有放在
  `f2fs_handle_error_async()`/`f2fs_stop_checkpoint()`，因为 `fault_report.ko`
  的回调会 `stack_trace_save()`/`queue_work()`，不适合原子上下文。
- `fault_report.ko` 通过 `for_each_kernel_tracepoint()` 找到事件，启动日志不再
  报 `tracepoint f2fs_fault_report not found`，`/proc/fault_report` 已出现。

### F2FS lock / priority

- 移植了 stock/上游的 `fs/f2fs/lock.c`：`f2fs_lock_context`、`f2fs_time_stat`、
  `f2fs_rwsem.sbi/name`、`f2fs_down_read_trace()`/`f2fs_up_read_trace()` 等。
- 新增 stock 原型 tracepoint：`f2fs_lock_elapsed_time`、
  `f2fs_priority_uplift`、`f2fs_priority_restore`；事件字段与 stock BTF 一致。
- sysfs：`max_lock_elapsed_time`（默认 500ms）、`adjust_lock_priority`
  （默认 0，bitmask）、`lock_duration_priority`（默认 120）、
  `critical_task_priority`（默认 120）。
- 默认不改变任务优先级；打开 `adjust_lock_priority` 后，在指定锁的临界区把
  非 RT 任务提升到 `lock_duration_priority`，解锁时恢复，并发出
  uplift/restore。`f2fs_lock_elapsed_time` 只在事件启用且超过阈值时记录。
- 2026-10-30 真机已验证 cp_rwsem 的 uplift/restore（120→110）、
  cp_rwsem/node_change 的 elapsed 事件，以及 foreground GC 的 `gc_lock`
  uplift/restore 和 elapsed 事件；tracefs 和 sysfs 已复原。
- `gc_lock` 的全部调用点（GC 线程、前台 GC ioctl、balance_fs、checkpoint、
  discard/trim、disable/enable checkpoint、resize）均已接入 trace wrapper。

### VIP file

- `CONFIG_F2FS_VIP_FILE=y`，实现排序 inode 管理器：
  `f2fs_vip_bsearch`、`f2fs_vip_insert`、`f2fs_vip_remove`，并暴露
  `vip_file_enable`；增加只读调试计数 `vip_inode_count`。
- 选择策略：调用 stock 的 `android_vh_f2fs_is_hiprio_task` 和
  `android_vh_f2fs_is_usr_task` hook；没有模块注册时，fallback 为“有用户地址空间的 RT 或 negative-nice 任务以
  写方式打开普通文件”，manager 上限 8192 个 inode；删除/evict 时移除。
- 与 stock 的差异：fallback 是行为级策略，manager 布局在 `f2fs_sb_info`
  而非 stock 的 `f2fs_nm_info`；`vip_inode_count` 是额外调试 ABI。
- 真机已验证：high-priority 写打开使计数增加、普通写不增加、删除减少、
  关闭开关清零、重新打开后恢复选择。

### Hybrid UFS

- `CONFIG_F2FS_FS_HYBRID_UFS=y` + `CONFIG_BLOCK_HYBRID_UFS=y`。
- 暴露 `hybrid`、`hybrid_free_ratio`、`hybrid_die_info`，提供
  `f2fs_hw_support_hybrid()` / `f2fs_hw_hybrid_get_avail()` 和
  `hybrid=%u` 挂载参数。
- 关键取舍：AOSP GKI 没有配对 ext LUN 的 block hybrid allocator。缺少该硬件契约
  时伪造地址映射可能导致写错介质。因此能力查询明确返回 false，`hybrid=1` 返回
  `-EOPNOTSUPP`，分配始终走原始单设备路径。`hybrid=0` 和 sysfs 只读接口可正常工作。
  这是安全回退，不是原厂双区域分配。

## 7. EROFS iostat

- `CONFIG_XIAOMI_EROFS_IOSTAT=y`。
- 在 `erofs_read_folio()` 和 `erofs_readahead()` 的实际读路径记录耗时、字节数、
  peak/avg、超阈值次数。
- 同时提供 `iostat_enable`、`iostat_config`、`iostat_window_period_s`、
  `iostat_latency_threshold_ms`、`iostat_window_latency`、
  `iostat_daily_latency`。
- 2026-10-30 改为每 CPU 统计（`alloc_percpu`），sysfs 汇总各 CPU；与原厂
  剩余差异是原厂有 10 个 window 槽/10 个 abnormal 槽/5 个 daily 槽和 5 档阈值，
  本实现每 CPU 只有一个 aggregate bucket，`iostat_config` 输出 `percpu=1`。
  只统计 EROFS 读路径，不虚报压缩解压线程细分。

## 8. UFS 与 lz4kd

- UFS：包内官方 MTK UFS 源保留为参考，但本次没有把 37 个文件整体替换进 AOSP
  核心。原因：stock 的 UFS 初始化被 bootloader/内核命令行 blacklist，且替换核心
  UFS 会扩大启动风险；本任务的可选优先级低于已验证的 GKI 构建。
- lz4kd：已实现普通 lz4kd 压缩算法接入（非 delta zram）。stock vendor zram
  通过 crypto API 接受本内核注册的 `lz4kd-generic`，无需替换 zram 模块；
  当前 Scene 开机配置已选中 `[lz4kd]`。注意本机“内存扩展”是 ExtM，位于
  vendor zram 模块内部，替换 zram 会破坏回写；详见
  [ZRAM_EXTM.md](ZRAM_EXTM.md)。

## 9. 安全与回退

- 所有产物可用 `STOCK_BOOT_IMG` 重新继承生成。最终 boot 由
  `scripts/repack-boot.py` 保留原厂 64MB header、OEM vbmeta 和 AVB footer，只替换
  kernel；不写入 init_boot/vendor_boot/dtbo/vbmeta。该封装方式已实机启动成功，
  细节和失败对照见 [BOOT_PACKAGING.md](BOOT_PACKAGING.md)。
- 源码树可随时由 `scripts/apply-patches.sh` 重置并重新应用，长期修改只在
  `patches/`、`configs/` 和报告文件中。
- `out/baseline-6.6.118/` 保留一份未加 hooks/功能补丁的内核和旧式 mkbootimg
  boot；该 boot 不可启动，仅作内核对照，不得误当作 stock 原厂镜像。
