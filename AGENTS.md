# AGENTS.md — mikernel 操作手册

本文件是 agent/协作者进入仓库的第一入口。目标：**先读 1–2 份文档就开始工作；每类事实只改一个地方。**

最后更新：2026-11-21

## 1. 任务 → 最小阅读集

| 要做的事 | 只读这些 | 需要时再查 |
|---|---|---|
| 了解当前版本、产物、实机状态 | [docs/STATUS.md](docs/STATUS.md) | `dash/out/artifacts/BUILD_INFO`、`SHA256SUMS` |
| 构建、同步、打补丁、打包 | [docs/kernel/README.md](docs/kernel/README.md) | [BOOT_PACKAGING.md](docs/kernel/BOOT_PACKAGING.md) |
| 刷机、AVB、boot 封装 | [docs/kernel/BOOT_PACKAGING.md](docs/kernel/BOOT_PACKAGING.md) | [docs/STATUS.md](docs/STATUS.md) |
| 缺口、风险、下一步 | [docs/kernel/OPEN_ISSUES.md](docs/kernel/OPEN_ISSUES.md) | `STOCK_PARITY_AUDIT.md`、`UFS_HYBRID_EVIDENCE.md`、`GAP_RESEARCH.md` |
| 改实现、看与 stock 的差异 | [docs/kernel/DESIGN.md](docs/kernel/DESIGN.md) | `TEST_REPORT.md` 对应 § |
| mihomo / 代理内核能力 | [docs/kernel/MIHOMO_ANDROID.md](docs/kernel/MIHOMO_ANDROID.md) | 客户端为 AsteriskMETA（KSU 模块已移除） |
| zram / lz4kd / ExtM | [docs/kernel/ZRAM_EXTM.md](docs/kernel/ZRAM_EXTM.md) | `TEST_REPORT.md` §14 |
| node_cache 源码评估 | [docs/kernel/NODE_CACHE_SOURCE.md](docs/kernel/NODE_CACHE_SOURCE.md) | `DEVICE_MODULES.md` |
| 源码树、子模块 pin、设备资产 | [docs/project/NAVIGATION.md](docs/project/NAVIGATION.md) | `dash/versions.env`、`git submodule status` |
| 查历史怎么测的 | [docs/kernel/TEST_REPORT.md](docs/kernel/TEST_REPORT.md)（按 § 或关键词） | `handoff/logs-*` |
| 历史交接、旧结论 | `handoff/`（只读） | 不作为当前状态 |

## 2. 文档所有权：每类信息只有一个落点

| 信息 | 唯一落点 | 不要再写进 |
|---|---|---|
| 当前版本、产物哈希、模块数、实机验证结论 | `docs/STATUS.md` | 根 README、docs/README、kernel/README、NAVIGATION |
| 新实测证据、命令、日志摘要、失败复盘 | `docs/kernel/TEST_REPORT.md`（追加带日期的 §） | STATUS（只留一行结论） |
| 缺口、风险、未覆盖项、性能排序 | `docs/kernel/OPEN_ISSUES.md` | 其他文档 |
| 实现方式、hook、与 stock 的差异 | `docs/kernel/DESIGN.md` | STATUS |
| mihomo / TUN / 内核网络能力 | `docs/kernel/MIHOMO_ANDROID.md` | OPEN_ISSUES 只留风险 |
| zram / ExtM / lz4kd | `docs/kernel/ZRAM_EXTM.md` | 其他文档 |
| 构建命令、目录、版本锁定 | `docs/kernel/README.md` + `dash/versions.env` | 状态类文档 |
| boot / AVB 硬规则 | `docs/kernel/BOOT_PACKAGING.md` | 其他文档 |
| 资源、pin、源码树位置 | `docs/project/NAVIGATION.md` | 状态类文档 |

## 3. 一次任务的最小文档改动

1. 改**唯一权威文档**（见上表）。
2. 有新的真机/构建证据 → 追加 `TEST_REPORT.md` 一个新 §。
3. 当前状态发生变化 → 只改 `STATUS.md` 对应行，并更新“最后核对”日期。
4. 只有源文档变了才重新生成笔记：
   ```bash
   make -C dash notes && make -C dash notes-check
   ```
5. `docs/kernel/DEV_NOTES.md` 是生成物，永不手工修改；`handoff/dash-gap-handoff/` 是归档，永不修改。

不要：把同一条状态复制到多个 README；为一次小改动同时改 5–6 份文档；把 `dash/src/` 当长期修改位置。

## 4. 硬安全规则

- 不写 `lk`、`super`、用户数据；刷写前完整备份；每次刷入重启后等机主确认开机。详见 `BOOT_PACKAGING.md`。
- 不刷紧凑 boot、不清 AVB footer、不改 vbmeta flags。
- 厂商 `.ko` 兼容会跳过签名/CRC/vermagic/namespace 检查，只用于自有已解锁设备。
- 不为取证关闭 SELinux。
- MPTCP 保持关闭：mihomo 配置必须 `inbound-mptcp: false`。
- mihomo 模块只加热点转发所需的 FORWARD 放行；TUN/NAT/路由由配置决定。
- 不自行运行 Full LTO：日常构建与验证一律 `FAST=1`（NoLTO）。`LTO_CLANG_FULL`
  全量构建在 15 GiB 主机上链接极慢且大量 swap；只有机主针对本次构建明确说
  “授权跑 Full LTO”才可执行。“产出生产级内核/最终产物”不等于授权。

## 5. 验证与表述

- 文档：`make -C dash notes-check`
- 产物：`dash/out/artifacts/BUILD_INFO`、`SHA256SUMS`、`bash dash/scripts/finalize.sh`
- 结论必须区分：**真机实测 / 静态匹配 / 未验证**。不要用 README 或配置声明代替实测。
- 失败和限制要保留，不要把“行为级实现”写成“与 stock 等价”。

## 6. 权威顺序

> 旧的会话记忆、`handoff/` 和 `docs/project/` 调研可能引用已合并或过时的文档
> （例如 `UNRESOLVED_GAPS.md` 已并入 `OPEN_ISSUES.md`）；以本文件、
> `docs/STATUS.md` 和 `docs/kernel/OPEN_ISSUES.md` 为准。

冲突时按此顺序判断：

1. `docs/STATUS.md` + `dash/out/artifacts/BUILD_INFO` + 真机实测
2. `docs/kernel/BOOT_PACKAGING.md`（boot/AVB 硬规则）
3. `docs/kernel/OPEN_ISSUES.md`（缺口/风险）
4. `docs/kernel/DESIGN.md`（实现路径）
5. `docs/project/`（上下文，可能过时）
6. `handoff/`（历史输入）
7. `third_party/`（上游参考）

文档总索引与维护规则见 [docs/README.md](docs/README.md)。
