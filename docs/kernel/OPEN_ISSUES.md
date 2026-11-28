# 未完成项、风险与验证缺口

> 本文件是当前缺口、风险和可执行 todo 的唯一台账。当前版本与实机状态见
> [STATUS.md](../STATUS.md)；原始命令、日志和失败复盘见
> [TEST_REPORT.md](TEST_REPORT.md)；特性取舍见
> [FEATURES_SURVEY.md](FEATURES_SURVEY.md)。
>
> 最后更新：2026-11-28（含**最后一轮 7 轮 GitHub 全关键词搜索**；新增 F4 `lz4p`、
> F5 `kshrink_slabd`、E5 UFS `power_mode` 三行）。以 OS4.0.4.0、实机 `6.6.144-4k #1`
> （dash，NoLTO 验证版）实测为准。本文为**表驱动、单一表格**：每行一个缺口，带
> 「默认被 OS4 用？」和「决策」两列。决策为「待决策」/「未做」的条目等机主定夺，
> 不擅自执行。

## 1. 结论摘要

当前内核可正常运行 OS4：设备正常启动，584 个关键厂商模块加载，ExtM 回写设备
`/dev/block/dm-71`，F2FS/EROFS 挂载正常，stock 七项 cgroup 控制器不变，本轮调查
未发现由内核引起的 panic/Oops/UFS·F2FS I/O 错误或模块拒载。

**本轮最重要的纠正**：dash 的 zram 内存后端是 **XRING（zgroup/xswapd/mctrl）**，
不是小米 bixi 机型的 **MFZ**。stock dash `ikconfig` 实测
`# CONFIG_MI_MEMORY_FREEZE is not set`，而 `CONFIG_XRING_ZRAM_MEMCG=y`、
`CONFIG_XRING_ZRAM_MEMCG_WRITEBACK=y`、`CONFIG_XRING_ZRAM_XSWAPD=y`；真机
`/proc/kallsyms` 中 `zgroup_enable_show`/`mctrl_score_read`/`smart_cache_attr_group`
均归属 `[zram]`。故先前判定的「MFZ 是 P1 缺口」**对 dash 不成立**——
`mfz_enable`/`writeback_quota`/`anno_writeback_*` 在 dash 上本就不存在。

## 2. 缺口总览（唯一表格）

决策语义：`待决策` = 等机主；`未做` = 本轮不做；`已证伪` = 经核实不是缺口；
`保持 stock` = 用厂商模块不自研；`观察` = 仅监控。

| 编号 | 项目 | 默认被 OS4 用？ | 实机现状（2026-11-28） | 决策 |
|---|---|---|---|---|
| A1 | `mfz_enable`/`mfz_disk_quota`/`anno_writeback_*`（小米 bixi MFZ） | **否**（dash 不用 MFZ） | stock dash `MI_MEMORY_FREEZE=n`，故无此节点；PerfInit 报 `mfz_enable not exist` 属正常 | **已证伪(对 dash)**——bixi/高通特性，不移植 |
| A2 | zram `writeback_quota` | 否 | 不存在（正常） | **已证伪(对 dash)** |
| A3 | **XRING `zgroup_enable`** | 是（dash 真正的 zram 分组回写开关） | 节点存在，值 **0**；`[zram]` 含 `zgroup_enable_show`；源码 `mtk-device-modules-hikari`；语义见 venus 文档 | **待决策**——是否启用 XRING zgroup / 与 SmartCache 关系待定 |
| A4 | **XRING `memory.xswapd.*`**（后台换出线程） | 是（stock `XRING_ZRAM_XSWAPD=y`） | 16 个节点全在；实测 `enable=0`、`watermark(mem_press)=3000`、`quota=7GiB`、`stat nr_comp=0`；源码 `xswapd.c` + venus 文档 | **待决策**——是否启用自动 xswapd（stock 默认关） |
| A5 | `memory.mctrl.*`（SmartCache 组策略） | 是 | 9 个节点全在；根值为 `-1`(未设)，`group_param` 表头与 venus 文档一致；`SmartCacheEnable=true` | **保持 stock**（不重写；语义见 venus 文档） |
| A6 | zram `zgroup_enable` 伪造 | — | — | **不做**——禁止用空节点冒充（会让 PerfInit 切到不支持模式） |
| B1 | blkio v1 `weight`/`group_idle` | 是（`on init` 写） | 根缺 `weight`/`group_idle`，子有 `blkio.bfq.weight` | **待决策**（alias 到 bfq / 记不适用） |
| B2 | blkio `cpq.level` | 是（`smartfocusio.v1=on`） | vip/hipri/lowpri/limit 无 `blkio.cpq.level`；调度器有 cpq 但当前 `[adios]` | **待决策**（先定 cpq vs ADIOS） |
| B3 | `/proc/sys/vm/min_free_order_shift` | 名义上 | 不存在；6.x 已删，stock 6.6 也无 | **已证伪**（不做） |
| B4 | `extra_free_kbytes` / `mi_wmark` | 是（shim 路径） | shim 已写 `watermark_scale_factor=50`；`/sys/kernel/mi_wmark` 无 | **已证伪**（非必需） |
| C1 | `memory.swappiness`（PerfInit 报 Permission denied） | 是 | `/proc/sys/vm/swappiness=100` 正常；属 SELinux 域权限 | **未做**（非内核缺口，不新增 sysctl） |
| D1 | stock 小米模块（mi_reclaim/vip_sched/rss_monitor/dynamic_readahead/mi_memory/mi_mempool/mi_game/fault_report） | 是 | 全部已加载并工作（mi_reclaim `refill_total:15567`） | **保持 stock**（不自研；dada 重建版多 DO NOT LOAD） |
| E1 | Hybrid UFS | 否 | `hybrid=1` → `-EOPNOTSUPP` | **未做**（stock-only，禁伪造） |
| E2 | UFS 官方 core 变体替换 | 否 | 未替换 | **未做**（依赖未齐） |
| E3 | SCSI fastdiscard / 多 descriptor UNMAP | 否 | `max_discard_segments=1`（2026-11-28 复测不变） | **未做**（无测试介质） |
| E4 | F2FS/EROFS VIP、iostat 行为级 vs stock | 部分（iostat 默认关） | 行为级实现，非逐字 ABI | **未做**（需 stock 语义） |
| E5 | UFS `power_mode`/gear-lane debugfs 运行时切档 | 否（非 stock） | 我们的 `ufs-debugfs.c` 只有 `exception_event_mask`/`exception_event_rate_limit_ms`；设备 `clkscale_control` current=0 | **未做**——研究/调试价值高；源码见 FEATURES_SURVEY 末节（MT6991 实机修复可用） |
| F1 | iostat_enhance / UFS monitor 路径不匹配 | 否（property 门控） | 缺 `/proc/iostat_enhance`，但 `/proc/io_monitor` 已用 | **观察** |
| F2 | `/sys/kernel/dmabuf_hugetlb/enable` | 否（property 门控） | 缺失 | **观察** |
| F3 | `lz4asm`（NEON LZ4 加速模块） | 否（property 门控） | 无该模块；zram 用 lz4kd | **观察** |
| F4 | **XRING `lz4p` zram 压缩算法**（`CONFIG_XRING_ZRAM_LZ4P`） | 否（stock dash 未编入） | 设备 `comp_algorithm` = `lzo lzo-rle lz4 zstd [lz4kd]`，无 `lz4p`；vendor `zram.ko` 中 `lz4p` 字符串 0 | **未做**——可选性能项；唯一公开源码在 `marble`（`lib/lz4p/` 12 文件 + `zcomp.c` 注册） |
| F5 | **`kshrink_slabd`**（异步 shrink_slab） | 否 | `lsmod` 无；`/proc/kallsyms` 中 `shrink_async` 计数 0 | **未做**——性能项；完整源码 `marble:drivers/staging/kshrink_slabd/`，仅需本树已导出的 `android_vh_shrink_slab_bypass` + `shrink_slab` |
| G1 | MGLRU / SmartCache 与 OOM deadlock 因果 | 否（厂商默认关） | `lru_gen=0x0000`，SmartCache 默认开 | **待决策**（隔离 A/B 前保持关） |
| H1 | 性能/功耗 A/B（stock vs 自编） | — | 缺数据 | **未做** |
| H2 | suspend/resume ≥10 次 | — | 缺数据 | **未做** |
| H3 | UFS 长时 I/O / 冷缓存回读 / power-loss | — | 缺数据 | **未做** |
| H4 | mihomo/AsteriskMETA 网络回归（TUN/热点/弱网/30min） | — | 未做 | **未做** |
| H5 | KSU/SUSFS/BakaSU/DroidSpaces 独立回归 | — | 部分验证，未独立回归 | **未做** |
| H6 | 隔离 FS 的 checkpoint/end-I/O 故障注入 | — | 静态核对过 | **未做** |
| I1 | `zram.ko` 文件身份（已澄清） | — | **运行的是 vendor_boot ramdisk 的厂商 zram.ko（269480 B，含 zgroup/mctrl/xswapd，无 mfz；sha256 `21d0c6c6…`）**，不是 `/system_dlkm` 的 85 KB AOSP 版；见 [ZRAM_EXTM.md](ZRAM_EXTM.md) | **已澄清**（保持 vendor zram；不得替换） |

> 「已证伪」的行是对先前台账的纠正，不要重新实现（详见 §3）。

## 3. 已证伪 / 保持 stock 的证据链（供复核）

- **MFZ 对 dash 不适用**：stock dash `ikconfig` = `# CONFIG_MI_MEMORY_FREEZE is not set`；
  运行态 kallsyms 无 `mfz*`/`anno_writeback`/`writeback_quota` 符号；
  有 `zgroup_enable_show`、`mctrl_score_read`、`smart_cache_attr_group`（均 `[zram]`）。
  MFZ 是 bixi/sm8750（高通）机型实现（`CONFIG_MI_MEMORY_FREEZE`，源码在
  BIXI 6.6 与 ONEFEI 0048），dash（MT6991）走 XRING。**不移植 MFZ。**
- **`writeback_quota`**：PerfInit 检查项，属 bixi MFZ 路径；dash 无此路径，正常缺失。
- **`min_free_order_shift`**：Linux 5.x 已删；BIXI 6.6 无；全 GitHub 6.x `page_alloc.c`
  搜不到；stock OS4 同样无效。
- **`mi_wmark`/`extra_free_kbytes`**：设备走 `/system/bin/extra_free_kbytes.sh`，
  属性不存在时降级写 `watermark_scale_factor`（实测 50，默认 10 → 已生效）。
- **`swappiness` 报错**：`/proc/sys/vm/swappiness=100` 正常；是 `system_perf_init`
  域 SELinux 权限，不新增 sysctl。
- **stock 小米模块**：实测已加载并工作（见总表 D1），`/proc/kallsyms` 证明它们在跑；
  dada 仓库的重建版多为 PARTIAL 或 `DO NOT LOAD`（充电/电池/TEE/Wi-Fi 族绝不可刷），
  我们**保留 stock `.ko`**，只借鉴接口与思路。
- **XRING 源码权威性已字节核验**（2026-11-28）：`third_party/mtk-device-modules-hikari/
  drivers/ufs/ufs-mediatek.c`（3527 行）与 MiCode 官方 `MTK_kernel_device_modules`
  的 `dash-w-oss` 分支 `diff -q` **完全一致**；同目录 `drivers/block/zram/`
  含 `zgroup/zgroup_wb/mctrl/xswapd/smart_cache`。→ 引用的 XRING 源码是 stock，不是逆向版。
- **XRING 非 MTK 通用**（2026-11-28 反证）：官方 MT6991 6.6.118 树
  `OnePlusOSS/android_kernel_oneplus_mt6991` 与 OPPO `mt6991` 的
  `drivers/block/zram` 均为纯 AOSP（无 XRING/lz4p）；公开 GKI 树
  `yili-w-oss`(6.12.38)/`piano-w-oss`(6.6.57) 也无 XRING。→ XRING 仅存在于小米
  `kernel_device_modules`（即我们的 `hikari` 子模块）。
- **`lz4p`/`kshrink_slabd` 是真实缺口**（2026-11-28）：设备 `comp_algorithm`
  无 `lz4p`、vendor `zram.ko` 内 `lz4p` 字符串 0、`kallsyms` 无 `shrink_async`；
  两者完整源码只在 `marble`（MT6878）公开。**注意**：当前 `[lz4kd]` 来自本内核
  crypto，不是厂商 ko（ko 内 `lz4kd` 字符串同样为 0，只带 `lzo-rle`/`zstd`）。

## 4. 待决策项的执行预案（机主定后按此做）

### 4.1 XRING 后端（A3/A4）
- 源码：`third_party/mtk-device-modules-hikari/drivers/block/zram/{zgroup,zgroup_wb,
  mctrl,xswapd,smart_cache}.c`（mt6991 分支），是该机型 `zgroup_enable`/
  `memory.mctrl.*`/`memory.xswapd.*` 的权威实现。
- [ ] 先只读核对：我们的 AOSP zram 是否已带这些 vendor 扩展；`zgroup_enable=0`
      是否符合厂商预期；`xswapd` 是否需与 `CONFIG_XRING_ZRAM_XSWAPD` 对应开启。
- [ ] 若决定启用：按 stock 语义对齐，跑 `check-abi.py` + 厂商模块/KCFI/dmesg 核对；
      禁止伪造空节点。

### 4.2 blkio（B1/B2）
- [ ] `weight` → `blkio.bfq.weight` alias 评估；`group_idle` 在 BFQ 无对应，明确记「不适用」，
      不改 cgroup 子系统编号。
- [ ] 先决策 cpq 与 ADIOS 取舍；确定恢复才实现 `cpq.level`。

### 4.3 MGLRU（G1）
- [ ] SmartCache 关闭、仅改 MGLRU 的受控 A/B（meminfo/vmstat/文件页/swap/OOM/lockup/功耗）。
      未完成前 MGLRU 日常构建保持关闭。

### 4.4 验证缺口（H1–H6）
- [ ] 逐项补实测；结果追加 TEST_REPORT，STATUS 只留摘要。
- [x] BBR3 ECN 5ms 门槛属上游策略、丢包吞吐短板已有受控链路实测（TEST_REPORT §43），不作兼容缺陷。

### 4.5 新增可选性能项（F4/F5，2026-11-28 搜出的真实缺口）
- **F5 `kshrink_slabd`**（建议优先，风险最低）：源码
  `marble:drivers/staging/kshrink_slabd/{Kconfig,Makefile,kshrink_slabd.c}`（230 行）。
  依赖已满足：本树 `android_vh_shrink_slab_bypass` 已导出、
  `mm/vmscan.c:1131 EXPORT_SYMBOL_GPL(shrink_slab)`。落地步骤：拷 3 文件到
  `drivers/staging/kshrink_slabd/` → `drivers/staging/Kconfig` 加 source →
  `drivers/staging/Makefile` 加 `obj-$(CONFIG_KSHRINK_SLABD)` → `CONFIG_KSHRINK_SLABD=m`
  → 跑 `check-abi.py`（新增独立模块，理论上不动 KABI）→ 实机 insmod + `/proc` 节点核对。
- **F4 `lz4p`**（收益不确定，优先级低）：需引 `lib/lz4p/`（12 文件，含 `.S` NEON 汇编）
  + `lib/Kconfig`/`lib/Makefile` + `zcomp.c` 注册 `"lz4p"`。**风险**：dash 的 zram 是
  厂商 ko，`zcomp.c` 在 ko 内不在内核镜像里 → 内核侧加 `lz4p` 也**不一定**能被厂商
  zram 选中。落地前必须先确认 dash 厂商后端是否预留算法名（当前 `comp_algorithm`
  无 `lz4p` 已说明未预留）。因此**建议先只做 F5，F4 暂缓**。
- **E5 UFS `power_mode`**：只读研究价值；`ShriHari33/mt6991-ufs-gear-lane` 的
  `proposed/0001`+`0002` 对 stock `android15-6.6` 干净应用（其对 stock 6.6 未编译验证）。
  若要动 UFS，必须先在 stock 上 dry-run + 单独验证，不与 F5 混做。

## 5. 必须保持的兼容约束（硬门禁，非决策项）

- `CONFIG_RSEQ`/`SCHED_MM_CID` 必须关；否则 `task_struct` 与厂商 `mi_game.ko` 硬编码偏移漂移。
- `CONFIG_CGROUP_DEVICE`、`CONFIG_CGROUP_HUGETLB` 必须关；否则 cgroup 子系统编号与
  `struct cgroup` 布局漂移。七项 v1 controller 保持
  `cpuset/cpu/cpuacct/blkio/memory/freezer/net_prio` 顺序。
- writeback 回移 0004 暂不启用；新增字段只放允许的 KABI/OEM reserve 槽。
- 每次改配置/结构必跑 `python3 dash/scripts/check-abi.py <vmlinux>`，并核对厂商模块加载/
  KCFI/dmesg/OS4 启动日志。
- MGLRU 默认关、MPTCP 关（`inbound-mptcp: false`）。
- 不关 SELinux，不写 `lk`/`super`/用户数据，不清 AVB footer、不改 vbmeta flags。

## 6. 已关闭或不再列为缺口

- LTS 缺口、init_boot 未还原、ExtM dm 回写失败、stock core tracepoint 缺失、
  F2FS lock/priority、lz4kd/zram 基础路径、DroidSpaces 基础容器能力：已分别验证。
- ExtM `gc_pin_file_thresh` 兼容补丁已实机验证，`backing_dev=dm-71`；不回退。
- `tcp_default_init_rwnd` 已实现并真机验证（OS4 写 60、回环 A/B 生效）。
- OS4 调查期间两次 `reboot,shell` 无 kernel panic 证据。
- `writeback_quota`、`min_free_order_shift`、`mi_wmark`、`swappiness`、MFZ：见 §3「已证伪」。