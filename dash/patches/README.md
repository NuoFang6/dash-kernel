# dash kernel patches

## 当前：6.6.144（AOSP `android15-6.6` 分支 tip `a5c942b8c`）

补丁按**功能特性**分目录存放，`series` 是唯一应用顺序（每行一个特性目录，
目录内补丁按文件名排序逐个应用）：

```text
010-bakasu-susfs/       BakaSU 内建 + SUSFS inline hook（VFS/core 交错文件不可
                        再拆；SELinux hide 由 BakaSU 运行时 auto hook 处理，
                        不再改 security/selinux/hooks.c/selinuxfs.c）
020-vendor-ko-compat/   厂商 .ko 加载兼容（签名/vermagic/CRC/namespace）
030-vendor-hooks-os4/   dash OS4 android_vh_* vendor hooks
040-memfd-ashmem-shim/  MEMFD_ASHMEM shim 配置接入
050-lz4kd-zram/         lz4kd crypto 模块、LZ4 trace 事件、zram 后端
060-f2fs-xiaomi/        Xiaomi F2FS 增强（iostat/VIP/hybrid/lock priority）
070-erofs-xiaomi/       Xiaomi EROFS iostat sysfs
080-dash-misc/          dash 维护性修复（pid_max clamp、OpenSSL 4 host-tool）
090-droidspaces/        DroidSpaces 容器支持：SYSVIPC 字段移入 ANDROID_KABI
                        填充槽（官方 below-6.12 kABI 补丁的 6.6.143 适配；
                        本树槽 1-2 已被 AOSP 使用，sysvsem→6、sysvshm→7+8）
100-sched-eevdf/        EEVDF/PREEMPT_SHORT、EAS/uclamp/misfit、RT/timer slack
110-net-bbrv3/          KABI-safe BBRv3 + TCP retransmit 生命周期修复
115-hide-appsockets/     app UID 隐藏 adbd/JDWP unix socket
120-arm64-perf/          arm64 copy/memcmp/clear/int_sqrt/per-cpu/-mtune
130-f2fs-perf/          F2FS GC、拥塞等待与 fsync 调优
131-unicode-bypass/      Unicode casefold 空分解边界修复
140-power-mm/            alarmtimer/s2idle/MGLRU/swap/cpufreq/OPP 修复
150-drivers-ntsync/      NTSync 驱动 backport
160-block-adios/         ADIOS blk-mq 调度器（内建，内核默认）
170-security-bbg/       Baseband Guard LSM
180-stable-backports/   EVONIX 已收录的 stable 回移：UDP tunnel 分段 UAF、
                        IPv6 解析加固、DAMON、writeback/ext4
susfs-overrides/        SUSFS 子模块文件安装后的 dash 本地覆盖（不进 series）
```

拆分是**文件级**的：每个文件只属于一个补丁（归属唯一记录在
`scripts/split-patches.py` 的 `SERIES` 映射表），补丁之间互不触碰同一文件，
因此应用顺序稳定、不会出现无法应用的 hunk。文件内的多特性交错（BakaSU 与
SUSFS 的 hook 调用点）整体归入 `010-bakasu-susfs`。

其余上游内容不存副本：

- **KSU 源码**：`BakaSU` 子模块，apply 时以符号链接接入（`drivers/kernelsu`）；
- **SUSFS 内核文件**：`third_party/susfs4ksu` 子模块（`kernel_patches/`），
  apply 时直接安装。bump 子模块 pin 即可带上游更新，无需重生成补丁；
- **NoMount**：`third_party/nomount` 子模块（pin `$NOMOUNT_TAG`），apply 时
  符号链接到 `fs/nomount` 并挂入 `fs/Makefile`/`fs/Kconfig`（镜像上游
  `kernel/setup.sh`），`CONFIG_NOMOUNT=y` 内建；
- **参考用补丁/文档**：全部在 `third_party/` 子模块里（susfs4ksu、
  dash-droidspaces `patches/os4-vendor-hooks`、hyperos-lz4kd 等）；
- 旧 6.6.118 拆分系列（0000–0009 + vendor-hooks）和 6.6.143 整树 squash
  `0000-6.6.143-dash-integration.patch` 已从仓库删除，需要时看 git 历史。

## 应用与再生成

应用（`scripts/apply-patches.sh`，编译时逐目录逐补丁汇总）：

1. `git reset --hard $AOSP_COMMIT` + `git clean -fdx`（`a5c942b8c`，6.6.144）；
2. 校验 BakaSU / susfs4ksu / nomount 子模块在 `versions.env` pin 的 commit；
3. 建立 `drivers/kernelsu -> BakaSU/kernel` 符号链接；
4. 按 `series` 逐目录逐补丁 `git apply --index`；
5. 安装 `$SUSFS_DIR/kernel_patches/` 的 3 个 SUSFS 文件；
6. 挂接 NoMount（`fs/nomount` 符号链接 + `fs/Makefile`/`fs/Kconfig`）。

再生成（改了 `src/aosp/common` 之后，永不手改补丁文件）：

```bash
cd dash && make gen-patches    # src 树 diff -> squash -> 按映射表拆分 -> 校验
```

`scripts/split-patches.py check`（`gen-patches.sh` 末步自动执行）校验：
series 与映射表一致、每个补丁触碰的文件与映射表一致、与 squash 重新拼装
逐字节一致。树 diff 中出现映射表之外的文件会直接报错，不会静默丢内容；
脚本侧接线（NoMount 的 `fs/Kconfig`、susfs/kernelsu/nomount 符号链接）在
排除清单里。

验证（2026-11-24）：在 `android15-6.6` tip `a5c942b8c`（Merge 6.6.144-r01）
干净树上完整应用 35 个补丁（156 个唯一归属文件）+ SUSFS 安装后 override，
零 warning/error；`split-patches.py check` 确认补丁映射与 source-tree squash
逐字节一致。

## 维护约定

- 修改 `src/aosp/common` 后运行 `make gen-patches`，在 clean worktree 或
  CI 的 `make source patches` 重放通过后再提交；
- 新增特性 = 在 `split-patches.py` 的 `SERIES` 加目录与映射，然后
  `make gen-patches`；
- 文件内出现新的跨特性交错时，把该文件归入承载主要改动或先后依赖的
  特性目录，并在映射表注释说明，不要做 hunk 级拆分。

## 上游更新

子模块 pin 与远端分支头的对比由 `scripts/upstream-check.sh` 完成（本地可跑，
CI 每周跑一次，漂移时报 issue）。手动/自动 bump 走
`.github/workflows/bump-submodule.yml`：更新 pin → 重放补丁门禁 → 自动开 PR。
BakaSU / susfs4ksu / nomount 的 bump 不需要重生成补丁（kernelsu/nomount 是
符号链接、SUSFS 文件是安装的）；AOSP tag 升级和各特性的适配属于人工决策，
不在自动范围。
