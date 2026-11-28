# 未完成项、风险与验证缺口

> 本文件是当前缺口、风险和可执行 todo 的唯一台账。当前版本与实机状态见
> [STATUS.md](../STATUS.md)；原始命令、日志和失败复盘见
> [TEST_REPORT.md](TEST_REPORT.md)。
>
> 最后更新：2026-11-28。调查覆盖 OS4.0.4.0 的生产版 `#16` 和 NoLTO 验证版；
> 当前设备运行版本与槽位见 [STATUS.md](../STATUS.md)。

## 1. 结论摘要

当前内核可以正常运行 OS4：设备已正常启动，584 个关键厂商模块加载，ExtM
回写设备为 `/dev/block/dm-71`，F2FS/EROFS 挂载正常，stock 七项 cgroup 控制器
保持不变，未发现由本轮调查引起的 panic、Oops、UFS/F2FS I/O 错误或模块拒载。

仍然存在两类问题：

1. **OS4 依赖的厂商私有接口未完整复刻。** 主要影响内存回收策略、zram
   writeback 调节、前后台 I/O 优先级和少数调优项；目前没有证据表明它们会阻止
   开机，但不能宣称与 stock 行为等价。
2. **stock-only 文件系统/UFS 功能没有安全实现。** Hybrid UFS、fastdiscard、
   UFS 官方 core 变体和若干 iostat/VIP 细节仍缺少源码或硬件契约；这些项目不能
   通过创建同名 sysfs 节点或猜测 ABI 解决。

本轮调查期间设备出现两次 `reboot,shell`。pstore 记录的是用户空间显式 reboot，
不是 kernel panic/watchdog；调查命令均为读取操作。完整证据见
[TEST_REPORT.md §47](TEST_REPORT.md)。

## 2. OS4 实机核对后的当前缺口

### 2.1 内存回收与 SmartCache 策略

- **状态：默认策略可用，MGLRU 不应默认开启。** OS4 的
  `init.mt6991.rc` 和 `init.rc` 都把 `/sys/kernel/mm/lru_gen/enabled` 关闭；
  `SmartCacheEnable=true` 时再次写 0。当前设备实测为 `0x0000`，SmartCache
  的 `/sys/kernel/smart_cache/*` 与 `/dev/memcg/memory.mctrl.*` 在工作。
- **冲突性质：策略互斥，不是持续抢写。** 手动打开 MGLRU 后 120 秒未被守护进程
  压回；但厂商显然把 SmartCache/mctrl 与 MGLRU 当成二选一方案。
- **风险：`PG_oem_reserved_5` 会在 MGLRU 开启时影响 forced readahead 页回收。**
  该逻辑已存在于当前 AOSP 基线 `a5c942b8` 的
  `mm/readahead.c`、`mm/vmscan.c` 和 `include/linux/page-flags.h`，不是本仓库
  的未跟踪改动；`make patches` 不会把它静默丢失。此前 33.7 小时运行后的 OOM
  deadlock 与手动开启 MGLRU 在时间上相关，但因果尚未证明。

**Todo**

- [x] 核对 `PG_oem_reserved_5` 是否属于当前基线及补丁重放范围；确认它不是
  独立的树内残留，也没有为它伪造额外补丁。
- [ ] 在 SmartCache 关闭、仅改变 MGLRU 的条件下做受控 A/B：记录
  `/proc/meminfo`、`/proc/vmstat`、文件页比例、swap 使用、OOM/lockup 和
  长时功耗；未完成前不要把 MGLRU 用于日常构建。
- [x] 检查当前活动源码相对基线的内存管理改动；除已纳入补丁系列的上游/稳定回移
  外，未发现另一份 `PG_oem_reserved_5` 残留。其长期行为仍需通过隔离 A/B 验证。

### 2.2 OS4 每次开机都会尝试但当前内核缺失的接口

以下路径来自 textdump 中的 OS4 `init.rc`/`init.mt6991.rc`，并在当前设备上复核。
“缺失”表示当前行为没有发生，不等于 stock 实现细节已经恢复。

| 接口 | 当前实测 | OS4 影响 | 优先级 |
|---|---|---|---|
| `/dev/memcg/*/memory.anno_writeback_*` | 节点和内核符号均不存在 | 冻结/保护应用的注解回写策略不生效 | 高 |
| `/proc/sys/vm/min_free_order_shift` | 不存在 | OS4 写入的高阶分配水位调节不生效 | 中高 |
| `/sys/block/zram0/writeback_quota` | 不存在；`CONFIG_ZRAM_WRITEBACK=y` 且 ExtM 正常 | `PerfInit` 的 quota 调节路径不生效；不等同于 zram 回写整体失效 | 高 |
| `/sys/block/zram0/mfz_enable` 等 MFZ 私有节点 | 不存在 | MFZ/厂商 zram 磁盘 quota 调节不生效 | 中 |
| `/proc/sys/net/ipv4/tcp_default_init_rwnd` | 验证版已实现，OS4 开机写入 60，窗口变化已实测 | 已闭环；此前发布版无此节点 | 已验证 |
| v1 blkio `weight`/`group_idle` 等 | OS4 请求的 `blkio.weight`/`group_idle` 缺失；当前有 `blkio.bfq.weight` 与 `prio.class` | 前后台 I/O 权重策略部分不生效，现有 BFQ 节点语义未与 OS4 契约对齐 | 中高 |
| `/sys/kernel/dmabuf_hugetlb/enable` | 当前属性为空，未形成有效触发；能力未与 stock 完整对照 | 只有启用对应 OS4 属性时才可能影响 DMA-BUF hugepage 策略 | 低 |

补充：OS4 还配置了 `/dev/blkio/*/blkio.cpq.level`；其当前设备可用性和
语义需要单独核对，不能用 `blkio.weight` 的结果代替。`memory.swappiness` 在
`/dev/memcg` 中也属于 OS4 依赖项；当前 `PerfInit` 报告访问
`/proc/sys/vm/swappiness` 为 `Permission denied`，应区分 SELinux/权限问题与
sysctl 本身不存在。

**Todo**

- [ ] 从 stock boot/vendor zram 模块、BTF/字符串和 `PerfInit` 调用者恢复
  `writeback_quota`、MFZ、quota 单位、边界和生命周期；先做只读 ABI 对照，再决定
  是否实现，禁止只创建兼容空节点。
- [ ] 调查 `anno_writeback` 的 stock 实现和调用路径，确认它是 F2FS/回写层、
  memcg 控制器还是小米私有 reclaim 逻辑；恢复前做 ABI 结构与厂商模块兼容检查。
- [ ] 评估 `min_free_order_shift` 与 6.6 上游 watermark/高阶分配逻辑的对应关系；
  只有找到 stock 语义后才实现 sysctl，不要简单映射到相近参数。
- [x] 实现 `tcp_default_init_rwnd` 兼容入口并通过 NoLTO、ABI 与模块静态门禁。
- [x] 启动候选内核，验证 OS4 自动写入 `60`；真机回环 A/B 中 SYN 和 SYN-ACK
  的窗口都随 sysctl 变化，测试后恢复 `60`。证据见测试报告 §50。
- [ ] 逐项核对 `/dev/blkio` 的 `cpq.level`、`weight`、`group_idle`、
  `prio.class`：已确认当前存在 `background/blkio.bfq.weight` 和
  `background/blkio.prio.class`，但 OS4 请求的 `blkio.weight`、`group_idle`、
  `cpq.level` 仍缺失；还需记录 stock/当前节点的写入返回值和实际 I/O 调度变化，
  并确认不改变 stock cgroup 子系统编号。
- [ ] 复核 `memory.swappiness` 的 SELinux 标签、权限和实际写入错误；已确认
  `/dev/memcg/memory.swappiness` 与各 memcg 节点存在且读值为 `100`，但
  `/proc/sys/vm/swappiness` 对 PerfInit 为 `Permission denied`；仍需区分
  SELinux/ownership 契约与全局 sysctl，不要误改全局 swappiness。
- [ ] 对 `dmabuf_hugetlb` 先取得 stock 是否存在及其用户态触发条件；当前设备节点
  仍缺失、对应属性为空，将其保持为低优先级观察项。

### 2.3 OS4 路径不匹配或未覆盖的观察接口

- OS4 init 尝试写 `/proc/iostat_enhance/enable` 和简化的 UFS monitor 路径；
  当前实际可用的是 `/proc/io_monitor/iostat/iostat_enabled` 与
  `.../16810000.ufshci/monitor/monitor_enable`。这是 init/厂商路径与内核接口
  的不匹配，不应再记录成“内核缺少 iostat”。
- OS4 的 `fault_report` 写路径与当前 `/proc/fault_report` 也不完全相同；当前
  模块和 proc 接口存在；checkpoint 路径已静态核对，仍缺故障注入验证。
- `lz4asm` 是 OS4 预留的可选模块位；当前系统没有该模块或符号，zram 仍可使用
  `lz4kd`/其他现有实现。这不是当前内核故障。

**Todo**

- [ ] 用 stock 与当前设备分别记录 iostat/UFS/fault_report 的真实读写路径、权限、
  输出和触发条件，决定是否需要兼容别名；不要为未触发的 init 写失败添加空节点。
- [x] 核对 stock `f2fs_stop_checkpoint()` 及模块回调：原厂和当前基线均会在非
  shutdown 路径上报，且没有按 `end_io` 过滤。无需重复添加 checkpoint 上报。
- [ ] 在隔离文件系统验证 checkpoint/end I/O 和其他原子回调上下文路径；静态匹配
  不等于故障注入验证。详见测试报告 §49。

## 3. stock-only 功能缺口

### 3.1 Hybrid UFS

当前已启用配置、sysfs 和挂载参数，但 `f2fs_hw_support_hybrid()` 固定返回
false，`hybrid=1` 返回 `-EOPNOTSUPP`。缺少 ext LUN 映射、die 发现协议和 GC
分配策略；错误实现有把数据写入错误介质的风险。

- [ ] 从 stock `vmlinux` 反汇编能力查询、die 发现和 GC 分配路径，或取得原厂源代码。
- [ ] 仅在双区域测试介质上先做只读映射验证，再进行写入/GC A/B；未完成前保持
  明确的 `EOPNOTSUPP` 回退，不伪造 hybrid 已支持。

### 3.2 UFS 官方 core 变体

stock 的 `ufs_mediatek_mod_ise.ko` 能加载，但 AOSP core 未替换。device_modules
版本依赖 MTK block/clock/power 头和 sibling/vendor 符号，不能单文件替换。

- [x] 用 device_modules 做独立 out-of-tree 编译，精简变体已生成两个 `.ko`，
  依赖原厂 `irq-dbg`；包含完整 vendor debug/feature 的变体仍未通过，见测试报告 §49。
- [ ] 补齐完整 vendor 变体的调试与 SCSI 依赖，在隔离设备上核对 UFS 初始化、
  电源/时钟、错误恢复和 I/O 延迟；未完成前不替换当前已验证的 AOSP/GKI core。

### 3.3 SCSI fastdiscard / 多 descriptor UNMAP

通用 discard 正常，但当前 `max_discard_segments=1`；stock 的
`xiaomi_fastdiscard_info`、`max_unmap_descriptors` 和 `multi_unmap_len_max`
没有公开实现。

- [ ] 恢复多 descriptor UNMAP 的命令构造、长度边界、错误回退和 queue 参数。
- [ ] 找到可安全清理的测试分区后再做 stock/当前 A/B；没有测试介质前不启用
  fastdiscard，也不把空属性当成已支持。

### 3.4 F2FS/EROFS 行为级实现与 stock 布局差异

- F2FS VIP：接口和保守 fallback 已实机验证；缺 stock inode 选择策略和调用时机。
- F2FS iostat：开关语义已实机验证；缺 stock 20 槽/10 档 per-CPU 布局语义。
- EROFS iostat：per-CPU aggregate 已验证；缺 stock 多桶布局和桶语义。
- fault_report：同步和 task-context 异步路径已验证；全路径仍未确认。

**Todo**

- [ ] 从 stock BTF/反汇编恢复 VIP 的选择阈值、调用点和 manager 所在结构。
- [ ] 从 stock show/record 函数恢复 F2FS iostat 与 EROFS 多桶的槽位、粒度和
  per-CPU 合并语义；在此之前保留行为级实现并明确非逐字 ABI。
- [ ] 对 F2FS/EROFS 做 fsck、长时写入、drop-caches 回读、故障注入和 power-loss
  验证；所有结果追加到 `TEST_REPORT.md`。

## 4. 必须保持的兼容约束

以下不是 todo，而是后续改动的硬门禁：

- `CONFIG_RSEQ`/`CONFIG_SCHED_MM_CID` 必须关闭；否则 `task_struct` 和厂商
  `mi_game.ko` 的硬编码偏移漂移。
- `CONFIG_CGROUP_DEVICE`、`CONFIG_CGROUP_HUGETLB` 必须关闭；否则 cgroup
  子系统编号和 `struct cgroup` 布局漂移。当前 OS4 依赖的七项 v1 controller
  必须保持 `cpuset/cpu/cpuacct/blkio/memory/freezer/net_prio` 顺序。
- writeback 回移 0004 暂不启用；它会改变 `bdi_writeback`/`backing_dev_info`
  布局。任何新增字段只能放入允许的 KABI/OEM reserve 槽位。
- 每次配置或结构改动都必须运行
  `python3 dash/scripts/check-abi.py <vmlinux>`，并核对厂商模块加载、KCFI、
  `dmesg` 和 OS4 启动日志。
- MGLRU 默认保持关闭，除非完成 §2.1 的隔离 A/B；MPTCP 保持关闭，代理配置
  必须 `inbound-mptcp: false`。
- 不关闭 SELinux，不写 `lk`/`super`/用户数据，不清 AVB footer 或修改 vbmeta
  flags；刷机实验必须保留完整 boot 回滚路径。

## 5. 验证缺口与可执行测试

- [ ] stock boot 与当前 boot 做启动时延、zram 压力、应用切换、I/O 延迟和功耗
  A/B；现有结果不能支持性能收益声明。
- [ ] suspend/resume 至少 10 次，覆盖 MGLRU 默认关闭、alarmtimer、s2idle，观察
  RCU stall、hung task、soft lockup 和模块恢复。
- [x] F2FS/EROFS 隔离冒烟：临时 zram 设备上各 10 轮重挂载校验；F2FS
  覆盖写入、fsync、rename、move-range 和 fsck，EROFS 覆盖只读回读和 fsck。
  见测试报告 §51。
- [ ] 实际 UFS 长时 I/O、冷缓存回读和可回滚的 power-loss
  测试；RAM 块设备不覆盖这些场景。
- [ ] mihomo/AsteriskMETA 的 TUN、热点 IPv4/IPv6 转发、弱网重连和 30 分钟大流量
  回归；保持 MPTCP 关闭。
- [ ] KSU/SUSFS 隐藏项、BakaSU 多 manager、DroidSpaces 容器和网络能力做一次
  独立回归；`CFS_BANDWIDTH`/`CGROUP_PIDS` 的限制仍需明确记录。
- [x] 确认 BBR3 的 ECN 5 ms 门槛属于上游策略，丢包下吞吐短板已有受控链路
  实测，均不作为 OS4 兼容缺陷处理；保留现有实现。见测试报告 §43。

每项测试记录命令、设备版本、结果和关键日志；新的实测证据追加到
[TEST_REPORT.md](TEST_REPORT.md)，`STATUS.md` 只保留当前状态摘要。

## 6. 已关闭或不再列为缺口的事项

- 2026-10/11 的 LTS 缺口、init_boot 未还原、ExtM dm 回写失败、stock core
  tracepoint 缺失、F2FS lock/priority、lz4kd/zram 基础路径和 DroidSpaces
  基础容器能力已分别验证，不要重新列入 todo。
- ExtM 的 `gc_pin_file_thresh` 兼容补丁已实机验证，`backing_dev` 已恢复为
  `/dev/block/dm-71`；不要回退该补丁，除非 OS4 用户态不再写超限值。
- OS4 调查期间的两次 `reboot,shell` 没有 kernel panic 证据，不能把它作为当前
  内核崩溃结论。
- `CONFIG_RSEQ`、两个额外 cgroup controller、nftables/BRIDGE_NETFILTER、
  Full LTO 等已按当前生产约束处理；它们不是可随意开启的“待补功能”。
