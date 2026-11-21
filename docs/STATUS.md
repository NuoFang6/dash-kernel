# 当前状态

> 本文件是“当前构建/运行状态”的**唯一事实源**。其他 README、导航和功能文档
> 只链接到这里，不再复制版本号、哈希、模块数和验证结论。
>
> 最后核对：2026-11-21。刷新方法见文末。

## 1. 版本与产物

| 项 | 值 |
|---|---|
| 设备 | `dash` / REDMI Turbo 5 Max / MT6991，4K 页 |
| 设备 stock | `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k` |
| 当前内核 | `6.6.143-4k #2`（NoLTO 调试构建，2026-11-21 22:41，含 NTSync 2026 上游修复）；`uname` 被 SUSFS 伪装为 stock `6.6.118`，以 `/dev/kmsg` 启动行和 `/proc/config.gz` 为准 |
| AOSP 基线 | `android15-6.6-2026-10_r4` / `e6c23f621ca6e839abdeca58957bbc529536cff1`（r2→r4 更新） |
| 工具链 | clang r614150（23.0.1）/ LLD 23.0.1；当前实机为 NoLTO 调试构建（LTO_NONE）；生产配置为 LTO Full + MLGO regalloc advisor + ACK 预制 AutoFDO profile（`kernel.afdo`，SHA256 已钉死），日常验证统一 NoLTO；MLGO/AutoFDO 仅完成 NoLTO 全量构建级验证，Full LTO 整链构建未完成，未做 A/B |
| 发布 | GitHub Actions `kernel-build`（默认 Full LTO，手动 dispatch，timeout 360min）→ Release `dash-6.6.143-prod`：Image/Image.lz4/SHA256SUMS + AnyKernel3 + `dash_art_tune` KSU 模块 |
| 运行槽位 | `boot_a`（`ro.boot.slot_suffix=_a`，2026-11-21） |
| `boot_a` SHA256 | `3d0d4245c6b41480c9c396acfbcda13409890fb943402903f965d827f7a50dba`（`#2`；刷前备份 `1b5af31a…` 与更早 `0dc871a5…` 均在 `dash/out/device-backup/`） |
| `init_boot_a/b` | `3d2062ae64992885cb4cfba19bac2699d1e07d7b7df91a8f0a770a493622b70a`（OS4.0.3.0 官方，两槽相同） |
| 安全 | SELinux `Enforcing`；BakaSU 内建（`CONFIG_KSU=y`）+ SUSFS v2.4.0（10 项特性，f98f082 即 v2.4.0，此前文档误标 v2.3.0） |
| 厂商模块 | 638 个 stock 清单 `hard_missing=0 weak_missing=0`；2026-11-21 `#2` 实机加载 584 个（KSU/NoMount 已内建，与历史 586 个 LKM 口径等价），无 `Unknown symbol`/CRC/vermagic/invalid format 错误；KCFI 13/13 |
| KSU 模块 | 无自建模块（`mihomo_alpha` 已移除）；代理客户端为 AsteriskMETA + 增强模块 |
| DroidSpaces | 内核支持 + 用户态 v7.2.0；`droidspaces check` 全绿；Alpine NAT 容器冒烟通过；`CFS_BANDWIDTH`/`CGROUP_PIDS` 关闭，`--cpus`/`--pids-limit` 不可用 |
| PID | `pid_max` 硬钳 32768（`PID_MAX_LIMIT`） |
| 内存扩展 | stock vendor zram + ExtM；lz4kd 经 crypto API 选中，不替换 zram 模块 |
| 网络代理 | AsteriskMETA（mihomo core）：TUN/GSO、auto-route/auto-redirect、addrtype、IPv6 NAT、BPF2SOCKS 能力齐备；MPTCP 关闭 |
| TCP Brutal | 外部 `tcp-brutal` v2.0.1，`make brutal` 生成 `brutal.ko` |

完整交付哈希在 `dash/out/artifacts/SHA256SUMS`，构建输入在
`dash/out/artifacts/BUILD_INFO`；当前 #8 的 Image/Image.lz4/boot/config/brutal.ko
均按清单复核，历史 System.map 本地副本已缺失（清单保留目标哈希）。本轮验证
产物隔离在 `dash/out/features-final/`，未作为当前实机产物发布。

## 2. 最近验证

- **2026-11-21（构建级，未刷机）**：FEATURES_SURVEY 落地批次完成；固定 r4
  干净树重放 28 补丁/140 文件 + SUSFS override，零 warning/error；NoLTO
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
