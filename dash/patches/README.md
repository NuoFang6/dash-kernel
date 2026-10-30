# dash kernel patches

## 当前：6.6.143（AOSP `android15-6.6-2026-10_r2`）

`series` 只包含一个补丁：

```text
0000-6.6.143-dash-integration.patch
```

这是**有意 squash** 的集成补丁。BakaSU、SUSFS、F2FS/EROFS、vendor-hooks
的改动在 VFS/security/core 文件里交错，按 6.6.118 的方式拆分会得到无法独立
应用的 hunk，因此当前以整树 diff 保证可复现。

应用流程（`scripts/apply-patches.sh`）：

1. `git reset --hard $AOSP_COMMIT` + `git clean -fdx`（bf768be0，6.6.143）；
2. 建立 `drivers/kernelsu -> BakaSU/kernel` 符号链接；
3. `git apply --index 0000-6.6.143-dash-integration.patch`；
4. 安装 `patches/susfs/{susfs.c,susfs.h,susfs_def.h}`。

验证（2026-10-30，离线）：在一个干净的 bf768 worktree 上应用本补丁并安装
SUSFS 文件后，补丁涉及的 87 个文件（84 个补丁文件 + 3 个 SUSFS 文件）与
当前构建工作树逐字节 sha256 一致，`git apply` 无 warning。

## legacy-6.6.118/

保留 6.6.118 时期按功能拆分的 0000–0009 和 vendor-hooks 补丁，仅作历史参考，
**不再被 `series` 引用**。这些补丁基于 AOSP 6.6.118，直接应用到 6.6.143 会
冲突或回退新代码。

## 维护约定

- 修改 `src/aosp/common` 后，重新生成整树补丁，而不是手改 `0000`；
- 生成时排除 `drivers/kernelsu`（符号链接）和 `fs/susfs*.c/h`（由 susfs
  目录安装）；
- 在 clean worktree 上做一次 `git apply --index` + 文件 hash 对比，再更新
  `docs/kernel/TEST_REPORT.md`。
