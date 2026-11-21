# 当前状态

> 本文件是“当前构建/运行状态”的**唯一事实源**。其他 README、导航和功能文档
> 只链接到这里，不再复制版本号、哈希、模块数和验证结论。
>
> 最后核对：2026-11-22。刷新方法见文末。

## 1. 版本与产物

| 项 | 值 |
|---|---|
| 设备 | `dash` / REDMI Turbo 5 Max / MT6991，4K 页 |
| 设备 stock | `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k` |
| 当前内核 | `6.6.143-4k #1`（Full LTO 生产构建，2026-11-21 16:44 UTC，CI run 44923883114）；`uname` 被 SUSFS 伪装为 stock `6.6.118`，以 `/dev/kmsg` 启动行和 `/proc/config.gz` 为准 |
| AOSP 基线 | `android15-6.6-2026-10_r4` / `e6c23f621ca6e839abdeca58957bbc529536cff1`（r2→r4 更新） |
| 工具链 | clang r614150（23.0.1）/ LLD 23.0.1；当前实机为 Full LTO 生产构建（`LTO_CLANG_FULL` + MLGO regalloc advisor + ACK 预制 AutoFDO profile `kernel.afdo`，SHA256 已钉死）；日常验证仍统一 NoLTO，未做 A/B |
| 发布 | GitHub Actions `kernel-build`（默认 Full LTO，手动 dispatch，timeout 360min）→ Release `dash-6.6.143-prod`（2026-11-22）：Image 47,684,096 B / Image.lz4 22,808,794 B/SHA256SUMS + AnyKernel3 + `dash_art_tune` KSU 模块 |
| 运行槽位 | `boot_a`（`ro.boot.slot_suffix=_a`，2026-11-22） |
| `boot_a` SHA256 | `d0cdd6adb2dbed3569b04a4fc25429eaecc7eb75488cf5e3fe7b83c8d79b6be2`（生产 `#1`；刷前 NoLTO `#2` 备份 `3d0d4245…` 在 `dash/out/device-backup/20261122-004847-pre-prod-slot_a/`，更早备份同目录） |
| `init_boot_a` / `b` | a: `ded406b1cb63252f9bfbcaa74fa86817f7848b9d6a6e74d8477c7d551e001ebd`（OS4.0.4.0 官方，实机在用；与 OTA 包内 `init_boot.img` 完全一致）；b: `3d2062ae64992885cb4cfba19bac2699d1e07d7b7df91a8f0a770a493622b70a`（OS4.0.3.0，未随 OTA 更新） |
| `boot_b` SHA256 | `0dc871a520c39aa6cf57a177d3a78dd833b79a3bcfa14a5cca01985dacedc06e`（历史自编 `#8`，非 stock；OTA 的 stock boot 为 `f8f0de69…f2b3c`） |
| 安全 | SELinux `Enforcing`；BakaSU 内建（`CONFIG_KSU=y`）+ SUSFS v2.4.0（10 项特性，f98f082 即 v2.4.0，此前文档误标 v2.3.0） |
| 厂商模块 | 638 个 stock 清单 `hard_missing=0 weak_missing=0`；2026-11-22 生产 `#1` 加载 584 个（KSU/NoMount 已内建，与历史 586 个 LKM 口径等价），无 `Unknown symbol`/CRC/vermagic/invalid format 错误；KCFI 13/13 |
| KSU 模块 | 无自建模块（`mihomo_alpha` 已移除）；代理客户端为 AsteriskMETA + 增强模块 |
| DroidSpaces | 内核支持 + 用户态 v7.2.0；`droidspaces check` 全绿；Alpine NAT 容器冒烟通过；`CFS_BANDWIDTH`/`CGROUP_PIDS` 关闭，`--cpus`/`--pids-limit` 不可用 |
| PID | `pid_max` 硬钳 32768（`PID_MAX_LIMIT`） |
| 内存扩展 | stock vendor zram + ExtM；lz4kd 经 crypto API 选中，不替换 zram 模块 |
| 网络代理 | AsteriskMETA（mihomo core）：TUN/GSO、auto-route/auto-redirect、addrtype、IPv6 NAT、BPF2SOCKS 能力齐备；MPTCP 关闭 |
| TCP Brutal | 外部 `tcp-brutal` v2.0.1，`make brutal` 生成 `brutal.ko` |

完整交付哈希在 `dash/out/artifacts/SHA256SUMS`，构建输入在
`dash/out/artifacts/BUILD_INFO`；本地 artifacts 仍是历史 #8 交付批次，
生产 Full LTO 产物以 Release `dash-6.6.143-prod` 的 SHA256SUMS 为准。历史
System.map 本地副本已缺失（清单保留目标哈希）。本轮验证产物隔离在
`dash/out/features-final/`，未作为当前实机产物发布。

## 2. 最近验证

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
  AK3/KSU 模块。见 [TEST_REPORT.md](kernel/TEST_REPORT.md) §28。
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
