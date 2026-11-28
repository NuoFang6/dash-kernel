# mikernel 文档中心

本目录是项目级 Markdown 的唯一入口。先看结论：

- 当前版本、产物哈希、实机状态：**[STATUS.md](STATUS.md)**（唯一事实源）
- 缺口、风险、未完成项：**[kernel/OPEN_ISSUES.md](kernel/OPEN_ISSUES.md)**（唯一台账）
- agent 操作手册：**[../AGENTS.md](../AGENTS.md)**（任务路由与文档所有权）

## 1. 权威顺序

遇到冲突时按以下顺序判断：

1. [STATUS.md](STATUS.md) + `dash/out/artifacts/BUILD_INFO` + 真机实测 =
   **当前运行事实**；证据在 [kernel/TEST_REPORT.md](kernel/TEST_REPORT.md)。
2. [kernel/BOOT_PACKAGING.md](kernel/BOOT_PACKAGING.md) = **boot/AVB 封装硬规则**。
3. [kernel/OPEN_ISSUES.md](kernel/OPEN_ISSUES.md) = **剩余缺口、风险和验证建议**。
4. [kernel/DESIGN.md](kernel/DESIGN.md) = **实现路径与 stock 差异**。
5. [project/](project/) 下的导航/调研/模块观察 = **上下文，允许有过时状态**。
6. [handoff/TASK_BRIEF.md](handoff/TASK_BRIEF.md) 与 `handoff/dash-gap-handoff/`
   = **历史交接输入**，不是当前状态。
7. `third_party/**` 与外部通用指南 = **上游/外部参考**，本机实测优先。

## 2. 文档地图

### 根与项目级

| 文档 | 用途 | 状态 |
|---|---|---|
| [STATUS.md](STATUS.md) | 当前版本、产物哈希、模块数、实机结论、已知限制 | **当前状态唯一事实源** |
| [../AGENTS.md](../AGENTS.md) | agent 入口、任务路由、文档所有权、更新规则 | 当前 |
| [README.md](README.md) | 文档索引、权威顺序、维护规则 | 当前 |

### kernel/：dash 内核交付

| 文档 | 用途 | 状态 |
|---|---|---|
| [README.md](kernel/README.md) | 构建/更新流程、目录、构建范围 | 当前；不记录状态 |
| [DESIGN.md](kernel/DESIGN.md) | 补丁、hooks、F2FS/EROFS 实现与差异 | 当前 |
| [TEST_REPORT.md](kernel/TEST_REPORT.md) | 静态检查、真机证据、AVB 复盘；按日期追加 | **证据日志**，不是当前状态 |
| [OPEN_ISSUES.md](kernel/OPEN_ISSUES.md) | 当前缺口、风险、可执行 todo 与验证缺口（按主题分组） | **缺口唯一台账** |
| [ZRAM_EXTM.md](kernel/ZRAM_EXTM.md) | 内存扩展 ExtM 与 lz4kd：stock vendor zram、backing_dev、xswapd、回写验证 | 当前 |
| [MIHOMO_ANDROID.md](kernel/MIHOMO_ANDROID.md) | mihomo Android 运行、TUN/TProxy 内核能力、tcp-brutal、MPTCP 结论；KSU 模块已移除（客户端为 AsteriskMETA） | 内核能力部分当前；模块章节过时 |
| [NODE_CACHE_SOURCE.md](kernel/NODE_CACHE_SOURCE.md) | node_cache 源码评估、与 stock 6.6.118 二进制差异、6.6.143 适配清单 | 当前；来源是 6.12 API 重实现，不是 stock 原源码 |
| [LOG_AUDIT_20261030.md](kernel/LOG_AUDIT_20261030.md) | 系统日志审计：kernel WARN、SELinux、crash/ANR、厂商噪声与结论 | 当前 |
| [BOOT_PACKAGING.md](kernel/BOOT_PACKAGING.md) | boot 封装、AVB、恢复规则 | 当前 |
| [STOCK_PARITY_AUDIT.md](kernel/STOCK_PARITY_AUDIT.md) | 实机 vs stock 6.6.118 的 config/模块/tracepoint/功能核对 | 当前 |
| [UPSTREAM_NOTES_REVIEW.md](kernel/UPSTREAM_NOTES_REVIEW.md) | 参考仓库工作笔记核对与可借鉴/不采纳的优化 | 当前 |
| [FEATURES_SURVEY.md](kernel/FEATURES_SURVEY.md) | WildKernels/GKID 特性调查:实现可信度分级、与 dash 对照、决策记录 | 调查快照 + 决策台账 |
| [UFS_HYBRID_EVIDENCE.md](kernel/UFS_HYBRID_EVIDENCE.md) | UFS/hybrid/fastdiscard 缺口证据与安全边界 | 当前 |
| [DEV_NOTES.md](kernel/DEV_NOTES.md) | 由 `dash/scripts/collect-notes.py` 生成的聚合避坑包 | **生成物**，不要手改 |
| [UNRESOLVED_GAPS.md](kernel/UNRESOLVED_GAPS.md) | 已并入 OPEN_ISSUES | **跳转页**，不要更新 |

### project/：项目上下文

| 文档 | 用途 | 状态 |
|---|---|---|
| [NAVIGATION.md](project/NAVIGATION.md) | 子模块 pin、源码树、设备资产、任务导航 | 上下文；不记录状态 |
| [GAP_RESEARCH.md](project/GAP_RESEARCH.md) | 精确源码/私有特性/UFS/dump 检索台账 | 上下文；2026-10-30 状态已追加 |
| [DEVICE_MODULES.md](project/DEVICE_MODULES.md) | `node_cache`/`os_cpu_qi` 的 stock 行为观察 | 上下文；数值是 stock 历史值 |

### handoff/：历史交接

| 文档 | 用途 | 状态 |
|---|---|---|
| [TASK_BRIEF.md](handoff/TASK_BRIEF.md) | 2026-10-29 交接需求书原文 | **历史输入**，已加状态提示 |
| [PACKAGE.md](handoff/PACKAGE.md) | 交接包哈希、内容、旧 pin 与维护规则 | 当前说明 |

`handoff/dash-gap-handoff/` 是 2026-10-29 的解包快照（约 284 MiB），内含
`docs/NAVIGATION.md`、`docs/GAP_RESEARCH.md`、`docs/DEVICE_MODULES.md` 和
`project/dash/README.md`。这些是**归档副本**，不随本目录维护；不要修改，
否则 `MANIFEST.sha256`/tar 哈希失效。

### 未移动的 Markdown

- `AGENTS.md`：仓库根目录的 agent 入口，刻意不放进 `docs/`；
- `dash/src/aosp/common/**/README.md`：AOSP 源码树自带，已由 `dash/.gitignore`
  排除；
- `dash/toolchains/**/*.md`：clang 预编译包自带；
- `third_party/**/README.md`、`BakaSU/**`：子模块自带；
- `handoff/dash-gap-handoff/**/*.md`：历史包归档。

## 3. 维护规则

- 新增项目文档优先放到本目录对应子目录；根目录只保留 `AGENTS.md`、`README.md`
  两个稳定入口。`dash/` 不再放新的项目级 Markdown。
- **每类信息只有一个落点**（见 [AGENTS.md](../AGENTS.md) §2）：当前状态只改
  `STATUS.md`；新证据只追加 `TEST_REPORT.md`；缺口只改 `OPEN_ISSUES.md`；
  实现差异只改 `DESIGN.md`。README/NAVIGATION 只放稳定信息，不复制状态。
- 代码/构建脚本仍以 `dash/` 下的实际路径为准；文档中的 `dash/...` 代码路径
  不因为文档移动而改变。
- `DEV_NOTES.md` 是生成物：改完源文档后运行
  `make -C dash notes`，再用 `make -C dash notes-check` 校验。生成器清单在
  `dash/scripts/collect-notes.py` 的 `SOURCES`，输出固定为
  `docs/kernel/DEV_NOTES.md`。
- `UNRESOLVED_GAPS.md` 已于 2026-11-07 并入 `OPEN_ISSUES.md`；保留跳转页只为
  兼容旧链接，不要再往里写内容。
- 文档移动或合并后，请同步更新本页、生成器 `SOURCES` 和相关相对链接；旧锚点
  尽量保留。
- 顶层 git 基线为 `02bba0a`（6.6.118 #29）；当前 `main` 已固化 6.6.144
  分支跟随、补丁序列和文档。提交范围包括 `docs/`、`dash/` 的文档/补丁/脚本和
  顶层导航；`dash/out/`、`dash/src/`、`dash/toolchains/` 与 `handoff/`
  由 `.gitignore` 排除，不入库。
