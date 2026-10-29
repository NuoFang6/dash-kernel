# dash 设备模块行为调查：node_cache / os_cpu_qi

> **定位：stock 运行态观察（2026-10-29），不是当前自编内核的实时快照。**
> 文中的 `cur_cnt/cur_bytes` 等是 stock 启动后的历史值；当前 #29 内核的实测值见
> [TEST_REPORT §8](../kernel/TEST_REPORT.md#8-真机运行验证)。公开源码仍未找到，
> 以下是对 stock 二进制和运行时状态的推断。

调查方式：设备 `adb shell su` 只读检查（sysfs/proc/tracefs、模块状态、slab、dmesg）+ 电脑侧模块 ELF 的符号/字符串分析。没有写任何分区。公开源码仍未找到，以下是对 stock 二进制和运行时状态的推断。

## node_cache

### 运行时状态

- 已加载，`refcnt=0`，无 holders；依赖 `zsmalloc`。
- `/sys/kernel/node_cache/` 实测：
  - `max_bytes = 41943040`（40MB 上限）
  - `cur_cnt = 35051`
  - `cur_bytes = 13231761`（约 12.6MB 压缩数据）
  - `comp_enable = 1`
  - `comp_ratio = 50`
  - `swapin_cnt = 96433`
  - `invalid_cnt = 3`
  - `shrink_cnt = 0`
  - `reclaim_policy = 0`
  - `total_ram_mb = 15206`
  - `lowmem_mode = 0`
  - `avail_low_wmark_mb = 500`
  - `shrink_wmark = 75`
  - `trace_enable = 0`
- slab：`node_cache_entry` 35637/50560 objects，object size 32B；约 1.1MB 活跃元数据（加 slab 约 1.6MB）。
- 模块自身 coresize 36KB。

### 从符号/字符串可确认的行为

- 模块描述：`node cache for f2fs`，作者 `qiwenjie@xiaomi.com`，GPL v2，依赖 zsmalloc。
- 关键函数：`node_cache_attach`、`node_cache_lookup_locked`、`node_cache_compress_folio`、`node_cache_decompress_folio`、`node_cache_valid_node_data`、`node_cache_shrink_*`、`node_cache_put`。
- 使用 hook：`do_new_mount_fc`、`filemap_get_folio_end`、`put_super`、`remove_mapping`、`remove_mapping_failed`。
- 依赖 LZ4（模块未定义 `LZ4_compress_default` / `LZ4_decompress_safe` 等），以及 zsmalloc pool。

### 实际作用判断

它是一个 **F2FS node 页的压缩缓存层**：

1. 在 F2FS 挂载时 attach；
2. 当 node folio 即将从 page cache 移除/回收时，压缩后放进 zsmalloc 池，而不是直接丢弃；
3. 再次访问 node 页时从压缩池解压回 page cache；
4. 有 shrinker、低内存水位、压缩比例、回收策略和 trace 开关；
5. 当前 35k 条目、约 12.6MB 压缩数据、96k 次 swapin，说明它确实在工作，而不是空模块。

收益是**节省 F2FS 元数据占用的物理内存/减少重新读 UFS**；代价是压缩/解压 CPU 开销。它不直接提升文件读写带宽。

## os_cpu_qi

### 运行时状态

- 已加载，`refcnt=4`；holders：`cpq`、`mi_reclaim`、`os_cpu_qs`、`task_turbo`。
- 依赖：`os_cpu_perf_actuator`、`vip_sched`、`plat_common`。
- `/sys/kernel/qos_inherit/inherit_enable = QI_ENABLE: 1`
- `/sys/kernel/qos_sched/sched_enable = QS_ENABLE: 1`
- `/sys/kernel/qos_sched/rt_prio`：`ui prio: 98`、`render prio: 98`
- `/proc/sys/kernel/xr_qos/`：
  - `mutex_normal_opt_spin_time_ns = 60000`
  - `mutex_qos_opt_spin_time_ns = 100000`
- `qos_inherit_events` 下的 tracepoint 当前全部 `enable=0`（未开启采样）。

### 从符号/字符串可确认的行为

- 模块描述：`MI QOS inherit Driver`，作者 `Shaohua Fan <fanshaohua@xiaomi.com>`，GPL v2。
- 关键函数：`qi_set_qos`、`qi_get_qos_by_tid/pid`、`get_static_qos_lvl`、`get_proc_static_qos_lvl`、`get_qos_lvl`、`is_qos_task`、`kern_qi_set_qos`。
- 继承路径：`binder`、`mutex`、`rwsem`、`percpu-rwsem`、`futex`、`fuse`、`rcu`；每个都有 `inherit/uninherit`、`iter_*`、`do_*` 逻辑。
- tracepoint：`qos_inherit_events` 下有 `qi_set_qos`、`qi_get_qos_by_tid/pid`、binder set/restore/proc transaction/buffer release、mutex/rwsem/futex/fuse/rcu inherit/uninherit、iter、GPU blocked/unblocked、free task 等。
- 依赖 `os_cpu_perf_actuator` / `vip_sched` / `plat_common`，说明它不是单独调频，而是把 QoS 等级交给 Xiaomi/MTK 的 CPU 性能控制链。

### 实际作用判断

它是一个 **QoS 继承与调度提升引擎**：

1. 用户态（Xiaomi 框架/服务）通过 `qi_set_qos` 给任务设置 static/dynamic QoS 等级；
2. 任务在 binder、mutex、rwsem、percpu-rwsem、futex、fuse、RCU 上阻塞/被唤醒时，把 QoS 临时继承给锁持有者或对端任务；
3. 通过 `os_cpu_perf_actuator`、`vip_sched`、`plat_common` 提升 CPU 调度/频率/优先级；
4. `qos_sched` 给 UI/render 设置 RT 优先级 98，`qos_inherit` 开关当前都启用；
5. 任务释放/唤醒/退出时 uninherit，避免永久提升。

它优化的是**锁竞争、binder/FUSE 跨进程、UI/render 的尾延迟**，不是通用省电机制；boost 会消耗额外 CPU/功耗。当前 `refcnt=4`、多个 holder 说明系统里有实际使用链。

## 对我们自编内核的意义

- 两者都不是开机必需；但缺失对应 hook 会让 stock 模块加载失败（`node_cache` 需要 4 个新 hook + LZ4；`os_cpu_qi` 需要 9 个新 hook，以及大量 AOSP 已有 hook）。
- 当前 6.6.118 + BakaSU 构建已导出 13 个 hook 和 LZ4，KCFI
  13/13 通过，真机加载 `node_cache`/`os_cpu_qi`；完整 hook 调用点仍需在压力、
  suspend/resume 和异常退出路径持续验证。
- 公开源码仍未找到；只能从 stock 二进制/运行时行为推断，不能声称等价重写。
- 如果只想保证开机和基本功能，可以先不带这两个模块的厂商 hook；如果要在 HyperOS 下保留它们的性能/内存行为，必须保证 hook 原型和调用点安全，且注意 `node_cache` 的压缩 CPU 成本与 `os_cpu_qi` 的 boost 功耗。

## 证据位置

- 模块二进制：[node_cache.ko](../../dash/out/device-audit/vendor_ramdisk_root/lib/modules/node_cache.ko)、[os_cpu_qi.ko](../../dash/out/device-audit/vendor_modules/modules/os_cpu_qi.ko)
- 设备原始审计：[phone-dump](../../dash/out/device-audit/phone-dump)
- 缺口调研：[GAP_RESEARCH.md](GAP_RESEARCH.md)
- 导航：[NAVIGATION.md](NAVIGATION.md)
