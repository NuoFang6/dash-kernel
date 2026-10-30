# 仍未完成项：按性能影响排序（2026-10-30，构建 #29）

本文件只列**确实尝试过但仍无法完成**的项；已完成项见
[STOCK_PARITY_AUDIT.md](STOCK_PARITY_AUDIT.md) 和
[TEST_REPORT.md](TEST_REPORT.md)。排序依据是“对实际 I/O/存储/调度性能的潜在影响”，
不是实现难度；影响方向可能是提升也可能是退化，均按潜在幅度排序。

## 安全/LTS 缺口（不计入性能排序）

本机 stock `ro.build.version.security_patch=2026-10-01`；当前基线是
`android15-6.6-2026-01_r1`（6.6.118），中间缺少 2026-02..10 的 LTS/安全修复。
（Mi15 另一台 OS4 设备的 dump 是 2026-08-01，比本机更旧；以本机实测为准。）
这不是性能项，但属于未完成的功能/维护缺口。升级到 2026-07_r1/2026-10_r2
可以补齐，同时保持 KMI `android15-8`；代价是重放全部补丁、638 模块/KCFI/
启动复验，见 [UPSTREAM_NOTES_REVIEW.md](UPSTREAM_NOTES_REVIEW.md)。

## 排序总表

| # | 项 | 潜在性能影响 | 当前状态 | 为什么不能完成 |
|---|---|---|---|---|
| 1 | **F2FS hybrid UFS 双区域分配** | **高**：写放置/GC/寿命/吞吐 | sysfs/挂载参数存在，`f2fs_hw_support_hybrid()` 固定 false，`hybrid=1` 返回 `-EOPNOTSUPP` | 缺 ext LUN 映射、die 分区发现、GC 分配策略；无公开源码，无法安全伪造地址 |
| 2 | **UFS 官方 core 变体** | **高（未证实）**：UFS 初始化、电源/时钟、I/O 路径 | stock `ufs_mediatek_mod_ise.ko` 可加载；AOSP core 未替换 | 官方 37 文件源是 device_modules 模块形态，依赖 MTK block/clk/power 头和 vendor 对象；独立变体未完成 |
| 3 | **SCSI fastdiscard / 多 descriptor UNMAP** | **中高**：discard/TRIM 吞吐、GC、寿命 | 通用 `sd` discard 正常；`max_discard_segments=1`；`CONFIG_SCSI_DISCARD`/`FASTDISCARD` 缺失 | 公开源码无实现；stock 的 `xiaomi_fastdiscard_info` 是 SCSI disk 层批处理，需改命令构造和硬件验证 |
| 4 | **F2FS VIP 原厂选择策略** | **中**：前台/存储优先级、UI 延迟 | hook + 保守 fallback，`vip_inode_count` 可用；manager 布局是简化版 | 原厂“哪些 inode 进入 VIP”的策略无公开来源；只恢复了 `f2fs_vip_manager` 48B 布局 |
| 5 | **F2FS 增强 iostat 精确布局** | **低-中**：观测开销/统计精度 | 单开关语义正确，5 类聚合 | stock 是 20 槽窗口 + 10 档粒度 + per-CPU 私有布局；槽位语义未知，不伪造 |
| 6 | **EROFS iostat 多桶布局** | **低**：观测；对 I/O 路径影响很小 | 已 per-CPU，单 aggregate bucket | stock 是每 CPU 10 window + 10 abnormal + 5 daily + 5 阈值；桶语义未知 |
| 7 | **F2FS fault_report 全路径** | **极低**：可靠性/诊断，不是吞吐 | 同步 + task-context 异步已上报 | `f2fs_stop_checkpoint()` 等路径是否上报未确认；不能确定 stock 行为 |
| 8 | **`MODULE_SCMVERSION`/版本串** | **无**：仅元数据/可追溯性 | 未启用 | 打开 `LOCALVERSION_AUTO` 会把 release 变成 `6.6.118-gf9c84f40b6ba-dirty`，丢掉 `-4k` 并改变 vermagic；已实测后回退 |
| 9 | **深度性能/稳定性 A/B** | 无法量化 | 未做 | 缺 stock 运行时 A/B、suspend/resume、fsck/power-loss、长时压力；不是“功能缺失”，是验证缺口 |

## 逐项说明

### 1. F2FS hybrid UFS（最高性能影响）

- 已知：stock BTF `f2fs_hybrid_info` 192B（`main/ext f2fs_die_info` 72B、
  `free_ratio`、`gc_threshold`、`large_file_threshold`、`main/ext_new_seg_ratio`、
  `gc_alloc_mode[5]`）；`f2fs_hw_hybrid_get_avail`、`f2fs_hybrid_die_info_show`
  等函数存在。
- 已尝试：恢复布局、sysfs/挂载参数、能力查询、安全回退；从 stock 二进制和
  BTF 找分配器未果。
- 为什么停：没有 ext LUN 地址映射和 die 发现契约，错误映射可能把数据写到错误
  介质；这是数据安全问题，不是性能取舍。
- 下一步：从 stock `vmlinux` 反汇编 `device_hybrid_capable`/GC 分配路径，或取得
  原厂 6.6.118 源码；在双区域设备上先做只读校验。

### 2. UFS 官方 core 变体（高，未证实）

- 已知：MiCode `dash-w-oss` 的 `drivers/ufs` 已 sparse checkout（25 + 13 文件）；
  `ufs-mediatek.c` 在 6.6.118 头文件下可以编译，但 modpost 缺
  `ufs_mtk_init_sysfs`、`ufs_mb_init`、`ufs_mb_queue_error`、`ufsm_disable_intr`、
  `mt_irq_dump_status` 等 sibling/vendor 符号。
- 已尝试：独立 `M=` 编译探针；依赖 `DEVICE_MODULES_PATH`、MTK block/clk/power
  头、`drivers/ufs/vendor`。
- 为什么停：不能单文件替换；整体替换 AOSP core 会改变启动初始化链，且本机
  无法在无写入条件下验证 UFS 初始化/电源路径。
- 下一步：用 MTK device_modules 的 out-of-tree 构建做独立 boot 变体，只读 A/B
  UFS monitor、电源/时钟和 I/O 延迟。

### 3. SCSI fastdiscard（中高）

- 已知：stock BTF `xiaomi_fastdiscard_info` 16B
  （`fastdiscard_enable`、`max_unmap_descriptors`、`multi_unmap_len_max`），
  内嵌在 `struct scsi_disk` 的 `xiaomi_feature_info`；字符串有
  `multi_unmap_len_max_show`、`[FASTDISCARD debug]`。
- 当前：通用 discard 可用；`/sys/block/sda/queue/max_discard_segments=1`。
- 已尝试：BTF/字符串恢复、AOSP `sd_setup_unmap_cmnd` 路径核对、公开源码检索
  （只命中 config/ikconfig）。
- 为什么停：需要多 descriptor UNMAP 命令构造和真实 UFS/分区验证；错误实现可能
  丢数据。没有 stock 源码和可安全丢弃的测试分区。
- 下一步：实现/验证多 descriptor UNMAP 的边界、错误处理和 `max_discard_segments`，
  在 scratch 分区上做 A/B。

### 4. F2FS VIP 原厂策略（中）

- 已知：`f2fs_vip_manager` 48B（sorted/unsorted/count/capacity/
  unsorted_buf_size/head/tail/lock/enabled），`vip_inode_sorted` 8B
  （`ino` + `unsorted_idx`），`vip_inode_unsorted` 4B。
- 当前：hook + fallback（有用户地址空间的 RT/negative-nice 写打开，上限 8192），
  不是原厂选择策略；manager 布局也简化。
- 为什么停：没有公开的选择策略/阈值/调用时机；恢复布局但不恢复策略只是“看起来
  像”，不能宣称等价。
- 下一步：从 stock Image 恢复 `f2fs_vip_insert` 调用点和 manager 操作，或取得原厂
  源码。

### 5. F2FS 增强 iostat（低-中）

- 当前：`en_iostat_enable` 单开关、window/daily/阈值、5 类聚合。
- stock：20 槽窗口、10 档粒度、per-CPU 私有布局；输出格式也不保证逐字相同。
- 为什么停：槽位/粒度语义未知，强行按名字实现会给出错误统计。
- 下一步：取得原厂 `f2fs_iostat` 结构/调用点，或接受“行为级统计”并明确不做逐字
  ABI 兼容。

### 6. EROFS iostat 多桶（低）

- 当前：per-CPU、单 aggregate bucket、`percpu=1`。
- stock：每 CPU 10 window + 10 abnormal + 5 daily + 5 阈值；布局已知，
  桶语义未知。
- 下一步：从 stock show/record 函数恢复语义；在此之前保留聚合统计。

### 7. F2FS fault_report 全路径（极低）

- 同步 + task-context 异步已上报；`f2fs_stop_checkpoint()` 等路径未额外上报，
  避免原子上下文调用可能睡眠的回调。
- 影响：诊断完整性，不是性能。
- 下一步：确认 stock 在这些路径是否上报，再决定是否加 `in_task()` 保护。

### 8. `MODULE_SCMVERSION`/版本串（无性能影响）

- 已实测打开 `LOCALVERSION_AUTO`/`MODULE_SCMVERSION` 后 release 变为
  `6.6.118-gf9c84f40b6ba-dirty`，丢失 `-4k` 并改变自编模块 vermagic，已回退。
- 只影响 `/sys/module/*/scmversion` 和版本可追溯性。
- 下一步：如果只需模块 scmversion，可只对自编模块启用，不改变内核 release；
  需要单独验证。

### 9. 深度性能/稳定性 A/B（验证缺口）

- 未做：stock vs 自编的 zram/node_cache/QoS/启动时延、suspend/resume、
  fsck/power-loss、长时压力。
- 没有这些数据，不能对任何性能收益作声明。
- 下一步：用 stock boot 备份做 A/B；先做只读/可回滚的启动时延和 zram 测试，
  再做 suspend/resume 和长时压力。

## 已完成、不要重复列为缺口的项

- core tracepoint：stock 的 1860 个 `__traceiter_*` 全部存在；6.6.143 另含
  46 个上游新增（合计 1906），2 个 LZ4 事件已恢复并实测触发。
- GKI dynamic task_struct。
- F2FS lock/priority、`gc_lock` 全调用点、VIP 接口/保守策略、fault_report
  同步+异步。
- EROFS per-CPU iostat（单桶）。
- `/proc/iostat_enhance` 误记纠正；UFS `monitor` 路径复核。
