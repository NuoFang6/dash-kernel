# 未完成项、风险与验证缺口

> 本文件是缺口/风险/未完成项的**唯一台账**。当前版本与实机状态见
> [STATUS.md](../STATUS.md)；已完成项的证据见
> [STOCK_PARITY_AUDIT.md](STOCK_PARITY_AUDIT.md) 和
> [TEST_REPORT.md](TEST_REPORT.md)。
>
> 最后更新：2026-11-07。

## 0. 未完成项总表（按性能影响排序）

本表只列**确实尝试过但仍无法完成**的项；排序依据是“对实际 I/O/存储/调度性能的
潜在影响”，不是实现难度。影响方向可能是提升也可能是退化，均按潜在幅度排序。

**安全/LTS 说明（2026-10-30 已关闭）**：本机 stock
`ro.build.version.security_patch=2026-10-01`。旧文档中“当前基线 6.6.118、
缺 2026-02..10 LTS”是历史状态；现已升级到 AOSP `android15-6.6-2026-10_r2`
（6.6.143），该缺口不再成立，不要再列为未完成项。

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

## 1. 启动、封装与安全约束

1. **boot 封装已解决，但必须继续遵守约束。** 已实测成功的方式是从 stock 64MB
   boot 继承 header、OEM vbmeta 和 AVB footer，只替换 kernel；详见
   [BOOT_PACKAGING.md](BOOT_PACKAGING.md)。不要再用旧 mkbootimg 镜像、短镜像、
   清零 AVB 尾部的镜像，或改 `--disable-verity/--disable-verification` 的 vbmeta。
   这些均已实测 bootloop。
2. **本机隐藏解锁的启动语义。** `fastboot getvar unlocked=yes`，但系统属性仍是
   `vbmeta.device_state=locked`、`verifiedbootstate=green`、`flash.locked=1`。
   它接受保留 OEM 签名 vbmeta/footer、但 boot hash 不匹配的镜像，拒绝缺失或签名
   损坏的元数据。不要把该行为当成通用 AVB 绕过。
3. **恢复资产。** 完整 `boot_a`、`boot_b`、`vbmeta_b`、`oops` 备份在
   `out/device-backup/`；还原前的 KernelSU patched init_boot A/B 副本在
   `/home/nuofang/t5m/backup/init_boot_{a,b}_current_20261030.img`。任何时候
   不要写 `lk`、`super` 或用户数据。恢复 boot 必须使用完整 64MB 分区镜像。
4. **init_boot 已还原官方。** `init_boot_a/b` 都是 OS4.0.3.0 官方镜像
   （sha256 `3d2062ae…`）；旧的 KernelSU patched 副本只作回滚，不再把
   init_boot 视为未还原项。当前哈希见 [STATUS.md](../STATUS.md)。
5. **legacy vendor-hooks 分组回退表（未来改动时）。** 完整 13-hook 系列已实机
   启动，不再需要先证明“能否开机”。以后若 hooks 或调用点变更后出现异常，可按
   旧 6.6.118 拆分系列的分组回退定位（当前 6.6.143 已并入整树补丁）：

   ```text
   vendor-hooks/0004  remove_mapping / remove_mapping_failed
   vendor-hooks/0005  filemap_get_folio_end
   vendor-hooks/0006  put_super
   vendor-hooks/0007  fuse_request_end_ext / fetch
   vendor-hooks/0008  mmap_lock_init / free
   vendor-hooks/0009  percpu_rwsem_init
   vendor-hooks/0010  rcu_boost_* / sync_rcu_wait_*
   ```

6. **启动后采集命令。** 以下命令已在 root（KSU 域）实际执行成功，不需要关闭
   SELinux；历史数值见 [TEST_REPORT.md](TEST_REPORT.md) §8。

   ```bash
   adb shell su -c 'uname -a; cat /proc/version; getprop ro.boot.slot_suffix'
   adb shell su -c 'cat /proc/modules | grep -E "node_cache|os_cpu_qi|zsmalloc"'
   adb shell su -c 'find /sys/kernel/node_cache -maxdepth 1 -type f -exec sh -c "echo {}; cat {}" \;'
   adb shell su -c 'cat /sys/kernel/qos_inherit/inherit_enable; cat /sys/kernel/qos_sched/sched_enable; cat /sys/kernel/qos_sched/rt_prio'
   ```

### 安全注意事项

1. 关闭模块签名/vermagic/CRC/protected-export 检查会允许任意匹配架构的模块
   加载；仅用于自有、已解锁设备。
2. 内核包含 BakaSU/SUSFS，会改变 root 与隐藏行为；不要用于不受控设备。
3. `abi_symbollist.raw` 保留 stock 导出名，构建产物仍不是原厂签名内核。
4. `out/baseline-6.6.118/` 是旧式 mkbootimg 对照内核，**不是 stock 备份且不可
   启动**；恢复请使用 `out/device-backup/` 的完整原厂 boot/vbmeta。

## 2. 功能未完全等价（stock-only）

### 2.1 Hybrid UFS（最高性能影响）

- 已知：stock BTF `f2fs_hybrid_info` 192B（`main/ext f2fs_die_info` 72B、
  `free_ratio`、`gc_threshold`、`large_file_threshold`、`main/ext_new_seg_ratio`、
  `gc_alloc_mode[5]`）；`f2fs_hw_hybrid_get_avail`、`f2fs_hybrid_die_info_show`
  等函数存在。
- 当前：`CONFIG_F2FS_FS_HYBRID_UFS` 和 `CONFIG_BLOCK_HYBRID_UFS` 已启用，
  sysfs/挂载参数/函数接口存在，但 `f2fs_hw_support_hybrid()` 固定为 `false`，
  `hybrid=1` 返回 `-EOPNOTSUPP`。
- 已尝试：恢复布局、sysfs/挂载参数、能力查询、安全回退；从 stock 二进制和
  BTF 找分配器未果。
- 为什么停：没有 ext LUN 地址映射和 die 发现契约，错误映射可能把数据写到错误
  介质；这是数据安全问题，不是性能取舍。
- 下一步：从 stock `vmlinux` 反汇编 `device_hybrid_capable`/GC 分配路径，或取得
  原厂 6.6.118 源码；在双区域设备上先做只读校验。在实现前不要声称与 stock
  hybrid 等价。

### 2.2 UFS 官方 core 变体（高，未证实）

- 已知：MiCode `dash-w-oss` 的 `drivers/ufs` 已 sparse checkout（25 + 13 文件）；
  `ufs-mediatek.c` 在 6.6.118 头文件下可以编译，但 modpost 缺
  `ufs_mtk_init_sysfs`、`ufs_mb_init`、`ufs_mb_queue_error`、`ufsm_disable_intr`、
  `mt_irq_dump_status` 等 sibling/vendor 符号。包内 37 个 MTK UFS 文件保留为参考。
- 已尝试：独立 `M=` 编译探针；依赖 `DEVICE_MODULES_PATH`、MTK block/clk/power
  头、`drivers/ufs/vendor`。
- 为什么停：不能单文件替换；整体替换 AOSP core 会改变启动初始化链，且本机
  无法在无写入条件下验证 UFS 初始化/电源路径。替换会扩大启动风险，当前优先级
  低于已验证的 GKI 构建。
- 下一步：用 MTK device_modules 的 out-of-tree 构建做独立 boot 变体，只读 A/B
  UFS monitor、电源/时钟和 I/O 延迟。

### 2.3 SCSI fastdiscard / 多 descriptor UNMAP（中高）

- 已知：stock BTF `xiaomi_fastdiscard_info` 16B
  （`fastdiscard_enable`、`max_unmap_descriptors`、`multi_unmap_len_max`），
  内嵌在 `struct scsi_disk` 的 `xiaomi_feature_info`；字符串有
  `multi_unmap_len_max_show`、`[FASTDISCARD debug]`。
- 当前：通用 discard 可用；`/sys/block/sda/queue/max_discard_segments=1`；
  stock 有 `CONFIG_SCSI_DISCARD`/`CONFIG_SCSI_FASTDISCARD`，AOSP 树和当前构建没有。
- 已尝试：BTF/字符串恢复、AOSP `sd_setup_unmap_cmnd` 路径核对、公开源码检索
  （只命中 config/ikconfig）。
- 为什么停：需要多 descriptor UNMAP 命令构造和真实 UFS/分区验证；错误实现可能
  丢数据。没有 stock 源码和可安全丢弃的测试分区。
- 下一步：实现/验证多 descriptor UNMAP 的边界、错误处理和 `max_discard_segments`，
  在 scratch 分区上做 A/B。`persist.sys.stability.fastdiscard` 目前为空，默认不
  触发；在没有私有源码和有效属性前不伪造“fastdiscard 已启用”。

### 2.4 F2FS VIP 原厂选择策略（中）

- 已知：`f2fs_vip_manager` 48B（sorted/unsorted/count/capacity/
  unsorted_buf_size/head/tail/lock/enabled），`vip_inode_sorted` 8B
  （`ino` + `unsorted_idx`），`vip_inode_unsorted` 4B。
- 当前：`vip_file_enable`、排序 manager 和 `f2fs_vip_bsearch/insert/remove`
  已实现；`android_vh_f2fs_is_hiprio_task`/`is_usr_task` hook 已有调用点。
  当前没有 stock 模块注册这两个 hook，因此使用保守 fallback：有用户地址空间的
  RT 或 negative-nice 任务以写方式打开普通文件时调用 `f2fs_vip_insert`，inode
  删除/evict 时移除；fallback 管理器上限 8192 个 inode。
- 真机验证：high-priority 写打开使 `vip_inode_count` 增加，普通写不增加，删除
  减少，关闭 `vip_file_enable` 清零。`vip_inode_count` 是调试属性，不是 stock ABI。
- 为什么停：没有公开的选择策略/阈值/调用时机；恢复布局但不恢复策略只是“看起来
  像”，不能宣称等价。与 stock 的差异是 fallback 选择策略和 manager 布局
  （stock 在 `f2fs_nm_info`，当前在 `f2fs_sb_info`），不是接口不可用。
- 下一步：从 stock Image 恢复 `f2fs_vip_insert` 调用点和 manager 操作，或取得原厂
  源码。

### 2.5 F2FS 增强 iostat 精确布局（低-中）

- 当前：`en_iostat_enable` 单开关、window/daily/阈值、5 类聚合。
- stock：20 槽窗口、10 档粒度、per-CPU 私有布局；输出格式也不保证逐字相同。
- 已修复：`__update_iostat_latency()` 现在分别判断 stock `iostat_enable` 和
  Xiaomi `en_iostat_enable`；只开 `en_iostat_enable=1`、保持
  `iostat_enable=0` 时，4MiB 写入已实测记录
  read/write_sync/write_async/meta 计数，stock `io_lat` 仍只在
  `iostat_enable=1` 时更新。剩余差异是布局/粒度，不是开关语义。
- 为什么停：槽位/粒度语义未知，强行按名字实现会给出错误统计。
- 下一步：取得原厂 `f2fs_iostat` 结构/调用点，或接受“行为级统计”并明确不做逐字
  ABI 兼容。

### 2.6 EROFS iostat 多桶布局（低）

- 当前：`read_folio`/`readahead` 正常读路径已覆盖；每 CPU 统计
  （`alloc_percpu`，sysfs 汇总各 CPU），单 aggregate bucket，`iostat_config`
  输出 `percpu=1`。
- stock：每 CPU 10 window + 10 abnormal + 5 daily + 5 阈值；布局已知，
  桶语义未知。
- 已实测：drop_caches 后读取 `/product/.../AiasstVision.apk`，window/daily
  均记录 `count>=1 bytes>=4096`；缓存命中不重复计数是预期行为。
- 下一步：从 stock show/record 函数恢复语义；在此之前保留聚合统计。

### 2.7 F2FS fault_report 全路径（极低）

- 当前：`f2fs_fault_report` tracepoint 原型与 stock BTF 一致；
  `fault_report.ko` 不再报 `tracepoint ... not found`，`/proc/fault_report`
  已出现。同步 `f2fs_handle_error()` 和 task context 的
  `f2fs_handle_error_async()` 都会触发；原子 end_io 路径由 `in_task()` 过滤，
  避免回调在原子上下文做 `stack_trace_save()`/`queue_work()`。
- 未覆盖：`f2fs_stop_checkpoint()` 等路径未额外上报，避免原子上下文调用可能
  睡眠的回调；F2FS 实际故障注入/长时验证仍未做。
- 下一步：确认 stock 在这些路径是否上报，再决定是否加 `in_task()` 保护。

### 2.8 `MODULE_SCMVERSION` / 版本串（无性能影响）

- 已实测：打开 `LOCALVERSION_AUTO`/`MODULE_SCMVERSION` 后 release 变为
  `6.6.118-gf9c84f40b6ba-dirty`，丢失 `-4k` 并改变自编模块 vermagic，已回退。
- 只影响 `/sys/module/*/scmversion` 和版本可追溯性。
- 下一步：如果只需模块 scmversion，可只对自编模块启用，不改变内核 release；
  需要单独验证。

### 2.9 6.6.143 有意偏离项（不是缺口）

- **ThinLTO**：已构建并实机启动；`pid.o` 为 LLVM bitcode、`.cmd` 含
  `-flto=thin`。尚无性能/功耗 A/B，不能声明收益。
- **AutoFDO**：未启用，需要先采集 profile；按当前约定跳过。
- **pid_max clamp**：已生效并实机验证，32768 为硬上限；这是有意偏离 stock，
  用于规避 DroidSpaces 的 0x8000 PID 掩码 bug。
- **补丁序列**：已按特性拆分为 `patches/<feature>/` 系列（2026-11-21）；
  旧 6.6.118 系列与 6.6.143 整树 squash 归档，不再参与构建。

## 3. 验证缺口

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
- **`MEMFD_ASHMEM_SHIM`**：AOSP 6.6.118 自带实现，已启用；没有移植 MiCode
  6.6.89 的重复版本。缺少 Android 上层 `libmemfd`/ashmem 用户态回归测试。
- **DroidSpaces（2026-11-21）**：kABI 补丁 + 官方 GKI fragment 已接入
  （`patches/090-droidspaces`、`configs/features.fragment`）；云端 FAST
  构建通过且 ABI 核查全绿（task_struct 偏移不变、9106 个导出符号 CRC
  零漂移，见 TEST_REPORT §21）。**未实机验证**：首次刷机后需确认 586 个
  厂商模块仍全部加载、`droidspaces check` 全绿。功能限制（永久）：
  `CFS_BANDWIDTH`/`CGROUP_PIDS` 保持关闭（破坏 kABI 且无填充槽方案），
  `--cpus`/`--pids-limit` 不可用；`NETFILTER_XT_TARGET_REJECT`（nft 变体）
  在 6.6 无此符号，REJECT 由 legacy `IP_NF/IP6_NF_TARGET_REJECT` 覆盖。
- **性能/功耗与深度 A/B**：未做 stock vs 自编的 zram/node_cache/QoS/启动时延、
  suspend/resume、fsck/power-loss、长时压力。没有这些数据，不能对任何性能收益
  作声明。下一步：用 stock boot 备份做 A/B；先做只读/可回滚的启动时延和 zram
  测试，再做 suspend/resume 和长时压力。
- **SELinux**：系统保持 Enforcing；本次 root 读取 sysfs 成功，没有关闭 SELinux
  或修改上下文。`setenforce 0` 等降级策略仍不应为取证而使用。

## 4. mihomo / TCP Brutal / MPTCP

- **MPTCP 未启用。** 在 6.6.143 上 `CONFIG_MPTCP=y` +
  `CONFIG_MPTCP_IPV6=y` + `CONFIG_INET_MPTCP_DIAG=y` 实测启动失败（花屏后
  看门狗复位，无 pstore）；addrtype-only 正常启动。当前 mihomo 配置必须
  `inbound-mptcp: false`。如要继续，先做 MPTCP-only / 去 IPv6 子项隔离构建，
  不要把它当默认项。
- **Android auto-redirect 仅本机 IPv4 TCP。** mihomo Android 分支明确不用
  nftables，也不做 IPv6/热点转发；`tproxy-port` 的自动 iptables 只在 Linux
  执行，Android 需要手动规则。热点已改由 TUN auto-route + 模块的 FORWARD
  放行覆盖（2026-11-07，见 [MIHOMO_ANDROID.md](MIHOMO_ANDROID.md) §5.6）；
  REDIRECT/TPROXY 仍不覆盖转发。
- **TCP Brutal 是外部模块。** `tcp-brutal` v2.0.1 已配置为 submodule 和
  `make brutal`，但上游 GPL-3.0、`brutalctl` 的 Android 构建/`ip route
  congctl` 支持未完成；mihomo 的 Hysteria2/ShadowQUIC brutal 是 QUIC 用户态，
  不使用该模块。
- **IPv6 REDIRECT 已启用并验证 TCP。** #8（`0dc871a5…`）开启
  `IP6_NF_NAT`，`ip6tables -t nat` 正常，IPv4/IPv6 TCP REDIRECT 均进入
  mihomo；nat REDIRECT 的 UDP 丢失原始目的地址，本机 UDP 仍不可用。
- **TFO 持久化已安装并验证。** 标准 `mihomo_alpha` KSU 模块在 #8 重启后写入
  `tcp_fastopen=3`，`post-fs-data.sh`/`service.sh` 都会重写。
- **TPROXY TCP/IPv6 未形成可信结论。** TPROXY IPv4 UDP 已验证；
  veth/netns 测试环境自身 TCP 路径异常，TPROXY TCP 未 accept；IPv6
  TPROXY 也没有可信日志。本机 OUTPUT 不能使用 TPROXY target，需 TUN 或
  REDIRECT 覆盖本机应用。
- **自动 fastboot 未实现。** 需要 LK/BCB 层面的可靠机制；内核 panic
  notifier 只能 best-effort 覆盖晚 panic，见 BOOT_PACKAGING.md §7。

## 5. 上游同步（dash-droidspaces，2026-10-29）

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

## 6. 已完成、不要重复列为缺口

- **LTS/安全**：2026-10-30 已升级到 AOSP `android15-6.6-2026-10_r2`（6.6.143）。
- **stock core tracepoint**：stock 的 1860 个 `__traceiter_*` 全部存在；6.6.143
  另含 46 个上游新增（合计 1906）。集成补丁（历史拆分为
  `0007-stock-parity-hooks.patch`）回移了 51 个缺失 hook，其中 44 个同时回移
  调用点；剩余 7 个 export-only hook 已在 legacy `0008`/`0009` 补上调用点
  （MMC/DMA/lazy resched）。2 个 LZ4 事件已恢复并实测触发。这些 hook 默认无
  注册者，本构建只保证事件/符号/调用点与 stock 形状一致。
- **GKI dynamic task_struct**：`CONFIG_GKI_DYNAMIC_TASK_STRUCT_SIZE=y`、
  `GKI_TASK_STRUCT_VENDOR_SIZE_MAX=1024`；新增 `arch_task_struct_size`、
  `vendor_data_pad`（GPL 导出）和 `android_arch_task_struct_size=` early param。
  未传参数时大小为 4800B/217 成员，与 stock BTF 一致。
- **F2FS lock / priority**：`fs/f2fs/lock.c`、`f2fs_lock_elapsed_time`、
  `f2fs_priority_uplift/restore`、4 个 lock sysfs 已实现；`gc_lock` 全部调用点
  已接入 trace wrapper；默认 `adjust_lock_priority=0`。真机验证见
  [TEST_REPORT.md](TEST_REPORT.md) §12。
- **F2FS VIP 接口**：接口/fallback 已完成并实机验证；原厂选择策略仍是缺口，见
  §2.4。
- **F2FS iostat 单开关语义**：已修复并实测；布局仍是缺口，见 §2.5。
- **EROFS iostat per-CPU**：已实现；多桶布局仍是缺口，见 §2.6。
- **F2FS fault_report 同步/异步**：已恢复；全路径仍是缺口，见 §2.7。
- **lz4kd / zram ExtM（2026-10-30 已闭环）**：stock vendor zram 的 zcomp 走
  crypto API，本内核注册了 `lz4kd-generic`（type=compression），无需替换 zram
  模块；Scene 开机配置已选中 `[lz4kd]`。本机“内存扩展”是小米 ExtM，宿主是
  vendor_boot 里的 ExtM 版 `zram.ko`；**不要 rmmod + insmod 自编 zram 模块**，
  否则 `backing_dev=none`、无 `xswapd0`。详见 [ZRAM_EXTM.md](ZRAM_EXTM.md)。
- **误记纠正**：`/proc/iostat_enhance` 不是 dash 的 stock ABI；stock
  `io_monitor.ko` 实际创建 `/proc/io_monitor/...`，iostat 开关在
  `/proc/io_monitor/iostat/iostat_enabled`。UFS `monitor` 路径与 stock 模块
  一致，不再列为已确认缺口。旧文档中的这两个说法不要重复。
- **init_boot 已还原**：A/B 两槽均为 OS4.0.3.0 官方镜像；详见 §1.4 和
  [STATUS.md](../STATUS.md)。

完整核对表见 [STOCK_PARITY_AUDIT.md](STOCK_PARITY_AUDIT.md)。
