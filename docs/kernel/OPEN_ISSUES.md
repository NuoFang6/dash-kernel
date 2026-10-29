# 未覆盖项与实机验证建议

## 优先级 0：启动与封装

1. **boot 封装已解决，但必须继续遵守约束。** 已实测成功的方式是从 stock 64MB
   boot 继承 header、OEM vbmeta 和 AVB footer，只替换 kernel；详见
   [BOOT_PACKAGING.md](BOOT_PACKAGING.md)。不要再使用旧 mkbootimg 镜像、短镜像、
   清零 AVB 尾部的镜像，或改 `--disable-verity/--disable-verification` 的 vbmeta。
   这些均已实测 bootloop。
2. **本机隐藏解锁的启动语义。** `fastboot getvar unlocked=yes`，但系统属性仍是
   `vbmeta.device_state=locked`、`verifiedbootstate=green`、`flash.locked=1`。
   它接受保留 OEM 签名 vbmeta/footer、但 boot hash 不匹配的镜像，拒绝缺失或签名
   损坏的元数据。不要把该行为当成通用 AVB 绕过。
3. **运行时已初步通过。** 完整 hooks/功能构建成功启动：
   - `6.6.118-4k`，KernelSU built-in v4.2.0-rc3，SUSFS 2.3.0；
   - 584 个 stock 非 LKM 模块全部加载，`node_cache`、`os_cpu_qi` 及 QoS 依赖链
     正常；stock `kernelsu` LKM 被内建替换，没有双加载；
   - 启动日志无 KCFI `brk`、未知符号、CRC/vermagic 拒载。
   仍需长时运行、压力、suspend/resume 和具体功能行为验证。
4. **sysfs 数值已补采（2026-10-29 晚）。** root（KSU 域）已成功读取
   node_cache/QoS/F2FS/EROFS 数值，系统始终保持 Enforcing，没有关闭 SELinux；
   具体值见 `TEST_REPORT.md` §8。此前读失败是权限/上下文问题，不是节点未注册。
5. **恢复资产。** 完整 `boot_a`、`boot_b`、`vbmeta_b`、`oops` 备份和当前
   KSU init_boot 副本在 `out/device-backup/`；任何时候不要写 `lk`、`super` 或
   用户数据。恢复 boot 必须使用完整 64MB 分区镜像。
6. **init_boot 不是 stock。** 当前 `init_boot_b` 与交接包一致地带有 KernelSU
   init wrapper/`kernelsu.ko`，但当前比交接包少一个 `stock_image.sha1`（仅 41B）。
   本次未写 init_boot；不要把该分区当原厂恢复源，恢复用 `out/device-backup/`。

### hooks 分组测试（未来改动时）

本次完整 13-hook 系列已成功启动，不再需要先证明“能否开机”。以后若 hooks 或
调用点变更后出现异常，可按以下组回退定位：

```text
vendor-hooks/0004  remove_mapping / remove_mapping_failed
vendor-hooks/0005  filemap_get_folio_end
vendor-hooks/0006  put_super
vendor-hooks/0007  fuse_request_end_ext / fetch
vendor-hooks/0008  mmap_lock_init / free
vendor-hooks/0009  percpu_rwsem_init
vendor-hooks/0010  rcu_boost_* / sync_rcu_wait_*
```

### 启动后采集命令

```bash
adb shell su -c 'uname -a; cat /proc/version; getprop ro.boot.slot_suffix'
adb shell su -c 'cat /proc/modules | grep -E "node_cache|os_cpu_qi|zsmalloc"'
adb shell su -c 'find /sys/kernel/node_cache -maxdepth 1 -type f -exec sh -c "echo {}; cat {}" \;'
adb shell su -c 'cat /sys/kernel/qos_inherit/inherit_enable; cat /sys/kernel/qos_sched/sched_enable; cat /sys/kernel/qos_sched/rt_prio'
```

这些命令已在 2026-10-29 晚用 root 实际执行成功（node_cache/QoS 数值见
`TEST_REPORT.md` §8），不需要关闭 SELinux。若换 manager/域后读不到，再用有权限的
调试域，不能为此关闭用户数据保护。

## 优先级 1：功能未完全等价

### Hybrid UFS

这是最大的行为缺口。`CONFIG_F2FS_FS_HYBRID_UFS` 和 `CONFIG_BLOCK_HYBRID_UFS`
已启用，sysfs/挂载参数/函数接口存在，但 `f2fs_hw_support_hybrid()` 固定为
`false`，`hybrid=1` 返回 `-EOPNOTSUPP`。没有 AOSP 可用的配对 ext LUN 和 block
hybrid allocator，伪造映射有写错介质风险。

后续路径：从 stock 内核反汇编/恢复 `device_hybrid_capable`、die 分区发现和
GC 分配策略；在具备双区域 UFS 的设备上做只读验证和故障注入，才可启用。
在实现前不要声称与 stock hybrid 等价。

### VIP file

`vip_file_enable`、排序 manager 和 `f2fs_vip_bsearch/insert/remove` 已实现。
2026-10-30 增加了 `android_vh_f2fs_is_hiprio_task`/`is_usr_task` hook 调用；
当前没有 stock 模块注册这两个 hook，因此使用保守 fallback：有用户地址空间的
RT 或 negative-nice 任务以写方式打开普通文件时调用 `f2fs_vip_insert`，inode
删除/evict 时移除；fallback 管理器上限 8192 个 inode。
真机验证：high-priority 写打开使 `vip_inode_count` 增加，普通写不增加，删除
减少，关闭 `vip_file_enable` 清零。`vip_inode_count` 是调试属性，不是 stock ABI。
与 stock 的差异是 fallback 选择策略和 manager 布局（stock 在 `f2fs_nm_info`，
当前在 `f2fs_sb_info`），不是接口不可用。

### F2FS lock / priority

已移植 stock/上游 `fs/f2fs/lock.c`：`f2fs_lock_context`、
`f2fs_lock_elapsed_time`、`f2fs_priority_uplift/restore`、
`max_lock_elapsed_time`/`adjust_lock_priority`/`lock_duration_priority`/
`critical_task_priority`。默认 `adjust_lock_priority=0`，不改变任务优先级。
真机实测：开启 cp_rwsem bit 后，`f2fs_priority_uplift/restore` 对
`cp_rwsem` 的 orig/new prio 120/110 成对出现；`f2fs_lock_elapsed_time` 在
threshold=0 时记录 cp_rwsem/node_change 的等待时间；删除临时文件后设置复原。
2026-10-30 已把剩余 `gc_lock` 调用点全部接入 trace wrapper：GC 线程、前台
GC ioctl、balance_fs、checkpoint、discard/trim、disable/enable checkpoint 和
resize 路径均使用 `f2fs_*_trace()`；真机用 foreground GC ioctl 验证
`gc_lock` 的 uplift 130→120、restore 和 elapsed 事件。

### F2FS iostat

sysfs 名称和 window/daily/阈值语义存在，但输出格式与内部布局不是 stock 的逐字
复制；统计来自正常 F2FS bio 完成路径，而非原厂 percpu 20 槽实现。性能开销
低于原厂完整采样，但窗口边界和分类粒度不完全相同。

**单开关语义已修复（2026-10-30）**：`__update_iostat_latency()` 现在分别判断
stock `iostat_enable` 和 Xiaomi `en_iostat_enable`；只开
`en_iostat_enable=1`、保持 `iostat_enable=0` 时，4MiB 写入已实测记录
read/write_sync/write_async/meta 计数，stock `io_lat` 仍只在
`iostat_enable=1` 时更新。剩余差异是 5 类聚合 vs stock 20 槽/per-CPU 布局，
不是开关语义。

### F2FS fault report

`f2fs_fault_report` tracepoint 已补，原型与 stock BTF 一致；
`fault_report.ko` 启动日志不再报 `tracepoint ... not found`，`/proc/fault_report`
已出现。同步 `f2fs_handle_error()` 和 task context 的
`f2fs_handle_error_async()` 都会触发；原子 end_io 路径由 `in_task()` 过滤，
避免回调在原子上下文做 `stack_trace_save()`/`queue_work()`。
`f2fs_stop_checkpoint()` 等路径未额外上报，F2FS 实际故障注入/长时验证仍未做。

### EROFS iostat

已覆盖 `read_folio`/`readahead` 的正常读路径，2026-10-30 改为 **每 CPU**
统计（`alloc_percpu`，sysfs 汇总各 CPU），不再用全局锁聚合一整棵挂载点。
剩余差异是 stock 的 10 个 window 槽/10 个 abnormal 槽/5 个 daily 槽和 5 档阈值
没有逐桶复刻；当前每 CPU 一个 aggregate bucket，`iostat_config` 输出
`percpu=1`。2026-10-30 实测 drop_caches 后读取 `/product/.../AiasstVision.apk`，
window/daily 均记录 `count>=1 bytes>=4096`；缓存命中不重复计数是预期行为。

### `MEMFD_ASHMEM_SHIM`

AOSP 6.6.118 自带实现，已启用；没有移植 MiCode 6.6.89 的重复版本。缺少
Android 上层 `libmemfd`/ashmem 用户态回归测试。

### UFS 官方源码

包内 37 个 MTK UFS 文件保留为参考，没有整体替换 AOSP UFS 核心。替换会扩大启动
风险，且当前任务的可选优先级低于已验证的 GKI 构建。后续如需官方 UFS，应单独
做厂商 UFS 驱动/设备树/初始化链路测试。

### lz4kd/zram

未加入。没有把“注册算法”包装成“delta zram 实际调用”。后续需要先确认 stock
zram 的 `system_dlkm/zram.ko` 加载位置和压缩后端 ABI。

### 仍缺的 stock-only 实现（2026-10-30 复核）

- **stock core tracepoint 已对齐**：当前 `__traceiter_*` 与 stock 均为 1860 个，
  差集为 0。补丁 `0007-stock-parity-hooks.patch` 从 AOSP
  `android15-6.6-2026-10_r2` 回移了 51 个缺失 hook，其中 44 个同时回移调用点；
  剩余 7 个 export-only hook 已在 `0008`/`0009` 补上调用点
  （MMC/DMA/lazy resched），当前所有目标 hook 都有调用点。
  2 个 LZ4 事件按 stock BTF 字段在 EROFS LZ4 解压路径实现，已实测触发。
  这些 hook 默认无注册者，回调路径需要厂商模块主动注册；本构建只保证事件/
  符号/调用点与 stock 形状一致。
- **SCSI fastdiscard 未实现**：stock 有 `CONFIG_SCSI_DISCARD` /
  `CONFIG_SCSI_FASTDISCARD`，AOSP 树和当前构建没有；只剩通用 `sd` discard。
  BTF/字符串证据表明确实是多 descriptor UNMAP 的 `xiaomi_fastdiscard_info`
  路径，但公开源码没有实现；详见
  [UFS_HYBRID_EVIDENCE.md](UFS_HYBRID_EVIDENCE.md)。`persist.sys.stability.fastdiscard`
  目前为空，默认不触发；在没有私有源码和有效属性前不伪造“fastdiscard 已启用”。
- **GKI dynamic task_struct 已实现**：`CONFIG_GKI_DYNAMIC_TASK_STRUCT_SIZE=y`、
  `GKI_TASK_STRUCT_VENDOR_SIZE_MAX=1024`；新增 `arch_task_struct_size`、
  `vendor_data_pad`（GPL 导出）和 `android_arch_task_struct_size=` early param。
  未传参数时大小为 4800B/217 成员，与 stock BTF 一致；传参时按页对齐扩大
  task_struct slab 的分配大小。
- **UFS 内核侧未替换**：`ufs_mediatek_mod_ise` 仍是 stock 模块，AOSP
  UFS/SCSI core 不是原厂 37 文件源。2026-10-30 复核：stock vmlinux 和
  `ufs-mediatek-mod-ise.ko` 的字符串都只有 `monitor`，当前
  `/sys/devices/.../monitor/monitor_enable` 与模块自身一致；只有
  `vendor_file_contexts` 里的 `/ufs_monitor` 路径，未找到对应的内核节点或写入者。
  因此不再把“monitor 路径不一致”列为已确认缺口；仍需 UFS 官方 core 的独立
  变体做 A/B。
- **`/proc/iostat_enhance` 不是 dash 的 stock ABI**：stock 的 `io_monitor.ko`
  实际创建 `/proc/io_monitor/...`，iostat 开关在
  `/proc/io_monitor/iostat/iostat_enabled`；本机模块已加载且这些节点存在。
  之前文档中的 `/proc/iostat_enhance/enable` 是误记，不再作为缺口。
- **`MODULE_SCMVERSION`/`LOCALVERSION_AUTO`**：当前为可复现构建关闭
  `LOCALVERSION_AUTO`，因此 `MODULE_SCMVERSION` 及 `/sys/module/*/scmversion`
  缺失；只影响版本元数据，不影响运行时逻辑。

完整核对表见 [STOCK_PARITY_AUDIT.md](STOCK_PARITY_AUDIT.md)。

## 优先级 2：验证缺口

- **KCFI 运行时**：13/13 静态哈希已校验；完整 hooks 镜像已实机启动且没有出现
  `brk #0x8228`。仍需在压力、suspend/resume、异常进程退出等路径持续观察。
- **模块签名/CRC**：`CONFIG_VENDOR_KO_COMPAT` 跳过检查，模块能加载不等于签名
  有效；这是有意降低的安全边界。
- **BakaSU/SUSFS**：内建 KernelSU v4.2.0-rc3、`su`、ReSukiSU manager 包和
  `ksu_susfs show version=v2.3.0`、9 项 enabled_features 已确认；SUSFS 各隐藏项
  的实际效果、双 manager 场景和长时间行为未逐项验证。
- **F2FS/EROFS 数据**：系统正常挂载并运行；F2FS 已做 16MiB 随机数据写入、
  `fsync`、drop_caches 后回读 SHA256 一致；EROFS 已做冷缓存读计数。仍未做
  fsck、写入压力、power-loss 或故障注入。
- **boot/AVB**：最终 64MB boot 保留 OEM vbmeta/footer，已实机启动。`fastboot boot`
  不可用；boot 的 kernel hash 与 OEM vbmeta 描述不一致，依赖本机隐藏解锁接受该
  组合。其它设备或更严格 bootloader 不保证可用；不要在没有恢复方案时写 `lk`。
- **性能/功耗**：没有 A/B 数据，不能对 zram、node_cache、QoS、启动时延作收益
  声明。
- **SELinux**：系统保持 Enforcing；本次 root 读取 sysfs 成功，没有关闭 SELinux
  或修改上下文。`setenforce 0` 等降级策略仍不应为取证而使用。

## 优先级 3：dash-droidspaces 上游同步（2026-10-29）

- 上游 `origin/main` 到 `6039943a9c15`；与本交接相关的 13-hook 补丁已同步：
  `0001/0002/0004/0005/0007-0010` 逐字节相同，`0006` 仅为本树 SUSFS include
  调整上下文。
- `41f923c` 的 root cause 修复（把 `mmap_lock_init/free` 的 EXPORT 放到
  declaration-only TU，使 genksyms CRC 与 stock 一致）已在本仓库 `0002` 中；
  本镜像 CRC 实测 `0x615d194b`/`0xa301bcc9`，`os_cpu_qi` 正常加载，未使用
  `patch-kcrctab.py` 后处理。
- 上游新增的 `OS4_HOOKS=off`、`NO_LZ4_EXPORT`、分组 `HOOK_CALL_SITES` 是它自己
  的 CI/单变量调试开关，本仓库未引入（本交付走完整 13-hook 镜像）。
- 上游 `trusty-rescue`、`pid-max-clamp`、KSU/SUSFS pin 更新和 DroidSpaces 容器
  配置（SYSVIPC、POSIX_MQUEUE、PID_NS、USER_NS、DEVTMPFS、IP_SET 等）未合入；
  本内核基于 stock config，没有这些容器项。若目标是跑 DroidSpaces，需要单独
  变体并实机验证，不能直接使用本内核。
- 上游 README 的 “full call site bootloop” 与本仓库实测不冲突：本仓库完整
  hooks + 全调用点已稳定启动；其后续实验也显示无调用点仍 bootloop，问题更可能
  在该仓库的 KSU/SUSFS 组合（`exp/ksu-*` 分支正在排查），不是 hook 原型。
  最新 `exp/ksu-diag-recorder`（`6b48e83`，2026-10-29 23:40）仍记录约 1.5s 崩溃，
  与本仓库 BakaSU 结果不同。

## 已知安全注意事项

1. 关闭模块签名/vermagic/CRC/protected-export 检查会允许任意匹配架构的模块
   加载；仅用于自有、已解锁设备。
2. 内核包含 BakaSU/SUSFS，会改变 root 与隐藏行为；不要用于不受控设备。
3. `abi_symbollist.raw` 保留 stock 导出名，构建产物仍不是原厂签名内核。
4. `out/baseline-6.6.118/` 是旧式 mkbootimg 对照内核，**不是 stock 备份且不可
   启动**；恢复请使用 `out/device-backup/` 的完整原厂 boot/vbmeta。
