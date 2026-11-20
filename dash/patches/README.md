# dash kernel patches

## 当前：6.6.143（AOSP `android15-6.6-2026-10_r2`）

`series` 只包含一个补丁：

```text
0000-6.6.143-dash-integration.patch
```

这是**有意 squash** 的集成补丁，也是本仓库唯一保存的自有补丁：BakaSU 接入、
F2FS/EROFS、vendor-hooks 的改动在 VFS/security/core 文件里交错，按 6.6.118
的方式拆分会得到无法独立应用的 hunk，因此当前以整树 diff 保证可复现。

其余上游内容不存副本：

- **KSU 源码**：`BakaSU` 子模块，apply 时以符号链接接入（`drivers/kernelsu`）；
- **SUSFS 内核文件**：`third_party/susfs4ksu` 子模块（`kernel_patches/`），
  apply 时直接安装。曾经 vendored 在 `patches/susfs/` 的副本与 pinned 上游
  逐字节一致，已删除；bump 子模块 pin 即可带上游更新，无需重生成补丁；
- **参考用补丁/文档**：全部在 `third_party/` 子模块里（susfs4ksu、
  dash-droidspaces `patches/os4-vendor-hooks`、hyperos-lz4kd 等）；
- 旧 6.6.118 拆分系列（0000–0009 + vendor-hooks）基于 AOSP 6.6.118，不能
  应用到 6.6.143，2026-11-21 起从仓库删除，需要时看 git 历史
  （commit `1e5c8f4` 之前）。

应用流程（`scripts/apply-patches.sh`）：

1. `git reset --hard $AOSP_COMMIT` + `git clean -fdx`（bf768be0，6.6.143）；
2. 校验 BakaSU / susfs4ksu 子模块在 `versions.env` pin 的 commit；
3. 建立 `drivers/kernelsu -> BakaSU/kernel` 符号链接；
4. `git apply --index 0000-6.6.143-dash-integration.patch`；
5. 安装 `$SUSFS_DIR/kernel_patches/{fs/susfs.c,include/linux/susfs.h,
   include/linux/susfs_def.h}`。

验证（2026-10-30，离线）：在一个干净的 bf768 worktree 上应用本补丁并安装
SUSFS 文件后，补丁涉及的 87 个文件（84 个补丁文件 + 3 个 SUSFS 文件）与
当前构建工作树逐字节 sha256 一致，`git apply` 无 warning。

## 维护约定

- 修改 `src/aosp/common` 后，重新生成整树补丁，而不是手改 `0000`；
- 生成时排除 `drivers/kernelsu`（符号链接）和 `fs/susfs*.c/h`（由 susfs
  子模块安装）；
- 在 clean worktree 上做一次 `git apply --index` + 文件 hash 对比，再更新
  `docs/kernel/TEST_REPORT.md`。

## 上游更新

子模块 pin 与远端分支头的对比由 `scripts/upstream-check.sh` 完成（本地可跑，
CI 每周跑一次，漂移时报 issue）。手动/自动 bump 走
`.github/workflows/bump-submodule.yml`：更新 pin → 重放补丁门禁 → 自动开 PR。
BakaSU / susfs4ksu 的 bump 不需要重生成 `0000`（kernelsu 是符号链接、SUSFS
文件是安装的）；AOSP tag 升级和 F2FS/EROFS/vendor-hooks 的适配属于人工决策，
不在自动范围。
