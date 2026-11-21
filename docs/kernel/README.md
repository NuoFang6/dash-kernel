# dash kernel

REDMI Turbo 5 Max（`dash` / 2602BRT18C / MT6991）的 GKI2.0 内核工作区。

设备 stock 为 `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`，
GKI 分支 `android15-6.6`，KMI 字符串 `android15-8`，4K 页。当前自编版本、
工具链、产物哈希和实机状态见 [docs/STATUS.md](../STATUS.md)；本文件只维护
构建/更新流程。

## 目录

```text
configs/stock.config          设备 stock 配置，构建起点
configs/abi_symbollist.raw    stock 导出白名单，保持 TRIM_UNUSED_KSYMS
configs/features.fragment     本次新增配置摘要
patches/                      按特性分目录的补丁；series 是唯一应用顺序
scripts/                      同步、打补丁、配置、构建、boot 打包和静态检查
src/aosp/common/              clean AOSP 浅克隆，可随时重置
toolchains/                   clang r614150（clang 23.0.1）
out/                          构建目录和 artifacts
```

> SUSFS 内核文件（`fs/susfs.c`、`include/linux/susfs*.h`）不存仓库副本，
> apply 时从 pinned 的 `third_party/susfs4ksu` 子模块安装。

## 快速开始

```bash
cd dash
make deps       # Arch/CachyOS 依赖检查
make toolchain  # 获取固定 clang r614150
make source     # 浅克隆/更新 AOSP 到 2026-10_r2（6.6.143）
make patches    # 重置源码、接入 BakaSU、按 series 打补丁
make config     # stock.config + 功能开关
make build      # Image / Image.lz4 / vmlinux / System.map
make config FAST=1 build  # 速度优先测试构建：关 ThinLTO；产物未经 finalize，不可刷机
make brutal     # 外部 tcp-brutal v2.0.1 模块（需要先 build）
make boot       # 从 stock boot_b 继承生成 boot.img
bash scripts/finalize.sh  # KCFI + 638 模块 + boot 校验，写 SHA256SUMS
make notes                 # 合并仓库开发笔记为 docs/kernel/DEV_NOTES.md（给 LLM 的避坑包）
```

> **6.6.143 补丁序列（2026-11-21 起按特性拆分）**：`patches/` 下是按功能
> 特性分目录的补丁系列（bakasu-susfs / vendor-ko-compat / vendor-hooks-os4
> / memfd-shim / lz4kd-zram / f2fs / erofs / dash-misc），`series` 是唯一
> 应用顺序；文件级拆分（每文件只属于一个补丁），归属表在
> `dash/scripts/split-patches.py`。旧的 6.6.118 拆分系列和 6.6.143 整树
> squash 已从仓库删除（git 历史保留）。已在干净 bf768 worktree 验证 11 个
> 补丁 apply 后与构建工作树逐字节一致，无 warning。
> `make patches` 会重置源码再重放，执行前确认没有补丁之外的未固化改动；
> 改 `src/aosp/common` 后用 `make gen-patches` 再生成，不要手改补丁文件。

产物在 `out/artifacts/`，构建日志在 `out/dash/build.log`。

## CI（GitHub Actions）

> 所有工作流**只保留手动 dispatch 触发**（push/PR/schedule 自动触发已按
> 仓库主人的要求关闭）；跑到 Actions 页手动触发。

- [`.github/workflows/ci.yml`](../../../.github/workflows/ci.yml)：轻量检查——
  `shellcheck -S warning`、补丁序列校验（浅克隆 pinned AOSP + `make patches`）。
  DEV_NOTES 的刷新/校验（`make notes`、`collect-notes.py --check`）只在本地
  做，不在 CI 里跑。
- [`.github/workflows/kernel-build.yml`](../../../.github/workflows/kernel-build.yml)：
  手动 dispatch 全量构建（工具链走 cache），Image 产物上传为 artifact。
  构建前做内存扩展（16G swapfile + 8G zram/zstd + zswap），方案经
  `storage-ram-test` 实测；磁盘清理 action 不采用——runner 基线约 87GB
  空闲，足够 ThinLTO 构建。boot 打包和 `finalize.sh` 需要 gitignored 的
  stock `boot_b.img` 与模块 manifest，仍只在本机执行。
- [`.github/workflows/storage-ram-test.yml`](../../../.github/workflows/storage-ram-test.yml)：
  手动 dispatch 的存储/内存方案对比：基线探测、两个磁盘清理 action 实测
  （jlumbroso v2：28GiB/257s；endersonmenezes v4 rmz：26GiB/40s）、
  swap/zram/zswap 可用性与组合彩排。结论：zram/zswap 在 runner 上可用，
  清理 action 非必需。
- [`.github/workflows/upstream-check.yml`](../../../.github/workflows/upstream-check.yml)：
  手动 dispatch 对比子模块 pin 与远端分支头，漂移时报单条 issue；CC 系列仓库
  上游已不可达，会一直显示 (unreachable)。
- [`.github/workflows/bump-submodule.yml`](../../../.github/workflows/bump-submodule.yml)：
  手动 dispatch，把指定子模块 bump 到分支头并同步 `versions.env` pin，以
  `make source patches` 重放为门禁后自动开 PR；合并与刷机始终是人工决定。

## 当前功能

> 本节是构建范围说明；验证状态以 [docs/STATUS.md](../STATUS.md) 为准，
> 实现细节以 [DESIGN.md](DESIGN.md) 和各功能文档为准。

- BakaSU 内建（`CONFIG_KSU=y`）+ SUSFS inline hook。
- 厂商 `.ko` 加载兼容（签名、vermagic、CRC、namespace、GKI protected export）。
- 13 个 dash OS4 `android_vh_*` trace hooks，供 `node_cache.ko` /
  `os_cpu_qi.ko` 使用；KCFI 哈希已做静态比对。
- `MEMFD_ASHMEM_SHIM`；AOSP 6.6.118 已自带实现，仅启用配置。
- Xiaomi F2FS 增强 iostat 已按 stock 单开关语义工作：只开
  `en_iostat_enable=1` 即可记录，stock `io_lat` 仍由 `iostat_enable` 控制。
- 新增 `f2fs_fault_report` tracepoint；`fault_report.ko` 的
  `/proc/fault_report` 已恢复。
- Xiaomi F2FS lock/priority：`f2fs_lock_elapsed_time`、
  `f2fs_priority_uplift/restore` tracepoint 和 `max_lock_elapsed_time`、
  `adjust_lock_priority`、`lock_duration_priority`、`critical_task_priority`
  sysfs；默认 `adjust_lock_priority=0`，不改变默认行为。`gc_lock` 的全部
  调用点已接入 trace wrapper。
- F2FS VIP：`vip_file_enable` + `f2fs_vip_bsearch/insert/remove`；
  `android_vh_f2fs_is_hiprio_task/usr_task` hook 加保守 fallback（RT 或
  negative-nice 且有用户地址空间的写打开，fallback 上限 8192 个 inode）。
  `vip_inode_count` 是调试用只读计数，不是 stock ABI。
- Xiaomi F2FS hybrid sysfs ABI；hybrid 在缺少原厂 block 映射时安全回退为
  “不支持”，不会重定向写入。
- Xiaomi EROFS iostat sysfs。
- stock core tracepoint：stock 的 1860 个 `__traceiter_*` 全部存在；6.6.143
  上游额外 46 个（合计 1906）。51 个 stock-only hook（含 legacy 0008/0009
  补齐的 MMC/DMA/lazy-resched 调用点）和 2 个 LZ4 事件已恢复，LZ4 已实测触发；
  GKI dynamic task_struct（`arch_task_struct_size`、`vendor_data_pad`、
  1024B vendor 上限）。
- mihomo Android root CLI：TUN `/dev/tun`、MTU 9000/GSO 65536、auto-route、
  auto-redirect、DNS hijack、进程/包名匹配；`CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y`。
  MPTCP 实测启动失败未启用；详见 [MIHOMO_ANDROID.md](MIHOMO_ANDROID.md)。
- 外部 TCP Brutal v2.0.1：`third_party/tcp-brutal`，`make brutal` 产物
  `brutal.ko`；ABI 白名单保留 `tcp_prot`、`tcpv6_prot` 及注册函数。

> mihomo Alpha KSU 模块已于 2026-11-21 移除：代理客户端统一改用
> [AsteriskMETA](https://github.com/Asterisk4Magisk/AsteriskMETA)（自带 mihomo
> core）与其增强模块；内核侧 TUN/TPROXY/netfilter/BPF 能力保持不变（上文与
> `features.fragment`）。
- NoMount v2.3.1：`third_party/nomount` 子模块，apply 时符号链接进
  `fs/nomount`，`CONFIG_NOMOUNT=y` 内建（上游 Kconfig `default y` +
  `select KEYS`）。仅编译级验证（FAST 构建通过），未实机验证；规则与
  配置由其 KSU metamodule 管理，本仓库不含用户态部分。
- DroidSpaces 容器支持（2026-11-21）：官方 GKI fragment 全套
  （SYSVIPC/POSIX_MQUEUE/IPC_NS/PID_NS/DEVTMPFS/USER_NS/TMPFS xattr+ACL/
  MACVLAN/IP_SET 等，`configs/features.fragment`）；SYSVIPC/IPC_NS 的
  task_struct 字段经 `patches/090-droidspaces` 移入 ANDROID_KABI 填充槽，
  vendor `.ko` ABI 不变。`CFS_BANDWIDTH`/`CGROUP_PIDS` 按官方文档保持
  关闭（会破坏 kABI；`--cpus`/`--pids-limit` 不可用）。参考内核
  `third_party/dash-droidspaces`（同设备，marble 配方 7 轮 CI 实机验证）。
- `TRIM_UNUSED_KSYMS=y`，使用 stock 导出表作为 ABI 白名单。

详细差异、验证分层和未覆盖项见：

- [DESIGN.md](DESIGN.md)
- [TEST_REPORT.md](TEST_REPORT.md)
- [BOOT_PACKAGING.md](BOOT_PACKAGING.md)
- [OPEN_ISSUES.md](OPEN_ISSUES.md)
- [ZRAM_EXTM.md](ZRAM_EXTM.md)：内存扩展/ExtM 与 lz4kd 的实机结论（stock
  vendor zram + crypto lz4kd，不替换 zram 模块）
- [MIHOMO_ANDROID.md](MIHOMO_ANDROID.md)：mihomo Android 实机运行、TUN/TProxy
  内核能力、tcp-brutal 与 MPTCP 结论；KSU 模块已移除，客户端为 AsteriskMETA
- [NODE_CACHE_SOURCE.md](NODE_CACHE_SOURCE.md)：用户提供的 node_cache 重实现
  评估、与 stock 6.6.118 二进制的差异、可借鉴点和 6.6.143 适配清单
- [DEV_NOTES.md](DEV_NOTES.md)：仓库开发笔记合并版；由
  [`scripts/collect-notes.py`](../../dash/scripts/collect-notes.py) 生成。
  只读原笔记，不改源文件；`make notes` 重新生成，`--check` 可校验是否过期。
  日常任务按 [AGENTS.md](../../AGENTS.md) 读单个文档即可，不需要先读全文。

## 厂商 `.ko` 兼容

集成补丁中的 `CONFIG_VENDOR_KO_COMPAT`（6.6.118 时代拆分补丁已删，见 git
历史）在模块加载路径跳过：

- 模块签名验证（保留 GKI 签名配置本身）
- vermagic 检查
- symbol CRC / `module_layout` 检查
- namespace import 检查
- GKI protected export 限制

符号仍然必须真实存在。集成补丁同时适配 BakaSU 三参数
`ksu_handle_sys_read`。关闭校验会降低安全性，
仅用于已解锁的自有设备。

## 更新规则

- 更新 AOSP：改 `versions.env` 的 `AOSP_TAG`/`AOSP_COMMIT`，运行
  `make patches`；如果补丁冲突，在 `src/aosp/common` 修正后运行
  `make gen-patches` 重新生成特性补丁，不要手改补丁文件。流程见
  [patches/README.md](../../dash/patches/README.md)。
- 更新 BakaSU：更新子模块并改 `BAKASU_COMMIT`，然后 `make patches config build`。
- 更新 SUSFS：更新 `SUSFS_COMMIT` 并 bump `third_party/susfs4ksu` 子模块即可；
  SUSFS 文件 apply 时从子模块安装，不需要手动取。bump 可走
  `.github/workflows/bump-submodule.yml`（自动 PR），漂移检测见
  `scripts/upstream-check.sh`（CI 每周跑，报 issue）。
- 源码目录可以随时由脚本重置；长期修改只保存在 `patches/`、`configs/` 和报告。
- 版本、哈希、模块数和验证结论只更新 [docs/STATUS.md](../STATUS.md)；本文件
  只记录构建流程和稳定的构建范围。

## 注意

- 本机 `fastboot boot` 不可用；最终 boot 通过继承 stock 64MB header/vbmeta/AVB
  footer、只替换 kernel 生成，已实机启动成功。不要用 mkbootimg 重建或清空 AVB
  尾部，详见 [BOOT_PACKAGING.md](BOOT_PACKAGING.md)。
- 当前 boot 镜像保留原厂 header v4/空 ramdisk/空 cmdline 和 OEM 签名的
  vbmeta/footer，只把 kernel 换成自编。本次没有写 `vendor_boot`/`dtbo`/`vbmeta`。
  `init_boot_a/b` 已于 2026-10-30 还原为 OS4.0.3.0 官方镜像（sha256
  `3d2062ae…`，两槽相同），设备启动和内置 KSU root 正常；KernelSU patched
  旧副本只留作历史回滚。不要刷紧凑镜像或改 vbmeta flags，否则 bootloop。
- AnyKernel/LunarKernel 也采用同一思路：基于当前 stock boot 用 magiskboot 重封并
  写满分区，保留 AVB 元数据；它的可用不代表存在额外签名权限。
- 内建 BakaSU v4.2.0-rc3 已替代 stock 的 `kernelsu` LKM；584 个 stock 非 LKM
  模块和 node_cache/os_cpu_qi 链已实测加载。
- hooks 的完整调用点系列已实机启动成功；KCFI 静态匹配和启动日志均已通过。仍建议
  在后续改动后做模块加载、长时稳定性和 suspend/resume 验证。

