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
| 当前内核 | `6.6.143-4k #8` |
| AOSP 基线 | `android15-6.6-2026-10_r4` / `e6c23f621ca6e839abdeca58957bbc529536cff1`（r2→r4 更新） |
| 工具链 | clang r614150（23.0.1）/ LLD 23.0.1；ThinLTO 已开启，AutoFDO 未启用 |
| 运行槽位 | `boot_b` |
| `boot_b` SHA256 | `0dc871a520c39aa6cf57a177d3a78dd833b79a3bcfa14a5cca01985dacedc06e` |
| `init_boot_a/b` | `3d2062ae64992885cb4cfba19bac2699d1e07d7b7df91a8f0a770a493622b70a`（OS4.0.3.0 官方，两槽相同） |
| 安全 | SELinux `Enforcing`；BakaSU 内建（`CONFIG_KSU=y`）+ SUSFS v2.4.0（9 项特性，f98f082 即 v2.4.0，此前文档误标 v2.3.0） |
| 厂商模块 | 638 个 stock 清单 `hard_missing=0 weak_missing=0`；实机加载 586 个；KCFI 13/13 |
| KSU 模块 | 无自建模块（`mihomo_alpha` 已移除）；代理客户端为 AsteriskMETA + 增强模块 |
| PID | `pid_max` 硬钳 32768（`PID_MAX_LIMIT`） |
| 内存扩展 | stock vendor zram + ExtM；lz4kd 经 crypto API 选中，不替换 zram 模块 |
| 网络代理 | AsteriskMETA（mihomo core）：TUN/GSO、auto-route/auto-redirect、addrtype、IPv6 NAT、BPF2SOCKS 能力齐备；MPTCP 关闭 |
| TCP Brutal | 外部 `tcp-brutal` v2.0.1，`make brutal` 生成 `brutal.ko` |

完整产物哈希在 `dash/out/artifacts/SHA256SUMS`，构建输入在
`dash/out/artifacts/BUILD_INFO`；这两处与真机实测冲突时以它们为准。

## 2. 最近验证

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
| Image / boot / brutal.ko 哈希 | `dash/out/artifacts/SHA256SUMS` |
| 模块版本 | AsteriskMETA 上游 release（自带 mihomo core；本仓库不再维护模块） |
| 实机证据 | `docs/kernel/TEST_REPORT.md` |
| 缺口状态 | `docs/kernel/OPEN_ISSUES.md` |

更新规则：只改本文件的状态行；不要同步复制到根 README、`docs/README.md`、
`docs/kernel/README.md` 或 `docs/project/NAVIGATION.md`。
