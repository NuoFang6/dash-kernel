# mikernel 文档中心

本目录是 `mikernel` 项目级 Markdown 的唯一入口。原先散落在仓库根目录和
`dash/` 下的交付/调研文档已移入这里；子模块自带 README 和已打包的
`handoff/dash-gap-handoff/` 快照保持原位，不改动。

## 1. 当前状态（2026-10-30）

| 项 | 值 |
|---|---|
| 设备 | dash / REDMI Turbo 5 Max / MT6991 |
| stock | `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k` |
| 当前内核 | `6.6.143-4k #3`（AOSP `android15-6.6-2026-10_r2` / `bf768be0`，clang r614150，ThinLTO） |
| `boot_b` | `5d4e1ab14785fff3379520f711ee5b765285cf8f58145bddd1e74df15546c93c` |
| `init_boot_a/b` | `3d2062ae64992885cb4cfba19bac2699d1e07d7b7df91a8f0a770a493622b70a`（OS4.0.3.0 官方，两槽相同） |
| 模块 | 586 个（当前实机加载；638 个 stock 清单 `hard_missing=0`）；KSU 内建 |
| 静态检查 | KCFI 13/13；638 stock 模块 `hard_missing=0 weak_missing=0` |
| 安全 | SELinux `Enforcing`；SUSFS v2.3.0，9 项特性 |

2026-10-30 已补齐：

- F2FS 增强 iostat 的 stock 单开关语义（只开 `en_iostat_enable=1` 即记录）；
- `f2fs_fault_report` tracepoint，`fault_report.ko` 的 `/proc/fault_report`
  恢复；同步和 task-context 异步路径均已上报；
- F2FS lock/priority：`fs/f2fs/lock.c`、`f2fs_lock_elapsed_time`、
  `f2fs_priority_uplift/restore`、4 个 lock sysfs；`gc_lock` 全部调用点已
  接入 trace wrapper；真机验证 uplift/restore 和 lock elapsed；
- F2FS VIP：`android_vh_f2fs_is_hiprio_task/usr_task` hook + 保守 fallback（有用户地址空间
  的 RT/negative-nice 写打开，上限 8192）；真机验证 `vip_inode_count` 增删和开关清零。
- stock core tracepoint：stock 的 1860 个 `__traceiter_*` 全部存在；6.6.143
  上游额外 46 个，当前共 1906 个。51 个 stock-only hook 与 2 个 LZ4 事件已补
  （LZ4 start/end 已在实机触发）；7 个 export-only hook 已补
  MMC/DMA/lazy-resched 调用点；GKI dynamic task_struct
  （`arch_task_struct_size`、`vendor_data_pad`、1024B vendor 上限）。
- EROFS iostat 改为每 CPU 统计（`iostat_config` 输出 `percpu=1`），
  保留单 aggregate bucket；stock 的多桶/多阈值布局仍未复刻。
- `/proc/iostat_enhance` 经复核不是 dash stock ABI；io_monitor 实际节点是
  `/proc/io_monitor/iostat/iostat_enabled`。

仍未补齐的 stock-only 项：hybrid UFS、EROFS 多桶粒度（已 per-CPU）、
SCSI fastdiscard、UFS 官方 37 文件源；详见
[kernel/UFS_HYBRID_EVIDENCE.md](kernel/UFS_HYBRID_EVIDENCE.md) 和
[kernel/OPEN_ISSUES.md](kernel/OPEN_ISSUES.md)。

### 2026-10-30 偏离 stock 的已落地项

- AOSP 同步到 `android15-6.6-2026-10_r2`（6.6.143，`bf768be0`），实机启动；
- clang 升级到 r614150（23.0.1，PGO/BOLT/LTO 预编译），构建全程 clang/LLD；
- ThinLTO 已开启并实机启动：`kernel/pid.o` 为 LLVM IR bitcode，`.pid.o.cmd`
  带 `-flto=thin`；AutoFDO 未启用（需要 profile，按约定跳过）；
- `pid_max` 硬钳 32768，实测 root 写 40000/100000 均返回失败；
- lz4kd 通过 crypto `compression` 算法 + stock vendor zram 选中，保留 ExtM
  内存扩展（见 [kernel/ZRAM_EXTM.md](kernel/ZRAM_EXTM.md)）；
- 6.6.143 补丁序列已重生成：`patches/0000-6.6.143-dash-integration.patch`
  （整树 squash），旧 6.6.118 系列归档到 `patches/legacy-6.6.118/`；干净
  bf768 worktree 上 apply 后 87 个文件 hash 与当前工作树一致。

## 2. 权威顺序

遇到冲突时按以下顺序判断：

1. [kernel/TEST_REPORT.md](kernel/TEST_REPORT.md) + `dash/out/artifacts/BUILD_INFO`
   + 真机实测 = **当前运行事实**。
2. [kernel/BOOT_PACKAGING.md](kernel/BOOT_PACKAGING.md) = **boot/AVB 封装硬规则**。
3. [kernel/OPEN_ISSUES.md](kernel/OPEN_ISSUES.md) = **剩余缺口和风险**。
4. [kernel/DESIGN.md](kernel/DESIGN.md) = **实现路径与 stock 差异**。
5. [project/](project/) 下的导航/调研/模块观察 = **上下文，允许有过时状态**。
6. [handoff/TASK_BRIEF.md](handoff/TASK_BRIEF.md) 与 `handoff/dash-gap-handoff/`
   = **历史交接输入**，不是当前状态。
7. `third_party/**` 与外部通用指南 = **上游/外部参考**，本机实测优先。

## 3. 文档地图

### kernel/：dash 内核交付

| 文档 | 用途 | 状态 |
|---|---|---|
| [README.md](kernel/README.md) | 构建/更新流程、目录、当前功能 | 当前 |
| [DESIGN.md](kernel/DESIGN.md) | 补丁、hooks、F2FS/EROFS 实现与差异 | 当前 |
| [TEST_REPORT.md](kernel/TEST_REPORT.md) | 静态检查、真机证据、AVB 复盘、stock parity 修复 | 当前 |
| [OPEN_ISSUES.md](kernel/OPEN_ISSUES.md) | 未覆盖项、风险、剩余 stock 缺口 | 当前 |
| [ZRAM_EXTM.md](kernel/ZRAM_EXTM.md) | 内存扩展 ExtM 与 lz4kd：stock vendor zram、backing_dev、xswapd、回写验证 | 当前 |
| [LOG_AUDIT_20261030.md](kernel/LOG_AUDIT_20261030.md) | 系统日志审计：kernel WARN、SELinux、crash/ANR、厂商噪声与结论 | 当前 |
| [BOOT_PACKAGING.md](kernel/BOOT_PACKAGING.md) | boot 封装、AVB、恢复规则 | 当前 |
| [STOCK_PARITY_AUDIT.md](kernel/STOCK_PARITY_AUDIT.md) | 实机 vs stock 6.6.118 的 config/模块/tracepoint/功能核对 | 当前 |
| [UNRESOLVED_GAPS.md](kernel/UNRESOLVED_GAPS.md) | 未完成项按性能影响排序、原因与已知信息 | 当前 |
| [UPSTREAM_NOTES_REVIEW.md](kernel/UPSTREAM_NOTES_REVIEW.md) | 参考仓库工作笔记核对与可借鉴/不采纳的优化 | 当前 |
| [UFS_HYBRID_EVIDENCE.md](kernel/UFS_HYBRID_EVIDENCE.md) | UFS/hybrid/fastdiscard 缺口证据与安全边界 | 当前 |
| [DEV_NOTES.md](kernel/DEV_NOTES.md) | 由 `dash/scripts/collect-notes.py` 生成的聚合避坑包 | **生成物**，不要手改 |

### project/：项目上下文

| 文档 | 用途 | 状态 |
|---|---|---|
| [NAVIGATION.md](project/NAVIGATION.md) | 子模块 pin、源码树、设备资产、任务导航 | 上下文；路径已更新 |
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

- `dash/src/aosp/common/**/README.md`：AOSP 源码树自带，已由 `dash/.gitignore`
  排除；
- `dash/toolchains/**/*.md`：clang 预编译包自带；
- `third_party/**/README.md`、`BakaSU/**`：子模块自带；
- `handoff/dash-gap-handoff/**/*.md`：历史包归档。

## 4. 维护规则

- 新增项目文档优先放到本目录对应子目录；根目录和 `dash/` 不再放新的项目级
  Markdown。
- 代码/构建脚本仍以 `dash/` 下的实际路径为准；文档中的 `dash/...` 代码路径
  不因为文档移动而改变。
- `DEV_NOTES.md` 是生成物：改完源文档后运行 `make -C dash notes`，再用
  `make -C dash notes-check` 校验。生成器清单在
  `dash/scripts/collect-notes.py` 的 `SOURCES`，输出固定为
  `docs/kernel/DEV_NOTES.md`。
- 文档移动后，相对链接已按新位置重写；如再移动，请同步更新本页、生成器
  `SOURCES` 和相关链接。
- 顶层 git 基线为 `02bba0a`（6.6.118 #29）；当前 `main` 已固化 6.6.143
  同步、补丁序列和文档。提交范围包括 `docs/`、`dash/` 的文档/补丁/脚本和
  顶层导航；`dash/out/`、`dash/src/`、`dash/toolchains/` 与 `handoff/`
  由 `.gitignore` 排除，不入库。
