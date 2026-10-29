# dash 交接包说明（历史快照）

本页说明 `handoff/` 下的交接包，避免把它误当成当前源码或当前交付。

## 1. 资产

| 项 | 值 |
|---|---|
| 压缩包 | [`handoff/dash-gap-handoff-20261029.tar.zst`](../../handoff/dash-gap-handoff-20261029.tar.zst) |
| SHA256 | `3fdc8b41d1cb442ae8763c7ac2b956e5afe2511a7bd9f1a8926fba17af4521b7` |
| 大小 | 107,383,982 B（103 MiB） |
| 解包目录 | [`handoff/dash-gap-handoff/`](../../handoff/dash-gap-handoff)（约 284 MiB） |
| MANIFEST | `MANIFEST.sha256`，744 个文件条目 |
| tar 条目 | 766（含目录） |
| 打包时间 | 2026-10-29 22:07 |

包内主要内容：

- `boot/`：stock `boot_b`、`init_boot_b`、`vendor_boot_b`、`dtbo_b`、`vbmeta_b`；
- `device/`：stock config、kallsyms、getprop、lsmod、module manifest、
  hook 依赖、stock/our exports；
- `modules/`：638 个 stock 模块；
- `source/`：UFS 37 文件、memfd-ashmem-shim；
- `project/dash/`：交接时的补丁、脚本、README、旧构建产物；
- `docs/`：交接时的 NAVIGATION/GAP_RESEARCH/DEVICE_MODULES；
- `TASK_BRIEF.md`：交接需求书。

## 2. 它是什么，不是什么

**是**：2026-10-29 交给另一模型时的一次性输入快照，用于追溯当时的设备事实、
原厂资产和需求。

**不是**：

- 不是当前源码树。包内 `project/dash/versions.env` 仍钉在 6.6.144 的
  `aa8f225d...`；最终实现已切到 AOSP `android15-6.6-2026-01_r1`
  （6.6.118，`f9c84f40...`）。
- 不是最终交付。包内没有最终的 6.6.118 补丁、9 个 vendor hooks、
  `TEST_REPORT.md`、`BOOT_PACKAGING.md`、`OPEN_ISSUES.md` 和 `DEV_NOTES.md`。
- 不是当前设备状态。当前设备运行自编 `6.6.118-4k #29`，`boot_b` SHA256
  `a28344f9...7cac`；包内 `boot_b` 是 stock `b9991f92...`。
- 不是可直接照做的恢复指令。恢复必须使用 `dash/out/device-backup/` 的完整
  64MB `boot_b`/`vbmeta_b` 备份；不要碰 `lk`、`super` 或用户数据。

## 3. 维护规则

- **不要修改已打包目录**：`handoff/dash-gap-handoff/` 是归档快照，改动会使
  `MANIFEST.sha256` 和 tar 哈希失去意义。需要新包时另建文件名/目录。
- 当前交付文档在 [`docs/kernel/`](../kernel/)；当前实现状态以
  [TEST_REPORT](../kernel/TEST_REPORT.md)、[OPEN_ISSUES](../kernel/OPEN_ISSUES.md)
  和 `dash/out/artifacts/BUILD_INFO` 为准。
- 任务书原文已移到 [TASK_BRIEF.md](TASK_BRIEF.md)，并加了“历史输入”提示；
  包内 `TASK_BRIEF.md` 仍保持打包时的原文。
- 如果要把“当前完成态”再交给别人，应重新生成一个新的交接包，并在包内放入
  当前 `dash/patches/`、`dash/scripts/`、`docs/`、`out/artifacts/SHA256SUMS`
  和设备备份说明；不要复用这个旧包。
