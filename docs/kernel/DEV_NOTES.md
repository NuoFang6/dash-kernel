# dash 6.6.118 开发笔记合并包（给 LLM 的避坑包）

<!-- 由 dash/scripts/collect-notes.py 自动生成；不要手改本文件。 -->

> 生成时间（源文件最新 mtime）：2026-10-30 02:45:29 +0800  
> 覆盖 21 个源，218552 字节；脚本版本 1。  
> 重新生成：`make notes` 或 `python3 scripts/collect-notes.py`；
> 校验是否过期：`python3 scripts/collect-notes.py --check`。  
> 源文件才是权威；本文件只做汇总，遇到冲突按下面的顺序判断。

## 0. LLM 速读（先看这里）

### 0.1 权威顺序

1. `docs/kernel/TEST_REPORT.md` + `dash/out/artifacts/BUILD_INFO` + 真机实测 = **当前运行事实**。
2. `docs/kernel/BOOT_PACKAGING.md` = **boot/AVB 封装硬规则**（违反会花屏 bootloop）。
3. `docs/kernel/OPEN_ISSUES.md` = **剩余缺口和风险**（不要重复声称已解决）。
4. `docs/kernel/DESIGN.md` = **实现路径与 stock 差异**。
5. `docs/project/NAVIGATION.md` / `GAP_RESEARCH.md` / `DEVICE_MODULES.md` = 上下文和检索台账，**状态行可能过时**。
6. `docs/handoff/TASK_BRIEF.md` = 历史交接输入，不是当前执行指令。
7. `third_party/**` 与通用指南 = 上游/外部参考，**本机实测优先**。

### 0.2 硬规则（踩过的坑）

1. **不要写 `lk`、`super` 或用户数据。** 只允许在所有者明确授权下写当前
   `boot` 槽位；每次刷入重启后先等所有者确认开机，不要继续自动操作。
2. **boot 镜像必须继承 stock 64MB 分区布局。** 保留 header v4、OEM 签名
   vbmeta、AVB footer，只替换 kernel；不要用 mkbootimg 生成紧凑镜像，不要清零
   AVB 尾部，不要改 `--disable-verity/--disable-verification` 的 flags。
3. **本机 `fastboot boot` 不可用**（返回 `unknown command`）。可回退路径是
   完整备份 + 写当前槽位 `boot_b`，不是 RAM 临时启动。
4. **hidden-unlock 不是普通 Orange State。** 它接受“OEM 签名元数据 + kernel
   hash 不匹配”，但拒绝缺失/损坏的 vbmeta；不要把本机结论套到别的设备。
5. **`init_boot` 不是 stock。** 设备现有 init_boot 带 KernelSU wrapper /
   `kernelsu.ko`，且与交接包只差 41B 的 `stock_image.sha1`。恢复源用
   `out/device-backup/`，不要把 init_boot 当原厂镜像。
6. **厂商模块兼容不等于签名有效。** `CONFIG_VENDOR_KO_COMPAT` 跳过了签名、
   vermagic、CRC、namespace、protected-export 检查；只用于自有已解锁设备。
7. **13 个 `android_vh_*` hook 的 TP_PROTO 不能随意改。** KCFI 原型不匹配会在
   首次触发时 `brk #0x8228`；改后必须跑 `verify-os4-kcfi.py` 并再实机验证。
8. **`mmap_lock_init/free` 的 EXPORT 必须在 declaration-only TU**（本仓库
   `drivers/android/dash_os4_decl_exports.c`），否则 genksyms CRC 与 stock
   `os_cpu_qi.ko` 的 `__versions` 不一致，整条 QoS 链拒载。
9. **F2FS 增强 iostat 当前需要两个开关**：`iostat_enable=1` 和
   `en_iostat_enable=1`；只开后者计数为 0。这是已知实现差异，不要误判为没实现。
10. **stock 模块全部加载的判断要看逐名对比**：本机 585 个模块 = 584 个 stock
    非 LKM + 额外 `mkp`；stock `kernelsu` LKM 被内建驱动替代，没有双加载。
11. **SELinux 保持 Enforcing。** 不应为了读 sysfs 关闭 SELinux；root（KSU 域）
    已经能读 node_cache/QoS/F2FS/EROFS 数值。
12. **DroidSpaces 不是本交接内核的目标。** 上游加的 SYSVIPC/POSIX_MQUEUE/
    PID_NS/USER_NS/DEVTMPFS/IP_SET 等容器配置，本 stock-config 内核没有；要跑
    容器必须另建变体并单独验证。
13. **上游 dash-droidspaces 的“call site bootloop”不是本仓库的结论。** 本仓库
    完整 13-hook + 全调用点已实机启动；其 `exp/ksu-*` 分支更像是在查它自己的
    KSU/SUSFS early hang，不要据此删掉本仓库的调用点。
14. **不要相信旧状态行。** `docs/project/NAVIGATION.md` /
    `docs/project/GAP_RESEARCH.md` 保留了 6.6.144 调研痕迹；当前构建/运行结论
    以 `docs/kernel/TEST_REPORT.md`、`dash/out/artifacts/BUILD_INFO`、
    `SHA256SUMS` 为准。

### 0.3 当前状态快照（从文件自动生成，不靠旧 prose）

### 版本锁定

来源：`dash/versions.env`

```text
AOSP_REPO=https://android.googlesource.com/kernel/common
AOSP_BRANCH=android15-6.6
AOSP_TAG=android15-6.6-2026-01_r1
AOSP_COMMIT=f9c84f40b6ba6152b6f51daba0193c9564af4172

CLANG_PREBUILT_REPO=https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86
CLANG_PREBUILT_BRANCH=main-kernel-build-2024
CLANG_VERSION=r510928

BAKASU_DIR=../BakaSU
BAKASU_COMMIT=d5e9e025b8b49155f8014684d64c91742b465f65

SUSFS_REPO=https://gitlab.com/simonpunk/susfs4ksu.git
SUSFS_BRANCH=gki-android15-6.6
SUSFS_COMMIT=0606e19afae93ffc88e53883dbf3cfced62a7b59
```

### 构建信息

来源：`dash/out/artifacts/BUILD_INFO`

```text
AOSP_TAG=android15-6.6-2026-01_r1
AOSP_COMMIT=f9c84f40b6ba6152b6f51daba0193c9564af4172
KERNEL_VERSION=6.6.118-4k
KERNEL_RELEASE=6.6.118-4k
CLANG=Android (11368308, +pgo, +bolt, +lto, +mlgo, based on r510928) clang version 18.0.0 (https://android.googlesource.com/toolchain/llvm-project 477610d4d0d988e69dbc3fae4fe86bff3f07f2b5)
CONFIG_SHA256=ee75ae6c2369621a68b8c21ef7fda8bfa6ad1737df733a3006ffcb27f5ecbce1
BASH_VERSION=GNU bash，版本 5.3.20(1)-release (x86_64-pc-linux-gnu)
```

### 产物校验和

来源：`dash/out/artifacts/SHA256SUMS`

```text
193235f7b85454433ea68c29ceaac697551b32e7aef7b727ee042d1367f8e386  Image
f60bca7052e6d519974b00c50447a6f8ba1615886fc9386cac1c5229d7103826  Image.lz4
a28344f9296fb9796b2c8dc231812c59aa76770d069158897d1305dc55ab7cac  boot.img
ee75ae6c2369621a68b8c21ef7fda8bfa6ad1737df733a3006ffcb27f5ecbce1  config
0a3b685454da3e238dd39a60d7f96a532fc9a95b63e91cf0fae110bae228bc10  System.map
```

### boot 校验和

来源：`dash/out/artifacts/boot.img.sha256`

```text
a28344f9296fb9796b2c8dc231812c59aa76770d069158897d1305dc55ab7cac  /home/nuofang/code/mikernel/dash/out/artifacts/boot.img
```

### 0.4 已知冲突 / 容易误读的地方

- **本机 AVB 特例**：hidden-unlock 接受保留 OEM vbmeta/footer、kernel hash 不匹配的 boot；拒绝缺 vbmeta/改 flags。通用指南里的“解锁后随便刷”不适用于此。
- **init_boot**：当前是 KernelSU patched，不是 stock；与交接包只差 `stock_image.sha1`。恢复源用 `out/device-backup/`。
- **上游 call-site bootloop**：那是 `kernel_dash_droidspaces` 自己的组合；本仓库完整 13-hook 全调用点已开机。不要据此删调用点。
- **F2FS iostat**：2026-10-30 已修正为 stock 单开关语义：只开 `en_iostat_enable=1` 即记录；stock `io_lat` 仍由 `iostat_enable` 控制。
- **F2FS fault report**：`f2fs_fault_report` tracepoint 已补，只在同步 `f2fs_handle_error()` 触发；`/proc/fault_report` 已恢复。
- **DroidSpaces**：本内核没有 SYSVIPC/POSIX_MQUEUE/PID_NS/USER_NS/DEVTMPFS/IP_SET 等容器配置；容器目标要另建变体。
- **旧状态**：`docs/project/NAVIGATION.md`/`GAP_RESEARCH.md` 里有 6.6.144 时代文字；当前构建是 6.6.118，见 `BUILD_INFO`。
- **未补齐**：stock core tracepoint 还缺 58 个；VIP 选择策略、hybrid、EROFS per-device、SCSI fastdiscard、GKI task_struct 等见 OPEN_ISSUES。

## 源清单（Sources）

| # | 类别 | 标题 | 源文件 | 大小 | SHA256 | 状态/警告 |
|---|---|---|---|---:|---|---|
| 01 | 当前交付 | dash 构建与交付入口 | [`docs/kernel/README.md`](README.md) | 6190 | `3143113ac73701a8` | 当前交付（优先相信） |
| 02 | 当前交付 | boot / AVB 封装踩坑与硬规则 | [`docs/kernel/BOOT_PACKAGING.md`](BOOT_PACKAGING.md) | 6392 | `e7da50a04b7a9f42` | 当前交付（优先相信） |
| 03 | 当前交付 | 测试报告：静态检查、真机证据与 AVB 复盘 | [`docs/kernel/TEST_REPORT.md`](TEST_REPORT.md) | 24571 | `83f94761ee5f07f8` | 当前交付（优先相信） |
| 04 | 当前交付 | 未覆盖项、风险与上游同步评估 | [`docs/kernel/OPEN_ISSUES.md`](OPEN_ISSUES.md) | 14300 | `b9e6d4ccf065c67a` | 当前交付（优先相信） |
| 05 | 当前交付 | 实现路径、与 stock 的差异和回退 | [`docs/kernel/DESIGN.md`](DESIGN.md) | 12233 | `8d02e10fe07b4935` | 当前交付（优先相信） |
| 06 | 当前交付 | 实机 vs stock 特性核对 | [`docs/kernel/STOCK_PARITY_AUDIT.md`](STOCK_PARITY_AUDIT.md) | 9595 | `a132c132b60b864c` | 当前交付（优先相信） |
| 07 | 当前交付 | 未完成项按性能影响排序 | [`docs/kernel/UNRESOLVED_GAPS.md`](UNRESOLVED_GAPS.md) | 8667 | `b4f3cc82120212cf` | 当前交付（优先相信） |
| 08 | 当前交付 | 参考仓库工作笔记核对 | [`docs/kernel/UPSTREAM_NOTES_REVIEW.md`](UPSTREAM_NOTES_REVIEW.md) | 12054 | `df1338b663dd03aa` | 当前交付（优先相信） |
| 09 | 当前交付 | UFS/hybrid/fastdiscard 缺口证据与安全边界 | [`docs/kernel/UFS_HYBRID_EVIDENCE.md`](UFS_HYBRID_EVIDENCE.md) | 5569 | `40b17b16dee1d3a2` | 当前交付（优先相信） |
| 10 | 仓库上下文 | 仓库导航、子模块 pin 与资源索引 | [`docs/project/NAVIGATION.md`](../project/NAVIGATION.md) | 14724 | `68c54c57b5d93b85` | 这是仓库地图，不是实时状态；若与 TEST_REPORT 冲突，以 TEST_REPORT 为准。 |
| 11 | 仓库上下文 | 缺口调研台账：公开源码/近似来源/结论 | [`docs/project/GAP_RESEARCH.md`](../project/GAP_RESEARCH.md) | 10446 | `0e634fe9b74a13c6` | 这是检索台账，不是构建状态；2026-10-30 状态追加在文末，部分链接只记录未下载。 |
| 12 | 仓库上下文 | node_cache / os_cpu_qi 的 stock 行为调查 | [`docs/project/DEVICE_MODULES.md`](../project/DEVICE_MODULES.md) | 6039 | `8f7140e5e3638897` | 数值是 stock 运行态历史值；当前自编内核的实测值见 TEST_REPORT §8。 |
| 13 | 需求 | 交接任务书与验收标准（历史输入） | [`docs/handoff/TASK_BRIEF.md`](../handoff/TASK_BRIEF.md) | 12697 | `6cc641eb2f82e514` | 任务书写于 2026-10-29 交接时（文中“当前 6.6.144/只生成 Image”是旧状态）；本仓库已完成 6.6.118 并实机启动。保留原文追溯，不作为当前执行指令。 |
| 14 | 需求 | 来源、pin 与“只记录不下载”的近失链接 | [`handoff/dash-gap-handoff/links/SOURCES.md`](../../handoff/dash-gap-handoff/links/SOURCES.md) | 4855 | `2c5a8d73a4bf5443` | 来源清单中的 project/dash 描述是交接时状态（6.6.144）；当前实现已切到 6.6.118。 |
| 15 | 上游参考 | dash-droidspaces 项目说明（上游参考） | [`third_party/dash-droidspaces/README.md`](../../third_party/dash-droidspaces/README.md) | 3567 | `b458cb4cfde6737c` | 上游基线 commit 与本机 stock 不完全相同；其 DroidSpaces 配置不是本交接目标。 |
| 16 | 上游参考 | OS4 vendor hooks / CRC / CI 单变量开关（上游参考） | [`third_party/dash-droidspaces/patches/README.md`](../../third_party/dash-droidspaces/patches/README.md) | 8397 | `0a8516136bfbec0a` | 上游 README 的 full-call-site bootloop 与本仓库实测不同；详见 docs/kernel/TEST_REPORT.md §10。 |
| 17 | 上游参考 | vendor_boot v15 逐字节变更记录（上游参考） | [`third_party/dash-droidspaces/docs/vendor-boot-v15-changeset.md`](../../third_party/dash-droidspaces/docs/vendor-boot-v15-changeset.md) | 6613 | `9f4db4eb626b2f7d` | 上游参考（版本可能漂移） |
| 18 | 上游参考 | gz/Trusty 被擦除与 nvhe 启动变更（上游参考） | [`third_party/dash-droidspaces/docs/gz-erased-changeset.md`](../../third_party/dash-droidspaces/docs/gz-erased-changeset.md) | 7269 | `fa4a4878660c70f2` | 本仓库使用 stock cmdline（kvm-arm.mode=protected），未合入 trusty-rescue/nvhe。 |
| 19 | 通用参考 | GKI / LZ4KD 通用避坑指南（外部通用指南） | [`third_party/hyperos-lz4kd/Android_GKI_通用内核定制与LZ4KD实战避坑全指南.md`](../../third_party/hyperos-lz4kd/Android_GKI_通用内核定制与LZ4KD实战避坑全指南.md) | 19197 | `24a08fae5abc330b` | 通用指南的 AVB/解锁结论不适用于本机 hidden-unlock；boot 封装以 docs/kernel/BOOT_PACKAGING.md 为准。 |
| 20 | 上游参考 | hyperos-lz4kd 项目说明（上游参考） | [`third_party/hyperos-lz4kd/README.md`](../../third_party/hyperos-lz4kd/README.md) | 18119 | `02074aa9cd5a5d3f` | 该 README 在“七、开机”处截断，内容与完整避坑指南重复；保留仅用于记录上游现状。 源文件代码围栏未闭合，已在合并稿中补齐。 |
| 21 | 上游参考 | SUSFS 上游集成说明（上游参考） | [`third_party/susfs4ksu/README.md`](../../third_party/susfs4ksu/README.md) | 7058 | `e5b8c8a2cdeefb99` | 上游参考（版本可能漂移） |

快速跳转：[01](#src-01) · [02](#src-02) · [03](#src-03) · [04](#src-04) · [05](#src-05) · [06](#src-06) · [07](#src-07) · [08](#src-08) · [09](#src-09) · [10](#src-10) · [11](#src-11) · [12](#src-12) · [13](#src-13) · [14](#src-14) · [15](#src-15) · [16](#src-16) · [17](#src-17) · [18](#src-18) · [19](#src-19) · [20](#src-20) · [21](#src-21)

---

<a id="src-01"></a>
## 1. dash 构建与交付入口

> 来源：[`docs/kernel/README.md`](README.md) · 6190 字节 · SHA256 `3143113ac73701a856f0b5da230f3b3061d186873b5047e4c87ebd8bcca7e985`
> 类别：当前交付 · 状态：当前交付（优先相信）

REDMI Turbo 5 Max（`dash` / 2602BRT18C / MT6991）的 GKI2.0 内核工作区。

当前目标基线是 **AOSP `android15-6.6-2026-01_r1`（6.6.118）**，不是早期
6.6.144 实验构建。设备 stock 为
`6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`，GKI 分支
`android15-6.6`，KMI 字符串 `android15-8`，4K 页。

### 目录

```text
configs/stock.config          设备 stock 配置，构建起点
configs/abi_symbollist.raw    stock 导出白名单，保持 TRIM_UNUSED_KSYMS
configs/features.fragment     本次新增配置摘要
patches/                      有序补丁系列；series 是唯一应用顺序
patches/susfs/                SUSFS 内核侧新增文件
patches/vendor-hooks/         node_cache/os_cpu_qi 的 13 个 trace hooks
scripts/                      同步、打补丁、配置、构建、boot 打包和静态检查
src/aosp/common/              clean AOSP 浅克隆，可随时重置
toolchains/                   clang r510928
out/                          构建目录和 artifacts
```

### 快速开始

```bash
cd dash
make deps       # Arch/CachyOS 依赖检查
make toolchain  # 获取固定 clang r510928
make source     # 浅克隆/更新 AOSP 到 6.6.118 标签
make patches    # 重置源码、接入 BakaSU、按 series 打补丁
make config     # stock.config + 功能开关
make build      # Image / Image.lz4 / vmlinux / System.map
make boot       # 从 stock boot_b 继承生成 boot.img
bash scripts/finalize.sh  # KCFI + 638 模块 + boot 校验，写 SHA256SUMS
make notes                 # 合并仓库开发笔记为 docs/kernel/DEV_NOTES.md（给 LLM 的避坑包）
```

产物在 `out/artifacts/`，构建日志在 `out/dash/build.log`。

### 当前功能

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
- stock core tracepoint 1860/1860 对齐：51 个 stock-only hook（含 0008/0009
  补齐的 MMC/DMA/lazy-resched 调用点）、2 个 LZ4 事件；GKI dynamic
  task_struct（`arch_task_struct_size`、`vendor_data_pad`、1024B vendor 上限）。
- `TRIM_UNUSED_KSYMS=y`，使用 stock 导出表作为 ABI 白名单。

详细差异、验证分层和未覆盖项见：

- [DESIGN.md](DESIGN.md)
- [TEST_REPORT.md](TEST_REPORT.md)
- [BOOT_PACKAGING.md](BOOT_PACKAGING.md)
- [OPEN_ISSUES.md](OPEN_ISSUES.md)
- [DEV_NOTES.md](DEV_NOTES.md)：仓库开发笔记合并版；由
  [`scripts/collect-notes.py`](../../dash/scripts/collect-notes.py) 生成，供 LLM 快速避坑。
  只读原笔记，不改源文件；`make notes` 重新生成，`--check` 可校验是否过期。

### 厂商 `.ko` 兼容

`0001-vendor-ko-compat.patch` 新增 `CONFIG_VENDOR_KO_COMPAT`，在模块加载路径跳过：

- 模块签名验证（保留 GKI 签名配置本身）
- vermagic 检查
- symbol CRC / `module_layout` 检查
- namespace import 检查
- GKI protected export 限制

符号仍然必须真实存在。`0004-susfs-bakasu-hooks.patch` 适配 BakaSU 三参数
`ksu_handle_sys_read`。关闭校验会降低安全性，仅用于已解锁的自有设备。

### 更新规则

- 更新 AOSP：改 `versions.env` 的 `AOSP_TAG`/`AOSP_COMMIT`，运行
  `make patches`；如果补丁冲突，在 `src/aosp/common` 修正后用 `git diff`
  重新导出对应补丁。
- 更新 BakaSU：更新子模块并改 `BAKASU_COMMIT`，然后 `make patches config build`。
- 更新 SUSFS：更新 `SUSFS_COMMIT`，重新取上游 patch 和
  `patches/susfs/{susfs.c,susfs.h,susfs_def.h}`。
- 源码目录可以随时由脚本重置；长期修改只保存在 `patches/`、`configs/` 和报告。

### 注意

- 本机 `fastboot boot` 不可用；最终 boot 通过继承 stock 64MB header/vbmeta/AVB
  footer、只替换 kernel 生成，已实机启动成功。不要用 mkbootimg 重建或清空 AVB
  尾部，详见 [BOOT_PACKAGING.md](BOOT_PACKAGING.md)。
- 当前 boot 镜像保留原厂 header v4/空 ramdisk/空 cmdline 和 OEM 签名的
  vbmeta/footer，只把 kernel 换成自编。本次没有写 `init_boot`/`vendor_boot`/
  `dtbo`/`vbmeta`；但当前设备的 `init_boot` 本身就是交接前的 KernelSU patched
  版本（含 `kernelsu.ko`），不是 stock，且与交接包只差 `stock_image.sha1`。
  不要把 init_boot 当原厂恢复源。不要刷紧凑镜像或改 vbmeta flags，否则 bootloop。
- AnyKernel/LunarKernel 也采用同一思路：基于当前 stock boot 用 magiskboot 重封并
  写满分区，保留 AVB 元数据；它的可用不代表存在额外签名权限。
- 内建 BakaSU v4.2.0-rc3 已替代 stock 的 `kernelsu` LKM；584 个 stock 非 LKM
  模块和 node_cache/os_cpu_qi 链已实测加载。
- hooks 的完整调用点系列已实机启动成功；KCFI 静态匹配和启动日志均已通过。仍建议
  在后续改动后做模块加载、长时稳定性和 suspend/resume 验证。

---

<a id="src-02"></a>
## 2. boot / AVB 封装踩坑与硬规则

> 来源：[`docs/kernel/BOOT_PACKAGING.md`](BOOT_PACKAGING.md) · 6392 字节 · SHA256 `e7da50a04b7a9f42fc1c5618ad9ca4afb7077db0517997c453e8374c7e32e771`
> 类别：当前交付 · 状态：当前交付（优先相信）

日期：2026-10-29；2026-10-30 更新到构建 #29。适用范围：dash / REDMI Turbo 5 Max
（MT6991），stock `6.6.118`，当前设备的“隐藏解锁”状态。以下结论均来自本机实测，
不是推断。

### 1. 原厂 boot 的真实结构

原厂 `boot_b` 分区是 **64MB**，不是 17MB 的紧凑镜像：

```text
0x00000000 - 0x00000fff   Android boot header v4（1584B）
0x00001000 - 0x1088fff    LZ4 kernel + 零填充
0x1089000 - 0x108997f     原厂 AVB vbmeta（0x980 = 2432B）
...........................零填充
0x3ffffc0 - 0x3ffffff     AVB footer（AVBf）
```

关键字段：

- header version 4，page size 4096，ramdisk_size 0，cmdline 为空
- kernel LZ4 legacy，stock 压缩后 17,317,780B
- AVB footer：`original_image_size = 0x1089000`，
  `vbmeta_offset = 0x1089000`，`vbmeta_size = 0x980`
- vbmeta 起始 magic 为 `AVB0`，签名链为 OEM 签名

### 2. 三次失败及原因

| 尝试 | 结果 | 原因 |
|---|---|---|
| `mkbootimg` 重建的 17MB 自编 boot | 花屏、bootloop | 未保留 64MB 分区布局和 AVB footer；fastboot 写入后尾部校验结构不完整/被破坏 |
| stock kernel + 补齐 64MB、清零 AVB 尾部 | 花屏、bootloop | 明确去掉 AVB footer 和 vbmeta，bootloader 不接受 |
| 原厂 vbmeta 上直接改 `--disable-verity --disable-verification` | 花屏、bootloop | fastboot 只改 offset 120 的 flags，破坏 OEM vbmeta 签名；bootloader 拒绝签名已损坏的 vbmeta |
| **保留原厂 header+vbmeta+footer，仅替换 kernel** | **成功开机** | 见第 3 节 |

`fastboot boot` 在该 LK 上直接返回 `unknown command`，没有 RAM 临时启动这一
条路。`fastboot getvar unlocked` 虽然返回 yes，但系统属性是
`ro.boot.vbmeta.device_state=locked`、`ro.boot.verifiedbootstate=green`、
`ro.boot.flash.locked=1`；这不是标准 Orange State，不能按普通真解锁设备处理。

### 3. 通过的封装方式

最终 boot 由 [scripts/repack-boot.py](../../dash/scripts/repack-boot.py) 生成：

1. 复制整个 stock 64MB boot 作为底包。
2. 保留 header 的 v4 字段和 cmdline，只更新 `kernel_size`，`ramdisk_size=0`。
3. 在 offset 0x1000 写入新的 LZ4 kernel；kernel 结束后到 `original_image_size`
   之间清零。
4. **逐字节保留**原厂 vbmeta（`0x1089000..0x108997f`）和 AVB footer。
5. 如果新 kernel 超过原厂 17,338,368B 的 original image 空间，脚本会把原厂
   vbmeta 搬到新位置并更新 footer 的 original_image_size/vbmeta_offset；footer
   本身不是签名的一部分，vbmeta 字节仍保持原厂签名。

当前最终产物（构建 #29，2026-10-30）：

- `Image.lz4`：17,348,138B
- `boot.img`：64MB，SHA256
  `a28344f9296fb9796b2c8dc231812c59aa76770d069158897d1305dc55ab7cac`
- 新 kernel（17,348,138B）超过原厂 original_image_size 17,338,368B，
  repack 脚本把原厂 vbmeta 从 `0x1089000` 搬到 `0x108d000` 并把 footer 的
  original_image_size 更新为 `0x108d000`；vbmeta 字节和 OEM 签名未变
- boot 内 kernel 与 `out/artifacts/Image.lz4` 字节一致
- 自编内核实机启动成功：`6.6.118-4k #29`，KernelSU built-in，SUSFS 2.3.0，
  node_cache/os_cpu_qi 整条模块链加载；F2FS 单开关 iostat、
  `f2fs_fault_report`、lock/priority trace 与 VIP 已补；stock core
  tracepoint 1860/1860 和 GKI dynamic task_struct 已对齐

### 4. 为什么 LunarKernel 能开机

只读检查
`/storage/emulated/0/Download/QQ/LunarKernel6.6-V2.1.5-canary.zip`
（没有刷它）：

- zip 中**没有 boot.img**，只有裸 `Image`（38,914,560B）；用 lz4 legacy -12
  压缩后约 18,590,000B，已经超过 stock 的 original-image kernel 空间
  （17,334,272B）。
- 安装器是标准 AnyKernel3，调用 `split_boot` + `flash_boot`。
- `flash_boot` 使用包内 `magiskboot repack <当前 boot> boot-new.img`，没有改
  `vbmeta` 分区。
- 包内没有 OEM 私钥，也没有把 vbmeta 重新签成原厂链。
- 它把 `boot-new.img` 用 `cat boot-new.img /dev/zero > $BLOCK` 写满整个 boot
  分区，避免旧 footer 残留。
- magiskboot 必须保留 signed vbmeta 字节，并把 vbmeta/footer 重新定位到新
  kernel 之后（或生成等价的 AVB 结构）；否则 18.6MB 的 kernel 会覆盖原
  vbmeta。该结构在本机隐藏解锁状态下被接受。

结论：不是 Lunar 的内核比我们的“更有特权”，而是它的安装器保留了 stock boot 的
AVB/分区结构；我们最初的 mkbootimg 镜像把它丢了。它不违反 AVB，刚好相反，是
依赖原厂 AVB 元数据。

### 5. 后续硬性规则

1. **不要用 mkbootimg 重建 dash boot 作为最终产物。** 必须从 stock boot
   继承，保留 64MB 分区、header、vbmeta 和 AVB footer。
2. **不要把 boot.img 做成 17MB。** fastboot 写短镜像会留下旧尾部或破坏校验结构。
3. **不要为了自定义 kernel 改 vbmeta flags 或重签 vbmeta。** 本机 bootloader
   拒绝签名被修改的 vbmeta；`--disable-verity --disable-verification` 不是本机
   可行路线。
4. `init_boot_b`、`vendor_boot_b`、`dtbo_b`、`vbmeta_b` 保持本次操作前的状态；
   本方案只替换 `boot_b` 中 kernel。注意：当前 `init_boot_b` 是设备原有的
   KernelSU patched 镜像（含 `kernelsu.ko`），不是 stock；它与交接包只差
   `stock_image.sha1`。不要把 init_boot 当原厂恢复源。
5. kernel 压缩后必须能放进 stock original-image 空间；脚本支持把 vbmeta 搬迁到
   新位置，但如果超过分区可用空间会明确失败，不能截断。
6. 任何写入前备份完整 `boot_b`/`vbmeta_b`，不要碰 `lk`、`super` 或用户数据。
7. 这不是通用签名绕过方案：在其他安全策略更严格的 bootloader 上，保留旧
   vbmeta 但 hash 不匹配也可能被拒绝。本结论只对当前设备状态有效。

### 6. 恢复命令

```bash
fastboot flash vbmeta_b out/device-backup/vbmeta_b.img
fastboot flash boot_b out/device-backup/boot_b.img
fastboot reboot
```

两个文件的 SHA256 已记录在
[out/device-backup/SHA256SUMS](../../dash/out/device-backup/SHA256SUMS)。恢复不涉及
`lk` 或用户数据。当前设备的 KernelSU patched init_boot 副本也保存在
`out/device-backup/init_boot_b.current-kSU.img`；它不是 stock，不要用于恢复
原厂 init_boot。

---

<a id="src-03"></a>
## 3. 测试报告：静态检查、真机证据与 AVB 复盘

> 来源：[`docs/kernel/TEST_REPORT.md`](TEST_REPORT.md) · 24571 字节 · SHA256 `83f94761ee5f07f8c25d0135bcdeadfd108cd0dbf4fab2479ed77662e536489d`
> 类别：当前交付 · 状态：当前交付（优先相信）

测试日期：2026-10-29；2026-10-30 更新 stock parity 修复（内核构建 #29）。当前结论分为：

- **已执行并通过**：clean 补丁应用、完整编译、静态符号检查、KCFI 原型检查、
  64MB AVB 保留式 boot 封装；自编内核实机启动成功（`6.6.118-4k`），KernelSU
  built-in、SUSFS、584 个 stock 模块、node_cache/os_cpu_qi/QoS 模块加载。
- **已定位并解决**：早期 bootloop 是 boot 封装丢失原厂 AVB footer/vbmeta，
  不是内核构建错误。最终镜像保留 OEM vbmeta/footer，仅替换 kernel。
- **已补采（2026-10-29 晚）**：node_cache/QoS/F2FS/EROFS sysfs 数值、SUSFS
  版本/特性、F2FS 写入回读校验、EROFS 冷缓存读取计数、584 个 stock 非 LKM 模块
  的逐名对比均已取得。
- **已补齐（2026-10-30）**：F2FS 增强 iostat 已改为 stock 单开关语义；新增
  `f2fs_fault_report` tracepoint，`fault_report.ko` 的 `/proc/fault_report`
  恢复；F2FS lock/priority tracepoint + 4 个 lock sysfs；VIP hook + 保守
  fallback；所有 `gc_lock` 调用点接入 lock trace wrapper；构建 #29 已刷入
  `boot_b` 并启动。
- **已补齐（2026-10-30 晚）**：stock core tracepoint 1860/1860 对齐；
  2 个 LZ4 事件和 51 个 stock-only hook（7 个 export-only 已在 0008/0009
  补调用点）；GKI dynamic task_struct；EROFS iostat 改为每 CPU 统计；
  F2FS task-context 异步 fault report；lazy-resched restore hooks；
  `/proc/iostat_enhance` 经复核是误记并已纠正。
- **完整核对**：见 [STOCK_PARITY_AUDIT.md](STOCK_PARITY_AUDIT.md)。
- **未完成**：fsck/power-loss、长时压力与 suspend/resume、SUSFS 隐藏全项、
  性能/功耗 A/B；hybrid UFS、EROFS 多桶布局、SCSI fastdiscard、
  UFS 官方 37 文件源见 §11/§13、UFS_HYBRID_EVIDENCE 与 OPEN_ISSUES。

### 1. 环境与输入

| 项 | 值 |
|---|---|
| 设备 | `dash` / 2602BRT18C / REDMI Turbo 5 Max |
| stock 内核 | `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k` |
| 活动槽位 | `_b` |
| AOSP 标签 | `android15-6.6-2026-01_r1` |
| AOSP commit | `f9c84f40b6ba6152b6f51daba0193c9564af4172` |
| 编译器 | AOSP clang r510928（clang 18.0.0） |
| BakaSU | `d5e9e025b8b49155f8014684d64c91742b465f65` |
| SUSFS | `0606e19afae93ffc88e53883dbf3cfced62a7b59` |
| 基线配置 | [stock.config](../../dash/configs/stock.config) |

### 2. 补丁应用

从 clean tag 执行：

```bash
bash scripts/apply-patches.sh
```

结果：16 个补丁全部按 `patches/series` 顺序 `git apply --index` 成功，无 reject、
无 offset 失败。应用后源码 HEAD 仍为 `f9c84f40b6ba6152b6f51daba0193c9564af4172`，
变更均为工作树/索引补丁。

### 3. 构建

```bash
bash scripts/configure.sh
bash scripts/build.sh
```

结果：

- 退出码 0。
- `build.log` 中 `error:` 0，`warning:` 0。
- 使用 stock 配置，未回退到 `gki_defconfig`。
- `Image` 内版本字符串：`Linux version 6.6.118-4k (dash@mikernel)`。
- `CONFIG_LOCALVERSION_AUTO` 未设置，构建脚本抑制 git dirty 后缀。

关键配置：

```text
CONFIG_CFI_CLANG=y
CONFIG_SHADOW_CALL_STACK=y
CONFIG_MODVERSIONS=y
CONFIG_MODULE_SIG_PROTECT=y
CONFIG_TRIM_UNUSED_KSYMS=y
CONFIG_UNUSED_KSYMS_WHITELIST="<dash>/configs/abi_symbollist.raw"
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_VENDOR_KO_COMPAT=y
CONFIG_MEMFD_ASHMEM_SHIM=y
CONFIG_XIAOMI_ENHANCED_IOSTAT=y
CONFIG_XIAOMI_EROFS_IOSTAT=y
CONFIG_F2FS_VIP_FILE=y
CONFIG_F2FS_FS_HYBRID_UFS=y
CONFIG_BLOCK_HYBRID_UFS=y
```

ABI 白名单使用包内 stock 导出表生成，共 14,845 个名称。构建后
`vmlinux.symvers` 导出 8,996 个符号。保留 `TRIM_UNUSED_KSYMS=y`，没有为了省事
关闭该安全/体积选项。

### 4. 厂商模块静态兼容

脚本：

```bash
python3 scripts/check-vendor-modules.py \
  --symvers out/dash/vmlinux.symvers \
  --manifest ../handoff/dash-gap-handoff/device/module_manifest.tsv \
  --modules ../handoff/dash-gap-handoff/modules
```

结果：

```text
modules=638 kernel_exports=8996 hard_missing=0 weak_missing=0
```

方法：把 638 个 stock `.ko` 当成一个链接集合，先收集所有模块定义符号，再对
`vmlinux.symvers` 的导出集合解析。未解析 hard/weak 均为 0。该检查不等价于
运行时加载，不能证明 CFI 探针、签名、CRC 和硬件 probe。

补丁前同一检查恰好是 13 个 hard missing，全部为 `node_cache`/`os_cpu_qi`
使用的 `android_vh_*` tracepoint；加入 hooks 后归零，说明补丁命中目标而非掩盖
其它缺口。`leds-mtk-disp.ko` 的已知 weak 引用在本集合中可解析，检查报告 0。

### 5. KCFI 原型

```bash
python3 scripts/verify-os4-kcfi.py out/dash/vmlinux out/dash/.config
```

13/13 通过：

```text
remove_mapping / _failed             0xad16e271
filemap_get_folio_end                0xaf94231e
put_super                            0xcf650130
fuse_request_end_ext / _fetch        0x6d1df6d6
mmap_lock_init / _free               0xb294fbeb
percpu_rwsem_init                    0xdabec163
rcu_boost_start / _end               0x922a38d6
sync_rcu_wait_start / _end           0x389e96a6
```

这是对构建出的 `__traceiter_*` 机器码立即数与 stock 模块预期值逐项比较。完整 hooks
镜像也已实机启动并加载 os_cpu_qi/node_cache，启动日志无 KCFI `brk`；仍未做长时
压力/边界场景触发验证。

### 6. boot 镜像

```bash
bash scripts/make-boot.sh
```

生成规则（最终版本）：以 stock 64MB `boot_b.img` 为底包，保留 header v4、
cmdline、原厂 vbmeta 和 AVB footer，只替换 kernel，并写入完整 boot 分区大小。
具体实现见 `scripts/repack-boot.py` 和
[BOOT_PACKAGING.md](BOOT_PACKAGING.md)。本次没有写入 `init_boot_b`、
`vendor_boot_b`、`dtbo_b`、`vbmeta_b`；`init_boot_b` 本身是设备原有的
KernelSU patched 镜像，与交接包的 41B 差异见 §9.1。

检查结果：

```text
output size: 67108864
boot magic: ANDROID!
kernel_size: 17348138
ramdisk size: 0
boot image header version: 4
AVB footer: original_image_size=17354752 vbmeta=17354752+2432
boot SHA256: a28344f9296fb9796b2c8dc231812c59aa76770d069158897d1305dc55ab7cac
```

- boot 内 kernel 与 `out/artifacts/Image.lz4` 字节一致（`cmp` 通过）。
- boot 内 ramdisk 为 0 字节，符合 stock `boot_b`。
- 原厂 AVB footer/vbmeta 逐字节保留；本次 kernel 超过原厂
  `original_image_size`（17,338,368B），vbmeta 被搬到 `0x108d000`，footer 的
  original_image_size 更新为 17,354,752B，vbmeta/OEM 签名未改。这不是“重新签名”，也不是 AVB 合法哈希，
  而是该设备隐藏解锁状态接受的结构。关闭/修改 vbmeta flags 已实测会被拒绝。
- 该精确镜像已刷入 `boot_b` 并成功启动；当前运行分区的 SHA256 与产物一致。

> 注意：`out/artifacts/boot.img` 是已验证的 hooks + Xiaomi 功能版本。
> `out/baseline-6.6.118/boot.img` 是内容不含 hooks/新功能的旧测试镜像，使用旧的
> mkbootimg 封装，**不可启动**，仅保留作内核对照。


### 7. 产物校验和

最终由 `scripts/finalize.sh` 生成 `SHA256SUMS`：

```text
193235f7b85454433ea68c29ceaac697551b32e7aef7b727ee042d1367f8e386  Image
f60bca7052e6d519974b00c50447a6f8ba1615886fc9386cac1c5229d7103826  Image.lz4
a28344f9296fb9796b2c8dc231812c59aa76770d069158897d1305dc55ab7cac  boot.img
ee75ae6c2369621a68b8c21ef7fda8bfa6ad1737df733a3006ffcb27f5ecbce1  config
0a3b685454da3e238dd39a60d7f96a532fc9a95b63e91cf0fae110bae228bc10  System.map
```

产物位于 [out/artifacts](../../dash/out/artifacts)。校验和以目录内 `SHA256SUMS` 为准。

最终复验（2026-10-30 01:54，构建 #29）：补丁 0005 已包含 F2FS 单开关、
`f2fs_fault_report` 和全部 `gc_lock` trace 调用点；补丁 0007 已包含
51 个 stock-only hook、LZ4 事件和 dynamic task_struct。`scripts/finalize.sh`
通过 KCFI 13/13、638 模块 `hard_missing=0 weak_missing=0`，生成的
`boot.img` SHA256 为 `a28344f9...7cac`，已刷入设备 `boot_b` 并启动，
回读分区哈希与产物一致。

### 8. 真机运行验证

最终镜像启动后的实测（全部只读采集；F2FS 写入仅使用
`/data/local/tmp` 临时文件并删除）：

#### 8.1 内核、root 与模块

- `/proc/version`：`6.6.118-4k`（自编，dash@mikernel，clang r510928，构建 #29），
  活动槽位 `_b`；当前 `boot_b` SHA256 与 `out/artifacts/boot.img` 一致：
  `a28344f9296fb9796b2c8dc231812c59aa76770d069158897d1305dc55ab7cac`。
- KernelSU built-in：`su -v` = `4.2.0-rc3-81-gd5e9e025:KernelSU`，
  `ksud -V` = `4.2.0-rc3-81-gd5e9e025 (uapi: 6)`，`su -c id` 返回
  uid 0 / context `u:r:ksu:s0`；ReSukiSU manager 包
  `com.resukisu.resukisu` v4.2.0-rc3 已安装。
- SUSFS：`ksu_susfs show version` = `v2.3.0`；variant = `GKI`；
  `show enabled_features` 返回 SUS_PATH、SUS_MOUNT、SUS_KSTAT、SPOOF_UNAME、
  ENABLE_LOG、HIDE_KSU_SUSFS_SYMBOLS、SPOOF_CMDLINE_OR_BOOTCONFIG、
  OPEN_REDIRECT、SUS_MAP，共 9 项。
- 旧 `kernelsu` LKM 冲突：`/proc/modules` 中没有 `kernelsu`；启动日志有
  `ksuinit::init[1]: KernelSU may be already loaded in kernel, skip!`，
  说明 init_boot 的 KSU wrapper 检测到内建驱动后跳过 `kernelsu.ko`。
- `/proc/modules`：585 个。与 stock `lsmod` 的 585 个名字逐名比较，唯一差异是
  stock 的 `kernelsu` 被内建驱动替代，我方额外加载 `mkp`；其余 584 个 stock
  模块全部加载。
- 关键链：`node_cache`（refcnt 0，依赖 zsmalloc）、`os_cpu_qi`（refcnt 4，
  holders：`cpq`、`mi_reclaim`、`task_turbo`、`os_cpu_qs`）、`os_cpu_qs`、
  `vip_sched`、`task_turbo`、`zsmalloc` 均为 Live。
- 启动 dmesg：`node_cache module insmod success`、
  `node_cache module init success with f2fs path=/data`、
  `task_turbo_v_init ... task turbo hook done`。
- dmesg 错误扫描：`Unknown symbol` / `disagrees about version` /
  `invalid module format` / `vermagic` / `KCFI` / `CFI failure` /
  `brk #` / `Kernel BUG` / `Oops` / `Kernel panic` 均 0 条。
  日志中的 `Call trace` 来自 stock MTK `cmdq`、`cam_fs`、`btmtk` 的既有
  warning，不是本内核新增 panic。

#### 8.2 node_cache 与 QoS 数值

`node_cache` sysfs（`/sys/kernel/node_cache`，root 读取成功）：

```text
max_bytes=41943040  comp_enable=1  comp_ratio=50
reclaim_policy=0    avail_low_wmark_mb=500  shrink_wmark=75
stat:
  init 1 / live_instances 1 / total_ram_mb 15205 / lowmem_mode 0
  cur_cnt 5576 / cur_bytes 1803266 / swapin_cnt 185
  invalid_cnt 0 / shrink_cnt 0 / trace_enable 0
```

数值随启动时间变化；`cur_cnt`/`swapin_cnt` 非零说明压缩缓存层实际工作。
QoS sysfs 与 stock 行为一致：

```text
/sys/kernel/qos_inherit/inherit_enable = QI_ENABLE: 1
/sys/kernel/qos_sched/sched_enable     = QS_ENABLE: 1
/sys/kernel/qos_sched/rt_prio          = ui 98 / render 98
```

#### 8.3 F2FS / EROFS 与数据校验

- `/data` 实际以 F2FS 读写挂载（`dm-67`，478G，options 含 `atgc`、
  `age_extent_cache`、`inlinecrypt`、`checkpoint_merge` 等 stock 选项）。
- F2FS sysfs 属性可读：`en_iostat_enable=0`、`iostat_config` 默认
  `enabled=0 window_period_s=5 latency_threshold_ms=100`、
  `vip_file_enable=1`、`hybrid=0`、`hybrid_free_ratio=10`，window/daily
  输出格式正常。
- F2FS 增强 iostat 单开关已修复并实测（2026-10-30）：保持
  `iostat_enable=0`、只写 `en_iostat_enable=1`，写入 4MiB 后
  `iostat_window_latency` 记录 read=726、write_sync=169、write_async=240、
  meta=91；stock `io_lat` 仍只在 `iostat_enable=1` 时更新。剩余差异是 5 类
  聚合 vs stock 20 槽/per-CPU 布局，不是开关语义。
- F2FS fault report：`f2fs_fault_report` tracepoint 已加入并出现在
  `/sys/kernel/tracing/events/f2fs/`；`fault_report.ko` 启动日志不再报
  `tracepoint f2fs_fault_report not found`，`/proc/fault_report` 内容为 1。
  未做 F2FS 故障注入，实际错误路径未主动触发。
- F2FS 数据完整性：写入 16MiB 随机数据并 `conv=fsync`，`sync` 后
  `drop_caches`，回读 SHA256 完全一致（`985b6bd3...`），随后删除临时文件。
  未做 fsck 或断电测试。
- EROFS 实际挂载 `/`、`/vendor`、`/odm`、`/product`、`/vendor_dlkm` 等；
  sysfs `iostat_enable/iostat_config/iostat_window_period_s/
  iostat_latency_threshold_ms/iostat_window_latency/iostat_daily_latency`
  均存在且可读写。
- EROFS 冷缓存读取（drop_caches 后读 `/odm` 6MB 文件）产生
  `window count=4 bytes=16384`；2026-10-30 改为每 CPU 统计，sysfs 汇总，
  `iostat_config` 输出 `percpu=1`；stock 的 10/5 多桶布局仍未复刻。
- SELinux 始终保持 Enforcing；本次 root sysfs 读取成功，没有关闭 SELinux，
  没有修改文件上下文。性能/功耗和长时稳定性仍见 OPEN_ISSUES。


### 9. 实机启动与 AVB 踩坑总结

所有写入前均先拉取原分区，未触碰 `lk`、`boot_a` 或用户数据。完整分析见
[BOOT_PACKAGING.md](BOOT_PACKAGING.md)。

| 项 | 结果 |
|---|---|
| `fastboot boot` | bootloader 返回 `unknown command`，不支持 RAM 临时启动 |
| boot_a / boot_b / vbmeta_b 备份 | 64MB / 64MB / 8MB，SHA256 与交接包一致 |
| 首次写入：mkbootimg 紧凑自编 boot | 花屏 bootloop，完整 stock boot 恢复成功 |
| 对照：stock kernel + 64MB 零 padding、去 AVB 尾部 | 仍 bootloop，恢复成功 |
| 对照：stock boot + 修改 flags 的 vbmeta | bootloop；flags 改写破坏 OEM vbmeta 签名，恢复成功 |
| **最终：stock header/vbmeta/footer + 自编 kernel** | **成功开机并稳定运行** |
| 当前 boot_b | 与 `out/artifacts/boot.img` SHA256 完全一致 |

定位过程给出的硬结论：

1. boot header、4K page、LZ4 格式、内核 ARM64 header 都正确；不是内核入口格式
   问题。
2. 638 个 stock 模块的 `__versions` 共 36,947 条：其中 31,705 条对应本内核
   vmlinux 导出，逐项 CRC 0 差异；其余 5,242 条是模块间符号，由 stock 模块
   自身解析。`CONFIG_VENDOR_KO_COMPAT` 本身跳过 CRC 检查，所以这不是运行时
   CRC 验证；它说明的是静态符号/CRC 面没有明显漂移。
3. 失败镜像都丢失/破坏了原厂 AVB 元数据：mkbootimg 镜像没有转储尾部；零 padding
   镜像删除了 vbmeta/footer；改 flags 镜像破坏签名。
4. 保留原厂 vbmeta 字节和 AVB footer、只替换 kernel 后立即启动成功。说明本机
   隐藏解锁接受“OEM 签名元数据 + kernel hash 不匹配”的组合，但拒绝没有元数据或
   签名损坏的镜像。
5. LunarKernel zip 只包含裸 `Image`，由 AnyKernel/magiskboot 基于当前 stock boot
   重封并整分区写回，因此保留了同样的 OEM AVB 元数据。它能开机不是因为它有额外
   签名权限，也不是我们的内核有问题。

最终修正：`scripts/make-boot.sh` 改为调用 `scripts/repack-boot.py`，永远从 stock
64MB boot 继承 header、vbmeta 和 footer。不要再使用旧 mkbootimg 产物启动。

#### 9.1 当前分区状态与 init_boot 差异

2026-10-30 00:11 只读 `sha256sum` 实测：

| 分区 | 当前 SHA256 | 判断 |
|---|---|---|
| `boot_a` | `26a826db...311be6` | stock 备份（`out/device-backup/boot_a.img`） |
| `boot_b` | `a28344f9...7cac` | 本次成功镜像（#29），与 `out/artifacts/boot.img` 一致 |
| `vendor_boot_b` | `4e3c1bb4...8cffcf2` | 与交接包一致 |
| `dtbo_b` | `b0b093d7...38d5e5` | 与交接包一致 |
| `vbmeta_b` | `2c14b03d...e91e35` | 与交接包一致 |
| `init_boot_b` | `5bfcf159...086dee` | **与交接包 `22d86fe7...1ba9110` 不一致** |

`init_boot_b` 差异已解包核对：两者都是设备原有的 KernelSU patched init_boot，
都含 init wrapper、`kernelsu.ko`、`ksu_config=bundled=1`；当前镜像仅比交接包
少一个 41 字节的 `stock_image.sha1`（内容为 stock boot 的 SHA1）。本次会话只写
`boot_b`，没有执行 `init_boot` 写入；差异来自交接前的设备 root 工具状态或交接包
与设备现态不同步。当前 init_boot 副本已保存为
`out/device-backup/init_boot_b.current-kSU.img`。**不要把 init_boot 当 stock 原厂
镜像**；恢复仍使用 `out/device-backup/` 的 boot/vbmeta。

### 10. dash-droidspaces 上游检查（2026-10-29）

参考仓库 `lakitu12/kernel_dash_droidspaces` 在 2026-10-29 有更新；本节记录与本
交接有关的部分，不改变已交付镜像。

- `origin/main` 最新为 `6039943a9c1577044586fb90a132ca675eb88458`（2026-10-29
  19:53 +0800），`pushed_at=2026-10-29T14:44:52Z`。
- 关键 main 提交：`5448a6f` 13 个 hook 的真实调用点 + KCFI 原型；
  `885b1b2` 只在 CREATE_TRACE_POINTS pass 定义 `TRACE_INCLUDE_PATH`；
  `7fe006c` 用 kcrctab 钉 `mmap_lock_init/free` CRC；
  `41f923c` 改为在 declaration-only TU 导出这两个 hook（根因修复）；
  `6039943` 对应自检。另有 `OS4_HOOKS=off`、`NO_LZ4_EXPORT`、分组
  `HOOK_CALL_SITES` 等 CI 调试开关。
- 本仓库同步状态：`vendor-hooks/0001,0002,0004,0005,0007-0010` 与上游逐字节相同；
  `0006` 仅因本树 SUSFS 在 `fs/super.c` 插入了 include，调整了上下文位置。
  本镜像的两个 `__tracepoint_*` CRC 实测为 `0x615d194b` / `0xa301bcc9`，
  `os_cpu_qi` Live，无需 `patch-kcrctab.py` 后处理。
- 上游 README 仍写“full call site 会 bootloop”；本仓库的完整 13-hook + 全调用点
  镜像已实机稳定启动。上游后续又记录“没有任何 call site 也 bootloop”，说明其
  bootloop 更可能来自该仓库的 KSU/SUSFS 组合，而不是 hook 调用点；与本仓库
  BakaSU d5e9e025 + SUSFS 2.3.0 的结果不矛盾。
- 上游 `trusty-rescue`、`pid-max-clamp`、KSU/SUSFS pin 更新、DroidSpaces 容器
  配置（SYSVIPC/POSIX_MQUEUE/PID_NS/USER_NS/DEVTMPFS/IP_SET 等）不在本交接
  范围；本内核的 stock config 没有打开这些容器项。若要跑 DroidSpaces，需要另建
  变体并单独实机验证，不能把这个 stock 兼容内核直接当容器内核。
- 新出现的 `exp/ksu-*` 分支（bootwatchdog、diag-flash、diag-recorder、禁用
  SUS_MOUNT/SUS_PATH/nosusfs）是该仓库排查自身 KSU early hang 的诊断分支，未合入
  main。最新检查到 `exp/ksu-diag-recorder` `6b48e83`（2026-10-29 23:40 +0800）
  仍在记录“约 1.5s 崩溃”的黑盒日志；与本交付的 BakaSU 组合无关。

### 11. Stock parity 修复（2026-10-30）

#### 11.1 已补齐

- **F2FS iostat 单开关**：`__update_iostat_latency()` 现在分别判断 stock
  `iostat_enable` 与 Xiaomi `en_iostat_enable`；保持 `iostat_enable=0`、只开
  `en_iostat_enable=1` 时，4MiB 写入实测 read=726、write_sync=169、
  write_async=240、meta=91；stock `io_lat` 仍只在 `iostat_enable=1` 时更新。
- **F2FS fault report**：新增 `f2fs_fault_report` tracepoint，原型与 stock BTF
  一致；只在同步 `f2fs_handle_error()` 触发，避免回调在原子上下文
  `stack_trace_save()`/`queue_work()`。`fault_report.ko` 启动日志不再报
  `tracepoint f2fs_fault_report not found`，`/proc/fault_report` 已出现。
- 补丁 `0005-xiaomi-f2fs-features.patch` 已重新生成；`finalize.sh` 通过
  KCFI 13/13、638 模块 `hard_missing=0 weak_missing=0`。

#### 11.2 本次实机验证

- 构建 #29，`boot_b` SHA256：
  `a28344f9296fb9796b2c8dc231812c59aa76770d069158897d1305dc55ab7cac`。
- 585 个模块（586 包括 `lsmod` 表头）；`fault_report`、`node_cache`、
  `os_cpu_qi`、`vip_sched` 等加载正常；dmesg 无 KCFI/未知符号/panic。
- `persist.sys.stability.fault_report=true` 仍在；`/proc/fault_report` 内容为
  1。`/dev/sys/fs/by-name/userdata/fault_report_enable` 这个 F2FS sysfs 节点仍
  不存在，stock init 对它的写入仍失败；`/proc/fault_report` 的功能已恢复。
- F2FS 数据写入测试只使用 `/data/local/tmp` 临时文件并已删除；未做 fsck、
  断电、压力或故障注入。

#### 11.3 仍未补齐

- `hybrid=1` 仍 `-EOPNOTSUPP`；EROFS iostat 已 per-CPU，但仍是单 aggregate
  bucket，不是 stock 的 10/5 多桶布局。
- SCSI fastdiscard、UFS 官方 37 文件源仍未接入。
- 仍未做长时压力、suspend/resume、fsck/power-loss、性能/功耗 A/B。

### 12. F2FS lock / priority / VIP 实机验证（2026-10-30）

构建 #29 的验证结果：

- `max_lock_elapsed_time=500`、`adjust_lock_priority=0`、
  `lock_duration_priority=120`、`critical_task_priority=120` 默认值正确。
- 将 `adjust_lock_priority` 设为 cp_rwsem 位、`lock_duration_priority=110` 后，
  `f2fs_priority_uplift/restore` 成对出现，例如
  `comm=f2fs_ckpt-254:6 lock_name=cp_rwsem orig_prio=120 new_prio=110`；
  操作结束后恢复 `adjust_lock_priority=0`、`lock_duration_priority=120`。
- `max_lock_elapsed_time=0` 时 `f2fs_lock_elapsed_time` 记录 cp_rwsem/
  node_change 的实际等待时间（如 `total=60 running=0 runnable=60`），验证后
  恢复为 500ms。
- `gc_lock` 全部调用点接入 trace wrapper 后，用 `F2FS_IOC_GARBAGE_COLLECT`
  在 nice 10 的进程里触发 foreground GC（`adjust_lock_priority` 只开 GC 位、
  `max_lock_elapsed_time=0`）。tracefs 记录
  `f2fs_priority_uplift: lock_name=gc_lock lock_type=wlock orig_prio=130
  new_prio=120`、配对的 `f2fs_priority_restore`，以及
  `f2fs_lock_elapsed_time: lock_name=gc_lock lock_type=wlock total=3`。
  测试后恢复 `adjust_lock_priority=0`、`max_lock_elapsed_time=500`，并删除
  临时 ioctl 程序。
- VIP：`vip_file_enable=1`、`vip_inode_count` 初始非零；negative-nice 进程写
  打开使计数增加，普通 nice 写打开不增加，删除文件后计数减少；关闭
  `vip_file_enable` 清零，重新打开后只在新 high-priority 写打开时增加。
- 测试只使用 `/data/local/tmp` 临时文件并已删除；tracefs 事件和
  `adjust_lock_priority` 已恢复；未做长时压力或 suspend/resume。


### 13. stock core tracepoint / dynamic task_struct（2026-10-30，构建 #29）

- 从 clean AOSP 重新应用 `0000`–`0007` 和 vendor-hooks 系列，构建 #29：
  0 error / 0 warning；KCFI 13/13，638 个 stock 模块
  `hard_missing=0 weak_missing=0`。
- 以 stock `stock.kallsyms` 中非模块行（无 `[module]` 后缀）的
  `__traceiter_*` 为集合，当前 `System.map` 与 stock 均为 **1860** 个，
  missing=0、extra=0。
- `0007-stock-parity-hooks.patch` 回移 51 个 hook：其中 44 个带调用点
  （block/MM/CMA/folio/swap/readahead、scheduler/dtrace、fuse、madvise 等）；
  剩余 7 个在 0007 中保持上游的声明/导出状态，随后由
  `0008-mmc-dma-hook-callsites.patch` 和 `0009-lazy-resched-hooks.patch`
  补上 MMC attach/reset/cd、sdhci、dma-heap 和
  `restore_curr_resched` 调用点。
- `lz4_decompress_start/end` 按 stock BTF 的字段
  （`inputsize/outputsize/ret/bypass`，均为 int）在 EROFS LZ4 解压路径实现。
  实机 drop_caches 后读取 `/product/app/AiasstVision/AiasstVision.apk`，
  tracefs 记录到成对的 start/end，例如
  `inputsize=4096 outputsize=4675 ret=4675 bypass=0`。
- F2FS fault report：同步 `f2fs_handle_error()` 和 task context 的
  `f2fs_handle_error_async()` 都触发；原子 end_io 由 `in_task()` 过滤。
- UFS 官方源码编译探针：`ufs-mediatek.c` 可在 6.6.118 头文件下编译，
  modpost 缺 sibling/vendor 符号（`ufs_mtk_init_sysfs`、`ufs_mb_init` 等），
  证明它是 device_modules 模块形态，不能单文件替换。
- GKI dynamic task_struct：新增
  `CONFIG_GKI_DYNAMIC_TASK_STRUCT_SIZE=y`、
  `CONFIG_GKI_TASK_STRUCT_VENDOR_SIZE_MAX=1024`、
  `arch_task_struct_size`、`vendor_data_pad`（GPL 导出）和
  `android_arch_task_struct_size=` early param。未传参数时
  `task_struct` BTF 仍为 4800B/217 成员，与 stock 一致；`/proc/kallsyms`
  可见 `arch_task_struct_size` 和 `vendor_data_pad`。
- `/proc/iostat_enhance` 经 stock `io_monitor.ko` 复核并不存在；实际节点是
  `/proc/io_monitor/iostat/iostat_enabled`，本机构建中 `io_monitor` 已加载且
  节点可读。该项从缺口清单移除。
- EROFS iostat 改为每 CPU 统计（`alloc_percpu`，显示时汇总），
  `iostat_config` 输出 `percpu=1`。实机 drop_caches 后读取
  `/product/app/AiasstVision/AiasstVision.apk`，window/daily 均记录到
  `count>=1 bytes>=4096`。与 stock 的剩余差异是多槽/多阈值布局。

---

<a id="src-04"></a>
## 4. 未覆盖项、风险与上游同步评估

> 来源：[`docs/kernel/OPEN_ISSUES.md`](OPEN_ISSUES.md) · 14300 字节 · SHA256 `b9e6d4ccf065c67aac1993ef13df5c489cffb9959d99955ff3fd39d2a058559c`
> 类别：当前交付 · 状态：当前交付（优先相信）

### 优先级 0：启动与封装

1. **boot 封装已解决，但必须继续遵守约束。** 已实测成功的方式是从 stock 64MB
   boot 继承 header、OEM vbmeta 和 AVB footer，只替换 kernel；详见
   [BOOT_PACKAGING.md](BOOT_PACKAGING.md)。不要再使用旧 mkbootimg 镜像、短镜像、
   清零 AVB 尾部的镜像，或改 `--disable-verity/--disable-verification` 的 vbmeta。
   这些均已实测 bootloop。
2. **本机隐藏解锁的启动语义。** `fastboot getvar unlocked=yes`，但系统属性仍是
   `vbmeta.device_state=locked`、`verifiedbootstate=green`、`flash.locked=1`。
   它接受保留 OEM 签名 vbmeta/footer、但 boot hash 不匹配的镜像，拒绝缺失或签名
   损坏的元数据。不要把该行为当成通用 AVB 绕过。
3. **运行时已初步通过。** 完整 hooks/功能构建成功启动：
   - `6.6.118-4k`，KernelSU built-in v4.2.0-rc3，SUSFS 2.3.0；
   - 584 个 stock 非 LKM 模块全部加载，`node_cache`、`os_cpu_qi` 及 QoS 依赖链
     正常；stock `kernelsu` LKM 被内建替换，没有双加载；
   - 启动日志无 KCFI `brk`、未知符号、CRC/vermagic 拒载。
   仍需长时运行、压力、suspend/resume 和具体功能行为验证。
4. **sysfs 数值已补采（2026-10-29 晚）。** root（KSU 域）已成功读取
   node_cache/QoS/F2FS/EROFS 数值，系统始终保持 Enforcing，没有关闭 SELinux；
   具体值见 `TEST_REPORT.md` §8。此前读失败是权限/上下文问题，不是节点未注册。
5. **恢复资产。** 完整 `boot_a`、`boot_b`、`vbmeta_b`、`oops` 备份和当前
   KSU init_boot 副本在 `out/device-backup/`；任何时候不要写 `lk`、`super` 或
   用户数据。恢复 boot 必须使用完整 64MB 分区镜像。
6. **init_boot 不是 stock。** 当前 `init_boot_b` 与交接包一致地带有 KernelSU
   init wrapper/`kernelsu.ko`，但当前比交接包少一个 `stock_image.sha1`（仅 41B）。
   本次未写 init_boot；不要把该分区当原厂恢复源，恢复用 `out/device-backup/`。

#### hooks 分组测试（未来改动时）

本次完整 13-hook 系列已成功启动，不再需要先证明“能否开机”。以后若 hooks 或
调用点变更后出现异常，可按以下组回退定位：

```text
vendor-hooks/0004  remove_mapping / remove_mapping_failed
vendor-hooks/0005  filemap_get_folio_end
vendor-hooks/0006  put_super
vendor-hooks/0007  fuse_request_end_ext / fetch
vendor-hooks/0008  mmap_lock_init / free
vendor-hooks/0009  percpu_rwsem_init
vendor-hooks/0010  rcu_boost_* / sync_rcu_wait_*
```

#### 启动后采集命令

```bash
adb shell su -c 'uname -a; cat /proc/version; getprop ro.boot.slot_suffix'
adb shell su -c 'cat /proc/modules | grep -E "node_cache|os_cpu_qi|zsmalloc"'
adb shell su -c 'find /sys/kernel/node_cache -maxdepth 1 -type f -exec sh -c "echo {}; cat {}" \;'
adb shell su -c 'cat /sys/kernel/qos_inherit/inherit_enable; cat /sys/kernel/qos_sched/sched_enable; cat /sys/kernel/qos_sched/rt_prio'
```

这些命令已在 2026-10-29 晚用 root 实际执行成功（node_cache/QoS 数值见
`TEST_REPORT.md` §8），不需要关闭 SELinux。若换 manager/域后读不到，再用有权限的
调试域，不能为此关闭用户数据保护。

### 优先级 1：功能未完全等价

#### Hybrid UFS

这是最大的行为缺口。`CONFIG_F2FS_FS_HYBRID_UFS` 和 `CONFIG_BLOCK_HYBRID_UFS`
已启用，sysfs/挂载参数/函数接口存在，但 `f2fs_hw_support_hybrid()` 固定为
`false`，`hybrid=1` 返回 `-EOPNOTSUPP`。没有 AOSP 可用的配对 ext LUN 和 block
hybrid allocator，伪造映射有写错介质风险。

后续路径：从 stock 内核反汇编/恢复 `device_hybrid_capable`、die 分区发现和
GC 分配策略；在具备双区域 UFS 的设备上做只读验证和故障注入，才可启用。
在实现前不要声称与 stock hybrid 等价。

#### VIP file

`vip_file_enable`、排序 manager 和 `f2fs_vip_bsearch/insert/remove` 已实现。
2026-10-30 增加了 `android_vh_f2fs_is_hiprio_task`/`is_usr_task` hook 调用；
当前没有 stock 模块注册这两个 hook，因此使用保守 fallback：有用户地址空间的
RT 或 negative-nice 任务以写方式打开普通文件时调用 `f2fs_vip_insert`，inode
删除/evict 时移除；fallback 管理器上限 8192 个 inode。
真机验证：high-priority 写打开使 `vip_inode_count` 增加，普通写不增加，删除
减少，关闭 `vip_file_enable` 清零。`vip_inode_count` 是调试属性，不是 stock ABI。
与 stock 的差异是 fallback 选择策略和 manager 布局（stock 在 `f2fs_nm_info`，
当前在 `f2fs_sb_info`），不是接口不可用。

#### F2FS lock / priority

已移植 stock/上游 `fs/f2fs/lock.c`：`f2fs_lock_context`、
`f2fs_lock_elapsed_time`、`f2fs_priority_uplift/restore`、
`max_lock_elapsed_time`/`adjust_lock_priority`/`lock_duration_priority`/
`critical_task_priority`。默认 `adjust_lock_priority=0`，不改变任务优先级。
真机实测：开启 cp_rwsem bit 后，`f2fs_priority_uplift/restore` 对
`cp_rwsem` 的 orig/new prio 120/110 成对出现；`f2fs_lock_elapsed_time` 在
threshold=0 时记录 cp_rwsem/node_change 的等待时间；删除临时文件后设置复原。
2026-10-30 已把剩余 `gc_lock` 调用点全部接入 trace wrapper：GC 线程、前台
GC ioctl、balance_fs、checkpoint、discard/trim、disable/enable checkpoint 和
resize 路径均使用 `f2fs_*_trace()`；真机用 foreground GC ioctl 验证
`gc_lock` 的 uplift 130→120、restore 和 elapsed 事件。

#### F2FS iostat

sysfs 名称和 window/daily/阈值语义存在，但输出格式与内部布局不是 stock 的逐字
复制；统计来自正常 F2FS bio 完成路径，而非原厂 percpu 20 槽实现。性能开销
低于原厂完整采样，但窗口边界和分类粒度不完全相同。

**单开关语义已修复（2026-10-30）**：`__update_iostat_latency()` 现在分别判断
stock `iostat_enable` 和 Xiaomi `en_iostat_enable`；只开
`en_iostat_enable=1`、保持 `iostat_enable=0` 时，4MiB 写入已实测记录
read/write_sync/write_async/meta 计数，stock `io_lat` 仍只在
`iostat_enable=1` 时更新。剩余差异是 5 类聚合 vs stock 20 槽/per-CPU 布局，
不是开关语义。

#### F2FS fault report

`f2fs_fault_report` tracepoint 已补，原型与 stock BTF 一致；
`fault_report.ko` 启动日志不再报 `tracepoint ... not found`，`/proc/fault_report`
已出现。同步 `f2fs_handle_error()` 和 task context 的
`f2fs_handle_error_async()` 都会触发；原子 end_io 路径由 `in_task()` 过滤，
避免回调在原子上下文做 `stack_trace_save()`/`queue_work()`。
`f2fs_stop_checkpoint()` 等路径未额外上报，F2FS 实际故障注入/长时验证仍未做。

#### EROFS iostat

已覆盖 `read_folio`/`readahead` 的正常读路径，2026-10-30 改为 **每 CPU**
统计（`alloc_percpu`，sysfs 汇总各 CPU），不再用全局锁聚合一整棵挂载点。
剩余差异是 stock 的 10 个 window 槽/10 个 abnormal 槽/5 个 daily 槽和 5 档阈值
没有逐桶复刻；当前每 CPU 一个 aggregate bucket，`iostat_config` 输出
`percpu=1`。2026-10-30 实测 drop_caches 后读取 `/product/.../AiasstVision.apk`，
window/daily 均记录 `count>=1 bytes>=4096`；缓存命中不重复计数是预期行为。

#### `MEMFD_ASHMEM_SHIM`

AOSP 6.6.118 自带实现，已启用；没有移植 MiCode 6.6.89 的重复版本。缺少
Android 上层 `libmemfd`/ashmem 用户态回归测试。

#### UFS 官方源码

包内 37 个 MTK UFS 文件保留为参考，没有整体替换 AOSP UFS 核心。替换会扩大启动
风险，且当前任务的可选优先级低于已验证的 GKI 构建。后续如需官方 UFS，应单独
做厂商 UFS 驱动/设备树/初始化链路测试。

#### lz4kd/zram

未加入。没有把“注册算法”包装成“delta zram 实际调用”。后续需要先确认 stock
zram 的 `system_dlkm/zram.ko` 加载位置和压缩后端 ABI。

#### 仍缺的 stock-only 实现（2026-10-30 复核）

- **stock core tracepoint 已对齐**：当前 `__traceiter_*` 与 stock 均为 1860 个，
  差集为 0。补丁 `0007-stock-parity-hooks.patch` 从 AOSP
  `android15-6.6-2026-10_r2` 回移了 51 个缺失 hook，其中 44 个同时回移调用点；
  剩余 7 个 export-only hook 已在 `0008`/`0009` 补上调用点
  （MMC/DMA/lazy resched），当前所有目标 hook 都有调用点。
  2 个 LZ4 事件按 stock BTF 字段在 EROFS LZ4 解压路径实现，已实测触发。
  这些 hook 默认无注册者，回调路径需要厂商模块主动注册；本构建只保证事件/
  符号/调用点与 stock 形状一致。
- **SCSI fastdiscard 未实现**：stock 有 `CONFIG_SCSI_DISCARD` /
  `CONFIG_SCSI_FASTDISCARD`，AOSP 树和当前构建没有；只剩通用 `sd` discard。
  BTF/字符串证据表明确实是多 descriptor UNMAP 的 `xiaomi_fastdiscard_info`
  路径，但公开源码没有实现；详见
  [UFS_HYBRID_EVIDENCE.md](UFS_HYBRID_EVIDENCE.md)。`persist.sys.stability.fastdiscard`
  目前为空，默认不触发；在没有私有源码和有效属性前不伪造“fastdiscard 已启用”。
- **GKI dynamic task_struct 已实现**：`CONFIG_GKI_DYNAMIC_TASK_STRUCT_SIZE=y`、
  `GKI_TASK_STRUCT_VENDOR_SIZE_MAX=1024`；新增 `arch_task_struct_size`、
  `vendor_data_pad`（GPL 导出）和 `android_arch_task_struct_size=` early param。
  未传参数时大小为 4800B/217 成员，与 stock BTF 一致；传参时按页对齐扩大
  task_struct slab 的分配大小。
- **UFS 内核侧未替换**：`ufs_mediatek_mod_ise` 仍是 stock 模块，AOSP
  UFS/SCSI core 不是原厂 37 文件源。2026-10-30 复核：stock vmlinux 和
  `ufs-mediatek-mod-ise.ko` 的字符串都只有 `monitor`，当前
  `/sys/devices/.../monitor/monitor_enable` 与模块自身一致；只有
  `vendor_file_contexts` 里的 `/ufs_monitor` 路径，未找到对应的内核节点或写入者。
  因此不再把“monitor 路径不一致”列为已确认缺口；仍需 UFS 官方 core 的独立
  变体做 A/B。
- **`/proc/iostat_enhance` 不是 dash 的 stock ABI**：stock 的 `io_monitor.ko`
  实际创建 `/proc/io_monitor/...`，iostat 开关在
  `/proc/io_monitor/iostat/iostat_enabled`；本机模块已加载且这些节点存在。
  之前文档中的 `/proc/iostat_enhance/enable` 是误记，不再作为缺口。
- **`MODULE_SCMVERSION`/`LOCALVERSION_AUTO`**：当前为可复现构建关闭
  `LOCALVERSION_AUTO`，因此 `MODULE_SCMVERSION` 及 `/sys/module/*/scmversion`
  缺失；只影响版本元数据，不影响运行时逻辑。

完整核对表见 [STOCK_PARITY_AUDIT.md](STOCK_PARITY_AUDIT.md)。

### 优先级 2：验证缺口

- **KCFI 运行时**：13/13 静态哈希已校验；完整 hooks 镜像已实机启动且没有出现
  `brk #0x8228`。仍需在压力、suspend/resume、异常进程退出等路径持续观察。
- **模块签名/CRC**：`CONFIG_VENDOR_KO_COMPAT` 跳过检查，模块能加载不等于签名
  有效；这是有意降低的安全边界。
- **BakaSU/SUSFS**：内建 KernelSU v4.2.0-rc3、`su`、ReSukiSU manager 包和
  `ksu_susfs show version=v2.3.0`、9 项 enabled_features 已确认；SUSFS 各隐藏项
  的实际效果、双 manager 场景和长时间行为未逐项验证。
- **F2FS/EROFS 数据**：系统正常挂载并运行；F2FS 已做 16MiB 随机数据写入、
  `fsync`、drop_caches 后回读 SHA256 一致；EROFS 已做冷缓存读计数。仍未做
  fsck、写入压力、power-loss 或故障注入。
- **boot/AVB**：最终 64MB boot 保留 OEM vbmeta/footer，已实机启动。`fastboot boot`
  不可用；boot 的 kernel hash 与 OEM vbmeta 描述不一致，依赖本机隐藏解锁接受该
  组合。其它设备或更严格 bootloader 不保证可用；不要在没有恢复方案时写 `lk`。
- **性能/功耗**：没有 A/B 数据，不能对 zram、node_cache、QoS、启动时延作收益
  声明。
- **SELinux**：系统保持 Enforcing；本次 root 读取 sysfs 成功，没有关闭 SELinux
  或修改上下文。`setenforce 0` 等降级策略仍不应为取证而使用。

### 优先级 3：dash-droidspaces 上游同步（2026-10-29）

- 上游 `origin/main` 到 `6039943a9c15`；与本交接相关的 13-hook 补丁已同步：
  `0001/0002/0004/0005/0007-0010` 逐字节相同，`0006` 仅为本树 SUSFS include
  调整上下文。
- `41f923c` 的 root cause 修复（把 `mmap_lock_init/free` 的 EXPORT 放到
  declaration-only TU，使 genksyms CRC 与 stock 一致）已在本仓库 `0002` 中；
  本镜像 CRC 实测 `0x615d194b`/`0xa301bcc9`，`os_cpu_qi` 正常加载，未使用
  `patch-kcrctab.py` 后处理。
- 上游新增的 `OS4_HOOKS=off`、`NO_LZ4_EXPORT`、分组 `HOOK_CALL_SITES` 是它自己
  的 CI/单变量调试开关，本仓库未引入（本交付走完整 13-hook 镜像）。
- 上游 `trusty-rescue`、`pid-max-clamp`、KSU/SUSFS pin 更新和 DroidSpaces 容器
  配置（SYSVIPC、POSIX_MQUEUE、PID_NS、USER_NS、DEVTMPFS、IP_SET 等）未合入；
  本内核基于 stock config，没有这些容器项。若目标是跑 DroidSpaces，需要单独
  变体并实机验证，不能直接使用本内核。
- 上游 README 的 “full call site bootloop” 与本仓库实测不冲突：本仓库完整
  hooks + 全调用点已稳定启动；其后续实验也显示无调用点仍 bootloop，问题更可能
  在该仓库的 KSU/SUSFS 组合（`exp/ksu-*` 分支正在排查），不是 hook 原型。
  最新 `exp/ksu-diag-recorder`（`6b48e83`，2026-10-29 23:40）仍记录约 1.5s 崩溃，
  与本仓库 BakaSU 结果不同。

### 已知安全注意事项

1. 关闭模块签名/vermagic/CRC/protected-export 检查会允许任意匹配架构的模块
   加载；仅用于自有、已解锁设备。
2. 内核包含 BakaSU/SUSFS，会改变 root 与隐藏行为；不要用于不受控设备。
3. `abi_symbollist.raw` 保留 stock 导出名，构建产物仍不是原厂签名内核。
4. `out/baseline-6.6.118/` 是旧式 mkbootimg 对照内核，**不是 stock 备份且不可
   启动**；恢复请使用 `out/device-backup/` 的完整原厂 boot/vbmeta。

---

<a id="src-05"></a>
## 5. 实现路径、与 stock 的差异和回退

> 来源：[`docs/kernel/DESIGN.md`](DESIGN.md) · 12233 字节 · SHA256 `8d02e10fe07b4935eda375f2c457c886428b8096aa4b5c11602737bba41f25be`
> 类别：当前交付 · 状态：当前交付（优先相信）

### 1. 基线与交付边界

- 设备：`dash` / REDMI Turbo 5 Max / MT6991，stock
  `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`。
- AOSP 基线：`android15-6.6-2026-01_r1`，peeled commit
  `f9c84f40b6ba6152b6f51daba0193c9564af4172`（`SUBLEVEL=118`）。
- 工具链：AOSP `clang-r510928`。
- 配置起点：[stock.config](../../dash/configs/stock.config)，不是 `gki_defconfig`。
- 页面大小 4K；保留 `CFI_CLANG`、`SHADOW_CALL_STACK`、`MODVERSIONS`、
  `MODULE_SIG_PROTECT`、`LTO_NONE` 和 `TRIM_UNUSED_KSYMS`。
- 交付物不写 `lk`、`super` 或用户数据；实机测试只使用 `boot_b`，并在写入前备份
  完整 boot/vbmeta 分区。默认仍应优先无写入验证，任何刷机由设备所有者决定。

### 2. 补丁系列

[patches/series](../../dash/patches/series) 是唯一应用顺序：

| 补丁 | 内容 |
|---|---|
| `0000-tools-libbpf-const-strchr.patch` | 6.6.118 host `libbpf` 与 r510928 的 `const` 诊断修复，只影响构建主机 |
| `0001-vendor-ko-compat.patch` | 跳过厂商 `.ko` 的签名、vermagic、CRC、namespace 和 GKI protected-export 检查 |
| `0002-bakasu-integration.patch` | BakaSU 内建接入 |
| `0003-susfs-gki-android15-6.6.patch` | SUSFS inline 支持，已适配 6.6.118 |
| `0004-susfs-bakasu-hooks.patch` | BakaSU `ksu_handle_sys_read` 三参数适配 |
| `0005-xiaomi-f2fs-features.patch` | 增强 iostat、fault report、lock/priority、VIP manager、hybrid UFS 接口、block Kconfig |
| `0006-xiaomi-erofs-iostat.patch` | EROFS 每 CPU iostat 与 sysfs |
| `0007-stock-parity-hooks.patch` | 51 个 stock-only hook、44 个调用点、2 个 LZ4 事件、GKI dynamic task_struct |
| `0008-mmc-dma-hook-callsites.patch` | MMC attach/reset/cd、sdhci get_cd、dma-heap alloc latency 调用点 |
| `0009-lazy-resched-hooks.patch` | `restore_curr_resched` 的 arm64 lazy-resched 调用点 |
| `vendor-hooks/0001..0010` | node_cache/os_cpu_qi 需要的 13 个 `android_vh_*` hooks、导出和调用点 |

`susfs.c`、`susfs.h`、`susfs_def.h` 由 `scripts/apply-patches.sh` 从
`patches/susfs/` 安装；BakaSU 以固定提交的本地符号链接接入，不复制上游历史。

### 3. 厂商模块与 trace hooks

stock 的 638 个模块作为一个整体检查。它们需要 13 个 AOSP 6.6 基线没有的
tracepoint：

- `node_cache`：`remove_mapping`、`remove_mapping_failed`、
  `filemap_get_folio_end`、`put_super`；另使用基线已有的
  `android_vh_do_new_mount_fc`。
- `os_cpu_qi`：`fuse_request_end_ext`、`fuse_request_fetch`、
  `mmap_lock_init`、`mmap_lock_free`、`percpu_rwsem_init`、
  `rcu_boost_start`、`rcu_boost_end`、`sync_rcu_wait_start`、
  `sync_rcu_wait_end`。

实现采用 `include/trace/hooks/dash_os4_stub.h` 的 `DECLARE_HOOK`，在
`vendor_hooks.c` 中定义并导出。`mmap_lock_init/free` 的 `EXPORT_TRACEPOINT_SYMBOL_GPL`
单独放在只声明、不定义 tracepoint 的
`drivers/android/dash_os4_decl_exports.c`，以复现 stock 的 modversion CRC。
13 个原型均写入编译期 extern 原型 pin，构建后用
`scripts/verify-os4-kcfi.py` 对 `__traceiter_*` 的实际 KCFI 立即数逐项核对。

调用点参考 `dash-droidspaces` 的 OS4 hooks 系列（固定到本地 submodule 的
`6039943`）。本次完整调用点系列已随最终镜像实机启动成功，`os_cpu_qi` 整条 QoS
依赖链和 `node_cache` 均加载，启动日志无 KCFI `brk`、未知符号或 CRC/vermagic
拒载。参考仓库记录的历史 bootloop 未在本机构建中复现；如未来改动调用点后异常，
仍按 [OPEN_ISSUES.md](OPEN_ISSUES.md) 的分组方式回退。

#### stock core tracepoint / dynamic task_struct

`0007-stock-parity-hooks.patch` 以 AOSP `android15-6.6-2026-10_r2` 为参考，
回移 stock 6.6.118 有、2026-01 AOSP 没有的 51 个 hook，并回移其中 44 个的
调用点。`dma_heap_buffer_alloc_lat_*`、`mmc_*`/`sdhci_get_cd`、
`restore_curr_resched` 在上游只有声明/导出，保持相同的“事件可用、无内核调用点”
状态。`lz4_decompress_start/end` 没有公开源码，按 stock BTF 的
`inputsize/outputsize/ret/bypass` 字段在 EROFS LZ4 解压路径实现；它记录的是
EROFS 解压，不宣称覆盖所有 LZ4 使用点。

GKI dynamic task_struct 按 AOSP/OnePlus 公开实现接入：
`CONFIG_GKI_DYNAMIC_TASK_STRUCT_SIZE` 选择
`ARCH_WANTS_DYNAMIC_TASK_STRUCT`，`arch_task_struct_size` 默认等于
`sizeof(struct task_struct)`，`android_arch_task_struct_size=` early param
可把 slab 分配扩大到 `GKI_TASK_STRUCT_VENDOR_SIZE_MAX=1024`，并导出
`vendor_data_pad`。不传参数时 `task_struct` 布局与 stock 相同（4800B）。

### 4. BakaSU 与 SUSFS

- 内建 `CONFIG_KSU=y`、`CONFIG_KSU_MULTI_MANAGER_SUPPORT=y`。
- `CONFIG_KSU_SUSFS=y`，关闭 tracepoint/manual hook，使用 inline hook。
- `0001` 的 `CONFIG_VENDOR_KO_COMPAT` 只放宽模块加载校验，不伪造缺失符号；
  未知符号仍会导致加载失败。
- 安全影响：模块签名/CRC/vermagic/protected-export 检查被关闭，仅适用于已解锁的
  自有设备。`MODULE_SIG_PROTECT=y` 本身保留，以便随时关闭兼容开关回到严格模式。

### 5. memfd ashmem shim

交接说明假设需要从 MiCode 6.6.89 移植，但 AOSP 6.6.118 树已经包含：

- `mm/memfd-ashmem-shim.c`
- `mm/memfd-ashmem-shim.h`
- `mm/memfd-ashmem-shim-internal.h`
- `mm/shmem.c` 中的两个 hook
- `mm/Kconfig`、`mm/Makefile` 和 arm64 GKI defconfig 的配置

因此没有新增重复实现，只启用 `CONFIG_MEMFD_ASHMEM_SHIM=y`。这避免双份 ioctl
和 shmem 逻辑，兼容性风险低于强行移植 6.6.89 版本。

### 6. Xiaomi F2FS 功能

公开源中没有找到与 stock 二进制逐行一致的原厂实现，因此采用行为级等价实现，
并在 sysfs 名称上保持 stock ABI 可发现性。代码在
`fs/f2fs/xiaomi.c`、`fs/f2fs/xiaomi.h`。

#### 增强 iostat

- `CONFIG_XIAOMI_ENHANCED_IOSTAT=y`，依赖现有 `CONFIG_F2FS_IOSTAT=y`。
- 复用已有 `f2fs_iostat` / `f2fs_iostat_latency` tracepoints；不重复定义事件。
- 在 `iostat.c` 的 bio 完成延迟路径追加聚合，按 read / write_sync /
  write_async / meta 分类统计 window、daily、超阈值次数。
- 新增 sysfs：`en_iostat_enable`、`iostat_config`、
  `iostat_window_period_s`、`iostat_latency_threshold_ms`、
  `iostat_window_latency`、`iostat_daily_latency`。
- 和 stock 的差异：stock 有 20 槽窗口和按 10 档粒度/设备 percpu 的布局；本实现
  按文件系统做 5 类聚合，输出值语义一致但不保证逐字节输出格式相同。没有原厂
  percpu 内存开销，统计精度和窗口语义略有差异。
- 实测开关语义（2026-10-30 修正）：`__update_iostat_latency()` 现在分别判断
  `iostat_enable` 和 `en_iostat_enable`。stock MIUI init 的
  `iostat_enable=0, en_iostat_enable=1` 组合已实测能记录
  read/write_sync/write_async/meta；stock `io_lat` 仍只在 `iostat_enable=1`
  时更新。剩余差异仍是 5 类聚合 vs stock 20 槽/per-CPU 布局。

#### F2FS fault report

- 新增 `include/trace/events/f2fs.h` 中的 `f2fs_fault_report` tracepoint，原型
  与 stock BTF 一致：`(struct super_block *sb, unsigned int err_code,
  const char *function, unsigned int line)`。
- 在同步错误路径 `f2fs_handle_error()` 触发；没有放在
  `f2fs_handle_error_async()`/`f2fs_stop_checkpoint()`，因为 `fault_report.ko`
  的回调会 `stack_trace_save()`/`queue_work()`，不适合原子上下文。
- `fault_report.ko` 通过 `for_each_kernel_tracepoint()` 找到事件，启动日志不再
  报 `tracepoint f2fs_fault_report not found`，`/proc/fault_report` 已出现。

#### F2FS lock / priority

- 移植了 stock/上游的 `fs/f2fs/lock.c`：`f2fs_lock_context`、`f2fs_time_stat`、
  `f2fs_rwsem.sbi/name`、`f2fs_down_read_trace()`/`f2fs_up_read_trace()` 等。
- 新增 stock 原型 tracepoint：`f2fs_lock_elapsed_time`、
  `f2fs_priority_uplift`、`f2fs_priority_restore`；事件字段与 stock BTF 一致。
- sysfs：`max_lock_elapsed_time`（默认 500ms）、`adjust_lock_priority`
  （默认 0，bitmask）、`lock_duration_priority`（默认 120）、
  `critical_task_priority`（默认 120）。
- 默认不改变任务优先级；打开 `adjust_lock_priority` 后，在指定锁的临界区把
  非 RT 任务提升到 `lock_duration_priority`，解锁时恢复，并发出
  uplift/restore。`f2fs_lock_elapsed_time` 只在事件启用且超过阈值时记录。
- 2026-10-30 真机已验证 cp_rwsem 的 uplift/restore（120→110）、
  cp_rwsem/node_change 的 elapsed 事件，以及 foreground GC 的 `gc_lock`
  uplift/restore 和 elapsed 事件；tracefs 和 sysfs 已复原。
- `gc_lock` 的全部调用点（GC 线程、前台 GC ioctl、balance_fs、checkpoint、
  discard/trim、disable/enable checkpoint、resize）均已接入 trace wrapper。

#### VIP file

- `CONFIG_F2FS_VIP_FILE=y`，实现排序 inode 管理器：
  `f2fs_vip_bsearch`、`f2fs_vip_insert`、`f2fs_vip_remove`，并暴露
  `vip_file_enable`；增加只读调试计数 `vip_inode_count`。
- 选择策略：调用 stock 的 `android_vh_f2fs_is_hiprio_task` 和
  `android_vh_f2fs_is_usr_task` hook；没有模块注册时，fallback 为“有用户地址空间的 RT 或 negative-nice 任务以
  写方式打开普通文件”，manager 上限 8192 个 inode；删除/evict 时移除。
- 与 stock 的差异：fallback 是行为级策略，manager 布局在 `f2fs_sb_info`
  而非 stock 的 `f2fs_nm_info`；`vip_inode_count` 是额外调试 ABI。
- 真机已验证：high-priority 写打开使计数增加、普通写不增加、删除减少、
  关闭开关清零、重新打开后恢复选择。

#### Hybrid UFS

- `CONFIG_F2FS_FS_HYBRID_UFS=y` + `CONFIG_BLOCK_HYBRID_UFS=y`。
- 暴露 `hybrid`、`hybrid_free_ratio`、`hybrid_die_info`，提供
  `f2fs_hw_support_hybrid()` / `f2fs_hw_hybrid_get_avail()` 和
  `hybrid=%u` 挂载参数。
- 关键取舍：AOSP GKI 没有配对 ext LUN 的 block hybrid allocator。缺少该硬件契约
  时伪造地址映射可能导致写错介质。因此能力查询明确返回 false，`hybrid=1` 返回
  `-EOPNOTSUPP`，分配始终走原始单设备路径。`hybrid=0` 和 sysfs 只读接口可正常工作。
  这是安全回退，不是原厂双区域分配。

### 7. EROFS iostat

- `CONFIG_XIAOMI_EROFS_IOSTAT=y`。
- 在 `erofs_read_folio()` 和 `erofs_readahead()` 的实际读路径记录耗时、字节数、
  peak/avg、超阈值次数。
- 同时提供 `iostat_enable`、`iostat_config`、`iostat_window_period_s`、
  `iostat_latency_threshold_ms`、`iostat_window_latency`、
  `iostat_daily_latency`。
- 2026-10-30 改为每 CPU 统计（`alloc_percpu`），sysfs 汇总各 CPU；与原厂
  剩余差异是原厂有 10 个 window 槽/10 个 abnormal 槽/5 个 daily 槽和 5 档阈值，
  本实现每 CPU 只有一个 aggregate bucket，`iostat_config` 输出 `percpu=1`。
  只统计 EROFS 读路径，不虚报压缩解压线程细分。

### 8. UFS 与 lz4kd

- UFS：包内官方 MTK UFS 源保留为参考，但本次没有把 37 个文件整体替换进 AOSP
  核心。原因：stock 的 UFS 初始化被 bootloader/内核命令行 blacklist，且替换核心
  UFS 会扩大启动风险；本任务的可选优先级低于已验证的 GKI 构建。
- lz4kd：未加入，按交接说明不作为首版阻塞项。没有把“注册 zram 算法”冒充
  “delta 实际调用”。

### 9. 安全与回退

- 所有产物可用 `STOCK_BOOT_IMG` 重新继承生成。最终 boot 由
  `scripts/repack-boot.py` 保留原厂 64MB header、OEM vbmeta 和 AVB footer，只替换
  kernel；不写入 init_boot/vendor_boot/dtbo/vbmeta。该封装方式已实机启动成功，
  细节和失败对照见 [BOOT_PACKAGING.md](BOOT_PACKAGING.md)。
- 源码树可随时由 `scripts/apply-patches.sh` 重置并重新应用，长期修改只在
  `patches/`、`configs/` 和报告文件中。
- `out/baseline-6.6.118/` 保留一份未加 hooks/功能补丁的内核和旧式 mkbootimg
  boot；该 boot 不可启动，仅作内核对照，不得误当作 stock 原厂镜像。

---

<a id="src-06"></a>
## 6. 实机 vs stock 特性核对

> 来源：[`docs/kernel/STOCK_PARITY_AUDIT.md`](STOCK_PARITY_AUDIT.md) · 9595 字节 · SHA256 `a132c132b60b864c7f8db9590af70d0c3d6459371db6a40a6a49d8740b71aa82`
> 类别：当前交付 · 状态：当前交付（优先相信）

对象：当前设备运行的自编内核 `6.6.118-4k #29`，对比设备 stock
`6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`。
结论只区分“已核对一致”“已实现但有行为差异”“未实现/阻塞”，不把
“模块能加载”当成“功能完全等价”。

### 1. 总览

| 项 | stock | 当前 #29 | 结论 |
|---|---|---|---|
| config | 2259 项 | 2266 项，0 个值冲突 | 仅 7 个缺失项，见 §2 |
| 已加载模块 | 585 | 585 | 唯一差异 `kernelsu` LKM → 内建 KSU + `mkp` |
| stock 模块符号 | 638 模块 | `hard_missing=0 weak_missing=0` | 可加载性一致 |
| core tracepoint | 1860 | 1860 | `__traceiter_*` missing=0/extra=0 |
| KCFI | — | 13/13 静态哈希 | OS4 hooks 全部匹配 |
| 启动 | stock | #29 已启动 | 无 KCFI/未知符号/panic |

### 1.1 安全补丁差异

本机 stock 的安全补丁是 `2026-10-01`（`ro.build.version.security_patch`）；
当前基线 tag 是 `android15-6.6-2026-01_r1`（6.6.118），缺少 2026-02..10 的
LTS/安全修复。
KMI 字符串仍是 `android15-8`，升级 sublevel 不改变 KMI；但需要重放补丁并复验。
详见 [UNRESOLVED_GAPS.md](UNRESOLVED_GAPS.md)。

### 2. config 差异

stock 有、当前没有的 7 项：

| 配置 | 性质 | 影响 |
|---|---|---|
| `CONFIG_SCSI_DISCARD` | 功能 | 通用 `sd` discard 仍可用；stock fastdiscard 未实现 |
| `CONFIG_SCSI_FASTDISCARD` | 功能 | 多 descriptor UNMAP 未实现 |
| `CONFIG_MODULE_SCMVERSION` | 元数据 | `/sys/module/*/scmversion` 缺失 |
| `CONFIG_LOCALVERSION_AUTO` | 构建元数据 | 为可复现构建主动关闭 |

2026-10-30 实际尝试同时打开 `LOCALVERSION_AUTO`/`MODULE_SCMVERSION`：
`make kernelrelease` 变为 `6.6.118-gf9c84f40b6ba-dirty`，会丢掉现有的
`-4k` 后缀并改变所有自编模块的 vermagic；因此回退，保留可复现构建。
| `CONFIG_CC_CAN_LINK` | 构建探测 | 主机工具链检测，非运行时 |
| `CONFIG_CC_CAN_LINK_STATIC` | 构建探测 | 同上 |
| `CONFIG_UAPI_HEADER_TEST` | 构建测试 | 不参与运行时 |

除此之外两边没有 `y/m` 值冲突；zram、EROFS、F2FS、LZ4、GKI hacks 等一致。
stock `zram` 当前后端的实际算法是 `lz4`，当前设备也是 `lz4`，没有 stock
`lz4kd` 缺失问题。

### 3. 已核对一致 / 已补齐

- **core tracepoint**：1860/1860；51 个 stock-only hook、2 个 LZ4 事件已补，
  44 个 hook 有调用点，7 个与 AOSP 上游一样仅声明/导出。
- **GKI dynamic task_struct**：`arch_task_struct_size`、`vendor_data_pad`、
  1024B vendor 上限、early param 均已具备；未传参时 task_struct 4800B/217 成员
  与 stock BTF 一致。
- **BakaSU + SUSFS**：内建 KSU、SUSFS v2.3.0 9 项特性；stock `kernelsu` LKM
  不再加载。
- **厂商模块兼容**：638 个 stock 模块静态无硬缺失；`node_cache`、`os_cpu_qi`
  及 QoS 依赖链、`io_monitor`、`fault_report`、`ufs_mediatek_mod_ise` 均加载。
- **F2FS lock/priority**：`f2fs_lock_elapsed_time`、
  `f2fs_priority_uplift/restore`、4 个 lock sysfs、全部 `gc_lock` 调用点。
- **F2FS fault report**：`f2fs_fault_report` tracepoint、`/proc/fault_report`；
  2026-10-30 增加 `f2fs_handle_error_async()` 的 task-context 上报（`in_task()`
  保护），避免原子 end_io 路径调用可能睡眠的 fault_report 回调。
- **`/proc/iostat_enhance`**：复核为误记；实际是
  `/proc/io_monitor/iostat/iostat_enabled`，当前存在。
- **7 个 export-only hook**：`dma_heap_buffer_alloc_lat_*`、`mmc_*`/
  `sdhci_get_cd`、`restore_curr_resched` 已在 0008/0009 补上调用点；其中
  `restore_curr_resched` 按 OnePlus 公开的 lazy-resched 实现接入
  `do_notify_resume()`/`exit_to_user_mode_prepare()`。
- **UFS monitor 路径**：stock 内核和模块字符串都只有 `monitor`，当前
  `/sys/devices/.../monitor/monitor_enable` 与模块一致；`/ufs_monitor` 只出现在
  `vendor_file_contexts`，未找到内核节点或写入者，不再列为已确认缺失。

### 4. 已实现但与原厂行为有差异

#### F2FS 增强 iostat

- sysfs 开关/窗口/日统计/阈值存在，单开关语义已修复。
- 当前是 5 类聚合（read/write_sync/write_async/meta），不是 stock 的
  20 槽窗口 + 每 10 档粒度 + per-CPU 布局；`iostat_window_latency` 的输出格式
  不保证逐字节等于 stock。

#### F2FS VIP

- `vip_file_enable`、排序 manager、`f2fs_vip_bsearch/insert/remove` 存在。
- 当前选择策略是 hook + 保守 fallback（有用户地址空间的 RT/negative-nice
  写打开），上限 8192；stock 的原厂选择策略和 `f2fs_nm_info` 布局未复刻。
- 关闭开关时 manager 为空，开销为零。

#### F2FS fault report

- 同步 `f2fs_handle_error()` 和 task context 的
  `f2fs_handle_error_async()` 都会触发；原子 end_io 路径由 `in_task()` 过滤，
  避免 fault_report.ko 回调在原子上下文做 `stack_trace_save()`/`queue_work()`。
- 与 stock 的差异：`f2fs_stop_checkpoint()` 等路径没有额外上报，stock 是否
  覆盖这些路径未确认。

#### EROFS iostat

- 已改 per-CPU，sysfs 汇总；`iostat_config` 输出 `percpu=1`。
- stock 是每 CPU 10 个 window 槽 + 10 个 abnormal 槽 + 5 个 daily 槽 +
  5 档阈值；当前每 CPU 只有 1 个 aggregate bucket，统计粒度和输出格式不同。

#### LZ4 tracepoint

- `lz4_decompress_start/end` 的字段/ABI 按 stock BTF 实现，但调用点只在
  EROFS 解压路径；stock 是否覆盖其它 LZ4 解压路径未确认，不能宣称全部覆盖。

### 5. 未实现 / 阻塞

#### F2FS hybrid UFS（最大功能缺口）

- `hybrid`、`hybrid_free_ratio`、`hybrid_die_info` sysfs 存在，
  `f2fs_hw_support_hybrid()` 固定 false，`hybrid=1` 返回 `-EOPNOTSUPP`。
- 已从 stock BTF 恢复 `f2fs_hybrid_info` 192B 和 `f2fs_die_info` 72B 布局，
  但缺 ext LUN 映射、die 分区发现和 GC 分配策略；不能安全伪造地址映射。
- 详见 [UFS_HYBRID_EVIDENCE.md](UFS_HYBRID_EVIDENCE.md)。

#### SCSI fastdiscard

- stock config 有 `CONFIG_SCSI_DISCARD`/`CONFIG_SCSI_FASTDISCARD`，当前缺。
- stock 的 `xiaomi_fastdiscard_info` 是 SCSI disk 层的多 descriptor UNMAP；
  当前 `sd.c` 只有单 descriptor `sd_setup_unmap_cmnd()`，
  `max_discard_segments=1`（实测），无法批量 UNMAP。
- 通用 discard 仍可用（`discard_max_bytes`/`discard_granularity` 正常），
  但 fastdiscard 的吞吐优化未实现；`persist.sys.stability.fastdiscard` 为空。

#### UFS 官方 core

- MTK 官方 37 文件源已取到并被核对，且做了真实编译探针：
  `ufs-mediatek.c` 可在 AOSP 6.6.118 头文件下编译，但 modpost 缺
  `ufs_mtk_init_sysfs`、`ufs_mb_init` 等 sibling/vendor 符号；它是
  device_modules 模块形态，依赖 `DEVICE_MODULES_PATH`、MTK block/clk/power
  头文件，不能直接替换 AOSP core。
- stock 的 `ufs_mediatek_mod_ise.ko` 在当前 AOSP core 上可加载，因此没有把
  “整体替换 core”作为当前交付。
- 仍需在独立变体上做 UFS 初始化、monitor、电源/时钟路径 A/B。

#### 7 个 export-only hook

已在 0008/0009 补上调用点：MMC attach/reset/cd、sdhci get_cd、dma-heap
alloc latency、lazy resched restore；`restore_curr_resched` 按 OnePlus 公开
lazy-resched 路径接入。剩余差异是这些调用点是否与 stock 私有 MTK 调用点
完全同序，当前 638 模块没有引用它们。

### 6. 有意保留的差异

- `CONFIG_VENDOR_KO_COMPAT=y` 跳过模块签名/vermagic/CRC/namespace/GKI
  protected-export 校验。这是为了加载 stock 厂商模块，不是 stock 行为；
  安全性低于原厂。
- 关闭 `LOCALVERSION_AUTO`/`MODULE_SCMVERSION` 是为了可复现构建；
  只影响版本元数据。
- `SUSFS`、内建 KSU、`vip_inode_count` 等是额外能力/调试 ABI，不是 stock
  原厂特性。

### 7. 仍未验证

- 长时压力、suspend/resume、异常进程退出下的 KCFI/模块稳定性。
- fsck、power-loss、F2FS/EROFS 故障注入。
- hybrid、fastdiscard、UFS core 变体的硬件 A/B。
- 性能/功耗 A/B（zram、node_cache、QoS、启动时延）。

### 8. 核对命令

```bash
# config 差异
python3 - <<'PY'
from pathlib import Path
def parse(p):
    d={}
    for l in Path(p).read_text().splitlines():
        if l.startswith('CONFIG_') and '=' in l:
            k,v=l.split('=',1); d[k]=v
    return d
s=parse('dash/configs/stock.config'); c=parse('dash/out/dash/.config')
for k in sorted(s):
    if k not in c and s[k] in ('y','m'): print('missing',k,s[k])
PY

# tracepoint 差集（stock kallsyms 非模块行）
python3 - <<'PY'
import re
from pathlib import Path
def names(p, core=False):
    s=set()
    for line in Path(p).read_text(errors='replace').splitlines():
        if core and re.search(r'\[[^\]]+\]\s*$', line): continue
        m=re.search(r'\b(__traceiter_[A-Za-z0-9_]+)', line)
        if m: s.add(m.group(1))
    return s
s=names('dash/out/device-audit/stock.kallsyms', True)
c=names('dash/out/dash/System.map')
print(len(s), len(c), sorted(s-c))
PY
```

### 9. 结论

当前实机与 stock 的主要剩余差异集中在 **F2FS hybrid / fastdiscard / EROFS
多桶粒度 / UFS core 变体**，而不是启动、模块加载、tracepoint 或基本
F2FS/EROFS 功能。`node_cache`、`os_cpu_qi`、`fault_report`、`io_monitor`
等 stock 模块链已实测工作；不能把 hybrid、fastdiscard 的“开关存在”误报为
“功能等价”。

---

<a id="src-07"></a>
## 7. 未完成项按性能影响排序

> 来源：[`docs/kernel/UNRESOLVED_GAPS.md`](UNRESOLVED_GAPS.md) · 8667 字节 · SHA256 `b4f3cc82120212cfe948b703b5094383c95d95d242c4ad2cf1336a5c86b4d800`
> 类别：当前交付 · 状态：当前交付（优先相信）

本文件只列**确实尝试过但仍无法完成**的项；已完成项见
[STOCK_PARITY_AUDIT.md](STOCK_PARITY_AUDIT.md) 和
[TEST_REPORT.md](TEST_REPORT.md)。排序依据是“对实际 I/O/存储/调度性能的潜在影响”，
不是实现难度；影响方向可能是提升也可能是退化，均按潜在幅度排序。

### 安全/LTS 缺口（不计入性能排序）

本机 stock `ro.build.version.security_patch=2026-10-01`；当前基线是
`android15-6.6-2026-01_r1`（6.6.118），中间缺少 2026-02..10 的 LTS/安全修复。
（Mi15 另一台 OS4 设备的 dump 是 2026-08-01，比本机更旧；以本机实测为准。）
这不是性能项，但属于未完成的功能/维护缺口。升级到 2026-07_r1/2026-10_r2
可以补齐，同时保持 KMI `android15-8`；代价是重放全部补丁、638 模块/KCFI/
启动复验，见 [UPSTREAM_NOTES_REVIEW.md](UPSTREAM_NOTES_REVIEW.md)。

### 排序总表

| # | 项 | 潜在性能影响 | 当前状态 | 为什么不能完成 |
|---|---|---|---|---|
| 1 | **F2FS hybrid UFS 双区域分配** | **高**：写放置/GC/寿命/吞吐 | sysfs/挂载参数存在，`f2fs_hw_support_hybrid()` 固定 false，`hybrid=1` 返回 `-EOPNOTSUPP` | 缺 ext LUN 映射、die 分区发现、GC 分配策略；无公开源码，无法安全伪造地址 |
| 2 | **UFS 官方 core 变体** | **高（未证实）**：UFS 初始化、电源/时钟、I/O 路径 | stock `ufs_mediatek_mod_ise.ko` 可加载；AOSP core 未替换 | 官方 37 文件源是 device_modules 模块形态，依赖 MTK block/clk/power 头和 vendor 对象；独立变体未完成 |
| 3 | **SCSI fastdiscard / 多 descriptor UNMAP** | **中高**：discard/TRIM 吞吐、GC、寿命 | 通用 `sd` discard 正常；`max_discard_segments=1`；`CONFIG_SCSI_DISCARD`/`FASTDISCARD` 缺失 | 公开源码无实现；stock 的 `xiaomi_fastdiscard_info` 是 SCSI disk 层批处理，需改命令构造和硬件验证 |
| 4 | **F2FS VIP 原厂选择策略** | **中**：前台/存储优先级、UI 延迟 | hook + 保守 fallback，`vip_inode_count` 可用；manager 布局是简化版 | 原厂“哪些 inode 进入 VIP”的策略无公开来源；只恢复了 `f2fs_vip_manager` 48B 布局 |
| 5 | **F2FS 增强 iostat 精确布局** | **低-中**：观测开销/统计精度 | 单开关语义正确，5 类聚合 | stock 是 20 槽窗口 + 10 档粒度 + per-CPU 私有布局；槽位语义未知，不伪造 |
| 6 | **EROFS iostat 多桶布局** | **低**：观测；对 I/O 路径影响很小 | 已 per-CPU，单 aggregate bucket | stock 是每 CPU 10 window + 10 abnormal + 5 daily + 5 阈值；桶语义未知 |
| 7 | **F2FS fault_report 全路径** | **极低**：可靠性/诊断，不是吞吐 | 同步 + task-context 异步已上报 | `f2fs_stop_checkpoint()` 等路径是否上报未确认；不能确定 stock 行为 |
| 8 | **`MODULE_SCMVERSION`/版本串** | **无**：仅元数据/可追溯性 | 未启用 | 打开 `LOCALVERSION_AUTO` 会把 release 变成 `6.6.118-gf9c84f40b6ba-dirty`，丢掉 `-4k` 并改变 vermagic；已实测后回退 |
| 9 | **深度性能/稳定性 A/B** | 无法量化 | 未做 | 缺 stock 运行时 A/B、suspend/resume、fsck/power-loss、长时压力；不是“功能缺失”，是验证缺口 |

### 逐项说明

#### 1. F2FS hybrid UFS（最高性能影响）

- 已知：stock BTF `f2fs_hybrid_info` 192B（`main/ext f2fs_die_info` 72B、
  `free_ratio`、`gc_threshold`、`large_file_threshold`、`main/ext_new_seg_ratio`、
  `gc_alloc_mode[5]`）；`f2fs_hw_hybrid_get_avail`、`f2fs_hybrid_die_info_show`
  等函数存在。
- 已尝试：恢复布局、sysfs/挂载参数、能力查询、安全回退；从 stock 二进制和
  BTF 找分配器未果。
- 为什么停：没有 ext LUN 地址映射和 die 发现契约，错误映射可能把数据写到错误
  介质；这是数据安全问题，不是性能取舍。
- 下一步：从 stock `vmlinux` 反汇编 `device_hybrid_capable`/GC 分配路径，或取得
  原厂 6.6.118 源码；在双区域设备上先做只读校验。

#### 2. UFS 官方 core 变体（高，未证实）

- 已知：MiCode `dash-w-oss` 的 `drivers/ufs` 已 sparse checkout（25 + 13 文件）；
  `ufs-mediatek.c` 在 6.6.118 头文件下可以编译，但 modpost 缺
  `ufs_mtk_init_sysfs`、`ufs_mb_init`、`ufs_mb_queue_error`、`ufsm_disable_intr`、
  `mt_irq_dump_status` 等 sibling/vendor 符号。
- 已尝试：独立 `M=` 编译探针；依赖 `DEVICE_MODULES_PATH`、MTK block/clk/power
  头、`drivers/ufs/vendor`。
- 为什么停：不能单文件替换；整体替换 AOSP core 会改变启动初始化链，且本机
  无法在无写入条件下验证 UFS 初始化/电源路径。
- 下一步：用 MTK device_modules 的 out-of-tree 构建做独立 boot 变体，只读 A/B
  UFS monitor、电源/时钟和 I/O 延迟。

#### 3. SCSI fastdiscard（中高）

- 已知：stock BTF `xiaomi_fastdiscard_info` 16B
  （`fastdiscard_enable`、`max_unmap_descriptors`、`multi_unmap_len_max`），
  内嵌在 `struct scsi_disk` 的 `xiaomi_feature_info`；字符串有
  `multi_unmap_len_max_show`、`[FASTDISCARD debug]`。
- 当前：通用 discard 可用；`/sys/block/sda/queue/max_discard_segments=1`。
- 已尝试：BTF/字符串恢复、AOSP `sd_setup_unmap_cmnd` 路径核对、公开源码检索
  （只命中 config/ikconfig）。
- 为什么停：需要多 descriptor UNMAP 命令构造和真实 UFS/分区验证；错误实现可能
  丢数据。没有 stock 源码和可安全丢弃的测试分区。
- 下一步：实现/验证多 descriptor UNMAP 的边界、错误处理和 `max_discard_segments`，
  在 scratch 分区上做 A/B。

#### 4. F2FS VIP 原厂策略（中）

- 已知：`f2fs_vip_manager` 48B（sorted/unsorted/count/capacity/
  unsorted_buf_size/head/tail/lock/enabled），`vip_inode_sorted` 8B
  （`ino` + `unsorted_idx`），`vip_inode_unsorted` 4B。
- 当前：hook + fallback（有用户地址空间的 RT/negative-nice 写打开，上限 8192），
  不是原厂选择策略；manager 布局也简化。
- 为什么停：没有公开的选择策略/阈值/调用时机；恢复布局但不恢复策略只是“看起来
  像”，不能宣称等价。
- 下一步：从 stock Image 恢复 `f2fs_vip_insert` 调用点和 manager 操作，或取得原厂
  源码。

#### 5. F2FS 增强 iostat（低-中）

- 当前：`en_iostat_enable` 单开关、window/daily/阈值、5 类聚合。
- stock：20 槽窗口、10 档粒度、per-CPU 私有布局；输出格式也不保证逐字相同。
- 为什么停：槽位/粒度语义未知，强行按名字实现会给出错误统计。
- 下一步：取得原厂 `f2fs_iostat` 结构/调用点，或接受“行为级统计”并明确不做逐字
  ABI 兼容。

#### 6. EROFS iostat 多桶（低）

- 当前：per-CPU、单 aggregate bucket、`percpu=1`。
- stock：每 CPU 10 window + 10 abnormal + 5 daily + 5 阈值；布局已知，
  桶语义未知。
- 下一步：从 stock show/record 函数恢复语义；在此之前保留聚合统计。

#### 7. F2FS fault_report 全路径（极低）

- 同步 + task-context 异步已上报；`f2fs_stop_checkpoint()` 等路径未额外上报，
  避免原子上下文调用可能睡眠的回调。
- 影响：诊断完整性，不是性能。
- 下一步：确认 stock 在这些路径是否上报，再决定是否加 `in_task()` 保护。

#### 8. `MODULE_SCMVERSION`/版本串（无性能影响）

- 已实测打开 `LOCALVERSION_AUTO`/`MODULE_SCMVERSION` 后 release 变为
  `6.6.118-gf9c84f40b6ba-dirty`，丢失 `-4k` 并改变自编模块 vermagic，已回退。
- 只影响 `/sys/module/*/scmversion` 和版本可追溯性。
- 下一步：如果只需模块 scmversion，可只对自编模块启用，不改变内核 release；
  需要单独验证。

#### 9. 深度性能/稳定性 A/B（验证缺口）

- 未做：stock vs 自编的 zram/node_cache/QoS/启动时延、suspend/resume、
  fsck/power-loss、长时压力。
- 没有这些数据，不能对任何性能收益作声明。
- 下一步：用 stock boot 备份做 A/B；先做只读/可回滚的启动时延和 zram 测试，
  再做 suspend/resume 和长时压力。

### 已完成、不要重复列为缺口的项

- core tracepoint 1860/1860；51 个 hook（含 7 个原 export-only 的调用点）。
- GKI dynamic task_struct。
- F2FS lock/priority、`gc_lock` 全调用点、VIP 接口/保守策略、fault_report
  同步+异步。
- EROFS per-CPU iostat（单桶）。
- `/proc/iostat_enhance` 误记纠正；UFS `monitor` 路径复核。

---

<a id="src-08"></a>
## 8. 参考仓库工作笔记核对

> 来源：[`docs/kernel/UPSTREAM_NOTES_REVIEW.md`](UPSTREAM_NOTES_REVIEW.md) · 12054 字节 · SHA256 `df1338b663dd03aa01a3587fdfc53aa808886e8a72df20846d5a21119a0686f6`
> 类别：当前交付 · 状态：当前交付（优先相信）

范围：先读导航中每个带工作笔记/AGENTS 的仓库，再补读一批小米 MTK/OS3/OS4
内核构建仓库的 README、build guide、context/perf 笔记。目的不是照搬，而是找
**我们文档/实现中需要纠正或可优化**的点。

### 1. 已读的仓库内笔记

| 仓库/文档 | 类型 | 与本项目的关系 | 结论 |
|---|---|---|---|
| [BakaSU/manager/AGENTS.md](../../BakaSU/manager/AGENTS.md) | Agent 规范 | Manager UI/Koin/Compose | 只约束 Manager App；本仓库不构建 Manager，无可直接改动。记录：UI 改动需 `spotlessCheck`/`assembleRelease`，字符串必须资源化 |
| [dash-droidspaces/README.md](../../third_party/dash-droidspaces/README.md) | 同机型内核笔记 | dash 6.6.118 + DroidSpaces/SukiSU | 高价值；确认 KMI `android15-8`、`LTO_NONE`、CFI、boot v4；但它的 stock 版本是另一 OS4 build，不能覆盖我们的设备事实 |
| [dash-droidspaces/patches/README.md](../../third_party/dash-droidspaces/patches/README.md) | OS4 hooks/构建笔记 | 13 hooks、KCFI、CRC | 与我们的实现一致：原型不能改、declaration-only TU 修 CRC、分组 call site；本机全量 call site 启动成功，未复现其 bootloop |
| [dash-droidspaces/docs/gz-erased-changeset.md](../../third_party/dash-droidspaces/docs/gz-erased-changeset.md) | gz/pKVM/vendor_boot | 同机型但不同安全状态 | 仅在其 gz 擦除 + nvhe + vendor_boot 修补场景适用；本机未擦 gz、未改 vendor_boot，不能照搬 |
| [dash-droidspaces/docs/vendor-boot-v15-changeset.md](../../third_party/dash-droidspaces/docs/vendor-boot-v15-changeset.md) | vendor_boot 字节级 | 同上 | Mali/log_store DTB/ko 修补是 gz 擦除专属；本机不动 vendor_boot |
| [hyperos-lz4kd/README.md](../../third_party/hyperos-lz4kd/README.md) + 实战指南 | 通用 GKI/LZ4KD | LZ4KD、AVB、CFI | 核心认知正确：用 stock config、LZ4KD built-in、CFI 会拦孤立 .ko；本机 stock zram 实际算法是 lz4，lz4kd 不是 stock 特性，继续不引入 |
| [susfs4ksu/README.md](../../third_party/susfs4ksu/README.md) | SUSFS 集成 | SUSFS/KSU | 提醒删除 `abi_gki_protected_exports_*` 以免 WiFi 模块被拦；本机用 `CONFIG_VENDOR_KO_COMPAT` 绕过 protected-export 检查，无需删除。版本串/`-dirty` 建议不适用于我们的 Make 构建 |
| [cc-dash-build/abi/README.md](../../third_party/cc-dash-build/abi/README.md)、gki/kleaf READMEs | ABI/Kleaf 工具 | 构建/ABI | 通用工具文档；本仓库用 Make + clang r510928，不切 Kleaf。无直接改动 |
| [cc-dash-mtk-modules/mtkcam/README.md](../../third_party/cc-dash-mtk-modules/mtkcam/README.md) | MTK camera 模块 | out-of-tree Kleaf | 只说明相机模块构建；不属于 GKI core，无直接改动 |
| `cc-dash-device-modules`、`cc-dash-bazel-rules`、`sukisu-patch` | 无工作笔记 | — | 仓库内没有 README/AGENTS/工作笔记；只作为源码/构建规则参考，不纳入“笔记核对” |

### 2. 补读的小米 MTK/OS3/OS4 仓库

优先热度 + 小米 + 可能 MTK + OS3/OS4；没有工作笔记的仓库只做交叉验证，不照搬。

#### 2.1 [Re-s/Mi15-Droidspaces-Kernel](https://github.com/Re-s/Mi15-Droidspaces-Kernel)

- 设备：Xiaomi 15（SM8750，非 MTK），但 stock 与我们**完全相同**：
  `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`。
- 关键实证：KMI 字符串是 **`android15-8`**（不是 `android15-6.6`）；GKI 分支是
  `android15-6.6`；4K；clang r510928；`android15-6.6-2026-01_r1` == 6.6.118。
- OS4/Android 17 不改变 KMI，只是 vendor 安全补丁更新；其 Mi15 dump 显示
  `security_patch=2026-08-01`，本机 dash 实测是 `2026-10-01`（更晚，以本机为准）。
- 结论：**需要纠正我们文档中的 KMI 表述**，已把“KMI `android15-6.6`”改为
  “GKI 分支 `android15-6.6`，KMI 字符串 `android15-8`”。
- 另发现：我们的源 tag 是 2026-01，本机 stock 安全补丁是 2026-10-01；这是
  一个**未补的安全/LTS 差距**（见 §4）。

#### 2.2 [omajili-manbu/Xiaomi_Rodin_Kernel_Enhance](https://github.com/omajili-manbu/Xiaomi_Rodin_Kernel_Enhance)

- 设备：Redmi Turbo 4 / POCO X7 Pro（rodin，MT6899，HyperOS 3/Android 16）。
- 有价值笔记：`BUILD-GUIDE.md`、README。
- 可借鉴：
  - `.config` 必须从 `gki_defconfig` 生成（其 BSP 树经验）；我们用 stock.config
    + olddefconfig，已实测，不能直接套用，但其“不要混 defconfig”原则一致。
  - `Image.lz4` 必须是 **legacy LZ4**：magic `0221 4c18`，不是标准帧
    `0422 4d18`；我们已把该检查加入 `make-boot.sh`。
  - 性能选项：ThinLTO、AutoFDO、BBRv3、ZSTD 1.5.7、Cortex-A725 编译优化。
    这些都会偏离 stock 的 `LTO_NONE`/CFI 与默认算法，**未应用**；见 §4。
  - 防格机 Baseband-guard LSM、vendor 模块兼容修复；我们已有 vendor-ko 兼容，
    BBG 不是 stock 特性，未引入。
- 其 `dash-w-oss` 分支没有可用的额外笔记（README 是 AOSP 通用补丁指南）。

#### 2.3 [ZxAlif-ID/Flavenz-Kernel-Peridot](https://github.com/ZxAlif-ID/Flavenz-Kernel-Peridot)

- 设备：POCO F6 / Redmi Turbo 3（peridot，SM8635，HyperOS 3/Android 16）。
- 有价值笔记：`docs/kernel-context.en.md`、`docs/perf_analysis.md`、README。
- 可借鉴：
  - **构建时间戳漂移**会被 Duck Detector 类完整性检查识别；建议把
    `KBUILD_BUILD_TIMESTAMP` 同步到 ROM `ro.build.date`。我们当前 `#1 SMP ...
    Oct 30 2026`，设备 ROM 是 `Oct 20 2026`，存在 10 天漂移。**未应用**：
    会改变 `/proc/version` 和构建元数据，需决定是否追求 stealth/stock 外观。
  - AnyKernel3 在 OrangeFox 下用 `block=boot` + `is_slot_device=auto`，并用
    `/proc/bootconfig` 兜底 slot；我们不用 AK3，走完整 boot 分区继承 + dd，
    不受影响。
  - DroidSpaces 需要 SYSVIPC/PID_NS/IPC_NS/kABI 6/7/8 等；我们 stock 配置没有
    SYSVIPC/namespace 容器集，所以当前内核**不是 DroidSpaces 内核**。若目标是
    容器，需要单独变体和 kABI 补丁，不应混入 stock parity 构建。
  - 某些 config（CGROUP_DEVICE/PIDS、BRIDGE_NETFILTER、NF_TABLES）在 peridot
    上被报告 bootloop；我们的 stock dash 配置包含这些，未改动；不要照搬到 dash。
- Perf 笔记的调参（X4 cap、uclamp、BCL、GPU cap、zstd）是 ROM/thermal 层问题，
  不是 GKI 内核缺失；不纳入 stock parity。

#### 2.4 [2824799/droidspaces-xiaomi-17-kernel](https://github.com/2824799/droidspaces-xiaomi-17-kernel)

- 设备：Xiaomi 17（pudding，SM8850，**Android 17 / HyperOS 4**），非 MTK，但 OS4
  和 GKI 方法论可直接对照。
- 关键结论：
  - stock 是 `6.12.69-android16-6-...-4k`；KMI 字符串 `android16-6`，再次证明
    Android 平台版本 ≠ KMI。
  - 其 stock 属性包含 `CONFIG_GKI_TASK_STRUCT_VENDOR_SIZE_MAX=1024` 和
    `android_arch_task_struct_size=1024`；我们的 dynamic task_struct 实现与该方向
    一致，但我们的 stock 没传 early param，默认 4800B，不能假设 1024 扩展已启用。
  - 审计 569 个 stock 模块（466 vendor + 103 system_dlkm）和 28,290 个 import，
    发现 `rust_binder.ko` 这个 system_dlkm consumer 容易被漏审；我们目前的 638
    模块静态检查覆盖了 handoff 的模块集合，但没有 rust_binder 这类 Rust/C++ 绑定
    的运行时 ABI 验证，属于验证缺口。
  - 修改 kernel 后 boot 镜像没有有效 Xiaomi AVB 签名，只能 `fastboot boot`/研究，
    不能当通用刷机包；与我们的 hidden-unlock 约束一致。
  - DroidSpaces 需要 SYSVIPC/PID/IPC namespace 和 kABI SYSVIPC 布局；我们 stock
    配置没有这些，不是 DroidSpaces 内核。
- 可借鉴：模块 consumer 审计要覆盖 `system_dlkm`，不要只审 vendor；KMI/CRC
  静态通过不等于启动/suspend/IMS 正常。

#### 2.5 其他

- [XagaForge/android_kernel_xiaomi_mt6895](https://github.com/XagaForge/android_kernel_xiaomi_mt6895)
  与 [JuanArton/xiaomi_peridot_kernel](https://github.com/JuanArton/xiaomi_peridot_kernel)
  的 README 基本是 AOSP 通用补丁提交指南，没有设备工作笔记，无直接改动。
- [degas-developers/android_device_xiaomi_degas-kernel](https://github.com/degas-developers/android_device_xiaomi_degas-kernel)
  是 MT6897（Xiaomi 14T）**预编译 stock GKI**，没有构建；其 DTB 增加 GPU/CPU
  thermal backstop 是为 LineageOS 无 mi_thermald 场景，HyperOS stock 不需要。
  它也确认 MTK `mediatek_v2` DRM/mi_disp/panel 没有公开源码，和我们的 UFS/hybrid
  结论同类。
- `xiaomi-mediatek-devs/android_kernel_xiaomi_mt6877` 没有 README/工作笔记，
  仅作为 lineage-21 参考，无直接改动。

### 3. 已应用的纠正/优化

1. **KMI 表述纠正**：文档从“KMI `android15-6.6`”改为“GKI 分支 `android15-6.6`，
   KMI 字符串 `android15-8`”。依据：我们的 stock `uname -r` 与 Mi15 研究一致。
2. **LZ4 legacy 检查**：`make-boot.sh` 在打包前检查 `Image.lz4` magic 必须是
   `0221 4c18`；当前产物通过。这是 Rodin 构建笔记中很有价值的一条。
3. **UFS monitor 路径纠正**：stock 内核/模块字符串只有 `monitor`，当前
   `/monitor/monitor_enable` 与模块一致；`/ufs_monitor` 只在 vendor_file_contexts，
   不再列为已确认缺口。
4. **7 个 export-only hook** 已补调用点（0008/0009），不再悬空。
5. **F2FS fault report** 增加 task-context 异步上报；同步路径保留。

### 4. 建议但未应用的优化（含风险）

| 优化 | 收益 | 不应用的原因 |
|---|---|---|
| 升级到 6.6.139/6.6.142（2026-07/10 tag） | 补 2026-02..08 LTS/安全修复 | 需重放全部补丁、重建、638 模块/KCFI/启动复验；KMI 仍 android15-8，但 stock parity 基线变化 |
| ThinLTO / AutoFDO | 3-5% 级内核路径优化 | 偏离 stock `LTO_NONE`，改变镜像/KCFI/调试与可复现性；未有 A/B |
| BBRv3 / ZSTD 1.5.7 / zstd zram 默认 | 网络/压缩吞吐 | 不是 stock 默认（stock zram 运行 lz4）；会改变行为，需 A/B |
| `KBUILD_BUILD_TIMESTAMP` 同步 ROM | 降低完整性检测/时间漂移异常 | 改变 `/proc/version` 和可复现构建；是否追求 stealth 需设备所有者决定 |
| dash-droidspaces `pid_max` clamp 32768 | 规避 0x8000 掩码类 bug | 改变 PID 空间/用户态可见行为，不是 stock；需明确 bug 复现再上 |
| DroidSpaces SYSVIPC kABI 6/7/8 + namespace 配置 | 容器支持 | 不是 stock 配置；会改变 kABI/启动行为，应做独立变体 |
| Baseband-guard LSM | 防格机 | 额外 LSM，非 stock；需要白名单和设备验证 |
| SUSFS README 删除 protected exports | 避免 WiFi 模块被拦 | 我们已用 `CONFIG_VENDOR_KO_COMPAT` 绕过；删除会降低/改变 ABI 保护，不必要 |

### 5. 已验证无需改动

- stock 基线 `android15-6.6-2026-01_r1` == 6.6.118；clang r510928、4K、
  `LTO_NONE`、CFI、boot v4 与 stock 匹配。
- stock zram 运行算法是 `lz4`，不是 lz4kd；`zram.ko`/`zsmalloc.ko` 均为 stock
  模块，无缺失。
- `SUSFS`/内建 KSU 的集成方式与 BakaSU/上游说明一致；SUSFS 版本 2.3.0。
- 我们的 boot 封装是完整 64MB 继承 + OEM vbmeta/footer，不使用 AK3；Flavenz 的
  slot/bootconfig 修补不适用。

### 6. 下一步优先级

1. **安全/LTS**：评估把基线从 2026-01_r1 升到 2026-07_r1/2026-10_r2，KMI 保持
   `android15-8`；这是比性能调参更重要的缺口。
2. **性能 A/B**：在 stock 与自编之间测启动时延、zram、node_cache/QoS；再决定
   ThinLTO/AutoFDO/BBRv3 是否值得偏离 stock。
3. **DroidSpaces**：若确实需要容器，单独变体加 SYSVIPC kABI 6/7/8 + namespace
   配置，不混入 stock parity。
4. **hybrid/fastdiscard/UFS core**：继续按 [UNRESOLVED_GAPS.md](UNRESOLVED_GAPS.md)
   的证据路线推进。

---

<a id="src-09"></a>
## 9. UFS/hybrid/fastdiscard 缺口证据与安全边界

> 来源：[`docs/kernel/UFS_HYBRID_EVIDENCE.md`](UFS_HYBRID_EVIDENCE.md) · 5569 字节 · SHA256 `40b17b16dee1d3a2df5eb3ecdb57a0afb4cf9f6e9fdbec083a21b15b66ce3056`
> 类别：当前交付 · 状态：当前交付（优先相信）

本文记录三项无法在“无原厂源码、无硬件故障注入”条件下安全完成全部实现的工作，
以及已经完成的源码核对和可复现证据。结论是：**不伪造功能，不替换已验证的启动链**。

### 1. UFS 官方源码：可用，但不能直接替换 AOSP core

#### 已获取

MiCode `MTK_kernel_device_modules`（`dash-w-oss`）的
`drivers/ufs` 已 sparse checkout 到：

```text
dash/src/MTK_kernel_device_modules/drivers/ufs/
```

内容：25 个顶层文件 + `vendor/` 13 个文件，共约 720 KiB，包括
`ufs-mediatek.c/.h`、`ufs-mediatek-ise.c`、`ufs-mediatek-mbrain.c`、
`ufs-mediatek-mimic.c`、`ufs-mediatek-perf.c`、`ufs-mediatek-rpmb.c`、
`ufs-mediatek-sysfs.c`、`vendor/ufsfeature.c`、`ufshid.c`、`ufsringbuf.c`、
`ufsshpb.c`、`ufstw.c` 等。

复现：

```bash
cd dash/src/MTK_kernel_device_modules
git sparse-checkout set drivers/ufs
git checkout
```

#### 为什么没有并入 `drivers/ufs`

原厂源码是 **device_modules 形态**，不是 AOSP core 的 drop-in：

- `Kconfig` 使用 `DEVICE_MODULES_SCSI_UFS_MEDIATEK`，
  依赖 `SCSI_UFSHCD_PLATFORM && ARCH_MEDIATEK`，
  并 select `DEVICE_MODULES_PHY_MTK_UFS`、`DEVICE_MODULES_RESET_TI_SYSCON`。
- `Makefile` 依赖 `DEVICE_MODULES_PATH`，需要
  `drivers/misc/mediatek/include`、`blocktag`、`power_throttling`、
  `drivers/ufs/vendor`、`drivers/devfreq` 等外部头文件。
- 源码直接 include `../../../block/blk.h`、`../../clk/mediatek/clk-fmeter.h`、
  `../scsi_priv.h`、`ufshcd-crypto.h` 等内部头，不能作为普通模块独立编译。
- 如果整体替换 AOSP `drivers/ufs`，会同时替换 core/host UFS 初始化链；当前
  bootloader/内核命令行把 stock UFS 初始化路径列入 blacklist，替换会扩大
  启动失败风险，且无法在本机无写入条件下验证。

#### 编译探针

2026-10-30 用当前 AOSP 6.6.118 的 `O=out/dash` 对
`ufs-mediatek.c` 做了独立 `M=` 编译：

- 加上 `drivers/ufs`、`vendor`、AOSP `drivers/ufs/core`/`host` 和 CC 的
  `include` 路径后，`ufs-mediatek.o` 可以编译；
- modpost 失败于 sibling/vendor 符号：
  `ufs_mtk_init_sysfs`、`ufs_mtk_remove_sysfs`、`ufs_mb_init`、
  `ufs_mb_queue_error`、`ufsm_disable_intr`、`mt_irq_dump_status`。
- 这说明官方源码的 C 代码与 6.6.118 头文件基本兼容，但必须把
  `ufs-mediatek-sysfs.c`、`ufs-mediatek-mbrain.c`、`ufs-mediatek-ise.c` 和
  MTK 私有 core 一起链接，不能只替换一个文件。

#### 当前结论

stock 把 `ufs_mediatek_mod_ise.ko` 作为模块加载（13,885,440B），本内核已经能
加载这个 stock 模块（`/proc/modules` 可见，依赖 `rpmb_mtk`、`ise_trusty` 等）。
因此“UFS 官方源码”不是当前启动链的必需替换项；要做独立变体，应使用
device_modules 的 out-of-tree 构建和单独的 boot/DT 验证，而不是并入本内核。

### 2. hybrid UFS：布局已恢复，分配契约仍缺失

从 stock BTF 恢复的结构（`stock.btf`）：

```text
struct f2fs_hybrid_info (192B)
  main                    f2fs_die_info
  ext                     f2fs_die_info
  free_ratio              u32
  gc_threshold            u32
  large_file_threshold    u64
  main_new_seg_ratio      u32
  ext_new_seg_ratio       u32
  gc_alloc_mode[5]        u32

struct f2fs_die_info (72B)
  start, start_segno, start_secno, len,
  free, free_segs, dirty_segs,
  gc_selected_count, gc_count,
  wbt, rbt, dbt, gc_type_count
```

stock 的 `device_hybrid_capable` 是 static 函数，`f2fs_hw_support_hybrid`
返回 bool；但没有公开的双区域 allocator、ext LUN 映射或 die 分区发现代码。
当前实现继续返回 `false`、`hybrid=1` 返回 `-EOPNOTSUPP`，不会把写请求重定向到
未知介质。这是安全回退，不是原厂 hybrid。

后续若要实现，至少需要：

1. 从 stock `vmlinux`/`kallsyms` 恢复 `device_hybrid_capable` 的 die 发现条件；
2. 确认 main/ext 两个 LUN 的地址映射和 GC 分配策略；
3. 在双区域设备上做只读校验和故障注入，确认不会写错介质。

### 3. SCSI fastdiscard：只有 ABI 证据，没有公开实现

stock 二进制/BTF 证据：

- 字符串：`[FASTDISCARD debug] fastdiscard_enable=[%d]`、
  `[FASTDISCARD debug] max_segments %d-%d`、`fast_discard_info`、
  `xiaomi_fastdiscard_info`、`multi_unmap_len_max_show`。
- BTF：

```text
struct xiaomi_fastdiscard_info (16B)
  fastdiscard_enable        u32
  max_unmap_descriptors     u32
  multi_unmap_len_max       u64

struct xiaomi_feature_info (8B)
  fast_discard_info         void *

struct scsi_disk (1216B) 内嵌 xiaomi_feature_info
```

说明 fastdiscard 是 SCSI disk 层的 **多 descriptor UNMAP** 逻辑，不是简单的
`CONFIG_SCSI_DISCARD` 开关。AOSP `sd.c` 只有单 descriptor 的
`sd_setup_unmap_cmnd()`；公开源码中没有 `CONFIG_SCSI_FASTDISCARD` 的实现，
GitHub code search 只命中 config/ikconfig。

当前状态：保留通用 `sd` discard；`persist.sys.stability.fastdiscard` 为空，
默认不触发；不添加无效 Kconfig，也不伪造批处理路径。

### 4. 可安全继续的边界

- UFS：只做 device_modules 独立变体；不改当前 core，不写 boot。
- hybrid：先恢复 `device_hybrid_capable`/die 发现，再做只读 A/B；未完成前保持
  `-EOPNOTSUPP`。
- fastdiscard：先实现并验证多 descriptor UNMAP 的命令构造和错误处理，再接入；
  未完成前保持通用 discard。

---

<a id="src-10"></a>
## 10. 仓库导航、子模块 pin 与资源索引

> 来源：[`docs/project/NAVIGATION.md`](../project/NAVIGATION.md) · 14724 字节 · SHA256 `68c54c57b5d93b85c2391fb9632e9a19edaae08986efb3a55b0a90307f4e9446`
> 类别：仓库上下文 · 状态：仓库上下文（可能有过时状态）
> 注意：这是仓库地图，不是实时状态；若与 TEST_REPORT 冲突，以 TEST_REPORT 为准。

本文件是 `mikernel` 的仓库资源导航；文档总入口见
[docs/README.md](../README.md)。详细构建步骤见
[docs/kernel/README.md](README.md)，版本锁定见
[dash/versions.env](../../dash/versions.env)。缺口的逐项搜索结果见
[GAP_RESEARCH.md](../project/GAP_RESEARCH.md)，两个厂商模块的实测行为见
[DEVICE_MODULES.md](../project/DEVICE_MODULES.md)。

目标设备：`dash` / REDMI Turbo 5 Max（MT6991），stock `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`，GKI 分支 `android15-6.6`，KMI 字符串 `android15-8`，4K 页。当前自编产物已切到 **6.6.118** 基线，并已在真机 `boot_b` 启动验证；准确状态以 [docs/kernel/TEST_REPORT.md](TEST_REPORT.md) 和 [dash/out/artifacts/BUILD_INFO](../../dash/out/artifacts/BUILD_INFO) 为准。本页部分章节保留了早期 6.6.144 调研痕迹，遇到冲突不要沿用旧状态。

> 大源码树（AOSP common、MiCode、CC 主内核）故意没有做成子模块，避免把几 GB 历史带进仓库；它们的浅克隆位置和上游地址在下文单独记录。

### 1. 子模块

以下子模块已加入 `.gitmodules` 和 git 索引（尚未创建提交）。当前 clone 使用 `--depth 1`，但没有把 depth 写进 `.gitmodules`；新机器请用 `git clone --recurse-submodules --shallow-submodules` 或 `git submodule update --init --recursive --depth 1`。

| 路径 | 上游 | 分支 | 当前 pin | 用途 |
|---|---|---|---|---|
| [BakaSU](../../BakaSU) | https://github.com/Baka-SU/BakaSU.git | main | `d5e9e025b8b4` | BakaSU/KSU 内核源码（`BakaSU/kernel`），当前内建 + SUSFS |
| [third_party/sukisu-patch](../../third_party/sukisu-patch) | https://github.com/SukiSU-Ultra/SukiSU_patch.git | main | `eec45788c9a1` | SukiSU 补丁集合；`other/zram` 下有 lz4k/lz4k_oplus/lz4kd 参考 |
| [third_party/susfs4ksu](../../third_party/susfs4ksu) | https://gitlab.com/simonpunk/susfs4ksu.git | gki-android15-6.6 | `0606e19afae9` | SUSFS kernel patches；`dash/patches/0003` 的来源 |
| [third_party/dash-droidspaces](../../third_party/dash-droidspaces) | https://github.com/lakitu12/kernel_dash_droidspaces.git | main | `6039943a9c15` | dash 的 DroidSpaces/SukiSU 参考项目；`patches/os4-vendor-hooks` 在这里；实验性，README 已报告 call site bootloop |
| [third_party/hyperos-lz4kd](../../third_party/hyperos-lz4kd) | https://github.com/2108282/hyperos-lz4kd.git | main | `e58761a19874` | 小米 14 的 LZ4KD/自动切换参考；非 delta zram 实现 |
| [third_party/cc-dash-build](../../third_party/cc-dash-build) | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_build.git | dash-w-oss | `627ef9ba0d31` | CC dash 的 repo manifest / Kleaf 构建脚本 |
| [third_party/cc-dash-device-modules](../../third_party/cc-dash-device-modules) | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_device_modules.git | dash-w-oss | `94914f6bc83f` | dash DTS、`kernel/configs/dash*.config`、重实现的触摸/热管理/millet/mi_memory/UFS 模块源码 |
| [third_party/cc-dash-mtk-modules](../../third_party/cc-dash-mtk-modules) | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_mtk_modules.git | dash-w-oss | `d3e32dcf9f67` | MediaTek camera/connectivity/GPU/等模块源码 |
| [third_party/cc-dash-bazel-rules](../../third_party/cc-dash-bazel-rules) | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_bazel_mgk_rules.git | lineage-23.2 | `1573a08b7d6b` | CC dash Kleaf/MGK 构建规则 |

注意：CC 的 device modules 中很多厂商模块是**反汇编/逆向重实现**，不是原厂源码；README 明确写“it compiles doesn't mean it works”，且**不要直接刷到 HyperOS 上**。只作为接口/实现参考。

### 2. 大源码树（非子模块，浅克隆/本地）

| 路径 | 上游 | pin / 分支 | 用途 |
|---|---|---|---|
| [dash/src/aosp/common](../../dash/src/aosp/common) | https://android.googlesource.com/kernel/common | tag `android15-6.6-2026-01_r1`，commit `f9c84f40b6ba6152b6f51daba0193c9564af4172`（6.6.118） | 当前自编内核源码；由 `dash/versions.env` 固定 |
| [dash/src/micode-kernel](../../dash/src/micode-kernel) | https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git | `2d28e280ea36` / `dash-w-oss`（6.6.89） | 官方公开 dash 参考源码；`mm/memfd-ashmem-shim*` 来源 |
| [dash/src/MTK_kernel_device_modules](../../dash/src/MTK_kernel_device_modules) | https://github.com/MiCode/MTK_kernel_device_modules.git | `9c62564` / `dash-w-oss` | 官方公开 dash DTS/device modules 参考 |
| [dash/src/MTK_kernel_modules](../../dash/src/MTK_kernel_modules) | https://github.com/MiCode/MTK_kernel_modules.git | `8c88cf7` / `dash-w-oss` | 官方公开 MTK camera/WiFi 等模块参考 |
| [dash/toolchains/clang-prebuilt](../../dash/toolchains/clang-prebuilt) | https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 | `62dc563` / `main-kernel-build-2024` | AOSP clang r510928，与 stock 编译链一致 |
| `/tmp/cc_dash_tree`（临时） | https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash.git | `86b65f8476c7` / `dash-w-oss`（6.6.144） | CC 主内核参考；2.8GB，**故意不做子模块**，需要时按 shallow 方式取 |

大源码树的更新方式：

```bash
# AOSP common（脚本）
cd dash
bash scripts/sync-aosp.sh
# 或手工
git -C src/aosp/common fetch --depth=1 origin android15-6.6
git -C src/aosp/common checkout --detach <commit>

# MiCode 参考树（不要拉完整历史）
git clone --depth=1 --filter=blob:none --no-checkout \
  -b dash-w-oss https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git dash/src/micode-kernel

# CC 主内核（只在需要时，2.8GB）
git clone --depth=1 --filter=blob:none \
  -b dash-w-oss https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash.git /tmp/cc_dash_tree
```

### 3. 原厂设备审计资产

全部在 [dash/out/device-audit](../../dash/out/device-audit)。手机侧只在 `/data/local/tmp/dash-audit` 写文件；分区只读 `dd`，没有写分区。

| 路径 | 内容 |
|---|---|
| [phone-dump](../../dash/out/device-audit/phone-dump) | 201MB 原厂审计包：`boot_b.img`、`init_boot_b.img`、`vendor_boot_b.img`、`dtbo_b.img`、`vbmeta_b.img`、`stock.config.gz`、`stock.kallsyms`、`getprop.txt`、`lsmod.txt`、`dmesg.txt`、模块 tar；[SHA256SUMS](../../dash/out/device-audit/phone-dump/SHA256SUMS) |
| [stock.config](../../dash/out/device-audit/stock.config) | 原厂完整 config（2259 项） |
| [config.diff](../../dash/out/device-audit/config.diff) | 原厂 config 与当前产物 config 的差异 |
| [stock.kallsyms](../../dash/out/device-audit/stock.kallsyms) | 原厂符号/导出名（地址被 kptr 限制为 0） |
| [vendor_ramdisk_root](../../dash/out/device-audit/vendor_ramdisk_root) | `vendor_boot` 解包：275 个厂商模块 + DTB 等 |
| [vendor_modules](../../dash/out/device-audit/vendor_modules) | `vendor_dlkm` 的 289 个模块 |
| [system_modules](../../dash/out/device-audit/system_modules) | `system_dlkm` 的 78 个模块 |
| [micode-memfd](../../dash/out/device-audit/micode-memfd) | MiCode `memfd-ashmem-shim` 源码副本 |

当前原厂 boot 布局（`_b`）：`boot_b` 64MB/header v4/kernel 17,317,780B；`init_boot_b` ramdisk 3,301,406B；`vendor_boot_b` vendor ramdisk 63,506,233B + DTB 536,161B。只备份了 active `_b`；`boot_a`/`init_boot_a`/`vendor_boot_a`/`dtbo_a`/`vbmeta_a` 及 `vbmeta_system/vendor` 尚未收集。

### 4. 构建、补丁、产物

| 路径 | 用途 |
|---|---|
| [docs/kernel/README.md](README.md) | dash 构建/更新流程 |
| [docs/kernel/DEV_NOTES.md](DEV_NOTES.md) | 仓库开发笔记合并版（自动生成，给 LLM 的避坑包；`make notes` 重新生成） |
| [dash/versions.env](../../dash/versions.env) | AOSP / BakaSU / SUSFS / clang 版本锁定 |
| [dash/Makefile](../../dash/Makefile) | `deps/toolchain/source/patches/config/build` 入口 |
| [dash/scripts](../../dash/scripts) | 源码同步、补丁、配置、构建脚本 |
| [dash/patches/series](../../dash/patches/series) | 当前 16 个补丁：vendor-ko 兼容、BakaSU、SUSFS/read hook、Xiaomi F2FS/EROFS、9 个 OS4 vendor hooks |
| [dash/patches/0001-vendor-ko-compat.patch](../../dash/patches/0001-vendor-ko-compat.patch) | 绕过厂商 `.ko` 的签名/vermagic/CRC/namespace/protected export 检查 |
| [dash/patches/0003-susfs-gki-android15-6.6.patch](../../dash/patches/0003-susfs-gki-android15-6.6.patch) | 上游 SUSFS 6.6 patch |
| [dash/out/artifacts](../../dash/out/artifacts) | 当前 6.6.118 构建产物：`Image`、`Image.lz4`、`boot.img`、`vmlinux`、`System.map`、`config`、`BUILD_INFO`、`SHA256SUMS` |

当前产物：`6.6.118-4k #29`（clang r510928，0 error/0 warning），BakaSU built-in
+ SUSFS inline Hook；已生成 64MB AVB 保留式 `boot.img`（SHA256
`a28344f9...7cac`）并在真机启动，584 个 stock 非 LKM 模块和
node_cache/os_cpu_qi 链加载。2026-10-30 已补 F2FS 单开关 iostat、
`f2fs_fault_report`、lock/priority tracepoint 和 VIP 选择策略。详见
[docs/kernel/TEST_REPORT.md](TEST_REPORT.md)。

### 5. 按任务导航

- 想快速避坑/让 LLM 接手：先读 [docs/kernel/DEV_NOTES.md](DEV_NOTES.md)，再按其中的权威顺序读源文档。
- 想构建/更新内核：从 [docs/kernel/README.md](README.md) 开始，版本改 [dash/versions.env](../../dash/versions.env)。
- 想恢复原厂 boot/kernel：用 [phone-dump](../../dash/out/device-audit/phone-dump) 里的 `boot_b.img` 等；不要碰 `lk`。
- 想改 BakaSU/KSU：看 [BakaSU/kernel](../../BakaSU/kernel) 和 [0002-bakasu-integration.patch](../../dash/patches/0002-bakasu-integration.patch)。
- 想改 SUSFS：看 [third_party/susfs4ksu](../../third_party/susfs4ksu)，对应 [0003](../../dash/patches/0003-susfs-gki-android15-6.6.patch)；注意 BakaSU 三参数 `ksu_handle_sys_read` 的 [0004](../../dash/patches/0004-susfs-bakasu-hooks.patch)。
- 想研究 lz4kd/zram：看 [third_party/sukisu-patch/other/zram](../../third_party/sukisu-patch/other/zram)、[third_party/hyperos-lz4kd](../../third_party/hyperos-lz4kd)；当前结论是 delta 未真正接入 zram。
- 想找 dash DTS / 原厂模块接口：看 [third_party/cc-dash-device-modules](../../third_party/cc-dash-device-modules)，尤其是 `arch/arm64/boot/dts/mediatek/dash*`、`kernel/configs/dash*.config`、`drivers/ufs/`、`drivers/input/touchscreen/`、`drivers/misc/xiaomi/`。这些是逆向重实现，不是 stock 源码。
- 想找 OS4 vendor hooks：看 [third_party/dash-droidspaces/patches/os4-vendor-hooks](../../third_party/dash-droidspaces/patches/os4-vendor-hooks)；上游 README 报告过 full call site bootloop，但本仓库完整 13-hook + 全调用点镜像已实机启动，冲突时以 [docs/kernel/TEST_REPORT.md](TEST_REPORT.md) 为准。
- 想走 CC 的 Kleaf 构建：看 [third_party/cc-dash-build/default.xml](../../third_party/cc-dash-build/default.xml) 和 [third_party/cc-dash-bazel-rules](../../third_party/cc-dash-bazel-rules)。

### 6. 更新与 clone 规则

```bash
# 新机器拉本项目 + 子模块（浅）
git clone --recurse-submodules --shallow-submodules <mikernel-url>
# 或已有仓库
git submodule update --init --recursive --depth 1

# 只更新某个子模块到其分支（会移动 pin，需手动 review）
git submodule update --remote --merge third_party/susfs4ksu
```

- 子模块 pin 以 `git submodule status` 为准；不要在生产构建里随意 `--remote`。
- AOSP、MiCode、CC 主内核等大源码树用浅克隆，不放进子模块；只保留路径和 pin。
- `dash/src`、`dash/toolchains`、`dash/out` 已在 `dash/.gitignore` 中忽略。

### 7. 已知缺口与风险

- 原厂精确源码：stock `6.6.118` commit `b9cc6ec16bc8`（设备）/CC 文档里的 `c44b714366cc` 不是 AOSP tag；当前使用 AOSP `android15-6.6-2026-01_r1`（`f9c84f40`，6.6.118）作为近似基线，MiCode 公开分支是 `6.6.89`。
- 仍缺 Xiaomi 私有内核特性**原厂源码**：`XIAOMI_ENHANCED_IOSTAT`、`XIAOMI_EROFS_IOSTAT`、`F2FS_VIP_FILE`、`F2FS_FS_HYBRID_UFS`、`BLOCK_HYBRID_UFS`。当前已有行为级实现；F2FS 单开关 iostat、`f2fs_fault_report`、lock/priority tracepoint 和 VIP 选择策略已补齐；hybrid、EROFS per-device 统计仍未复刻。
- 仍缺 `node_cache.ko` / `os_cpu_qi.ko` 源码；当前用 stock 二进制 + 13 个 hook，真机加载和 KCFI 静态匹配已通过，调用点等价性未做 stock 二进制逐点对照。
- `MEMFD_ASHMEM_SHIM` 在 AOSP 6.6.118 树内已自带实现，当前 6.6.118 构建只启用配置（`memfd_ashmem_shim_ioctl` 已编入）。
- 当前产物为 `6.6.118-4k #29`（无 dirty 尾巴），已生成 boot.img 并在真机验证 CFI/厂商模块/BakaSU；详见 [docs/kernel/TEST_REPORT.md](TEST_REPORT.md)。
- 只备份 active `_b` boot 链；全机救砖资产（`lk`、`super`、system/vendor 等）没有收集；不要刷 `lk`。
- CC 仓库是 LineageOS 方向、逆向后重实现，**不要直接刷 HyperOS**，也不能当官方 stock 等价源码。
- 2026-10-30 已补 F2FS lock/priority tracepoint、VIP 选择策略（hook + 保守
  fallback）和 4 个 lock sysfs；真机已验证 uplift/restore、lock elapsed 和 VIP
  计数增删；stock core tracepoint 1860/1860 对齐、GKI dynamic task_struct
  已补齐。仍缺的 stock-only 项：hybrid UFS、EROFS per-device 统计、
  SCSI fastdiscard、UFS 官方 37 文件源；详见
  [OPEN_ISSUES.md](OPEN_ISSUES.md)。

### 8. 上游参考

- AOSP kernel common：https://android.googlesource.com/kernel/common
- AOSP 6.6.118 tag：https://android.googlesource.com/kernel/common/+/refs/tags/android15-6.6-2026-01_r1
- BakaSU：https://github.com/Baka-SU/BakaSU
- SUSFS4KSU：https://gitlab.com/simonpunk/susfs4ksu
- SukiSU patches：https://github.com/SukiSU-Ultra/SukiSU_patch
- dash DroidSpaces 参考：https://github.com/lakitu12/kernel_dash_droidspaces
- HyperOS LZ4KD 参考：https://github.com/2108282/hyperos-lz4kd
- CC dash 主内核：https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash
- MiCode dash：https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/dash-w-oss
- MiCode 6.6.118（其他设备）：https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/mist-w-oss
- Mi15 6.6.118 参考（含 stock config/构建脚本）：https://github.com/Re-s/Mi15-Droidspaces-Kernel
- dash 6.6.118 完整 dump（参考，不下载）：https://github.com/oss-dash/poco_dash_dump
- AOSP clang prebuilt：https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86

---

<a id="src-11"></a>
## 11. 缺口调研台账：公开源码/近似来源/结论

> 来源：[`docs/project/GAP_RESEARCH.md`](../project/GAP_RESEARCH.md) · 10446 字节 · SHA256 `0e634fe9b74a13c63083f25d157b627db6c958c69ad3cb68d7416cd8baa8da6e`
> 类别：仓库上下文 · 状态：仓库上下文（可能有过时状态）
> 注意：这是检索台账，不是构建状态；2026-10-30 状态追加在文末，部分链接只记录未下载。

目标：逐个查清 stock 6.6.118 相关缺口，优先找可直接使用的源码；沾边但不精确的链接只记录，不下载。检索时间：2026-10-29；实现状态更新：2026-10-30（见文末）。

检索方式：WebSearch（多组中英文关键词）、GitHub repo/code/commit search、Sourcegraph、GitLab API、Gitee API、MiCode 分支扫描、本地源码树核对。

### 1. 原厂 6.6.118 精确源码

#### 结论

**没有找到 dash 的精确厂商 6.6.118 源码。** 公开的最佳替代是 AOSP `android15-6.6-2026-01_r1`（6.6.118），再叠加原厂 config 和可获得的补丁。

#### 找到的精确/近似基线

| 来源 | 内容 | 判断 |
|---|---|---|
| [AOSP android15-6.6-2026-01_r1](https://android.googlesource.com/kernel/common/+/refs/tags/android15-6.6-2026-01_r1) | 6.6.118 GKI 源基线 | 精确 6.6.118 上游，不是 dash 厂商树 |
| [Re-s/Mi15-Droidspaces-Kernel](https://github.com/Re-s/Mi15-Droidspaces-Kernel) | 明确写 stock `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`；含 stock config、boot 构建脚本、DroidSpaces 补丁 | **高价值参考**，不是 dash 源码 |
| [MiCode `mist-w-oss`](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/mist-w-oss) | Xiaomi 6.6.118 源，另一个设备（REDMI Note 17/POCO M8 Power 5G） | 6.6.118 源候选，但不是 dash，也没有 Xiaomi F2FS 特性 |
| [MiCode `dada-v-oss`](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/dada-v-oss) | 6.6.30，Xiaomi 15/15 Pro | 版本太旧，不适用 |
| [android-kernels/xiaomi-dash-w-oss](https://github.com/android-kernels/xiaomi-dash-w-oss) | MiCode `dash-w-oss` 的镜像，6.6.89 | 旧版本镜像，不是 6.6.118 |
| [MiCode `dash-w-oss`](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/dash-w-oss) | 6.6.89，dash 官方公开源 | 公开版本落后于设备实际 6.6.118 |

#### 沾边线索（只记录，不下载）

- [ghostlock-app README_ZH](https://github.com/YuKongA/ghostlock-app/blob/main/README_ZH.md)：把 `6.6.118-android15-8-gc44b714366cc` 映射到 REDMI K80 Pro / Turbo 5 Max / POCO X8 Pro Max / Xiaomi Pad 7 Ultra；只是版本映射，不是源码。
- [CC dash 主内核](https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash)：6.6.144 LineageOS 方向，不是 stock 6.6.118。
- [donyanchen/android_kernel_xiaomi_sm8850](https://github.com/donyanchen/android_kernel_xiaomi_sm8850)：6.12 设备配置/补丁，不是 6.6.118 源。

### 2. Xiaomi F2FS/EROFS/hybrid 实现

#### 结论

**没有找到公开源码。** 只找到配置项、符号和二进制，找不到 `XIAOMI_ENHANCED_IOSTAT`、`XIAOMI_EROFS_IOSTAT`、`F2FS_VIP_FILE`、`F2FS_FS_HYBRID_UFS`、`BLOCK_HYBRID_UFS` 的实现。

#### 已确认的配置存在

- [Re-s stock 6.6.118 config](https://github.com/Re-s/Mi15-Droidspaces-Kernel/blob/main/docs/stock-6.6.118-android15-8.config)：全部包含上述选项。
- 我们设备 dump 的 [stock.config](../../dash/out/device-audit/stock.config) 同样包含。
- CC device modules 和 MiCode 分支的 Kconfig 里没有这些选项，说明实现不在这些公开树的当前分支。

#### 检索结果

- GitHub code search：只命中 `ikconfig`/`*.config`、DroidSpaces 配置、CC 配置；没有源码。
- Sourcegraph（含 forks/archived）：`f2fs_hw_support_hybrid`、`f2fs_vip_bsearch`、`erofs_iostat_update`、`device_hybrid_capable` 均无匹配。
- GitHub code search 的 `erofs_iostat_update` 只命中 OnePlus/LineageOS 的 `vendor_hooks.c`、`fs/erofs/zdata.c`，不是 Xiaomi IOSTAT 实现。
- MiCode 全分支扫描：`dash-w-oss`、`dada-v-oss`、`mist-w-oss` 等都没有这些 Kconfig/源码；`mist-w-oss` 虽然 SUBLEVEL=118，但 F2FS/EROFS 特性为 0。
- 中文搜索只命中 F2FS/EROFS 通用介绍，没有 Xiaomi 私有实现。

#### 沾边链接（只记录，不下载）

- [Re-s config](https://github.com/Re-s/Mi15-Droidspaces-Kernel/blob/main/docs/stock-6.6.118-android15-8.config)
- [donyanchen sm8850](https://github.com/donyanchen/android_kernel_xiaomi_sm8850)（6.12 配置/补丁）
- [klarnet2009/dada-closed-modules](https://github.com/klarnet2009/dada-closed-modules)（closed-module/struct-layout 文档）
- [hgn284/xiaomi_17pro_max_sm8850](https://github.com/hgn284/xiaomi_17pro_max_sm8850)、[Apr-YT/gg-rwproc33-driver](https://github.com/Apr-YT/gg-rwproc33-driver)、[wfqefwqf/share-poc-XRing-O1](https://github.com/wfqefwqf/share-poc-XRing-O1)：只有 stock config/日志。

### 3. node_cache.ko / os_cpu_qi.ko 源码

#### 结论

**没有公开源码。** 只有 stock 二进制、符号依赖和 OS4 hooks 补丁；没有找到厂商实现或等价重写。

#### 已确认

- 设备 stock 模块：`node_cache.ko`（F2FS node cache，依赖 5 个 tracepoint + LZ4）、`os_cpu_qi.ko`（QoS，依赖 40 个 tracepoint）。
- [dash-droidspaces os4-vendor-hooks](https://github.com/lakitu12/kernel_dash_droidspaces/tree/main/patches/os4-vendor-hooks) 只补 hook 注册/调用点，不含这两个模块源码；作者报告 full call site bootloop。
- MiCode/CC/DroidSpaces 源码树中没有 `node_cache`/`os_cpu_qi` 路径。

#### 沾边链接（只记录，不下载）

- [lakitu 的 os4-vendor-hooks](https://github.com/lakitu12/kernel_dash_droidspaces/tree/main/patches/os4-vendor-hooks)
- [CC device_modules](https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_device_modules)：有 touch/thermal/millet/UFS 等重实现，没有这两个模块。
- 我们设备的 [node_cache.ko](../../dash/out/device-audit/vendor_ramdisk_root/lib/modules/node_cache.ko) 和 [os_cpu_qi.ko](../../dash/out/device-audit/vendor_modules/modules/os_cpu_qi.ko)：stock 二进制，仅用于 ABI/依赖分析。

### 4. UFS 与固件/设备 dump

#### 4.1 UFS 官方源码：找到

[MiCode/MTK_kernel_device_modules `dash-w-oss`](https://github.com/MiCode/MTK_kernel_device_modules/tree/dash-w-oss) 的 `drivers/ufs/` 有 37 个文件，包括：

- `ufs-mediatek-ise.c/.h`
- `ufs-mediatek-dbg.c/.h`
- `ufs-mediatek-mbrain.c`
- `ufs-mediatek-mimic.c`
- `ufs-mediatek-perf.c`
- `ufs-mediatek-rpmb.c`
- `ufs-mediatek-sysfs.c`
- `ufs-mediatek.c/.h`
- `vendor/ufsfeature.c`、`ufshid.c`、`ufsringbuf.c`、`ufsshpb.c`、`ufstw.c` 等

这是**官方公开 UFS 源码**，可替代 CC device modules 里的逆向版 `ufs-mediatek-ise`。本地位置：[dash/src/MTK_kernel_device_modules](../../dash/src/MTK_kernel_device_modules) 下的 `drivers/ufs`（当前 blobless，按需 sparse checkout）。

#### 4.2 dash 完整 dump：找到，未下载

以下是**同代号 dash 的完整设备 dump**，不是源码；可作为 boot_a、stock kernel、DTB、kallsyms、vendor/system 模块的补充。都只记录，不下载。

| 仓库 | 系统/内核 | 内容 |
|---|---|---|
| [oss-dash/poco_dash_dump](https://github.com/oss-dash/poco_dash_dump) | OS3.1 / **6.6.118** / POCO dash | `boot/kernel` 36.8MB、`boot.elf` 42MB、`boot/dtb`、`boot/dts`、`ikconfig`、`kallsyms.txt`、`boot.img.aa/.ab`、`init_boot`、`vendor_boot`、`system_dlkm`、`vendor_dlkm`、`aosp-device-tree` |
| [xiaomi-mt6991/poco_dash_dump](https://github.com/xiaomi-mt6991/poco_dash_dump) | OS3.1 / 6.6.118 | 同上结构（另一个 dump） |
| [HexaUnion/redmi_dash_dump](https://github.com/HexaUnion/redmi_dash_dump) | OS3.1 / 6.6.118 | boot/init_boot/vendor_boot/dtbo、ikconfig、kallsyms、system/vendor |
| [xiaomi-dash-dev/redmi_dash_dump](https://github.com/xiaomi-dash-dev/redmi_dash_dump) | OS3.0 / **6.6.89** | 旧版完整 dump；含 boot/vendor_boot 分卷、ikconfig、kallsyms |
| [ONFIX dash 教程/ROM](https://onfix.cn/course?bid=1&mid=30095) | OS3.0.x | boot/init_boot 资源索引；需付费下载 |

`oss-dash` 的 `aosp-device-tree/BoardConfig.mk` 还确认了 dash boot 布局：header v4、kernel base `0x7fff8000`、页大小 4096、boot 64MB、init_boot 8MB、vendor_boot 64MB、super 9.1GB；这和我们从手机读到的布局一致。

#### 4.3 固件/完整 dump 的价值

- 可补 active `_b` 之外的 `boot_a`/`init_boot_a`/`vendor_boot_a` 等资产；
- `boot.elf`/`kallsyms.txt` 可补 stock ABI/符号分析（不提供源码）；
- `boot/dtb`、`boot/dts` 可补 dash 设备树；
- `vendor_dlkm`/`system_dlkm` 可补另一版 stock 模块；
- **不能**补 F2FS/EROFS/hybrid 源码或 `node_cache`/`os_cpu_qi` 源码。

### 5. 仍缺 / 下一步

仍然缺失：

- dash 精确 6.6.118 **厂商源码**（公开只有 AOSP tag、MiCode 6.6.89、mist 6.6.118 其他设备）。
- `XIAOMI_ENHANCED_IOSTAT`、`XIAOMI_EROFS_IOSTAT`、`F2FS_VIP_FILE`、`F2FS_FS_HYBRID_UFS`、`BLOCK_HYBRID_UFS` 实现源码。
- `node_cache.ko`、`os_cpu_qi.ko` 源码。
- boot_a/另一槽位、lk/super、完整固件（dump 仓库可补部分，但未下载）。

建议：

1. 以 AOSP `android15-6.6-2026-01_r1` + 设备 stock config 为主基线；`mist-w-oss` 可作为 6.6.118 源参考。
2. 从 MiCode `MTK_kernel_device_modules` sparse 取 `drivers/ufs`，替代 CC 逆向 UFS。
3. 如必须补 boot_a/stock kernel/DTB，优先只拉 `oss-dash/poco_dash_dump` 的 `boot/`、`boot/dtb`、`ikconfig`、`kallsyms.txt`，不要拉整个 6.8GB 仓库。
4. F2FS/EROFS/hybrid 和 `node_cache`/`os_cpu_qi` 没有公开源码；当前是行为级/接口级实现，不能声称与 stock 逐行等价。剩余差异需要原厂 6.6.118 源码、二进制反推或接受功能缺失。

#### 2026-10-30 实现状态更新

- **已做**：AOSP 6.6.118 + stock config + BakaSU/SUSFS + 13 个 OS4 hooks；
  真机启动；F2FS 增强 iostat 单开关语义；`f2fs_fault_report`；
  `fs/f2fs/lock.c`、`f2fs_lock_elapsed_time`、`f2fs_priority_uplift/restore`
  和 4 个 lock sysfs；F2FS VIP 的 hook + 保守 fallback。真机已验证
  uplift/restore、lock elapsed、VIP 计数增删和开关清零。
- **已补**：stock core tracepoint 1860/1860 对齐（51 个 hook、44 个调用点、
  2 个 LZ4 事件）；GKI dynamic task_struct；F2FS `gc_lock` 全部调用点接入
  lock trace wrapper。
- **仍缺**：hybrid UFS、EROFS per-device iostat、SCSI fastdiscard、UFS
  官方 37 文件源。`/proc/iostat_enhance` 经复核不是 dash stock ABI。
- **仍无**：dash 精确 6.6.118 厂商源码；上述实现是行为级/等价路径，不是原厂
  源码逐行复刻。当前运行状态以 [TEST_REPORT](TEST_REPORT.md) 和
  [OPEN_ISSUES](OPEN_ISSUES.md) 为准。

---

<a id="src-12"></a>
## 12. node_cache / os_cpu_qi 的 stock 行为调查

> 来源：[`docs/project/DEVICE_MODULES.md`](../project/DEVICE_MODULES.md) · 6039 字节 · SHA256 `8f7140e5e363889727d4b70b38f42eefa43d72e540929fb3c2403f3dfb880f40`
> 类别：仓库上下文 · 状态：仓库上下文（可能有过时状态）
> 注意：数值是 stock 运行态历史值；当前自编内核的实测值见 TEST_REPORT §8。

> **定位：stock 运行态观察（2026-10-29），不是当前自编内核的实时快照。**
> 文中的 `cur_cnt/cur_bytes` 等是 stock 启动后的历史值；当前 #29 内核的实测值见
> [TEST_REPORT §8](TEST_REPORT.md#8-真机运行验证)。公开源码仍未找到，
> 以下是对 stock 二进制和运行时状态的推断。

调查方式：设备 `adb shell su` 只读检查（sysfs/proc/tracefs、模块状态、slab、dmesg）+ 电脑侧模块 ELF 的符号/字符串分析。没有写任何分区。公开源码仍未找到，以下是对 stock 二进制和运行时状态的推断。

### node_cache

#### 运行时状态

- 已加载，`refcnt=0`，无 holders；依赖 `zsmalloc`。
- `/sys/kernel/node_cache/` 实测：
  - `max_bytes = 41943040`（40MB 上限）
  - `cur_cnt = 35051`
  - `cur_bytes = 13231761`（约 12.6MB 压缩数据）
  - `comp_enable = 1`
  - `comp_ratio = 50`
  - `swapin_cnt = 96433`
  - `invalid_cnt = 3`
  - `shrink_cnt = 0`
  - `reclaim_policy = 0`
  - `total_ram_mb = 15206`
  - `lowmem_mode = 0`
  - `avail_low_wmark_mb = 500`
  - `shrink_wmark = 75`
  - `trace_enable = 0`
- slab：`node_cache_entry` 35637/50560 objects，object size 32B；约 1.1MB 活跃元数据（加 slab 约 1.6MB）。
- 模块自身 coresize 36KB。

#### 从符号/字符串可确认的行为

- 模块描述：`node cache for f2fs`，作者 `qiwenjie@xiaomi.com`，GPL v2，依赖 zsmalloc。
- 关键函数：`node_cache_attach`、`node_cache_lookup_locked`、`node_cache_compress_folio`、`node_cache_decompress_folio`、`node_cache_valid_node_data`、`node_cache_shrink_*`、`node_cache_put`。
- 使用 hook：`do_new_mount_fc`、`filemap_get_folio_end`、`put_super`、`remove_mapping`、`remove_mapping_failed`。
- 依赖 LZ4（模块未定义 `LZ4_compress_default` / `LZ4_decompress_safe` 等），以及 zsmalloc pool。

#### 实际作用判断

它是一个 **F2FS node 页的压缩缓存层**：

1. 在 F2FS 挂载时 attach；
2. 当 node folio 即将从 page cache 移除/回收时，压缩后放进 zsmalloc 池，而不是直接丢弃；
3. 再次访问 node 页时从压缩池解压回 page cache；
4. 有 shrinker、低内存水位、压缩比例、回收策略和 trace 开关；
5. 当前 35k 条目、约 12.6MB 压缩数据、96k 次 swapin，说明它确实在工作，而不是空模块。

收益是**节省 F2FS 元数据占用的物理内存/减少重新读 UFS**；代价是压缩/解压 CPU 开销。它不直接提升文件读写带宽。

### os_cpu_qi

#### 运行时状态

- 已加载，`refcnt=4`；holders：`cpq`、`mi_reclaim`、`os_cpu_qs`、`task_turbo`。
- 依赖：`os_cpu_perf_actuator`、`vip_sched`、`plat_common`。
- `/sys/kernel/qos_inherit/inherit_enable = QI_ENABLE: 1`
- `/sys/kernel/qos_sched/sched_enable = QS_ENABLE: 1`
- `/sys/kernel/qos_sched/rt_prio`：`ui prio: 98`、`render prio: 98`
- `/proc/sys/kernel/xr_qos/`：
  - `mutex_normal_opt_spin_time_ns = 60000`
  - `mutex_qos_opt_spin_time_ns = 100000`
- `qos_inherit_events` 下的 tracepoint 当前全部 `enable=0`（未开启采样）。

#### 从符号/字符串可确认的行为

- 模块描述：`MI QOS inherit Driver`，作者 `Shaohua Fan <fanshaohua@xiaomi.com>`，GPL v2。
- 关键函数：`qi_set_qos`、`qi_get_qos_by_tid/pid`、`get_static_qos_lvl`、`get_proc_static_qos_lvl`、`get_qos_lvl`、`is_qos_task`、`kern_qi_set_qos`。
- 继承路径：`binder`、`mutex`、`rwsem`、`percpu-rwsem`、`futex`、`fuse`、`rcu`；每个都有 `inherit/uninherit`、`iter_*`、`do_*` 逻辑。
- tracepoint：`qos_inherit_events` 下有 `qi_set_qos`、`qi_get_qos_by_tid/pid`、binder set/restore/proc transaction/buffer release、mutex/rwsem/futex/fuse/rcu inherit/uninherit、iter、GPU blocked/unblocked、free task 等。
- 依赖 `os_cpu_perf_actuator` / `vip_sched` / `plat_common`，说明它不是单独调频，而是把 QoS 等级交给 Xiaomi/MTK 的 CPU 性能控制链。

#### 实际作用判断

它是一个 **QoS 继承与调度提升引擎**：

1. 用户态（Xiaomi 框架/服务）通过 `qi_set_qos` 给任务设置 static/dynamic QoS 等级；
2. 任务在 binder、mutex、rwsem、percpu-rwsem、futex、fuse、RCU 上阻塞/被唤醒时，把 QoS 临时继承给锁持有者或对端任务；
3. 通过 `os_cpu_perf_actuator`、`vip_sched`、`plat_common` 提升 CPU 调度/频率/优先级；
4. `qos_sched` 给 UI/render 设置 RT 优先级 98，`qos_inherit` 开关当前都启用；
5. 任务释放/唤醒/退出时 uninherit，避免永久提升。

它优化的是**锁竞争、binder/FUSE 跨进程、UI/render 的尾延迟**，不是通用省电机制；boost 会消耗额外 CPU/功耗。当前 `refcnt=4`、多个 holder 说明系统里有实际使用链。

### 对我们自编内核的意义

- 两者都不是开机必需；但缺失对应 hook 会让 stock 模块加载失败（`node_cache` 需要 4 个新 hook + LZ4；`os_cpu_qi` 需要 9 个新 hook，以及大量 AOSP 已有 hook）。
- 当前 6.6.118 + BakaSU 构建已导出 13 个 hook 和 LZ4，KCFI
  13/13 通过，真机加载 `node_cache`/`os_cpu_qi`；完整 hook 调用点仍需在压力、
  suspend/resume 和异常退出路径持续验证。
- 公开源码仍未找到；只能从 stock 二进制/运行时行为推断，不能声称等价重写。
- 如果只想保证开机和基本功能，可以先不带这两个模块的厂商 hook；如果要在 HyperOS 下保留它们的性能/内存行为，必须保证 hook 原型和调用点安全，且注意 `node_cache` 的压缩 CPU 成本与 `os_cpu_qi` 的 boost 功耗。

### 证据位置

- 模块二进制：[node_cache.ko](../../dash/out/device-audit/vendor_ramdisk_root/lib/modules/node_cache.ko)、[os_cpu_qi.ko](../../dash/out/device-audit/vendor_modules/modules/os_cpu_qi.ko)
- 设备原始审计：[phone-dump](../../dash/out/device-audit/phone-dump)
- 缺口调研：[GAP_RESEARCH.md](../project/GAP_RESEARCH.md)
- 导航：[NAVIGATION.md](../project/NAVIGATION.md)

---

<a id="src-13"></a>
## 13. 交接任务书与验收标准（历史输入）

> 来源：[`docs/handoff/TASK_BRIEF.md`](../handoff/TASK_BRIEF.md) · 12697 字节 · SHA256 `6cc641eb2f82e514c9160832cbd8f49fe9a051b3c8a3221c6ec30bafbbe543b2`
> 类别：需求 · 状态：需求/验收（设备操作受约束）
> 注意：任务书写于 2026-10-29 交接时（文中“当前 6.6.144/只生成 Image”是旧状态）；本仓库已完成 6.6.118 并实机启动。保留原文追溯，不作为当前执行指令。

> **历史交接输入（2026-10-29），不是当前状态。** 文中的“当前 6.6.144/只生成
> Image”和包内 `project/dash/versions.env` 都是交接时状态；接收方后来已完成
> 6.6.118 构建、真机启动和部分 stock parity 修复。当前状态以
> [kernel/TEST_REPORT.md](TEST_REPORT.md)、
> [kernel/OPEN_ISSUES.md](OPEN_ISSUES.md) 和
> [handoff/PACKAGE.md](../handoff/PACKAGE.md) 为准。本文保留原文用于追溯需求，不再按它
> 重新执行或覆盖当前实现。

本包是 dash 内核工作的完整交接材料。目标、设备事实、输入、原厂资产、模块、配置、boot 镜像、UFS/memfd 源码和外部 pin 都在包内或链接中。

**实现路径不限**：原厂源码恢复、等价重写、兼容 shim、行为级实现、上游 backport、二进制接口适配、重新设计或其他能达到目标的方案都可以。请在报告中说明所选方案、与 stock 行为的差异、验证结果和性能/能效影响；鼓励采用比现状更完整、更稳健的实现。

### 0. 执行环境默认（避免阻塞）

- 接收方可能**没有真机**，也**不能向用户提问**。不需要等待设备或询问确认。
- 无真机时：完成源码、补丁、配置、构建、静态 ABI/KCFI/符号检查和 boot 镜像生成；不做 fastboot、不写分区。实机启动可由设备所有者后续执行，不阻塞本任务。
- 网络可用时：按 `links/SOURCES.md` 获取 AOSP 6.6.118、BakaSU、SUSFS、clang r510928；网络不可用时：先用包内资产完成源码分析、补丁设计、配置/构建脚本和静态验证；如果因此无法实际编译，直接交付补丁/设计/分析并在报告中标记“构建未执行”，不因此中止。
- 默认决策（除非有更强证据）：AOSP `android15-6.6-2026-01_r1`（6.6.118）、设备 `device/stock.config`、BakaSU `d5e9e025b8b4`、SUSFS `0606e19afae9`、clang `r510928`；第一版不把 lz4kd 作为阻塞项；UFS/memfd 优先用包内源码。
- 遇到私有源码缺失、设备不可用、网络失败或测试环境缺失时，选择最合理的等价/替代路径继续交付，并在 `DESIGN.md`、`TEST_REPORT.md` 或 `OPEN_ISSUES.md` 说明边界；不要因此中止。
- 交付物可以在“仅构建/静态验证”的情况下完成；实机结果作为加分项，不作为唯一验收条件。

### 1. 交付目标

在 **AOSP `android15-6.6-2026-01_r1`（6.6.118）** 基线上，交付一套可应用的内核改动和可测试 boot 镜像，使 dash 的 stock 厂商模块（尤其 `node_cache.ko`、`os_cpu_qi.ko`）能够加载并工作，同时尽可能补齐缺失的 Xiaomi F2FS/EROFS/hybrid 功能；保留 BakaSU（内建）+ SUSFS + 厂商 `.ko` 兼容能力。

优先级：

1. **构建与镜像交付**：6.6.118 构建、boot 镜像、静态可验证性。
2. **厂商模块兼容**：638 个 stock 模块可加载；`node_cache`、`os_cpu_qi` 可 probe/工作；KCFI/ABI/vermagic/CRC/namespace/签名/符号问题被处理。
3. **BakaSU + SUSFS**：内建 KSU、SUSFS inline、BakaSU 读 hook 适配。
4. **Xiaomi F2FS/EROFS/hybrid 功能**：按 stock 行为实现或给出等价方案。
5. **可选**：UFS 官方源码替换、lz4kd/zram 研究。

### 2. 设备/原厂事实（实测）

| 项 | 值 |
|---|---|
| 设备 | `dash` / 2602BRT18C / REDMI Turbo 5 Max / MT6991 |
| 系统 | Android 17 / SDK 37；`ro.product.first_api_level=36` |
| stock 内核 | `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k` |
| KMI | `android15-6.6` / generation 8 |
| 页大小 | 4K；`CONFIG_ARM64_4K_PAGES=y` |
| boot | header v4；`boot_b` 64MB，kernel 17,317,780B，ramdisk_size=0 |
| init_boot | 8MB，ramdisk 3,301,406B |
| vendor_boot | 64MB，vendor ramdisk 63,506,233B + DTB 536,161B |
| dtbo/vbmeta | 各 8MB |
| zram | stock 当前 `lz4`，16GB disksize；`ZRAM=m`，默认 `lzo-rle` |
| 当前 root | stock 上 `kernelsu` LKM；`su` 上下文 `u:r:ksu:s0` |
| bootloader | 属性显示 locked/green，但设备所有者说明是隐藏解锁；`lk` 不在本次操作范围 |

安全配置：`CFI_CLANG=y`、`SHADOW_CALL_STACK=y`、`MODVERSIONS=y`、`MODULE_SIG_PROTECT=y`、`LTO_NONE=y`。

### 3. 当前工作状态与输入

- 已有 6.6.144 自编内核：BakaSU 内建 + SUSFS inline + `CONFIG_VENDOR_KO_COMPAT`；0 error/0 warning；只生成 Image，未生成 boot，未实机验证。
- `project/dash/`：当前补丁、脚本、配置、6.6.144 artifact config/BUILD_INFO。
- 当前补丁：
  - `0001-vendor-ko-compat.patch`：模块加载兼容；
  - `0002-bakasu-integration.patch`：BakaSU 接入；
  - `0003-susfs-gki-android15-6.6.patch`：SUSFS；
  - `0004-susfs-bakasu-hooks.patch`：BakaSU `ksu_handle_sys_read` 适配。
- 模块符号核对：把 vendor ramdisk 的 275 个模块纳入后，638 个 stock 模块没有硬缺失符号；`leds-mtk-disp.ko` 对 `mtk_drm_gateic_set_backlight` 只有 weak 引用。CFI/ABI 尚未实机验证。
- `node_cache`/`os_cpu_qi` 的运行时行为见 `docs/DEVICE_MODULES.md`；二进制在 `modules/`。

### 4. 需要补齐的功能

#### A. Xiaomi F2FS/EROFS/hybrid

目标配置和行为：

- `CONFIG_XIAOMI_ENHANCED_IOSTAT=y`：F2FS iostat 增强；`en_iostat_enable`、`iostat_window_period_s`、`iostat_latency_threshold_ms`、iostat daily/window latency sysfs；`f2fs_iostat`/`f2fs_iostat_latency` tracepoints。
- `CONFIG_XIAOMI_EROFS_IOSTAT=y`：EROFS iostat/sysfs；`erofs_iostat_*`。
- `CONFIG_F2FS_VIP_FILE=y`：F2FS VIP file；`f2fs_vip_bsearch/insert/remove`、`vip_file_enable`。
- `CONFIG_F2FS_FS_HYBRID_UFS=y` + `CONFIG_BLOCK_HYBRID_UFS=y`：F2FS/block hybrid UFS；`f2fs_hw_support_hybrid`、`f2fs_disable_hybrid`、`f2fs_hw_hybrid_get_avail`、`device_hybrid_capable`、`hybrid_*` sysfs。

公开源码没有找到；可通过原厂源码恢复、等价实现、兼容层、行为级实现或其他方案完成。报告中请说明：

- 选择了什么实现路径；
- 与 stock sysfs/统计/策略的对应关系；
- 数据正确性、性能、能效和失败回退；
- 与原厂行为的差异和未覆盖部分。

#### B. `node_cache.ko` / `os_cpu_qi.ko`

目标：

- 让 stock 模块可加载、probe 和工作；
- 13 个 `android_vh_*` tracepoint 的定义、导出、KMI 白名单和调用点正确；
- KCFI 原型 hash 匹配；
- `node_cache` 需要 LZ4 和 4 个新 hook；`os_cpu_qi` 需要 9 个新 hook + 已有 binder/futex 等 hook；
- 运行时按 `docs/DEVICE_MODULES.md` 核对 sysfs/行为。

可使用 `third_party/dash-droidspaces/patches/os4-vendor-hooks` 作为参考。该系列作者报告 full call site 会 bootloop；可以采用分组调用点、替代 hook 方案、等价实现或重新设计调用点。请报告方案和验证结果。

#### C. `MEMFD_ASHMEM_SHIM`

包内 `source/memfd-ashmem-shim/` 是 MiCode 6.6.89 实现；移植到 6.6.118，启用配置，并验证对现有 memfd 无回归。也可采用更新的等价实现。

#### D. UFS

包内 `source/ufs/` 是 MiCode `MTK_kernel_device_modules/dash-w-oss` 的官方 UFS 源（37 文件）。可将其作为官方 UFS 实现使用；也可选择其他经过验证的 UFS 方案。CC 的 UFS 实现是逆向重实现，可作为参考，使用时请标注来源和验证状态。

#### E. 可选

- lz4kd/zram：可研究普通 lz4kd 或真正的 delta zram；在报告中区分“算法注册”和“delta 实际调用”。
- 性能/能效 A/B：建议覆盖 zram、F2FS node cache、QoS 继承和启动时延。

### 5. 交付物

1. `patches/`：相对 clean AOSP `android15-6.6-2026-01_r1` 的 unified diff 系列，按顺序可应用；包含 6.6.118 适配、BakaSU/SUSFS/vendor-ko 兼容、memfd、F2FS/EROFS/hybrid、vendor hooks。
2. `configs/`：基于 `device/stock.config` 的 config fragment 或脚本。
3. `build/`：使用 AOSP clang `r510928` 的构建脚本/命令，能生成 `Image`/`Image.lz4`。
4. `boot.img`：从 `boot/boot_b.img` 继承 header/DTB/ramdisk/cmdline，仅替换 kernel；`init_boot_b`/`vendor_boot_b`/`dtbo_b`/`vbmeta_b` 保持不动；附 `SHA256SUMS`。
5. `TEST_REPORT.md`：构建配置、命令、启动、模块加载、KCFI、sysfs、F2FS/EROFS、性能/功耗 A/B、失败日志。
6. `DESIGN.md`（建议）：每个缺口的实现路径、与 stock 的差异、风险、回退。
7. `OPEN_ISSUES.md`（建议）：未覆盖项、替代方案和后续建议。

### 6. 验收目标

- 补丁应用到 clean AOSP 6.6.118；build 0 error。
- 生成 Image/boot；boot 镜像结构正确（header v4、页大小 4096、DTB/ramdisk 保留），附 `SHA256SUMS`。
- **无真机环境**：以 clean apply + build + 静态 ABI/KCFI/符号检查 + boot 镜像结构检查为验收；实机启动不是阻塞条件。
- 有真机/设备访问时：优先 `fastboot boot`；启动后 `/proc/version` 为 6.6.118 基线。
- 有真机时：stock 638 个模块加载；重点 `node_cache`、`os_cpu_qi` 加载；无 KCFI `brk`/panic/未知符号/vermagic/CRC 拒载。
- 有真机时：`node_cache` sysfs 出现 `max_bytes/cur_cnt/cur_bytes/...`；`os_cpu_qi` 的 `qos_inherit/qos_sched` 可读。
- F2FS/EROFS 可正常挂载；实现的功能 sysfs 可读；数据不损坏（有设备时实测，无设备时做代码/静态验证）。
- BakaSU manager 可识别 root；SUSFS 工作；内建 KSU 与旧 `kernelsu` LKM 冲突被处理（有设备时验证）。
- 报告中明确区分“编译通过”“离线/静态验证”“实机验证”和“性能/功耗结果”。

### 7. 设备与操作约束

- 本次工作环境可能没有真机；不需要设备即可完成源码、补丁、构建和静态验证。
- `lk` 分区不在本次操作范围；不执行 fastboot/flash/分区写入。
- 如设备所有者后续测试，优先 `fastboot boot`；不要在无授权时写 `boot`/`boot_a`/`lk`/`super`。
- 测试文件放在 `/data/local/tmp`，结束清理。
- 包内 `boot_b`/`vbmeta_b` 等是备份/参考，不是写入指令。

### 8. 构建路径参考

```bash
git clone --depth=1 --single-branch -b android15-6.6 \
  https://android.googlesource.com/kernel/common aosp-6.6.118
git -C aosp-6.6.118 fetch --depth=1 origin \
  refs/tags/android15-6.6-2026-01_r1
git -C aosp-6.6.118 checkout --detach FETCH_HEAD
cp device/stock.config out/.config
# 应用补丁；目标为 6.6.118，不是 6.6.144
# 使用 AOSP clang r510928、ARCH=arm64、LLVM=1、LLVM_IAS=1
# 生成 Image；再用 stock boot_b 继承式替换 kernel 生成 boot.img
```

`dash/scripts` 当前按 6.6.144 的组织方式编写，可按需要改造或替换。

### 9. 包内文件

```text
TASK_BRIEF.md
docs/{NAVIGATION,GAP_RESEARCH,DEVICE_MODULES}.md
project/dash/{README,versions.env,Makefile,configs,patches,scripts,artifacts}
device/{stock.config,config.diff,stock.kallsyms.gz,getprop,lsmod,cmdline,bootconfig,dmesg,
        module-list,module_manifest.tsv,module_hook_deps.tsv,stock_exports,our_exports,PHONE_DUMP.sha256}
boot/{boot_b,init_boot_b,vendor_boot_b,dtbo_b,vbmeta_b}.img
modules/{vendor_ramdisk,vendor_dlkm,system_dlkm,node_cache.ko,os_cpu_qi.ko}
source/ufs/ (37 个官方 MTK UFS 文件)
source/memfd-ashmem-shim/
links/SOURCES.md
MANIFEST.sha256
```

### 10. 关键背景与参考

- AOSP tag：`android15-6.6-2026-01_r1`（6.6.118）
- Re-s/Mi15-Droidspaces-Kernel：同 stock `b9cc6ec16bc8` 的 6.6.118 参考
- MiCode `mist-w-oss`：6.6.118 公开源（其他设备，无 Xiaomi F2FS 特性）
- MiCode `dash-w-oss`：6.6.89
- `oss-dash/poco_dash_dump`：dash 6.6.118 完整 dump（链接记录，未下载；可补 boot_a/stock kernel/DTB/kallsyms）
- CC dash：6.6.144 LineageOS 参考，逆向模块请标注来源
- `dash-droidspaces`：os4 vendor hooks 参考，作者报告 full call site bootloop
- SUSFS/BakaSU/SukiSU：见 `links/SOURCES.md` 的 pin

### 11. 已记录的注意点（供方案设计参考）

- KCFI 原型/调用点与 stock 模块的匹配决定运行时是否触发 `brk`；如采用不同原型，请同步提供匹配的 hook 适配和验证。
- `SHADOW_CALL_STACK`/`CFI_CLANG`/`MODVERSIONS`/`MODULE_SIG_PROTECT` 保持 stock 行为更利于厂商模块。
- 内建 KSU 需要与设备当前 `kernelsu` LKM 协调，避免重复 root。
- `node_cache` 是 F2FS node 页压缩缓存（zsmalloc/LZ4），当前 35k 条目/13MB 压缩数据；会消耗 CPU 换内存。
- `os_cpu_qi` 是 QoS 继承引擎（binder/mutex/rwsem/percpu-rwsem/futex/fuse/RCU + UI/render RT 98）；会提升延迟表现，也有 boost 功耗。
- 公开源码未找到不等于唯一路径；可以用等价实现、行为级实现或重新设计，只需在报告中说明差异和验证。

---

<a id="src-14"></a>
## 14. 来源、pin 与“只记录不下载”的近失链接

> 来源：[`handoff/dash-gap-handoff/links/SOURCES.md`](../../handoff/dash-gap-handoff/links/SOURCES.md) · 4855 字节 · SHA256 `2c5a8d73a4bf54435e6f0088595da758826a5d3e7b7bb0a940088fce802a337d`
> 类别：需求 · 状态：来源索引
> 注意：来源清单中的 project/dash 描述是交接时状态（6.6.144）；当前实现已切到 6.6.118。

### Local exact assets (included in this package)

- Device: dash / REDMI Turbo 5 Max (MT6991), Android 17/SDK 37, stock `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`.
- Active slot `_b`; bootloader reported `flash.locked=1`, verifiedbootstate=green, but per owner it is hidden-unlocked; **do not flash lk**.
- `boot/` contains stock `boot_b.img` (64MB), `init_boot_b.img` (8MB), `vendor_boot_b.img` (64MB), `dtbo_b.img` (8MB), `vbmeta_b.img` (8MB).
- `device/` contains stock config, kallsyms, getprop/lsmod/dmesg, module manifest/exports.
- `modules/` contains all 638 stock modules: vendor ramdisk 275, vendor_dlkm 289, system_dlkm 78; plus `node_cache.ko`/`os_cpu_qi.ko` copies at top.
- `project/dash/` contains current build scripts, patch series, config, and current 6.6.144 artifact config/BUILD_INFO.
- `source/ufs/` contains official MediaTek UFS source extracted from MiCode `MTK_kernel_device_modules` branch `dash-w-oss`.
- `source/memfd-ashmem-shim/` contains MiCode `mm/memfd-ashmem-shim*` source.

### AOSP / kernel source

- AOSP common 6.6.118 tag: https://android.googlesource.com/kernel/common/+/refs/tags/android15-6.6-2026-01_r1
- AOSP common branch: https://android.googlesource.com/kernel/common/+/refs/heads/android15-6.6
- AOSP clang r510928: https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 (branch `main-kernel-build-2024`)
- MiCode dash: https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/dash-w-oss (6.6.89 only)
- MiCode `mist-w-oss`: https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/mist-w-oss (6.6.118, other device; no Xiaomi F2FS features)
- MiCode `dada-v-oss`: https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/dada-v-oss (6.6.30)
- MiCode MTK device modules: https://github.com/MiCode/MTK_kernel_device_modules/tree/dash-w-oss
- MiCode MTK modules: https://github.com/MiCode/MTK_kernel_modules/tree/dash-w-oss

### Reference projects

- Re-s/Mi15-Droidspaces-Kernel: https://github.com/Re-s/Mi15-Droidspaces-Kernel
  - Explicit stock string `b9cc6ec16bc8`; contains `docs/stock-6.6.118-android15-8.config`, DroidSpaces patches, boot tooling. Not dash kernel source.
- CC dash kernel: https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash (6.6.144, LineageOS, not stock)
- CC device modules: https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_device_modules (DTS/config/reimplemented modules; reverse-engineered)
- CC MTK modules: https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_mtk_modules
- CC build: https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_build
- CC Bazel rules: https://github.com/Content-Creation-Club/android_kernel_xiaomi_dash_bazel_mgk_rules
- lakitu dash DroidSpaces: https://github.com/lakitu12/kernel_dash_droidspaces (os4-vendor-hooks; experimental, full call sites bootloop)
- SukiSU patch: https://github.com/SukiSU-Ultra/SukiSU_patch
- SUSFS4KSU: https://gitlab.com/simonpunk/susfs4ksu (branch `gki-android15-6.6`)
- BakaSU: https://github.com/Baka-SU/BakaSU
- HyperOS LZ4KD: https://github.com/2108282/hyperos-lz4kd

### Related dumps / near misses (recorded, NOT downloaded)

- oss-dash/poco_dash_dump: https://github.com/oss-dash/poco_dash_dump
  - dash / POCO X8 Pro Max, OS3.1, kernel 6.6.118, release-keys. Contains `boot/kernel` 36.8MB, `boot.elf` 42MB, `boot/dtb`, `boot/dts`, `ikconfig`, `kallsyms.txt`, split boot/vendor_boot, system_dlkm/vendor_dlkm, `aosp-device-tree` with BoardConfig. Not kernel source.
- xiaomi-dash-dev/redmi_dash_dump: https://github.com/xiaomi-dash-dev/redmi_dash_dump (dash, OS3.0, 6.6.89)
- xiaomi-mt6991/poco_dash_dump: https://github.com/xiaomi-mt6991/poco_dash_dump (dash, 6.6.118)
- HexaUnion/redmi_dash_dump: https://github.com/HexaUnion/redmi_dash_dump (dash, 6.6.118)
- ONFIX dash ROM: https://onfix.cn/course?bid=1&mid=30095 (boot/init_boot resources; paid)
- ghostlock version map: https://github.com/YuKongA/ghostlock-app/blob/main/README_ZH.md
- donyanchen sm8850: https://github.com/donyanchen/android_kernel_xiaomi_sm8850 (6.12, not 6.6.118)
- hgn284 xiaomi_17pro_max_sm8850: https://github.com/hgn284/xiaomi_17pro_max_sm8850
- Apr-YT/gg-rwproc33-driver: https://github.com/Apr-YT/gg-rwproc33-driver
- wfqefwqf/share-poc-XRing-O1: https://github.com/wfqefwqf/share-poc-XRing-O1
- klarnet2009/dada-closed-modules: https://github.com/klarnet2009/dada-closed-modules

### Search conclusion

- Exact dash 6.6.118 vendor source: **not found publicly**.
- `XIAOMI_ENHANCED_IOSTAT`, `XIAOMI_EROFS_IOSTAT`, `F2FS_VIP_FILE`, `F2FS_FS_HYBRID_UFS`, `BLOCK_HYBRID_UFS` implementation: **not found publicly** (config/symbols only).
- `node_cache.ko` / `os_cpu_qi.ko` source: **not found publicly** (binaries + behavior only).
- Official UFS source: found in MiCode `MTK_kernel_device_modules/drivers/ufs`.

---

<a id="src-15"></a>
## 15. dash-droidspaces 项目说明（上游参考）

> 来源：[`third_party/dash-droidspaces/README.md`](../../third_party/dash-droidspaces/README.md) · 3567 字节 · SHA256 `b458cb4cfde6737ced8007521475825c8ab51f6ec66a07d11b03eb4a0e533b87`
> 类别：上游参考 · 状态：上游参考（版本可能漂移）
> 注意：上游基线 commit 与本机 stock 不完全相同；其 DroidSpaces 配置不是本交接目标。

GKI android15-6.6 自定义内核 — Redmi Turbo 5 Max (dash, MT6991Z, 天玑 9500s)。

DroidSpaces（宿主容器）+ SukiSU Ultra（KPM + SUSFS）。仓库结构/方法论复用
[kernel_marble_droidspaces](https://github.com/lakitu12/kernel_marble_droidspaces)
（marble 5.10.236 同配方已实机验证 7 轮 CI + 开机）。

### Stock 基线（实机 boot.img 实测，2026-08-30）

| 项 | 值 | 来源 |
|---|---|---|
| 内核版本 | `6.6.118-android15-8-gc44b714366cc-abogki519650608-4k` | extract-ikconfig + strings，本地 stock boot.img |
| GKI 代 | **GKI 3.0**（boot.img header v4, RAMDISK_SZ=0 → boot 仅含内核, kernel LZ4；generic ramdisk 在 **init_boot** 分区） | magiskboot 头解析 |
| `abogki` 前缀 | MTK 用 AOSP GKI 产物做的 fork 构建 | 版本字符串 |
| KMI | `android15-8`（KMI generation 8） | 版本字符串 |
| page size | 4K（`CONFIG_ARM64_PAGE_SHIFT=12`，`-4k` 后缀） | ikconfig |
| LTO | **`CONFIG_LTO_NONE=y`**（与 marble 的 LTO_FULL 不同！） | ikconfig |
| CFI | `CONFIG_CFI_CLANG=y` | ikconfig |
| MODVERSIONS | y + `MODULE_SIG_PROTECT=y` | ikconfig |
| ANDROID_KABI | `ANDROID_KABI_RESERVE=y`（kABI 补丁有保留区可用） | ikconfig |
| SCSS | `CONFIG_SHADOW_CALL_STACK=y` | ikconfig |
| 源码 tag 对应 | `android15-6.6-2026-01_r1`（Makefile SUBLEVEL=118 已核实） | AOSP common |

`c44b714366cc` 本身不在 AOSP common 上（MTK fork 内部提交），但 base tag 锁
`android15-6.6-2026-01_r1`（同为 6.6.118）。

### Workflow

`.github/workflows/build.yml`（marble 模板改造，差异点见文件内注释）：

- repo sync 钉 `common-android15-6.6-2026-01` + local_manifest 锁 tag
  `android15-6.6-2026-01_r1`，SUBLEVEL=118 门禁
- DroidSpaces kABI 补丁 `001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch`
  （6.6 属 below-6.12；无 002 MQUEUE 补丁——那是 ≤5.10 专属）
- gki_defconfig：官方 GKI-safe 集 + KPROBES/KALLSYMS；**LTO/CFI 保持 stock**
- 版本尾巴：`.scmversion` 在 6.x 已死（setlocalversion 不再读）→ kleaf 无 stamp
  构建时 `build/kleaf/impl/stamp.bzl` 生成 literal `-maybe-dirty`，workflow 直接
  sed 该文件为 `-droidspaces-lakitu` → `6.6.118-android15-8-droidspaces-lakitu`
  （KMI 尾巴 `-android15-8` 由同一文件携带；`CONFIG_LOCALVERSION` 反而会拼在
  文件内容之后，不用）
- SukiSU builtin 分支（SUSFS 符号必需）+ susfs4ksu `gki-android15-6.6`
  分支补丁（已核实存在）
- AK3：Numbersf 大写变量基底；dash boot 仅含 kernel（generic ramdisk 在 init_boot、
  vendor ramdisk 在 vendor_boot）→ `flash_boot` 只换内核、init_boot/vendor_boot 不动
- 产物：matrix `ksu` / `bypass` 双变体，Image + AK3 zip

### 首刷安全规程（A/B 守护，同 marble）

```bash
fastboot getvar current-slot           # 记住当前槽
fastboot flash boot_<当前槽> boot.img   # 只刷当前槽
# 开机验证 uname -r；异常时 fastboot --set-active <另一槽> 回滚
```

vbmeta：解锁后镜像未签名，若卡第一屏 →
`fastboot flash vbmeta_<槽> --disable-verity --disable-verification vbmeta.img`。

### DroidSpaces 要求核查（stock → 目标）

`droidspaces check` 致命项：PID_NS/MNT/UTS/IPC_NS/CGROUP_DEVICE/DEVTMPFS。
stock 缺失项（ikconfig 实测）：SYSVIPC、POSIX_MQUEUE、IPC_NS、PID_NS、DEVTMPFS、
USER_NS、TMPFS_XATTR/POSIX_ACL、NETFILTER_XT_MATCH_ADDRTYPE、IP_SET —
全部由本内核补齐；UTS_NS/OVERLAY_FS/SECCOMP/VETH/CGROUP_FREEZER/MEMCG stock 已有。

---

<a id="src-16"></a>
## 16. OS4 vendor hooks / CRC / CI 单变量开关（上游参考）

> 来源：[`third_party/dash-droidspaces/patches/README.md`](../../third_party/dash-droidspaces/patches/README.md) · 8397 字节 · SHA256 `0a8516136bfbec0afdd440ca381a58b650e855f68983aa97ab7aa6392c62c59a`
> 类别：上游参考 · 状态：上游参考（版本可能漂移）
> 注意：上游 README 的 full-call-site bootloop 与本仓库实测不同；详见 docs/kernel/TEST_REPORT.md §10。

dash 自编内核（`kernel/common` @ `android15-6.6-2026-01_r1`，6.6.118）所需的所有
内核侧改动都集中在这里，以**标准 unified diff** 维护，由
[`../.github/scripts/apply-patches.py`](../../third_party/dash-droidspaces/.github/scripts/apply-patches.py) 统一应用。

```
patches/
├── trusty-rescue/        gz 被抹除（nvhe/pKVM）启动时的相机链自救驱动
├── os4-vendor-hooks/     dash OS4 厂商模块需要的 13 个 MTK vendor hook
└── pid-max-clamp/        pid 空间钳到 32768（MKP 0x8000 类 bug 的规避）
```

CI 里只有一步 `Apply maintenance patches`，它调用
[`apply-tree-patches.sh`](../../third_party/dash-droidspaces/.github/scripts/apply-tree-patches.sh)：先应用本目录
全部补丁，再逐条自检（每个 hook 的 `DECLARE_HOOK` / 导出 / 调用点、rescue 的
Kconfig/Makefile 挂钩与 nvhe cmdline、pid_max 的两处钳制）。少一条就 fail。

### 为什么用补丁而不是脚本

* 整个 delta 一屏可读、可 review、可 diff、可回滚；
* 应用器只做 `git apply` / `patch`，不做字符串手术；
* 上游漂移时补丁会**干净地失败**，而不是「悄悄插到错误位置还编译通过」。

代价是上下文变了要重新生成补丁——这是有意的取舍（宁失败，不静默错）。

### 应用器行为

```
apply-patches.py --tree <kernel/common> --patches <dir> [--check]
```

1. `git apply --check`（精确）
2. `git apply --check --ignore-whitespace`（行尾空白差异）
3. `patch -p1 --dry-run -F2`（轻微偏移）
4. 反向可应用 → 视为「已打过」，跳过（重跑幂等）
5. 否则失败并打印 `git apply -v` 的排查命令

补丁按路径排序应用，series 之间相互独立。

**注意应用时机**：本目录在 CI 里位于「版本串修正」之后，而该步骤会往
`arch/arm64/configs/gki_defconfig` 末尾追加 `# CONFIG_LOCALVERSION_AUTO is not set`。
所以补丁的 hunk 不要锚在文件末尾（0003 最初就是 end-of-file hunk，第一次 CI
必然失败），锚到改动点附近的稳定上下文（如 `CONFIG_CMDLINE_EXTEND=y` 后面）。
依此类推：任何「前置步骤会改的文件」都要按**前置步骤之后**的状态来生成补丁。

### 上机单变量开关（HOOK_CALL_SITES）

2026-10-29 教训：全量 call site 的内核在真机上 **bootloop**，而当时 missing=0、
13/13 KCFI 哈希全对、payload 也一致——**离线门禁证明不了调用点位置/锁上下文在真机安全**。
所以 call site 要一组一组上机验证，开关在 `apply-tree-patches.sh`：

| 值 | 含义 |
|---|---|
| `full`（默认，push 构建走这个） | 13 个 hook 定义+导出+全部调用点 |
| `none` | 只有定义+导出，没有任何调用点（先确认这种能进系统） |
| `0004` / `0004,0005` … | 只上指定分组的调用点，其余跳过 |

分组对应关系（补丁号 → 文件 → hook）：

```
0004 mm/vmscan      remove_mapping, remove_mapping_failed
0005 mm/filemap     filemap_get_folio_end
0006 fs/super       put_super
0007 fs/fuse        fuse_request_end_ext, fuse_request_fetch
0008 kernel/fork    mmap_lock_init, mmap_lock_free
0009 percpu-rwsem   percpu_rwsem_init
0010 rcu            rcu_boost_start/end, sync_rcu_wait_start/end
```

CI 里用 `workflow_dispatch` 的 `hook_call_sites` 输入选择；非 `full` 的产物文件名带
`-SITES<组号>` 后缀，避免和全量版混淆。

另有 `no_lz4_export` 输入（`0`/`1`）：`1` 时把 `LZ4_compress_default` 从 KMI 白名单里删掉。
`node_cache.ko` 需要 4 个 hook **加** LZ4，所以它会退化成「加载失败」（等同原厂行为）；
`os_cpu_qi.ko` 只需要 9 个 QoS hook，仍然能加载。用它在不改源码的前提下把两个模块分开。
产物带 `-NOLZ4` 后缀。

另有 `os4_hooks` 输入（`on`/`off`）：`off` 时整个 os4-vendor-hooks series 都不打，
树回到 stock 状态——`node_cache.ko`/`os_cpu_qi.ko` 会像原厂内核一样**加载失败**。
这是隔离「模块现在能加载了」与「我们改的其它东西」的控制组（2026-10-29：
`none` 版无任何调用点仍 bootloop，说明触发点不是调用点，而是模块能加载之后的行为）。
产物带 `-NOHOOKS` 后缀。`apply-tree-patches.sh` 的自检
会按选择断言：选中的组必须**有**调用点，未选中的组必须**没有**。

### 各 series 的前置知识

#### trusty-rescue
gz/Trusty 固件被抹除后（给内核 EL2 跑 pKVM），`gz_trusty_mod` 的 SMC 握手失败，
`/trusty/trusty-virtio` 不会生成，secure-cmdq mailbox → imgsys/IMGSCP 相机链永久
defer，`camerahalserver` 崩溃循环。这个驱动做三腿指纹自检（driver 已注册 / device
缺失 / 父设备未绑定），持续成立才动作，健康 gz 启动下是 no-op。
配套把 `CONFIG_CMDLINE` 的 `kvm-arm.mode=protected` 改成 `nvhe`。

#### os4-vendor-hooks
13 个 `android_vh_*` tracepoint 在 AOSP GKI 6.6 里不存在，但 dash OS4 的
`node_cache.ko`（4 个）与 `os_cpu_qi.ko`（9 个）要 probe 它们。
**TP_PROTO 不能改**：`CONFIG_CFI_CLANG=y` 下 `__traceiter_*` 会核对探针类型哈希，
与原厂不一致会在 hook 首次触发时 `brk #0x8228`。现有原型是用
`clang -fsanitize=kcfi` 复算、与 stock 内核立即数逐位对齐得到的；调用点位置则由
stock Image 反汇编里每一条 `bl __traceiter_*` 定位。构建后
[`verify-os4-kcfi.py`](../../third_party/dash-droidspaces/.github/scripts/verify-os4-kcfi.py) 再验一次哈希。
细节见 `~/下载/dash-os4/os4-hooks-callsite-map.md`。

#### pid-max-clamp
`PID_MAX_LIMIT` 与 `pid_max_max` 都钳到 32768，使 0x8000 掩码类 bug 不可达
（dash stock 的 id 空间约 8% 会踩到）。改两处是因为头文件宏可被重新定义，
`kernel/pid.c` 的 `pid_max_max` 是硬钳制。

### 重新生成

基线固定为 tag `android15-6.6-2026-01_r1`。改完补丁内容后：

```bash
# 在干净基线上应用本目录全部补丁，得到 after 树
python3 .github/scripts/apply-patches.py --tree ~/gki/common --patches patches
# 生成某个文件的 diff
git -C ~/gki diff --no-color -- mm/vmscan.c > patches/os4-vendor-hooks/0004-....patch
```
### modversions CRC：为什么只有两个 hook 对不上，以及修法

`os4-vendor-hooks` 的 13 个 hook 里，`android_vh_mmap_lock_init/_free` 两个
`__tracepoint_*` 符号的 genksyms CRC 与 stock 内核不一致（其余 11 个、以及全部
`__traceiter_*` / `__SCK__*` 的 CRC 逐位相同；2026-10-29 实测：stock 与自编 Image
的 8988 个公共导出符号里只有这 2 个不同）。后果是 `os_cpu_qi.ko` 被内核以
`disagrees about version of symbol ... (err -22)` 拒载，连带 `os_cpu_qs` /
`task_turbo` / `mi_game` / `cpq` / `mi_reclaim` 整条 QoS 模块链起不来
（实测 556 → 584 个模块）。

根因（2026-10-29 用 AOSP 6.6.118 树 + 树内 genksyms 复现，并由 CI 实测确认）：
genksyms 对 `__tracepoint_X` 的 CRC 取自 **EXPORT 语句所见的声明文本**：
若该 TU 里还见过 `DEFINE_TRACE_FN` 的定义（含
`__used __section("__tracepoints")` 属性 tokens），CRC 就把属性算进去；
若只见过 `extern struct tracepoint __tracepoint_X;`，则不算。
stock 把这两个 hook 的 EXPORT 放在一个**只声明 tracepoint 的 TU**（没有
`CREATE_TRACE_POINTS`），所以它的 CRC 是不带属性那一版；我们原来把 13 个 export
全塞在 `drivers/android/vendor_hooks.c`（该 TU 有 `CREATE_TRACE_POINTS`），于是
这 2 个 CRC 变成带属性那一版——只有这 2 个不同，正是因为只有它们的 export 位置
与 stock 不同。

修法就照抄 stock 的布局：`0002` 补丁新增 `drivers/android/dash_os4_decl_exports.c`
（只 `#include <linux/tracepoint.h>` + stub 头 + 两条 `EXPORT_TRACEPOINT_SYMBOL_GPL`，
并挂进 `drivers/android/Makefile`），把这两个 export 从 vendor_hooks.c 移过去。
`__tracepoint_*` 对象仍由 vendor_hooks.c 的 `CREATE_TRACE_POINTS` pass 定义。
CI 实测：这样编出来的 Image 里两个 CRC 就是 `0x615d194b` / `0xa301bcc9`，
os_cpu_qi.ko 直接加载，不再需要构建后钉值。

`.github/scripts/patch-kcrctab.py` 保留为**诊断/兜底工具**（CI 不再调用）：
先全量 diff kcrctab 定位是哪个符号，再用它临时钉值验证「就是这一个 CRC 的问题」。

---

<a id="src-17"></a>
## 17. vendor_boot v15 逐字节变更记录（上游参考）

> 来源：[`third_party/dash-droidspaces/docs/vendor-boot-v15-changeset.md`](../../third_party/dash-droidspaces/docs/vendor-boot-v15-changeset.md) · 6613 字节 · SHA256 `9f4db4eb626b2f7d4d3067db921881806e52c442705cc4abdc2decf02be8dc90`
> 类别：上游参考 · 状态：上游参考（版本可能漂移）

对象：`~/hermes_work/vendor_boot_a_nogz_patched_v15_devapc_on.img`
md5 `449da7a8221bc220532d70b8c4b9620c` / sha256 `6093b684…c8d4`
基线：原厂 `~/下载/vendor_boot_a.img`

### 0. 先说验证方法与两个易误导的现象

对原厂与 v15 做过三重取证：全文件逐字节 diff、两版 vendor_ramdisk 解包后
cpio **逐文件 md5 对比**、header 字段结构解析。结论与现象：

- 全文件 diff 有 8942 字节/90 段——**绝大部分不是修改**。构建链把 platform
  vendor_ramdisk 整段解压→（微改 cpio）→按 8 MiB 定长重新 LZ4-legacy 分块压缩，
  压缩器匹配选择与原厂不同，导致压缩流字节大面积变化，但 `RAMDISK_SZ` 与原厂
  **逐字节相等**（两侧均为 `0x3adc52f`）——是"同长度不同编码"，不是位移也不是改大。
- cpio 逐文件比对的结果才是真相：**整个 ramdisk 里只有 1 个文件被改**
  （`lib/modules/log_store.ko`，原厂 md5 `86a6b7a3…` → v15 内 `b6d90b1c…`），
  其余全部与原厂逐字节一致。
- 逻辑修改共 4 项（1 个 header 字段 + 1 个 .ko 两条指令 + 1 处 DTB 改名 +
  1 处 DTB 改名已回滚）；AVB 全程零触碰：ramdisk/dtb 尺寸不变，
  vbmeta struct/footer 不动，实测 `verifiedbootstate=green`。

### 1. header.cmdline 字段

- 偏移：header 页 `0x30` 起 256B 定长字符串区（vendor_boot v4 格式）。
  stock：`bootopt=64S3,32N2,64N2`；v15：`bootopt=64S3,32N2,64N2 nogzpatch=1 dapcdt=1`
  （magiskboot 复核一致）。
- 谱系：`nogzpatch=1` 自 v8 起就是"容器标记"（当时配套补丁就叫 nogz 补丁，
  供我们自己的 repack 脚本/校验认版本用）；`dapcdt=1` 是 v12 用 DTB skip 方案
  替代旧 `nodapc=1` 参数时一并改的。vendor 侧消费者未逐一定位，也无删除回归
  ——**存疑保留项**（两种态实测带着都正常）。

### 2. vendor_ramdisk: `/lib/modules/log_store.ko`（唯一被改的文件）

改在 `pl_lk_log_show()`（符号 0xe74 起）之内，`.text` 段文件偏移两处、共 5 字节，
全部等长替换。BuildID 锚定：`271867de…2cdf006`（脚本有断言）。

#### 2a. 功能补丁：`0x1000 + 0xb88`（ko 内偏移 0x1b88）
```
stock:  81 02 00 54   b.eq  <panic分支>      ; SRAM 区头 magic 校验失败
v15   : 00 00 00 91   add x0, x0, #0         ; 即 nop
```
作用：gz 擦除态下 LK 写入 log_store SRAM 区的头/数据不存在或不合法，原厂此处
`b.eq` 跳入的处理路径会拿 NULL `sram_header` 继续往下走 → 早期实测
（boot 时代 ramoops）表现为 panic；NOP 后失败分支被吞掉，模块照常工作
（console-ramoops 导出功能不受影响，实测可拉）。
来源脚本：`repack_v8.py`（注释原文 "b.ne 0xbd8 (first SRAM-magic check ->
NULLs sram_header) -> add x0,x0,#0"，实际指令为 b.eq，v8→v9→v10→v11→v12 沿用），
产物文件 `v8_log_store_patched.ko`/`v9_log_store.ko`（md5 `b6d90b1c…`）。
注：`patch_vendorboot.py`（更早一轮实验，打在 `0x1be4` 的另一条
`str xzr,[x19]`→NOP，产物 md5 `1b83ddc7…`）**没有**进入 v12→v15 线上链，
本文档旧版误把它写成了现行补丁，已按 cpio 实物证据更正。

#### 2b. 伪装性字符串微调：`0x207d`（同文件，rodata）
```
"  log_store: sram header address 0x%p."  → "  … header Address 0x%p."
```
（a→A，1 字节）。这是 repack_v9/v10 的压缩尺寸配平手法：重压缩流的输出字节数
受内容熵微扰影响，加一个无害大写让被改块压回与原厂**完全相同**的压缩长度，
从而不动 header、不挪后续任何偏移。属于工程手段，无运行时语义。

### 3. DTB：Mali 属性等长改名（v14 引入，现行存活）

- FDT strings 块一处，stock 内容（实测上下文）：
  `protected-memory-allocator\0` → `protected-memory-allocatoX\0`
  （27B 等长，仅末字节 `r`(0x72)→`X`(0x58)；v15 相对原厂 **FDT 差异仅此 1 字节**，
  FDT 内偏移 `0x79204`，两侧 FDT 总长同为 535899B）。
- 语义：`/soc/mali@48000000` 节点的 `protected-memory-allocator = <&gpu_protected_memory_allocator>`
  属性名变未知 → kbase `of_parse_phandle` 查不到 → 不走 protected memory 分配 →
  绕开 gz 擦除态 `mtee_assign_buffer_v2` SMC 返 -22 后 NULL deref 的 ipanic
  （v13 时代崩溃签名）。
- 唯一性保障：构建脚本（`build_v14_mali.py`）断言 strings 块全局命中恰 1 处、
  不与 `arm,protected-memory-allocator` 前缀混淆、struct 块节点名不动；
  产物 v14 与 v12 全文件差异恰 1 字节。**内核管不到，长期必须保留**。

### 4. DTB：devapc compatible（v12 改过 → v15 回滚，净效果为零）

- v12 曾把 strings 块 `mediatek,mt6991-devapc` → `mediatek,skip69-devapc`
  （等长改名跳过 AP devapc 驱动，当时用于相机问题隔离）。
- v15（`build_v15_devapc_on.py`）回滚：6 字节写回 `mt6991-`（文件偏移
  `0x3b15521–0x3b15526`，v15 与 v14 全文件差异恰此 6 字节）。
- 判别实验结论：devapc 恢复后相机症状不变（`driver registered` 日志实证）→
  无罪保留原厂值。当前镜像此项**与原厂一致**。

### 5. 版本谱系速查

```
stock(2e755ef8) ─v8: log_store NOP@0xb88(+Address 配平) + cmdline nogzpatch=1
              ─v9/v10/v11: 沿用，试验 kvmnvhe/nodapc 变体
              ─v12: DTB devapc→skip69，cmdline 定稿 "nogzpatch=1 dapcdt=1"
              ─v14: DTB Mali 改名 (build_v14_mali.py)
              ─v15: DTB devapc 还原 (build_v15_devapc_on.py)   ← 现行
```
自校验惯例：每版脚本"写后回读 + 与上一版逐字节 diff 断言差异恰 N 字节"。

### 6. 与内核侧修改的分工边界

| 需求 | 归属 | 载体 |
|---|---|---|
| 内核拿 EL2 / nVHE | 内核 | CONFIG_CMDLINE（CI） |
| 相机链 rescue | 内核 | drivers/trusty_rescue（CI） |
| Mali 不撞 mtee_assign | vendor_boot | §3 DTB 改名（kbase 是 vendor 模块） |
| LK log 区缺失不 panic | vendor_boot | §2a log_store NOP（vendor 模块） |
| gz↔EL2 切换 | 分区 | 只动 gz_a |

v15 的 §1/§2/§3 三处改动在 **gz 在位态同样存在且实测无害**（8 月 lakitu-1
基线的同款改动带 gz 正常开过机）；理论上 gz 恢复后 §2/§3 属"冗余但安全"。
未验项（DRM 受保护流退化、nogzpatch/dapcdt 可删性、三件套回滚矩阵）见
`gz-erased-changeset.md` §7 与本节记录，动手前勿当已证事实引用。

---

<a id="src-18"></a>
## 18. gz/Trusty 被擦除与 nvhe 启动变更（上游参考）

> 来源：[`third_party/dash-droidspaces/docs/gz-erased-changeset.md`](../../third_party/dash-droidspaces/docs/gz-erased-changeset.md) · 7269 字节 · SHA256 `fa4a4878660c70f26e4766d5f2afbbfc2b6d4d6194a47c915379f6eae253d8da`
> 类别：上游参考 · 状态：上游参考（版本可能漂移）
> 注意：本仓库使用 stock cmdline（kvm-arm.mode=protected），未合入 trusty-rescue/nvhe。

状态截至 2026-10-03，全部条目均有实测锚点；分区指纹为当次 dd 校验。

### 0. 设备当前分区状态

| 分区 | 内容 | md5（dd 校验） |
|---|---|---|
| boot_a | CI 构建内核（nvhe + trusty_rescue 内置），AK3 直刷 | `09011fc0…`（≠ 任何字节手术 boot） |
| vendor_boot_a | v15（见 §2） | `449da7a8221bc220532d70b8c4b9620c` |
| gz_a | 擦除（GenieZone/Trusty 固件置零，让内核拿 EL2） | 全零区 |

运行事实：EL2 + nVHE KVM（/dev/kvm 在）、AVB green、WiFi/BT/充电/指纹正常、
三摄拍照录像正常、开机 18.9s trusty_rescue 自动完成相机链救援。

### 1. 内核侧（本仓库，CI 注入）

历史既有（DroidSpaces/SukiSU 线，非本文重点）：SYSVIPC/kABI 补丁、pid_max clamp、
KSU+KPM+SUSFS（ksu variant）、MODULE_SIG_PROTECT off、LTO_NONE+CFI 对齐 stock。

本次新增（commit 6f1fd6e + fix）：

#### 1.1 CONFIG_CMDLINE: kvm-arm.mode protected → nvhe
- 位置：`arch/arm64/configs/gki_defconfig` 的 `CONFIG_CMDLINE="…"`，由
  `patches/trusty-rescue/0003-arm64-gki-defconfig-nvhe-and-enable.patch`，
  ikconfig 双向断言（必须见 nvhe、必须无 protected）。
- 原理：`kvm-arm.mode=protected` 是编译进内核的内置 cmdline（DTB/ramdisk 里都没有），
  原厂时代只能对 boot 做字节手术；自研内核直接在源码改，零 AVB 风险。
  `CMDLINE_EXTEND` 下该串就是实际生效值（实测 /proc/cmdline）。
- gz 正常态安全性：gz 在位 → LK 把内核起在 EL1 → KVM init 整体跳过
  （`KVM is not available. Ignoring kvm-arm.mode`），nvhe 字符串无害。

#### 1.2 drivers/trusty_rescue（CONFIG_TRUSTY_RESCUE=y，bool 内置）
- 源文件：本仓库 `patches/trusty-rescue/`（0001/0002 为驱动 + Kconfig/Makefile
  挂钩，由 `.github/scripts/apply-patches.py` 应用）。
- 要解决的问题：gz 擦除 → trusty SMC 版本握手失败 → gz_trusty_mod 的
  trusty_probe 返回 -22 → 其尾部 of_platform_populate("/trusty") 未执行 →
  /trusty/trusty-virtio 设备不存在 → gce-mbox-sec/-m-sec（secure cmdq mailbox）
  supplier 断链 deferred → camera-imgsys-cmdq 不完整 → 34000000.imgsys-fw 永不
  绑定 → IMGSCP 不上电 → camisp media 拓扑 0 实体 → camerahalserver 崩溃循环。
- 行为：3s 后起 delayed work，1s 粒度轮询三段指纹——
  ① bus 上存在名为 `trusty-virtio` 的 driver ② 其 DT 对应 platform device 缺失
  ③ `/trusty` 父设备未绑定驱动；三者连续成立 ≥15s 才动作（grace），总窗口 90s：
  a. `bus_for_each_drv` 迭代锁内 `try_module_get(owner)` 永久 pin gz_virtio_mod
     （防 rmmod 双注销 UAF；pin 失败则放弃动作）；
  b. `driver_unregister` 摘除 trusty_virtio_driver——它的 probe 会对 NULL
     trustye 解引用直接 ipanic（v1 实测炸过，pstore 有档案）；
  c. `of_platform_device_create` 造 trusty-virtio marker 设备（secure-cmdq 的
     probe 只做 of_find_compatible_node + device_link_add，设备"存在"即可解锁，
     无驱动可 bind → 无 probe → 无雷）；
  d. `driver_deferred_probe_trigger()` 唤醒整条 deferred 链。
- 自守卫：gz 完好时 trusty_probe 毫秒级绑父设备+造子设备，指纹 ②③ 永远不成立
  → 纯 no-op。任何异常/外平台/DT 缺节点 → 不动作。
- 已知且预期：开火前 init 拉起的首个 camerahalserver（~6.7s）会崩一次，
  重启后的 HAL 赶上救援完成的窗口，之后永稳。
- 工程红线（CI run #1 教训）：禁止 `driver_find()`+`put_device(&drv->p)`——
  `device_driver.p` 是私有 `struct driver_private *`，其配对 `put_driver()` 不导出。
  只用公开 API。
- 同名雷排除：ise 栈驱动在 bus 上注册名是 `ise-trusty-virtio`（sysfs 实证），
  精确 strcmp 不会误摘。

### 2. vendor_boot 侧（当前 v15 = 原厂 vendor_boot 之上的净修改）

版本谱系：v12（log_store 补丁 + devapc skip + cmdline）→ v14（+Mali 闸门）→
v15（devapc 撤销回原厂，判别实验定案 devapc 无罪）。v15 净差异 = 下表三项，
其余逐字节等长、AVB struct/footer 零变动：

| # | 位置 | 改动 | 作用 | 新内核下是否仍需 |
|---|---|---|---|---|
| 1 | vendor_ramdisk 内 `log_store.ko` | `.text(0x1000)+0xbe4` 一条 `str xzr,[x19]` → NOP（等长） | 修 gz 擦除态下该模块的 NULL 写崩溃（早期 ramoops `set_boot_phase+0x3c` panic） | 是。vendor 模块，内核管不到 |
| 2 | DTB strings 块 | Mali 节点属性名 `protected-memory-allocator`→`protected-memory-allocatoX`（等长改名） | 关 kbase protected-memory 路径：gz 擦除时 `mtee_assign_buffer_v2` SMC 返 -22 → mali prot alloc NULL deref ipanic | **是，且长期是**。DT 级闸门，graphicsengine 加载 CSF 固件即触发，与救援无关 |
| 3 | vendor_boot header `cmdline` 字段 | 追加 `nogzpatch=1 dapcdt=1` | v12 遗留开关，消费者未逐一定位（疑 vendor 侧） | **存疑保留**——相机链已由内核救援解决，理论上可能可删；未做删除回归前不动 |

镜像文件：`~/hermes_work/vendor_boot_a_nogz_patched_v15_devapc_on.img`
（md5 `449da7a8…`，sha256 `6093b684…`，元数据 `v15_meta.json`）。
字节级细节（实际偏移/指令/取证方法）见同目录 `vendor-boot-v15-changeset.md`
——该文档以 cpio 逐文件 md5 对比与 header 结构解析为准，修正了早期
"log_store NOP 在 0x1be4"的旧记录（实际线上链打的是 0xb88）。
构建脚本（等长 DTB/ko 手术范式，防 magiskboot v31 repack 破坏 AVB image_size 的
历史坑，一律手写二进制编辑）：`build_v14_mali.py`、`build_v15_devapc_on.py`、
`repack_v8/v10/v11/v12.py`、`patch_vendorboot.py`（未上线的早期变体，产物
`1b83ddc7` 系 ko 不在 v15 内）、`build_nvhe_safe.py`（boot 侧字节手术——已被
§1.1 取代，退役）。

### 3. 分层职责速查

```
EL2/内核模式 (nvhe)        → 内核 CONFIG_CMDLINE          （本仓库 CI）
trustey-virtio 链救援      → 内核 drivers/trusty_rescue   （本仓库 CI）
Mali protected 闸门        → vendor_boot DTB              （v15）
log_store 崩溃             → vendor_boot vendor_ramdisk   （v15）
gz↔EL2 互换               → 只动 gz_a 分区              （fastboot flash/erase，由人执行）
```

日常↔VM 一体后不再需要双模式镜像组；恢复"全原厂含 gz"路径 = flash 回原厂
gz_a + 原厂 vendor_boot + 原厂 boot（v15 的三处改动理论上也兼容 gz 在位态，
Mali 闸门最多使受保护视频通路退化，未实测，标注为待验）。

### 4. 未验项（诚实清单）

- gz 恢复 + 新内核 + v15 组合的开机回归（预期：rescue 静默、KVM 报 not
  available、其余如原厂）——未实测。
- DRM 受保护流媒体在 gz 擦除态（widevine L1 类）：预期失败（真 SMC 依赖），未测。
- v15 cmdline `nogzpatch/dapcdt` 能否删除：消费者未定位，未做单变量实验。
- HAL 开火前那一次崩溃是否可消除（如 settle 提前）：当前判定为无必要。

---

<a id="src-19"></a>
## 19. GKI / LZ4KD 通用避坑指南（外部通用指南）

> 来源：[`third_party/hyperos-lz4kd/Android_GKI_通用内核定制与LZ4KD实战避坑全指南.md`](../../third_party/hyperos-lz4kd/Android_GKI_通用内核定制与LZ4KD实战避坑全指南.md) · 19197 字节 · SHA256 `24a08fae5abc330bb7304dbd66732a11c6b1e9131c8a58a740410932c1478624`
> 类别：通用参考 · 状态：通用指南（设备差异处不适用）
> 注意：通用指南的 AVB/解锁结论不适用于本机 hidden-unlock；boot 封装以 docs/kernel/BOOT_PACKAGING.md 为准。

> **版本**：v2.0 (工业级最终归档版)  
> **适用机型范围**：搭载 Android 13 / 14 / 15 / 16、Linux 5.10 / 5.15 / 6.1 / 6.6+ 的所有 GKI 2.0 架构设备（包括但不限于高通骁龙 8G2 / 8G3 / 8 Gen 4、天玑 9200 / 9300 / 9400 等全系旗舰与主流机型）。  
> **实测验证平台**：小米 14（代号 `houji`，高通骁龙 8 Gen 3 / SM8650 纯 64 位平台，Xiaomi HyperOS / Android 14，基线内核 `6.1.138-android14-11-g0c3d559bcd85`）。

---

### 目录
- [一、 核心认知与 GKI 架构基本盘](#一-核心认知与-gki-架构基本盘)
- [二、 目标设备“核心四要素”精准锁定 SOP](#二-目标设备核心四要素精准锁定-sop)
- [三、 华为 LZ4KD 算法核心原理与源码适配准备](#三-华为-lz4kd-算法核心原理与源码适配准备)
- [四、 正统工业级云端构建流水线 (GitHub Actions + ACK)](#四-正统工业级云端构建流水线-github-actions--ack)
- [五、 全生命周期 12 大血泪踩坑复盘与根本原因剖析](#五-全生命周期-12-大血泪踩坑复盘与根本原因剖析)
- [六、 本地 Boot 镜像继承式缝合全流程 (纯血防翻车指南)](#六-本地-boot-镜像继承式缝合全流程-纯血防翻车指南)
- [七、 开机验收、Scene 界面接管与性能验证](#七-开机验收scene-界面接管与性能验证)

---

### 一、 核心认知与 GKI 架构基本盘

从 Android 12 / 13 起，Google 全面推行 **GKI 2.0（Generic Kernel Image）** 规范：
1. **内核本体解耦**：核心调度、虚拟内存管理、Crypto 算法库统一集成在核心 `Image`（存放在 `boot.img` 分区）中。
2. **厂商驱动外挂**：主板时钟树、SMMU、总线互联、GPU、声卡以及部分平台组件（如 `zram.ko`）作为动态加载驱动，存放在 `vendor_dlkm` 或 `system_dlkm` 分区中。
3. **AVB 签名与 Bootloader**：在 Bootloader 解锁（Orange State）后，AVB 允许引导非原厂签名的内核，**绝不需要关闭 vbmeta 验证，更严禁抹除用户数据（Wipe Data）！**

---

### 二、 目标设备“核心四要素”精准锁定 SOP

在为任何目标 Android 设备编译/移植内核前，**必须且只能在真机终端**读取并保存以下四大要素：

```bash
# 1. 抓取内核主版本、小版本与精准 Commit 哈希 (最核心基线)
uname -r
# 示例输出：6.1.138-android14-11-g0c3d559bcd85-ab14529422
# -> 内核分支：android14-6.1
# -> 局部版本后缀：-android14-11
# -> 精准提交 Commit：0c3d559bcd85 (后接 c64dae9c9c9687abbe5347fff3ad)

# 2. 确认当前运行的 A/B 槽位
getprop ro.boot.slot_suffix
# 回显：_a 或 _b

# 3. 提取原装 Boot 镜像 (救砖底线资产，严禁使用裁剪包！)
# 可直接通过 Root 提取当前槽位的完整物理镜像（例如 64MB 或 96MB）
dd if=/dev/block/by-name/boot$(getprop ro.boot.slot_suffix) of=/sdcard/stock_boot.img

# 4. 反解内核满血真实运行配置 (IKCONFIG)
# 现代内核均内置了压缩配置流，可在终端使用 Python 直接还原：
python3 -c '
import zlib
with open("/sdcard/stock_boot.img", "rb") as f:
    data = f.read()
pos = data.find(b"\x1f\x8b\x08")
while pos != -1:
    try:
        decomp = zlib.decompress(data[pos:], 16 + zlib.MAX_WBITS)
        if b"CONFIG_" in decomp:
            with open("/sdcard/device_stock_full.config", "wb") as out:
                out.write(decomp)
            print("成功提取出 100% 满血原厂配置！")
            break
    except:
        pass
    pos = data.find(b"\x1f\x8b\x08", pos + 1)
'
```

---

### 三、 华为 LZ4KD 算法核心原理与源码适配准备

#### 1. LZ4KD 优势
* **LZ4K（4KB 页剪裁）**：针对移动端 OS 内存按 4KB 页面分配的特点，精简传统 LZ4 的冗余查找窗口与哈希表，压缩时延大幅降低，功耗极小。
* **Delta（跨页差分增量）**：对于连续内存页，计算当前页与上一页的字节异或/差分序列，在后台高密度冷数据压缩场景下，压缩比显著超越原生 LZ4。

#### 2. 源码结构规范（必须放置在独立子目录）
必须将算法组织为独立模块，杜绝污染内核原生根目录：
```text
lz4kd_module/
├── Kconfig               # Kconfig 描述文件 (带 default y)
├── Makefile              # 驱动 Makefile (必须使用 obj-$(CONFIG_...) 模式)
├── lz4kd.h               # 核心算法头文件
├── lz4kd_crypto.c        # Crypto API 与 scomp 同步压缩注册接口
├── lz4kd_encode.c        # 编码核心
├── lz4kd_decode.c        # 解码核心
├── lz4kd_encode_delta.c  # 差分增量编码
├── lz4kd_decode_delta.c  # 差分增量解码
└── include/linux/lz4kd.h # 暴露给内核 include 的系统级头文件
```

#### 3. `lz4kd_crypto.c` 关键实现规范 (Linux 6.1+ 必须支持 `scomp`)
```c
#include <linux/init.h>
#include <linux/module.h>
#include <linux/crypto.h>
#include <linux/vmalloc.h>
#include <crypto/internal/scompress.h> // 必须是 scompress.h，绝对不能简写为 scomp.h！
#include "lz4kd.h"

// 上下文与压缩/解压实现 ...

static struct scomp_alg scomp = {
	.alloc_ctx		= lz4kd_alloc_ctx,
	.free_ctx		= lz4kd_free_ctx,
	.compress		= lz4kd_scompress,
	.decompress		= lz4kd_sdecompress,
	.base			= {
		.cra_name		= "lz4kd",
		.cra_driver_name	= "lz4kd-scomp",
		.cra_module		= THIS_MODULE,
	}
};

static int __init lz4kd_mod_init(void) {
	int ret = crypto_register_alg(&alg_lz4kd);
	if (ret) return ret;
	ret = crypto_register_scomp(&scomp);
	if (ret) {
		crypto_unregister_alg(&alg_lz4kd);
		return ret;
	}
	return 0;
}
```

---

### 四、 正统工业级云端构建流水线 (GitHub Actions + ACK)

本工作流基于官方 AOSP ACK（Android Common Kernel）和 TWRP 核心维护者 YukongA 的工业级标准构建，并在全流程中完整吸收了全部避坑补丁：

```yaml
name: Build Universal GKI LZ4KD Kernel from ACK

on:
  workflow_dispatch:
    inputs:
      TAG:
        description: 'ACK 分支 (例如 android14-6.1 / android15-6.6)'
        required: true
        default: 'android14-6.1'
      KERNEL_COMMIT:
        description: '精准锁定 Commit (与真机 uname -r 严格对齐)'
        required: false
        default: '0c3d559bcd85c64dae9c9c9687abbe5347fff3ad'
  push:
    branches:
      - main

jobs:
  build:
    name: Build LZ4KD Kernel
    runs-on: ubuntu-latest
    env:
      CCACHE_COMPILERCHECK: "%compiler% -dumpmachine; %compiler% -dumpversion"
      CCACHE_NOHASHDIR: "true"
      CCACHE_HARDLINK: "true"
    steps:
      # 1. 扩充磁盘空间 (释放 30GB+，将挂载区分离到大卷)
      - name: Maximize Build Space
        uses: easimon/maximize-build-space@master
        with:
          swap-size-mb: 8192
          root-reserve-mb: 16384
          temp-reserve-mb: 2048
          remove-dotnet: 'true'
          remove-android: 'true'
          remove-haskell: 'true'
          remove-codeql: 'true'

      # 2. 检出仓库代码 (必须在扩容后检出，避免路径漂移)
      - name: Checkout Repository
        uses: actions/checkout@v4

      # 3. 致命坑修复：将所有编译缓存重定向至 90GB+ 工作区大分区
      - name: Redirect Cache to High Capacity Partition
        run: |
          mkdir -p $GITHUB_WORKSPACE/.cache/bazel
          rm -rf /home/runner/.cache 2>/dev/null || true
          ln -sf $GITHUB_WORKSPACE/.cache /home/runner/.cache
          df -h

      # 4. 同步 Google 官方密封编译环境与精准源码基线
      - name: Download Kernel Source via Repo
        run: |
          sudo apt-get remove firefox -y 2>/dev/null || true
          sudo apt-get update
          sudo apt-get install -y repo ccache git zip unzip python3
          cd $GITHUB_WORKSPACE
          git config --global user.name "KernelBuilder"
          git config --global user.email "builder@kernel.local"
          mkdir -p android-kernel && cd android-kernel

          TARGET_TAG="${{ github.event.inputs.TAG || 'android14-6.1' }}"
          repo init --depth=1 -u https://android.googlesource.com/kernel/manifest -b "common-$TARGET_TAG" --repo-rev=v2.16
          repo --trace sync -c -j$(nproc --all) --no-tags

          TARGET_COMMIT="${{ github.event.inputs.KERNEL_COMMIT || '0c3d559bcd85c64dae9c9c9687abbe5347fff3ad' }}"
          if [ -n "$TARGET_COMMIT" ]; then
            cd common
            git fetch --depth=1 https://android.googlesource.com/kernel/common "$TARGET_COMMIT"
            git checkout FETCH_HEAD
            cd ..
          fi

      # 5. 算法注入与内核 Kbuild / 菜单注册
      - name: Inject LZ4KD Algorithm
        run: |
          GKI_ROOT=$GITHUB_WORKSPACE/android-kernel
          LZ4KD_SRC=$GITHUB_WORKSPACE/lz4kd_module

          mkdir -p $GKI_ROOT/common/crypto/lz4kd
          cp -rf $LZ4KD_SRC/* $GKI_ROOT/common/crypto/lz4kd/
          cp -rf $LZ4KD_SRC/include/linux/* $GKI_ROOT/common/include/linux/

          DRIVER_MAKEFILE=$GKI_ROOT/common/crypto/Makefile
          DRIVER_KCONFIG=$GKI_ROOT/common/crypto/Kconfig
          grep -q "lz4kd" "$DRIVER_MAKEFILE" || printf "\nobj-\$(CONFIG_CRYPTO_LZ4KD) += lz4kd/\n" >> "$DRIVER_MAKEFILE"
          grep -q "lz4kd" "$DRIVER_KCONFIG" || sed -i '/endmenu/i\source "crypto/lz4kd/Kconfig"' "$DRIVER_KCONFIG"

          # 注册到 ZRAM 静态菜单 (Scene / 性能调节 App 识别的关键)
          python3 -c '
          zcomp_file = "'$GKI_ROOT'/common/drivers/block/zram/zcomp.c"
          with open(zcomp_file, "r") as f:
              content = f.read()
          target = """#if IS_ENABLED(CONFIG_CRYPTO_ZSTD)\n\t\"zstd\",\n#endif"""
          replacement = target + """\n#if IS_ENABLED(CONFIG_CRYPTO_LZ4KD)\n\t\"lz4kd\",\n#endif"""
          if target in content and "CONFIG_CRYPTO_LZ4KD" not in content:
              content = content.replace(target, replacement, 1)
              with open(zcomp_file, "w") as f:
                  f.write(content)
              print("[+] Successfully registered lz4kd into zcomp.c backends[]")
          '

      # 6. 移除符号保护，全量导出符号支持厂商闭源驱动
      - name: Symbol and ABI Protection Removal
        working-directory: android-kernel
        run: |
          rm -f common/android/abi_gki_protected_exports_* || true
          sed -i '/^[[:space:]]*"protected_exports_list"/d' common/BUILD.bazel 2>/dev/null || true

      # 7. 清理工作树，防止版本号被打上 -dirty 导致驱动拒载
      - name: Clean Working Directory to Avoid -dirty Version
        working-directory: android-kernel
        run: |
          cd common
          git add -A
          git commit -a -m "Add LZ4KD compression algorithm" || true

      # 8. 编译 Image
      - name: Build ACK Kernel Image
        working-directory: android-kernel
        run: |
          if [ -e build/build.sh ]; then
            BUILD_BOOT_IMG=1 SKIP_VENDOR_BOOT=1 KERNEL_BINARY=Image LTO=thin build/build.sh CC="/usr/bin/ccache clang"
          else
            tools/bazel run --cache_dir=$GITHUB_WORKSPACE/.cache/bazel --config=fast --config=stamp --lto=thin //common:kernel_aarch64_dist -- --dist_dir=dist
          fi

      # 9. 产物上传 (归档 Image 与全套制品)
      - name: Upload Raw Kernel Image & Dist
        uses: actions/upload-artifact@v4
        with:
          name: Kernel_Dist_Artifacts
          path: |
            android-kernel/dist/Image
            android-kernel/dist/boot.img
```

---

### 五、 全生命周期 12 大血泪踩坑复盘与根本原因剖析

在实际推进过程中，任何一个细节的偏差都会直接导致编译中断、死机断电或无法生效。以下 12 大致命坑是全机型定制的核心教训：

#### 1. 通用 AOSP `make gki_defconfig` 裸编卡米断电
* **致命原因**：官方 `gki_defconfig` 仅有 ~660 项基础配置，而实际真机运行时拥有 **2100+ 项配置**。裸编会彻底丢弃高通/联发科平台的硬件时钟树（CLK）、总线互联（Interconnect）、SMMU 保护等驱动，CPU 上电前几毫秒连主板总线都访问不了，触发 Hard Fault 死循环复位。
* **规避原则**：必须使用官方密封 ACK + Kleaf / Bazel 编译，或者基于反解的真机满血 `.config` 编译。

#### 2. 源码拉取未锁定 Commit 导致驱动拒绝加载 (CRC Mismatch)
* **致命原因**：若只 clone `android14-6.1` 分支最新 HEAD，代码会滚动到如 `6.1.177`，而手机系统的 400+ 个闭源驱动是严格绑定在出厂 Commit（如 `6.1.138 0c3d559bcd85`）上的。函数符号 CRC 校验错位，驱动被内核集体拒载。
* **规避原则**：通过 `uname -r` 提取精准 Commit，`git fetch` 时精准锁定该 Commit。

#### 3. 外挂 `lz4kd.ko` 动态加载瞬间黑屏断电死机 (kCFI 拦截)
* **致命原因**：高通 8 Gen 3 等新平台开启了硬件级 **kCFI（内核控制流完整性保护）**。外部单独编译的模块函数指针前缺失 4 字节类型哈希，函数指针一被内核调用，CPU 直接触发硬件 `BRK` 保护，PMIC 瞬间切断供电。
* **规避原则**：**LZ4KD 必须同源内置编译（Built-in）进内核本体 `Image`**，绝不能作为孤立外挂模块加载。

#### 4. 误信“更换内核必须关闭 vbmeta 签名与抹除数据”
* **致命真相**：Bootloader 解锁（Orange State）后，AVB 验证级别已经放开，**允许引导第三方内核**！无论更换内核还是缝合 boot，**绝不需要关闭 vbmeta，更绝不需要清空用户数据（Wipe Data）！**

#### 5. 直接覆盖 `crypto/Makefile` 导致构建系统整体崩溃
* **致命原因**：文档若简写为 `cp -rf lz4kd_module/* common/crypto/`，模块自有的简易 Makefile 会直接冲掉 Linux 原生包含几十种加密算法的核心 `Makefile`，导致整个 crypto 目录编译报错停机。
* **规避原则**：建立独立子目录 `common/crypto/lz4kd/`，在原厂 Makefile 尾部通过 `obj-$(CONFIG_CRYPTO_LZ4KD) += lz4kd/` 引入。

#### 6. Makefile 写死 `obj-m` 导致无法打入内核镜像
* **致命原因**：Makefile 若固定写为 `obj-m += lz4kd.o`，Kbuild 只会在编译外部模块时生成 `.ko`，根本不会将其符号链接进 `Image`。
* **规避原则**：必须遵循 Kconfig 动态编译语法：`obj-$(CONFIG_CRYPTO_LZ4KD) += lz4kd.o`。

#### 7. 未声明 Kconfig 导致配置被 Kbuild 静默剔除
* **致命原因**：仅在 defconfig 写入 `CONFIG_CRYPTO_LZ4KD=y`，但没有在 `Kconfig` 中声明该符号，Kbuild 在执行配置收敛时会作为未知杂质**直接静默丢弃**。
* **规避原则**：规范编写 `Kconfig` 文件，并将其声明为 `default y`。

#### 8. Linux 6.1 ZRAM 依赖的 `scompress` 头文件拼写陷阱
* **致命原因**：原代码若 include `<crypto/internal/scomp.h>`，Clang 会直接报 `file not found`。在 Linux 6.1 GKI 中，官方头文件名严格为 **`<crypto/internal/scompress.h>`**（带完整 `ress` 后缀）。

#### 9. Bazel / Kleaf 构建设施的 `savedefconfig` 强校验拦截
* **致命原因**：在构建脚本中若手动追加改动了 `gki_defconfig`，Kleaf 在运行中会调用 `savedefconfig` 对比，一旦字段顺序或格式未对齐，直接中断报：`ERROR: savedefconfig does not match`。
* **规避原则**：在 `lz4kd_module/Kconfig` 中直接声明 `default y`，保持原厂 `gki_defconfig` 原汁原味，彻底规避校验拦截。

#### 10. CI 虚拟机根分区仅剩 2GB 导致 Bazel 缓存塞满强杀 Runner
* **致命原因**：GitHub 扩容插件将 92GB 挂载在工作区，但根分区 `/dev/root` 仅剩 2GB。Bazel 默认缓存路径 `/home/runner/.cache` 处在根分区，整核编译产生巨量缓存后根分区迅速撑爆，CI 守护进程因无法写磁盘直接崩溃中断。
* **规避原则**：在检出源码后立即执行 `ln -sf $GITHUB_WORKSPACE/.cache /home/runner/.cache`，并将 Bazel cache 参数显式指定为工作区路径。

#### 11. 骁龙 8 Gen 3 纯 64 位 CPU 硬件断代导致的 `Busybox setup failed`
* **致命原因**：骁龙 8 Gen 3 硬件级砍掉了 AArch32 架构支持。官方老版 AnyKernel3 默认携带的 `busybox` / `magiskboot` 是 32 位 ARM (ELF32) 二进制文件。在 Recovery 或系统执行时，CPU 硬件因不支持 32 位指令集直接报错退出。
* **规避原则**：必须全量替换为 **ELF64 AArch64 纯 64 位静态编译**工具链。

#### 12. 开机状态下直接 `swapoff` / `reset` 触发 `Device or resource busy` (EBUSY)
* **致命原因**：Android 开机进入桌面后，系统内存守护进程（`perfd`/`lmkd`）会常驻打开 `/dev/block/zram0` 句柄。Linux 内核具有死锁保护：`if (disk_openers(disk)) return -EBUSY;`，开机后再尝试 `reset` 必被内核拒绝！
* **规避原则**：必须采用**本地继承式缝合单 Boot 镜像**或在开机早期（`post-fs-data`）由模块自动接管，严禁在开机桌面状态下强行重置。

---

### 六、 本地 Boot 镜像继承式缝合全流程 (纯血防翻车指南)

无论针对什么机型，最优雅、对系统零破坏且 100% 保留原有 TWRP 与开机引导的方案，就是在本地通过 **64 位 `magiskboot`** 进行继承式缝合：

```bash
# 1. 准备独立缝合目录与资产
mkdir -p /tmp/repack_workspace && cd /tmp/repack_workspace
cp /path/to/stock_boot.img ./stock_boot.img   # 96MB 原厂底包 (内置 TWRP)
cp /path/to/magiskboot_64 ./magiskboot        # 纯 64 位 magiskboot 工具
chmod 755 ./magiskboot

# 2. 解包原装底包 (提取 Header v4 引导结构、Cmdline 和 VBMETA 签名链)
./magiskboot unpack stock_boot.img
# 回显应显示：HEADER_VER [4], KERNEL_SZ [...], VBMETA

# 3. 将云端编译出的新内核二进制覆盖 kernel
cp -f /path/to/Image ./kernel

# 4. 继承原厂所有结构重新封包
./magiskboot repack stock_boot.img final_lz4kd_boot.img
# 回显应显示：Repack to boot image: [final_lz4kd_boot.img]

# 5. 校验字节尺寸 (必须与原装 100,663,296 字节完全一致)
stat -c "%s %n" stock_boot.img final_lz4kd_boot.img
```

刷入方式：
* 在 TWRP 中切换为【安装镜像】-> 选择 `final_lz4kd_boot.img` -> 勾选【Boot】滑动刷入；
* 或在电脑 Fastboot 下直敲：`fastboot flash boot_a final_lz4kd_boot.img && fastboot reboot`。

---

### 七、 开机验收、Scene 界面接管与性能验证

#### 1. 内核生效验证
开机后在终端执行：
```bash
cat /proc/version
# 确认显示自编的时间戳与构建账号

grep -A 8 "lz4kd" /proc/crypto
# 确认 lz4kd-scomp 与 lz4kd-generic 自检状态均为 selftest : passed
```

#### 2. Scene / 性能调节 App 一键接管
由于方案中已将 `lz4kd` 注册到内核 ZRAM 的静态菜单数组 `backends[]`：
1. 打开 **Scene** App（或微调工具箱），授予 Root 权限；
2. 导航至【功能】->【Swap / ZRAM 调节】；
3. 下拉菜单中将原生出现 **`lz4kd`**，直接点选并勾选【开机自动应用】；
4. 以后每次手机开机，系统全自动接管为华为 LZ4KD 4KB 差分增量压缩模式！

---

<a id="src-20"></a>
## 20. hyperos-lz4kd 项目说明（上游参考）

> 来源：[`third_party/hyperos-lz4kd/README.md`](../../third_party/hyperos-lz4kd/README.md) · 18119 字节 · SHA256 `02074aa9cd5a5d3fea9a035988b6bf2ede5ef8295d114b523203f25f8d5d14bb`
> 类别：上游参考 · 状态：上游参考（版本可能漂移）
> 注意：该 README 在“七、开机”处截断，内容与完整避坑指南重复；保留仅用于记录上游现状。
> 注意：源文件末尾代码围栏未闭合，生成器已补上关闭围栏；源文件本身可能被截断。

> **版本**：v2.0
> **适用机型范围**：搭载 Android 13 / 14 / 15 / 16、Linux 5.10 / 5.15 / 6.1 / 6.6+ 的所有 GKI 2.0 架构设备（包括但不限于高通骁龙 8G2 / 8G3 / 8 Gen 4、天玑 9200 / 9300 / 9400 等全系旗舰与主流机型）。  
> **实测验证平台**：小米 14（代号 `houji`，高通骁龙 8 Gen 3 / SM8650 纯 64 位平台，Xiaomi HyperOS / Android 14，基线内核 `6.1.138-android14-11-g0c3d559bcd85`）。

---

### 目录
- [一、 核心认知与 GKI 架构基本盘](#一-核心认知与-gki-架构基本盘)
- [二、 目标设备“核心四要素”精准锁定 SOP](#二-目标设备核心四要素精准锁定-sop)
- [三、 华为 LZ4KD 算法核心原理与源码适配准备](#三-华为-lz4kd-算法核心原理与源码适配准备)
- [四、 正统工业级云端构建流水线 (GitHub Actions + ACK)](#四-正统工业级云端构建流水线-github-actions--ack)
- [五、 全生命周期 12 大血泪踩坑复盘与根本原因剖析](#五-全生命周期-12-大血泪踩坑复盘与根本原因剖析)
- [六、 本地 Boot 镜像继承式缝合全流程 (纯血防翻车指南)](#六-本地-boot-镜像继承式缝合全流程-纯血防翻车指南)
- [七、 开机验收、Scene 界面接管与性能验证](#七-开机验收scene-界面接管与性能验证)

---

### 一、 核心认知与 GKI 架构基本盘

从 Android 12 / 13 起，Google 全面推行 **GKI 2.0（Generic Kernel Image）** 规范：
1. **内核本体解耦**：核心调度、虚拟内存管理、Crypto 算法库统一集成在核心 `Image`（存放在 `boot.img` 分区）中。
2. **厂商驱动外挂**：主板时钟树、SMMU、总线互联、GPU、声卡以及部分平台组件（如 `zram.ko`）作为动态加载驱动，存放在 `vendor_dlkm` 或 `system_dlkm` 分区中。
3. **AVB 签名与 Bootloader**：在 Bootloader 解锁（Orange State）后，AVB 允许引导非原厂签名的内核，**不需要关闭 vbmeta 验证**

---

### 二、 目标设备“核心四要素”精准锁定 SOP

在为任何目标 Android 设备编译/移植内核前，**必须且只能在真机终端**读取并保存以下四大要素：

```bash
# 1. 抓取内核主版本、小版本与精准 Commit 哈希 (最核心基线)
uname -r
# 示例输出：6.1.138-android14-11-g0c3d559bcd85-ab14529422
# -> 内核分支：android14-6.1
# -> 局部版本后缀：-android14-11
# -> 精准提交 Commit：0c3d559bcd85 (后接 c64dae9c9c9687abbe5347fff3ad)

# 2. 确认当前运行的 A/B 槽位
getprop ro.boot.slot_suffix
# 回显：_a 或 _b

# 3. 提取原装 Boot 镜像 (救砖底线资产，严禁使用裁剪包！)
# 可直接通过 Root 提取当前槽位的完整物理镜像（例如 64MB 或 96MB）
dd if=/dev/block/by-name/boot$(getprop ro.boot.slot_suffix) of=/sdcard/stock_boot.img

# 4. 反解内核满血真实运行配置 (IKCONFIG)
# 现代内核均内置了压缩配置流，可在终端使用 Python 直接还原：
python3 -c '
import zlib
with open("/sdcard/stock_boot.img", "rb") as f:
    data = f.read()
pos = data.find(b"\x1f\x8b\x08")
while pos != -1:
    try:
        decomp = zlib.decompress(data[pos:], 16 + zlib.MAX_WBITS)
        if b"CONFIG_" in decomp:
            with open("/sdcard/device_stock_full.config", "wb") as out:
                out.write(decomp)
            print("成功提取出 100% 满血原厂配置！")
            break
    except:
        pass
    pos = data.find(b"\x1f\x8b\x08", pos + 1)
'
```

---

### 三、 华为 LZ4KD 算法核心原理与源码适配准备

#### 1. LZ4KD 优势
* **LZ4K（4KB 页剪裁）**：针对移动端 OS 内存按 4KB 页面分配的特点，精简传统 LZ4 的冗余查找窗口与哈希表，压缩时延大幅降低，功耗极小。
* **Delta（跨页差分增量）**：对于连续内存页，计算当前页与上一页的字节异或/差分序列，在后台高密度冷数据压缩场景下，压缩比显著超越原生 LZ4。

#### 2. 源码结构规范（必须放置在独立子目录）
必须将算法组织为独立模块，杜绝污染内核原生根目录：
```text
lz4kd_module/
├── Kconfig               # Kconfig 描述文件 (带 default y)
├── Makefile              # 驱动 Makefile (必须使用 obj-$(CONFIG_...) 模式)
├── lz4kd.h               # 核心算法头文件
├── lz4kd_crypto.c        # Crypto API 与 scomp 同步压缩注册接口
├── lz4kd_encode.c        # 编码核心
├── lz4kd_decode.c        # 解码核心
├── lz4kd_encode_delta.c  # 差分增量编码
├── lz4kd_decode_delta.c  # 差分增量解码
└── include/linux/lz4kd.h # 暴露给内核 include 的系统级头文件
```

#### 3. `lz4kd_crypto.c` 关键实现规范 (Linux 6.1+ 必须支持 `scomp`)
```c
#include <linux/init.h>
#include <linux/module.h>
#include <linux/crypto.h>
#include <linux/vmalloc.h>
#include <crypto/internal/scompress.h> // 必须是 scompress.h，绝对不能简写为 scomp.h！
#include "lz4kd.h"

// 上下文与压缩/解压实现 ...

static struct scomp_alg scomp = {
	.alloc_ctx		= lz4kd_alloc_ctx,
	.free_ctx		= lz4kd_free_ctx,
	.compress		= lz4kd_scompress,
	.decompress		= lz4kd_sdecompress,
	.base			= {
		.cra_name		= "lz4kd",
		.cra_driver_name	= "lz4kd-scomp",
		.cra_module		= THIS_MODULE,
	}
};

static int __init lz4kd_mod_init(void) {
	int ret = crypto_register_alg(&alg_lz4kd);
	if (ret) return ret;
	ret = crypto_register_scomp(&scomp);
	if (ret) {
		crypto_unregister_alg(&alg_lz4kd);
		return ret;
	}
	return 0;
}
```

---

### 四、 构建流水线 (GitHub Actions + ACK)

本工作流基于官方 AOSP ACK（Android Common Kernel）和 TWRP 核心维护者 YukongA 的标准构建并完善补丁：

```yaml
name: Build Universal GKI LZ4KD Kernel from ACK

on:
  workflow_dispatch:
    inputs:
      TAG:
        description: 'ACK 分支 (例如 android14-6.1 / android15-6.6)'
        required: true
        default: 'android14-6.1'
      KERNEL_COMMIT:
        description: '精准锁定 Commit (与真机 uname -r 严格对齐)'
        required: false
        default: '0c3d559bcd85c64dae9c9c9687abbe5347fff3ad'
  push:
    branches:
      - main

jobs:
  build:
    name: Build LZ4KD Kernel
    runs-on: ubuntu-latest
    env:
      CCACHE_COMPILERCHECK: "%compiler% -dumpmachine; %compiler% -dumpversion"
      CCACHE_NOHASHDIR: "true"
      CCACHE_HARDLINK: "true"
    steps:
      # 1. 扩充磁盘空间 (释放 30GB+，将挂载区分离到大卷)
      - name: Maximize Build Space
        uses: easimon/maximize-build-space@master
        with:
          swap-size-mb: 8192
          root-reserve-mb: 16384
          temp-reserve-mb: 2048
          remove-dotnet: 'true'
          remove-android: 'true'
          remove-haskell: 'true'
          remove-codeql: 'true'

      # 2. 检出仓库代码 (必须在扩容后检出，避免路径漂移)
      - name: Checkout Repository
        uses: actions/checkout@v4

      # 3. 致命坑修复：将所有编译缓存重定向至 90GB+ 工作区大分区
      - name: Redirect Cache to High Capacity Partition
        run: |
          mkdir -p $GITHUB_WORKSPACE/.cache/bazel
          rm -rf /home/runner/.cache 2>/dev/null || true
          ln -sf $GITHUB_WORKSPACE/.cache /home/runner/.cache
          df -h

      # 4. 同步 Google 官方密封编译环境与精准源码基线
      - name: Download Kernel Source via Repo
        run: |
          sudo apt-get remove firefox -y 2>/dev/null || true
          sudo apt-get update
          sudo apt-get install -y repo ccache git zip unzip python3
          cd $GITHUB_WORKSPACE
          git config --global user.name "KernelBuilder"
          git config --global user.email "builder@kernel.local"
          mkdir -p android-kernel && cd android-kernel

          TARGET_TAG="${{ github.event.inputs.TAG || 'android14-6.1' }}"
          repo init --depth=1 -u https://android.googlesource.com/kernel/manifest -b "common-$TARGET_TAG" --repo-rev=v2.16
          repo --trace sync -c -j$(nproc --all) --no-tags

          TARGET_COMMIT="${{ github.event.inputs.KERNEL_COMMIT || '0c3d559bcd85c64dae9c9c9687abbe5347fff3ad' }}"
          if [ -n "$TARGET_COMMIT" ]; then
            cd common
            git fetch --depth=1 https://android.googlesource.com/kernel/common "$TARGET_COMMIT"
            git checkout FETCH_HEAD
            cd ..
          fi

      # 5. 算法注入与内核 Kbuild / 菜单注册
      - name: Inject LZ4KD Algorithm
        run: |
          GKI_ROOT=$GITHUB_WORKSPACE/android-kernel
          LZ4KD_SRC=$GITHUB_WORKSPACE/lz4kd_module

          mkdir -p $GKI_ROOT/common/crypto/lz4kd
          cp -rf $LZ4KD_SRC/* $GKI_ROOT/common/crypto/lz4kd/
          cp -rf $LZ4KD_SRC/include/linux/* $GKI_ROOT/common/include/linux/

          DRIVER_MAKEFILE=$GKI_ROOT/common/crypto/Makefile
          DRIVER_KCONFIG=$GKI_ROOT/common/crypto/Kconfig
          grep -q "lz4kd" "$DRIVER_MAKEFILE" || printf "\nobj-\$(CONFIG_CRYPTO_LZ4KD) += lz4kd/\n" >> "$DRIVER_MAKEFILE"
          grep -q "lz4kd" "$DRIVER_KCONFIG" || sed -i '/endmenu/i\source "crypto/lz4kd/Kconfig"' "$DRIVER_KCONFIG"

          # 注册到 ZRAM 静态菜单 (Scene / 性能调节 App 识别的关键)
          python3 -c '
          zcomp_file = "'$GKI_ROOT'/common/drivers/block/zram/zcomp.c"
          with open(zcomp_file, "r") as f:
              content = f.read()
          target = """#if IS_ENABLED(CONFIG_CRYPTO_ZSTD)\n\t\"zstd\",\n#endif"""
          replacement = target + """\n#if IS_ENABLED(CONFIG_CRYPTO_LZ4KD)\n\t\"lz4kd\",\n#endif"""
          if target in content and "CONFIG_CRYPTO_LZ4KD" not in content:
              content = content.replace(target, replacement, 1)
              with open(zcomp_file, "w") as f:
                  f.write(content)
              print("[+] Successfully registered lz4kd into zcomp.c backends[]")
          '

      # 6. 移除符号保护，全量导出符号支持厂商闭源驱动
      - name: Symbol and ABI Protection Removal
        working-directory: android-kernel
        run: |
          rm -f common/android/abi_gki_protected_exports_* || true
          sed -i '/^[[:space:]]*"protected_exports_list"/d' common/BUILD.bazel 2>/dev/null || true

      # 7. 清理工作树，防止版本号被打上 -dirty 导致驱动拒载
      - name: Clean Working Directory to Avoid -dirty Version
        working-directory: android-kernel
        run: |
          cd common
          git add -A
          git commit -a -m "Add LZ4KD compression algorithm" || true

      # 8. 产物上传 (只交付纯血核心与一键缝合工具，剔除无用 64MB 假 boot 和鸡肋 AnyKernel3)
      - name: Prepare Kernel Image and Repack Tool Artifacts
        run: |
          mkdir -p release_kernel
          cp -f $OUTDIR/Image release_kernel/
          cp -f $OUTDIR/zram.ko release_kernel/ 2>/dev/null || true
          cp -f tools_arm64/magiskboot release_kernel/
          cp -f repack_boot.sh release_kernel/
          chmod +x release_kernel/magiskboot release_kernel/repack_boot.sh

      - name: Upload Kernel Image and Repack Tool
        uses: actions/upload-artifact@v4
        with:
          name: Kernel_Image_and_Repack_Tool
          path: release_kernel/

      - name: Upload LZ4KD Auto Switch Module
        uses: actions/upload-artifact@v4
        with:
          name: LZ4KD_ZRAM_Auto_Switch
          path: LZ4KD_ZRAM_Auto_Switch.zip
```

---

### 五、 复盘与原因剖析

在实际推进过程中，任何一个细节的偏差都会直接导致编译中断、死机断电或无法生效。以下 12 大致命坑是全机型定制的核心教训：

#### 1. 通用 AOSP `make gki_defconfig` 裸编卡米断电
* **致命原因**：官方 `gki_defconfig` 仅有 ~660 项基础配置，而实际真机运行时拥有 **2100+ 项配置**。裸编会彻底丢弃高通/联发科平台的硬件时钟树（CLK）、总线互联（Interconnect）、SMMU 保护等驱动，CPU 上电前几毫秒连主板总线都访问不了，触发 Hard Fault 死循环复位。
* **规避原则**：必须使用官方密封 ACK + Kleaf / Bazel 编译，或者基于反解的真机满血 `.config` 编译。

#### 2. 源码拉取未锁定 Commit 导致驱动拒绝加载 (CRC Mismatch)
* **致命原因**：若只 clone `android14-6.1` 分支最新 HEAD，代码会滚动到如 `6.1.177`，而手机系统的 400+ 个闭源驱动是严格绑定在出厂 Commit（如 `6.1.138 0c3d559bcd85`）上的。函数符号 CRC 校验错位，驱动被内核集体拒载。
* **规避原则**：通过 `uname -r` 提取精准 Commit，`git fetch` 时精准锁定该 Commit。

#### 3. 外挂 `lz4kd.ko` 动态加载瞬间黑屏断电死机 (kCFI 拦截)
* **致命原因**：高通 8 Gen 3 等新平台开启了硬件级 **kCFI（内核控制流完整性保护）**。外部单独编译的模块函数指针前缺失 4 字节类型哈希，函数指针一被内核调用，CPU 直接触发硬件 `BRK` 保护，PMIC 瞬间切断供电。
* **规避原则**：**LZ4KD 必须同源内置编译（Built-in）进内核本体 `Image`**，绝不能作为孤立外挂模块加载。

#### 4. 不需要关闭 vbmeta”
* **致命真相**：Bootloader 解锁（Orange State）后，AVB 验证级别已经放开，**允许引导第三方内核**！无论更换内核还是缝合 boot，**不需要关闭 vbmeta**

#### 5. 直接覆盖 `crypto/Makefile` 导致构建系统整体崩溃
* **致命原因**：文档若简写为 `cp -rf lz4kd_module/* common/crypto/`，模块自有的简易 Makefile 会直接冲掉 Linux 原生包含几十种加密算法的核心 `Makefile`，导致整个 crypto 目录编译报错停机。
* **规避原则**：建立独立子目录 `common/crypto/lz4kd/`，在原厂 Makefile 尾部通过 `obj-$(CONFIG_CRYPTO_LZ4KD) += lz4kd/` 引入。

#### 6. Makefile 写死 `obj-m` 导致无法打入内核镜像
* **致命原因**：Makefile 若固定写为 `obj-m += lz4kd.o`，Kbuild 只会在编译外部模块时生成 `.ko`，根本不会将其符号链接进 `Image`。
* **规避原则**：必须遵循 Kconfig 动态编译语法：`obj-$(CONFIG_CRYPTO_LZ4KD) += lz4kd.o`。

#### 7. 未声明 Kconfig 导致配置被 Kbuild 静默剔除
* **致命原因**：仅在 defconfig 写入 `CONFIG_CRYPTO_LZ4KD=y`，但没有在 `Kconfig` 中声明该符号，Kbuild 在执行配置收敛时会作为未知杂质**直接静默丢弃**。
* **规避原则**：规范编写 `Kconfig` 文件，并将其声明为 `default y`。

#### 8. Linux 6.1 ZRAM 依赖的 `scompress` 头文件拼写陷阱
* **致命原因**：原代码若 include `<crypto/internal/scomp.h>`，Clang 会直接报 `file not found`。在 Linux 6.1 GKI 中，官方头文件名严格为 **`<crypto/internal/scompress.h>`**（带完整 `ress` 后缀）。

#### 9. Bazel / Kleaf 构建设施的 `savedefconfig` 强校验拦截
* **致命原因**：在构建脚本中若手动追加改动了 `gki_defconfig`，Kleaf 在运行中会调用 `savedefconfig` 对比，一旦字段顺序或格式未对齐，直接中断报：`ERROR: savedefconfig does not match`。
* **规避原则**：在 `lz4kd_module/Kconfig` 中直接声明 `default y`，保持原厂 `gki_defconfig` 原汁原味，彻底规避校验拦截。

#### 10. CI 虚拟机根分区仅剩 2GB 导致 Bazel 缓存塞满强杀 Runner
* **致命原因**：GitHub 扩容插件将 92GB 挂载在工作区，但根分区 `/dev/root` 仅剩 2GB。Bazel 默认缓存路径 `/home/runner/.cache` 处在根分区，整核编译产生巨量缓存后根分区迅速撑爆，CI 守护进程因无法写磁盘直接崩溃中断。
* **规避原则**：在检出源码后立即执行 `ln -sf $GITHUB_WORKSPACE/.cache /home/runner/.cache`，并将 Bazel cache 参数显式指定为工作区路径。

#### 11. 骁龙 8 Gen 3 纯 64 位 CPU 硬件断代导致的 `Busybox setup failed`
* **致命原因**：骁龙 8 Gen 3 硬件级砍掉了 AArch32 架构支持。官方老版 AnyKernel3 默认携带的 `busybox` / `magiskboot` 是 32 位 ARM (ELF32) 二进制文件。在 Recovery 或系统执行时，CPU 硬件因不支持 32 位指令集直接报错退出。
* **规避原则**：必须全量替换为 **ELF64 AArch64 纯 64 位静态编译**工具链。

#### 12. 开机状态下直接 `swapoff` / `reset` 触发 `Device or resource busy` (EBUSY)
* **致命原因**：Android 开机进入桌面后，系统内存守护进程（`perfd`/`lmkd`）会常驻打开 `/dev/block/zram0` 句柄。Linux 内核具有死锁保护：`if (disk_openers(disk)) return -EBUSY;`，开机后再尝试 `reset` 必被内核拒绝！
* **规避原则**：必须采用**本地继承式缝合单 Boot 镜像**或在开机早期（`post-fs-data`）由模块自动接管，严禁在开机桌面状态下强行重置。

---

### 六、 本地 Boot 镜像继承式缝合全流程 (纯血防翻车指南)

无论针对什么机型，最优雅、对系统零破坏且 100% 保留原有 TWRP 与开机引导的方案，就是在本地通过 **64 位 `magiskboot`** 进行继承式缝合：

#### 1. 使用仓库自带脚本一键缝合（最推荐）

仓库已内置开箱即用的自动缝合脚本 `repack_boot.sh`，内部已集成全部解包、替换、重封包与 100,663,296 字节校验逻辑：

```bash
# 只要将原装救砖底包 boot.img 放在同一目录下，直接运行即可：
sh repack_boot.sh

# 也支持指定任意路径：
sh repack_boot.sh /path/to/stock_boot.img /path/to/Image /path/to/final_boot.img
```
脚本将自动调用 64 位 `magiskboot`，在 1 秒内输出结构严谨对齐的 `final_lz4kd_boot.img`！

#### 2. 分步缝合 (SOP)

刷入方式：
* 在 TWRP 中切换为【安装镜像】-> 选择 `final_lz4kd_boot.img` -> 勾选【Boot】滑动刷入；
* 或在电脑 Fastboot 下直敲：`fastboot flash boot_a final_lz4kd_boot.img && fastboot reboot`。

---

### 七、 开机

#### 1. 刷入配套的magisk模块，开机自动切换zram压缩方案
开机后在终端执行：
```bash
cat /proc/version
或使用配套sh脚本测试
```

---

<a id="src-21"></a>
## 21. SUSFS 上游集成说明（上游参考）

> 来源：[`third_party/susfs4ksu/README.md`](../../third_party/susfs4ksu/README.md) · 7058 字节 · SHA256 `e5b8c8a2cdeefb99a075a863b9cb33236e33dd50a357caa85e0b3960d5047a57`
> 类别：上游参考 · 状态：上游参考（版本可能漂移）

### Introduction ##
- An addon root hiding kernel patches and userspace module for KernelSU.

- The userspace tool `ksu_susfs`, as well as the ksu module, require a susfs patched kernel to work.

### Warning #
- This is only experimental code, that said it can harm your system or cause performance hit, **YOU ARE !! W A R N E D !!** already

### Compatibility ##
- The susfs kernel patches may differ for different kernel version or even on the same kernel version, you may need to create your own patches for your kernel.

### Patch Instruction (For GKI Kernel only and building from official google artifacts) ##
**- Prerequisite -**
1. All susfs patches are mainly based on the **original official KernelSU (the one from weishu)**, since KernelSU updates frequently and susfs needs to sync up with it, so it is now suggested to just clone the KernelSU and susfs repo without tag/release tag. If the applied susfs patches fails on KernelSU, you need to rollback KernelSU version to a specific commit and apply the patches again.
2. Since v2.0.0, SUSFS does not rely on kernel features like KPROBES, KRETPROBES and HAVE_SYSCALL_TRACEPOINTS, which means it will patch all the sucompat code in KernelSU, fs/exec.c, fs/open.c, and fs/stat.c.
3. Do NOT apply custom manual hooks for sucompat unless you implement your own one instead of the susfs one.


**- Apply SUSFS patches -**
1. Make sure you follow the offical KSU guild here to clone and build the kernel with KSU: `https://kernelsu.org/guide/how-to-build.html`, the kernel root directory should be `$KERNEL_REPO/common`, you should run script to clone KernelSU in `$KERNEL_REPO`, **make sure you clone with a tag version.**
2. Clone this susfs branch with a **tag / release tag** or up to a commit message containing **"Bump version to vX.X.X"**, as they are more stable in general.
3. Run `cp ./kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch $KERNEL_REPO/KernelSU/`
4. Run `cp ./kernel_patches/50_add_susfs_in_kernel-<kernel_version>.patch $KERNEL_REPO/common/`
5. Run `cp ./kernel_patches/fs/* $KERNEL_REPO/common/fs/`
6. Run `cp ./kernel_patches/include/linux/* $KERNEL_REPO/common/include/linux/`
7. Run `cd $KERNEL_REPO/KernelSU` and then `patch -p1 < 10_enable_susfs_for_ksu.patch`
8. Run `cd $KERNEL_REPO/common` and then `patch -p1 < 50_add_susfs_in_kernel.patch`, **if there are failed patches, you may try to patch them manually by yourself.**
9. If you want to make your kernel support other KSU manager variant, you can add its own hash size and hash in `ksu_is_manager_apk()` function in `KernelSU/kernel/apk_sign.c`
10. Make sure again to have `CONFIG_KSU` and `CONFIG_KSU_SUSFS` enabled before building the kernel, some other SUSFS feature may be disabled by default, you may enable/disable them via `menuconfig`, `kernel defconfig`, or change the `default [y|n]` option under each `config KSU_SUSFS_` option in `$KernelSU_repo/kernel/Kconfig` if you build with a new defconfig every time.
11. For `gki kernel android14` or above, if you are building from google artifacts, it is necessary to delete the file `$KERNEL_REPO/common/android/abi_gki_protected_exports_aarch64` and `$KERNEL_REPO/common/android/abi_gki_protected_exports_x86_64`, otherwise some modules like WiFi will not work. Or you can just remove those files whenever they exist in your kernel repo.
12. If you want to flash the fresh built gki boot.img, then before you build the kernel, first you need to fix or hardcode the `local spl_date` in function `build_gki_boot_images()` in `$KERNEL_REPO/build/kernel/build_utils.sh` to match the current boot security patch level of your phone. Or you can just use magiskboot to unpack and repack the built kernel for your stock boot.img.
13. Build and flash the kernel.
14. For other building tips, please refer to the section **[Other Building Tips]** below.

### Build ksu_susfs userspace tool ##
1. Run `./build_ksu_susfs_tool.sh` to build the userspace tool `ksu_susfs`, and the arm64 and arm binary will be copied to `ksu_module_susfs/tools/` as well.
2. Now you can also push the compiled `ksu_susfs` tool to `/data/adb/ksu/bin/` so that you can run it directly in adb root shell or termux root shell, as well as in your own ksu modules.

### Build susfs4ksu module ##
- The ksu module here is just a demo to show how to use it.
- It will also copy the `ksu_susfs` tool to `/data/adb/ksu/bin/` as well when installing the module.

1. ksu_susfs tool can be run in any stage scripts, post-fs-data.sh, services.sh, boot-completed.sh according to your own need.
2. Run `./build_ksu_module.sh` to build the susfs KSU module.

### Usage of ksu_susfs and supported features ##
- Run `ksu_susfs` in root shell for detailed usages.
- See `$KernelSU_repo/kernel/Kconfig` for supported features after applying the susfs patches.

### Other Building Tips ##
- To only remove the `-dirty` string from kernel release string, open file `$KERNEL_ROOT/scripts/setlocalversion`, then look for all the lines that containing `printf '%s' -dirty`, and replace it with `printf '%s' ''`
- Alternatively, If you want to directly hardcode the whole kernel release string, then open file `$KERNEL_ROOT/scripts/setlocalversion`, look for the last line `echo "$res"`, and for example, replace it with `echo "-android13-01-gb123456789012-ab12345678"`
- To hardcode your kernel version string, open `$KERNEL_ROOT/scripts/mkcompile_h`, and look for line `UTS_VERSION="$(echo $UTS_VERSION $CONFIG_FLAGS $TIMESTAMP | cut -b -$UTS_LEN)"`, then for example, replace it with `UTS_VERSION="#1 SMP PREEMPT Mon Jan 1 18:00:00 UTC 2024"`. But for kernel 6.1+, you need to edit `${KERNEL_ROOT}/init/Makefile`, and look for line `build-timestamp = $(or $(KBUILD_BUILD_TIMESTAMP), $(build-timestamp-auto))`, replace it with your own timestamp, like `build-timestamp = "Wed Jan 30 12:00:00 UTC 2025"`
- To hardcode your kernel version string which can be seen from /proc/version, open `$KERNEL_ROOT/scripts/mkcompile_h`, then search for variable name `LINUX_COMPILE_BY` and `LINUX_COMPILE_HOST`, then for example, append `LINUX_COMPILE_BY=build-user` and `LINUX_COMPILE_HOST=build-host` after line `UTS_VERSION="$(echo $UTS_VERSION $CONFIG_FLAGS $TIMESTAMP | cut -b -$UTS_LEN)"`
- To spoof the `/proc/config.gz` with the stock config, 

   1. Make sure you are on the stock ROM and using stock kernel.
   2. Use adb shell or root shell to pull your stock `/proc/config.gz` from your device to PC.
   3. Decompress it using `gunzip` or whatever tools, then copy it to `$KERNEL_ROOT/arch/arm64/configs/stock_defconfig`
   4. Open file `$KERNEL_ROOT/kernel/Makefile`.
   5. Look for line `$(obj)/config_data: $(KCONFIG_CONFIG) FORCE`, and replace it with `$(obj)/config_data: arch/arm64/configs/stock_defconfig FORCE`

### Credits ##
- KernelSU: https://github.com/tiann/KernelSU
- KernelSU fork: https://github.com/5ec1cff/KernelSU
- @Kartatz: for ideas and original commit from https://github.com/Dominium-Apum/kernel_xiaomi_chime/pull/1/commits/74f8d4ecacd343432bb8137b7e7fbe3fd9fef189

### Telegram ##
- @simonpunk

---

## 附录 A. 生成器与维护

- 脚本：[`dash/scripts/collect-notes.py`](../../dash/scripts/collect-notes.py)
- 清单：脚本顶部的 `SOURCES`（按顺序合并；新增笔记请同时更新 README 和本清单）。
- 幂等：同一组源文件内容/时间不变时，重复运行输出相同；`--check` 只在输出过期时失败。
- 安全：可用 `DASH_SECRET_GUARD` 环境变量指定敏感串做拒合检查；不会读取设备、不会写源文件。
