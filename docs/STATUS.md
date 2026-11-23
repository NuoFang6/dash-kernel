# 当前状态

> 本文件是“当前构建/运行状态”的**唯一事实源**。其他 README、导航和功能文档
> 只链接到这里，不再复制版本号、哈希、模块数和验证结论。
>
> 最后核对：2026-11-24。刷新方法见文末。

## 1. 版本与产物

| 项 | 值 |
|---|---|
| 设备 | `dash` / REDMI Turbo 5 Max / MT6991，4K 页 |
| 设备 stock | `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k` |
| 当前内核 | `6.6.144-4k #16`（生产标准 Full LTO + MLGO + AutoFDO + A720 tune + ExtM f2fs 兼容补丁，本机 2026-11-24 05:39 CST 构建并实机启动；ExtM 回写已恢复 `dm-71`）。`uname` 被 SUSFS 伪装为 stock `6.6.118`，以 `/dev/kmsg` 启动行和 `/proc/config.gz` 为准 |
| AOSP 基线 | `android15-6.6` 开发分支，tip `a5c942b8c5be461264ec25e7893e53fda4144a3a`（2026-11-23，Merge `android15-6.6.144_r01`，6.6.144）；2026-11-24 起不再固定发布 tag |
| 工具链 | clang r614150（23.0.1）/ LLD 23.0.1，2026-11-24 刷新到 `main-kernel` 最新同版本快照（build 16836431，tree `9258d46`）；当前实机为 Full LTO 生产构建（`LTO_CLANG_FULL` + MLGO regalloc advisor + ACK 预制 AutoFDO profile `kernel.afdo`，SHA256 已钉死）；日常验证仍统一 NoLTO，未做 A/B |
| 本地生产构建（2026-11-24） | 基线 `a5c942b8c` + 34 补丁（含 `DASH-EXTM-COMPAT`）+ 原厂 ABI 对齐配置；`LTO_CLANG_FULL` + MLGO + AutoFDO + A720 tune；`Image` 47,626,752 B（`fdf3b294…`）/ `Image.lz4` 22,724,910 B（`206d66a3…`）/ `boot.img` 67,108,864 B（`7e36a974…`）；零 warning；ABI 六项硬校验通过（`kmem_cache` 240 为软偏差）、KCFI 13/13、638 模块 `unresolved_hard=0/unresolved_weak=0`；**已刷入 `boot_a`，正常开机，ExtM backing device 恢复 `/dev/block/dm-71`** |
| 运行时能力（2026-11-24） | Landlock（ABI v3）、HUGETLBFS、VXLAN、VHOST_NET、EVONIX_IO_PRIO `=y`；**ABI 硬约束：`CONFIG_RSEQ`/`SCHED_MM_CID`、`CONFIG_CGROUP_DEVICE`、`CONFIG_CGROUP_HUGETLB` 必须保持关闭**（前者改 `task_struct` 4800→4864、vendor data 3008→3064、OEM data 3520→3576；后两者改 `cgroup` 1920→1984 且使 `freezer`/`net_prio` 的 `cgroup_subsys_id` 后移，厂商预编译模块按 stock 常量内联访问会错位）。**按机主要求未引入 nftables，`NF_TABLES`/`BRIDGE_NETFILTER` 保持关闭**；默认 ADIOS / BBR3 / fq / zram lz4kd；`UBSAN`/`UBSAN_TRAP`/`INIT_ON_ALLOC_DEFAULT_ON`/`KFENCE`/`SLAB_FREELIST_HARDENED`/`SLUB_DEBUG` 按机主要求关闭；`CFS_BANDWIDTH`/`CGROUP_PIDS`/`MPTCP` 保持关闭；Scene/YC 依赖项保持开启。ABI 由 `scripts/check-abi.py` 在每次构建后硬校验；`DASH-EXTM-COMPAT` 补丁维持厂商 ExtM 的 dm 回写（移除条件见 OPEN_ISSUES §2.11） |
| 发布 | Release `dash-6.6.143-prod`（2026-11-22 更新，tag `ebfc285`）：Image 45,857,280 B / Image.lz4 22,288,250 B / SHA256SUMS + `dash_art_tune-AnyKernel3-v1.4.zip` + `dash_art_tune-v1.4.zip`（显示名「内核附加模块」）；发布页含 AnyKernel3/fastboot 刷入说明 |
| 运行槽位 | `boot_a`（`ro.boot.slot_suffix=_a`，2026-11-22） |
| `boot_a` SHA256 | `7e36a9747569bacda2e3571c3a050affe45694044466f72f21bed4b209e12a86`（6.6.144 生产 Full LTO + ExtM 兼容补丁，2026-11-24 刷入）；`e12ff624…`（同基线无兼容补丁版）；回滚备份 `221cad2d8ca79e60a1b2649e0e37b5a9a40eb3e0d93cc54ffced609a41c80030`（6.6.143 生产，2026-11-22）；生产 `d0cdd6ad…` 备份在 `dash/out/device-backup/20261122-154445-pre-nolto-perf-fp-slot_a/`；NoLTO perf `7db11d8f…` 备份在 `20261122-162106-pre-full-lto-perf-slot_a/` |
| `init_boot_a` / `b` | a: `ded406b1cb63252f9bfbcaa74fa86817f7848b9d6a6e74d8477c7d551e001ebd`（OS4.0.4.0 官方，实机在用；与 OTA 包内 `init_boot.img` 完全一致）；b: `3d2062ae64992885cb4cfba19bac2699d1e07d7b7df91a8f0a770a493622b70a`（OS4.0.3.0，未随 OTA 更新） |
| `boot_b` SHA256 | `0dc871a520c39aa6cf57a177d3a78dd833b79a3bcfa14a5cca01985dacedc06e`（历史自编 `#8`，非 stock；OTA 的 stock boot 为 `f8f0de69…f2b3c`） |
| 安全 | SELinux `Enforcing`；BakaSU 内建（`CONFIG_KSU=y`）+ SUSFS v2.4.0（10 项特性，f98f082 即 v2.4.0）。SUSFS 伪装已按 OS4.0.4.0 OTA 官方 boot 校准：uname=`6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k` / `#1 SMP PREEMPT Mon Jul 20 11:15:20 UTC 2026`；`/proc/bootconfig` spoof 为 `verifiedbootstate=green`、`device_state=locked`；AVC log spoofing、SUS mount 隐藏开启，SUSFS 日志关闭；配置持久化在 `/data/adb/ksu/.susfs.json`。`/proc/version` 仍暴露 `6.6.143-4k`（SUSFS 无此 spoof 项） |
| 厂商模块 | 638 个 stock 清单 `hard_missing=0 weak_missing=0`；2026-11-22 生产 `#1` 加载 584 个（KSU/NoMount 已内建，与历史 586 个 LKM 口径等价），无 `Unknown symbol`/CRC/vermagic/invalid format 错误；KCFI 13/13 |
| KSU 模块 | 自建 `dash_art_tune` v1.5，显示名「内核附加模块」（BBRv3+fq、4 个 TCP sysctl、ADIOS 幂等、ART/dex2oat 调优、zram `lz4kd` 恢复、WLAN 日志关闭：3 个 persist 开关 + `cnss_diag.conf` bind mount + `wlan_logs` 清理/`tcpdump.pcap0` 目录 + 停止 `vendor_tcpdump`）；2026-11-24 已用 `ksud module install` 安装 v1.5（下次重启生效）；代理客户端为 AsteriskMETA + 增强模块 |
| DroidSpaces | 内核支持 + 用户态 v7.2.0；`droidspaces check` 全绿；Alpine NAT 容器冒烟通过；`CFS_BANDWIDTH`/`CGROUP_PIDS` 关闭，`--cpus`/`--pids-limit` 不可用 |
| PID | `pid_max` 硬钳 32768（`PID_MAX_LIMIT`） |
| 内存扩展 | stock vendor zram + ExtM；lz4kd 经 crypto API 选中，不替换 zram 模块。内核自建 `zram.ko` 默认改为 lz4kd（`ZRAM_DEF_COMP_LZ4KD=y`），实机 vendor zram 仍由附加模块恢复 `[lz4kd]` |
| 网络代理 | AsteriskMETA（mihomo core）：TUN/GSO、auto-route/auto-redirect、addrtype、IPv6 NAT、BPF2SOCKS 能力齐备；MPTCP 关闭 |
| TCP Brutal | 外部 `tcp-brutal` v2.0.1，`make brutal` 生成 `brutal.ko` |

完整交付哈希在 `dash/out/artifacts/SHA256SUMS`，构建输入在
`dash/out/artifacts/BUILD_INFO`；本地 artifacts 仍是历史 #8 交付批次，
生产 Full LTO 产物以 Release `dash-6.6.143-prod` 的 SHA256SUMS 为准。历史
System.map 本地副本已缺失（清单保留目标哈希）。2026-11-24 的 6.6.144 NoLTO
验证构建未发布 artifacts，只写 `dash/out/dash/`；它与实机运行的生产
Full LTO 版本无关。

## 2. 最近验证

- **2026-11-24（真机，#16 生产版 + ExtM 兼容补丁）**：刷入 `7e36a974…`
  后正常开机（`6.6.144-4k #16`）。`fs/f2fs/sysfs.c` 的
  `gc_pin_file_thresh` 兼容补丁（`DASH-EXTM-COMPAT`）生效：写
  4294967295 返回 0 并截断为 65535，`dmesg` 出现
  `ExtM: setup backing device /dev/block/dm-71`（不再是 loopNN），
  `PerfInit` 日志不再有 `gc_pin_file_thresh: Invalid argument`；
  `dmesg` 无 panic/BUG/WARNING/模块加载错误。
- **2026-11-24（真机，6.6.144 生产 Full LTO 首启）**：`boot_a` 刷入
  `e12ff624…` 后正常开机，`/proc/version` 为 `6.6.144-4k #15`（clang
  r614150）。开机后核查：`dmesg` 无 `BUG:`/`WARNING:`/panic/`brk #0x8228`/
  模块加载失败/rcu stall，`avc denied` 0 条；584 个厂商模块加载
  （`node_cache`/`os_cpu_qi`/`mtk_mbraink`/`cam_fs`/`mi_game`/`task_turbo`
  均在），taint 组合与上一版生产一致；`landlock: Up and running`，
  LSM 链为 `capability,landlock,selinux,bpf,baseband_guard,integrity`；
  `cc=bbr3`、`default_qdisc=fq`、`sdc scheduler=[adios]`；`/proc/config.gz`
  确认 RSEQ/CGROUP_DEVICE/CGROUP_HUGETLB/UBSAN/KFENCE/SLUB_DEBUG 等均为 off，
  `LTO_CLANG_FULL`/`AUTOFDO_CLANG`/`LANDLOCK`/`VXLAN`/`VHOST_NET` 为 on。
  发现 `dash_art_tune` 实机仍是旧 v1.4（把 qdisc 设回 `fq_codel` 且没有 4 个
  TCP sysctl），已装 v1.5（下次重启生效）并手动应用：`tcp_mtu_probing=1`、
  `tcp_ecn=1`、`tcp_slow_start_after_idle=0`、`tcp_notsent_lowat=16384`、
  `default_qdisc=fq`。见 [TEST_REPORT.md](kernel/TEST_REPORT.md) §41。
- **2026-11-24（真机，ABI 定位与修复）**：6.6.144 上带 `180-stable-backports`
  与新运行时配置的四个构建全部“花屏后重启、无启动动画”。从原厂
  `boot.img`（`f8f0de69…`）内嵌 BTF 解析出原厂 `task_struct` 4800 /
  vendor data 3008 / OEM data 3520 / `cgroup` 1920 / `bdi_writeback` 904 /
  `backing_dev_info` 1336 作为基线，逐版对照后二分：关 RSEQ 仍花屏、再摘
  writeback 回移仍花屏、**再关 `CGROUP_DEVICE`+`CGROUP_HUGETLB`（六项 ABI
  全部对齐）后正常开机**。根因是配置改坏原厂 ABI，cgroup 子系统编号为主。
  产物：`dash/out/no-cg/`（NoLTO，boot.img SHA256 `43a16a2d…`）。新增构建门禁
  `scripts/check-abi.py`。见 [TEST_REPORT.md](kernel/TEST_REPORT.md) §41。
- **2026-11-24（构建级，未刷机）**：仓库切换为跟随 AOSP `android15-6.6`
  开发分支，基线 `a5c942b8c`（6.6.144-r01）。重放 30 个补丁/143 个文件，
  唯一冲突为 f2fs 挂载选项（上游 `resizable_tail_secno` 与 dash `hybrid`
  并存）；同步 BakaSU `de80463`、SUSFS `f98f082`（分支头即 pin）、NoMount
  `6849f00`、tcp-brutal `d2397ff`，工具链刷新到最新 r614150 快照。NoLTO
  全量构建 4m17s 通过，零 warning；KCFI 13/13、638 模块硬/弱缺失均为 0。
  本轮同时按 BakaSU 新设计移除了 AOSP 侧过时的 SELinux 手动 hook（改由其
  运行时 auto hook 接管），并把 ADIOS 更新到 EVONIX `901a0cf`。
  **同日后续（未重编）**：新增 `180-stable-backports`（UDP tunnel 分段 UAF、
  IPv6 解析、DAMON、writeback/ext4，35 补丁/156 文件），按请求启用
  Landlock/RSEQ/HUGETLBFS/CGROUP_DEVICE/VXLAN/VHOST_NET/EVONIX_IO_PRIO
  （**nftables 与 BRIDGE_NETFILTER 按机主要求不引入**）；配置经
  `FAST=1` olddefconfig 验证。见
  [TEST_REPORT.md](kernel/TEST_REPORT.md) §40。
- **2026-11-22（实验收尾，已作为生产版发布）**：DASH_PERF 改为标准 Full LTO
  （移除 `--lto-O3`/ext-TSP/MFS/mergeicmps）。NoLTO 与 Full LTO 两版均实机
  启动：BPF loader 正常（此前 Full LTO 的 `schedcls_tether_downstream6_ether`
  EINVAL 不再出现），mtk_mbraink 帧链回溯不再崩溃，585 模块，无
  Oops/panic/SError。模块显示名改为「内核附加模块」，AnyKernel3 包名全称；
  NoMount 的 “Bootloop Prevented” 旧状态已重置。Release `dash-6.6.143-prod`
  已更新并写明刷入方法。见 [TEST_REPORT.md](kernel/TEST_REPORT.md) §39。
- **2026-11-22（生产内核首刷，真机）**：Full LTO 生产内核 `#1` 写入 `boot_a`
  （镜像 `d0cdd6ad…`，设备端回读一致），一次启动成功。真实版本行 6.6.143-4k
  与 CI 构建时间吻合；`LTO_CLANG_FULL`/`CFI_CLANG`/`AUTOFDO_CLANG`/MLGO/A720
  tune 全部在运行配置中。无 panic/BUG/KCFI trap/模块校验失败；唯一内核 WARNING
  仍是厂商 `mtk_cmdq_debug` 重复注册。584 模块、BBRv3+fq_codel、ADIOS、
  zram+lz4kd+ExtM 回写设备、SUSFS 10 项、KSU root、DroidSpaces required 全绿、
  UFS health 0x01 未变。见 [TEST_REPORT.md](kernel/TEST_REPORT.md) §29。
- **2026-11-22（CI 构建 + 发布）**：Full LTO 生产构建通过
  （run 44923883114，commit `b6aac16`，26 分钟）。修复了 `LD vmlinux.o`
  之后 `__kcfi_typeid_idmap_cpu_replace_ttbr1` 未定义：clang 为多个取址
  TU 生成重复弱绝对 typeid，Full LTO 合并时整体丢弃；改为不透明声明 +
  `arch/arm64/mm/idmap_cfi.c` 单一取址。`Image` 47,684,096 B、
  `Image.lz4` 22,808,794 B（限 67,098,176 B），BTF/kallsyms/最终链接全部
  通过；Release `dash-6.6.143-prod` 已发布 Image/Image.lz4/SHA256SUMS/
  AnyKernel3/KSU 模块。见 [TEST_REPORT.md](kernel/TEST_REPORT.md) §28。
- **2026-11-21（构建级，未刷机）**：FEATURES_SURVEY 落地批次完成；固定 r4
  干净树重放 28 补丁/142 文件 + SUSFS override，零 warning/error；NoLTO
  全量构建通过。对实机 #8 历史 `vmlinux` 比较 9102 个公共导出符号，CRC
  `0 mismatch / 0 removed`（新增 10）；`task_struct` 仍 4800B，SYSV 字段保持
  KABI 槽 6/7/8 偏移；638 模块 `hard_missing=0 weak_missing=0`，KCFI 13/13。
  Full LTO 仅在明确要求生产级产物时运行，本轮最终重链接按新策略主动停止；
  未刷入任何手机分区。见 [TEST_REPORT.md](kernel/TEST_REPORT.md) §24。
- **2026-11-21（实机 + 构建）**：6.6.143 #8 实机运行 23h51m 无
  panic/OOM/stall/fs 错误，crash buffer 为空；AOSP 基线 bump r2→r4、
  BakaSU/SUSFS 子模块更新后 12 补丁重放无冲突；SUSFS f98f082 优先级
  uid 过滤门控修复（本地 FAST 构建通过）；`mihomo_alpha` KSU 模块
  移除，代理客户端改用 AsteriskMETA（内核 TUN/TPROXY/BPF 能力核对齐备）。
  CI fast [run 44881172820](https://github.com/NuoFang6/dash-kernel/actions/runs/44881172820)
  通过（19 分钟，工具链 cache 命中，flashable 尺寸检查通过）。
  见 [TEST_REPORT.md](kernel/TEST_REPORT.md) §22/§23。
- **2026-11-21（构建级）**：DroidSpaces 容器支持内建（kABI 补丁 + 官方 GKI
  fragment）；云端 FAST 构建通过，task_struct 偏移与 9106 个导出符号 CRC
  实证零漂移，vendor `.ko` ABI 不变；未实机。见 [TEST_REPORT.md](kernel/TEST_REPORT.md) §21。
- **2026-11-07**：`mihomo_alpha` r5-pgo 增加热点转发所需的 FORWARD 放行；
  真实 Wi-Fi 客户端 IPv4/IPv6、DNS、TUN 转发实测通过。见
  [MIHOMO_ANDROID.md](kernel/MIHOMO_ANDROID.md) §5.6。
- **2026-10-30**：6.6.143 #8 实机启动；IPv6 NAT/addrtype、ThinLTO、
  lz4kd+ExtM、mihomo TUN、TFO 持久化、tcp-brutal 验证通过。见
  [TEST_REPORT.md](kernel/TEST_REPORT.md) §18/§19。
- **更早的证据**：按日期保留在 [TEST_REPORT.md](kernel/TEST_REPORT.md)，
  不在本文件重复。

## 3. 已知限制

完整清单和逐项原因见 [OPEN_ISSUES.md](kernel/OPEN_ISSUES.md)。

- stock-only 的 hybrid UFS、SCSI fastdiscard、EROFS 多桶 iostat、UFS 官方
  37 文件 core 未复刻；F2FS/EROFS iostat 是行为级实现，不是逐字 ABI。
- 网络覆盖：TUN 是唯一覆盖本机 IPv4/IPv6 TCP/UDP/ICMP 的完整模式；
  REDIRECT/TPROXY 有 UDP/转发/IPv6 缺口。
- MPTCP 开启会导致启动失败，保持关闭。
- 配置必须与原厂 ABI 对齐：`CONFIG_RSEQ`/`SCHED_MM_CID`、`CONFIG_CGROUP_DEVICE`、
  `CONFIG_CGROUP_HUGETLB` 不可开启；新增 `task_struct` 字段或 cgroup 控制器前
  先跑 `python3 dash/scripts/check-abi.py <vmlinux>`（详见
  [OPEN_ISSUES.md](kernel/OPEN_ISSUES.md) §2.10）。
- 没有 stock vs 自编的 A/B 性能/功耗、suspend/resume、fsck/power-loss 数据，
  不能声明性能收益。
- 厂商模块兼容跳过了签名/CRC/vermagic，仅适用于自有已解锁设备。

## 4. 如何刷新

| 数据 | 来源 |
|---|---|
| 内核版本、AOSP commit、配置哈希 | `dash/out/artifacts/BUILD_INFO` |
| Image / boot / brutal.ko 哈希 | `dash/out/artifacts/SHA256SUMS`（历史 System.map 副本缺失，目标哈希仍在清单） |
| 模块版本 | AsteriskMETA 上游 release（自带 mihomo core；本仓库不再维护模块） |
| 实机证据 | `docs/kernel/TEST_REPORT.md` |
| 缺口状态 | `docs/kernel/OPEN_ISSUES.md` |

更新规则：只改本文件的状态行；不要同步复制到根 README、`docs/README.md`、
`docs/kernel/README.md` 或 `docs/project/NAVIGATION.md`。
