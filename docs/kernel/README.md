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
configs/features.fragment     功能开关唯一权威输入(configure.sh 合并进 .config)
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
make source     # 浅克隆/更新 AOSP 到 2026-10_r4（6.6.143）
make patches    # 重置源码、接入 BakaSU、按 series 打补丁
make config     # stock.config + 功能开关
make build      # 最终生产构建：LTO Full（仅明确要产出生产级内核时运行）
make config FAST=1 build  # 默认开发/验证：NoLTO；产物未经 finalize，不可刷机
make brutal     # 外部 tcp-brutal v2.0.1 模块（需要先 build）
make boot       # 从 stock boot_b 继承生成 boot.img
bash scripts/finalize.sh  # KCFI + 638 模块 + boot 校验，写 SHA256SUMS
make notes                 # 合并仓库开发笔记为 docs/kernel/DEV_NOTES.md（给 LLM 的避坑包）
```

> **6.6.143 补丁序列（2026-11-21 起按特性拆分）**：`patches/` 下是按功能
> 特性分目录的补丁系列（bakasu-susfs / vendor-ko-compat / vendor-hooks-os4
> / memfd-shim / lz4kd-zram / f2fs / erofs / dash-misc / sched-eevdf / bbrv3 /
> arm64-perf / power-mm / ntsync / adios / bbg），`series` 是唯一应用顺序；
> 文件级拆分（每文件只属于一个补丁），归属表在
> `dash/scripts/split-patches.py`。旧的 6.6.118 拆分系列和 6.6.143 整树
> squash 已从仓库删除（git 历史保留）。已在固定 r4 (`e6c23f621`) 干净树
> 验证 28 个补丁/142 个文件与 SUSFS override 全量重放，零 warning/error；
> `make patches` 会重置源码再重放，执行前确认没有补丁之外的未固化改动；
> 改 `src/aosp/common` 后用 `make gen-patches` 再生成，不要手改补丁文件。

产物在 `out/artifacts/`，构建日志在 `out/dash/build.log`。非默认
`DEVICE=<name>` 验证构建只写 `out/<name>/`，不会污染共享 artifacts；确需将
变体晋升为交付产物时显式设 `PUBLISH_ARTIFACTS=1`。

> **构建策略（2026-11-21 起）**：日常编译、补丁重放、CRC/KMI 与静态门禁
> 一律使用 `FAST=1`（NoLTO）。默认的 LTO Full 构建**不得自行运行**：只有机主
> 针对本次构建明确说“授权跑 Full LTO”才可执行，“产出生产级内核/最终产物”
> 不等于授权。Full LTO 在 15 GiB 主机上单次链接耗时很长且大量 swap，不作为
> 常规验证门禁；NoLTO 不改变源码级 genksyms CRC。

## AutoFDO profile 优化

`CONFIG_AUTOFDO_CLANG=y` 已内建(arch/Kconfig;不提供 profile 时仅多出
fs-discriminator 元数据,行为不变)。生产构建**默认直接使用 ACK 仓库自带的
预制 profile**,无需先采集:

- profile:`android/gki/aarch64/afdo/kernel.afdo`(ACK 6.6.142 采集,约 4.0 MiB)
- SHA256 钉死在 `dash/versions.env` 的 `ACK_AUTOFDO_PROFILE_SHA256`;
  `lib.sh::verify_autofdo_profile` 在 configure/build 前校验,不匹配即失败
- `build.sh` / `build-tcp-brutal.sh` 自动把 `CLANG_AUTOFDO_PROFILE` 传给
  make;`scripts/Makefile.autofdo` 为每个 TU 注入 `-fprofile-sample-use`

构建级实证(2026-11-21,NoLTO):`dash/out/features-mlgo-afdo` 全量构建 exit 0,
6258 个 `.cmd` 中 3188 个带 `-fprofile-sample-use=.../kernel.afdo`、3230 个带
`regalloc-enable-advisor`;`Image` 38,877,696 B、`Image.lz4` 18,366,486 B。
**未刷机、未做性能 A/B。**

> **LTO 说明**:ACK `scripts/Makefile.autofdo` 只在 ThinLTO 分支给 LLD 传
> `--lto-sample-profile`,Full LTO 分支不传;但 profile 权重已作为 `!prof`
> 元数据写入每个 TU 的 bitcode,Full LTO 在编译期即应用,链接期不传该参数
> 不构成功能缺口(2026-11-21 以最小 Full LTO 对照实验验证)。Full LTO 全量
> 构建已于 2026-11-22 由 CI 通过（run 44923883114），Release
> `dash-6.6.143-prod`；尚未刷机验证。

`CLANG_AUTOFDO_PROFILE=/path/to/other.afdo bash dash/scripts/build.sh` 可覆盖为
自定义 profile;profile 与源码版本强相关,AOSP tag/补丁大改后应重新采集。

### 可选:自行采集 profile(实验路线,未在 dash 验证)

> **dash 实机限制(2026-11-21)**:当前运行内核只暴露
> `arm_dsu_0`/`armv8_pmuv3`/`armv9_cortex_a720`/`armv9_cortex_x4`,无
> `arm_spe_*` 或 `cs_etm`;stock 同时关闭 `CONFIG_ARM_SPE_PMU` 与
> `CONFIG_CORESIGHT`。arm64 AutoFDO 并非只能用 SPE,也支持 ETM/ETE。MT6991
> 厂商 DTS 已含 8×ETE 与 funnel→ETF→ETR 完整 CoreSight 拓扑,因此优先在
> **单独实验构建**中启用 `CORESIGHT`、`CORESIGHT_SOURCE_ETM4X`、
> `CORESIGHT_LINK_AND_SINK_TMC` 后实机验证,无需先改 DT。下列 ETE/SPE 命令均
> 仅为流程候选,尚未在 dash 验证。

1. **采集**(未来启用对应 PMU 的实验内核,需 root;优先 ETE):

   ```bash
   # ETE/ETM:确认 cs_etm 和 ETR sink 后,用内核内建的 AutoFDO strobing 配置:
   adb shell su -c 'ls /sys/bus/event_source/devices/cs_etm/events/autofdo'
   adb shell su -c 'perf record -e cs_etm/autofdo/ -a \
       -o /data/local/tmp/etm.data -- sleep 600'
   adb pull /data/local/tmp/etm.data .

   # 仅当 ETE 路线不可用且已确认 PMSVer/EL2/PPI 后才调查 SPE:
   adb shell su -c 'ls /sys/devices | grep -i spe'
   adb shell su -c 'perf record -e arm_spe_0/load_filter=1,store_filter=1,ts_enable=1 \
       -a -o /data/local/tmp/spe.data -- sleep 600'
   ```

2. **转换**(主机):ETE trace 先由支持 CoreSight/OpenCSD 的 perf 解码/注入分支样本,
   再用 LLVM AutoFDO 工具转换;SPE 可由支持 SPE 的 `create_llvm_prof` 转换。工具
   版本与参数仍需在选定路线后固定,以下都不是已验证 CLI:

   ```bash
   perf inject --itrace --strip -i etm.data -o etm.inject.data
   # 再以 llvm-profgen/create_llvm_prof 将 trace+vmlinux 转为 afdo.prof
   create_llvm_prof --format=extbinary --spe=/path/spe.data \
       --binary=out/artifacts/vmlinux --out=afdo.prof
   ```

3. **重编**:用刚采集的 profile 覆盖默认路径:

   ```bash
   CLANG_AUTOFDO_PROFILE="$PWD/afdo.prof" bash dash/scripts/build.sh
   ```

   `scripts/Makefile.autofdo` 会注入 `-fprofile-sample-use`;ThinLTO 链接期
   也会挂 `--lto-sample-profile`。自采 profile 不参与哈希校验,使用前应确认
   采集内核与待编译源码版本足够接近。

4. 对照 `out/dash/build.log` 无 profile 缺失告警;产物按 `finalize.sh`
   正常校验。

## CI（GitHub Actions）

> 所有工作流**只保留手动 dispatch 触发**（push/PR/schedule 自动触发已按
> 仓库主人的要求关闭）；跑到 Actions 页手动触发。

- [`.github/workflows/ci.yml`](../../../.github/workflows/ci.yml)：轻量检查——
  `shellcheck -S warning`、补丁序列校验（浅克隆 pinned AOSP + `make patches`）。
  DEV_NOTES 的刷新/校验（`make notes`、`collect-notes.py --check`）只在本地
  做，不在 CI 里跑。
- [`.github/workflows/kernel-build.yml`](../../../.github/workflows/kernel-build.yml)：
  手动 dispatch 全量构建（工具链 cache 以 `CLANG_VERSION` 为 key）。默认
  `fast=false`：Full LTO + MLGO + ACK AutoFDO + A720 tune；`fast=true` 是
  NoLTO 测试路径，不发布 Release。构建前做内存扩展（16G swapfile + 8G
  zram/zstd + zswap），方案经 `storage-ram-test` 实测；磁盘清理 action 不
  采用——runner 基线约 87GB 空闲。job timeout 360 分钟，Full LTO 在 4 核
  runner 上可能接近上限。artifact 上传（`if: always()`）包含：内核产物
  （Image/Image.lz4/System.map/vmlinux）、`build.log.gz`、构建实际生效的
  `final-config`、补丁系列+configs+versions.env+关键脚本的
  `build-inputs.tar.gz`、provenance `build-info.txt`；`Image.lz4` 超过
  64MiB boot 可刷入预算（67098176 B）时 workflow fail 但 artifact 保留。
  非 fast 且 `release=true` 时，额外打包 `dash_art_tune` KSU 模块和
  AnyKernel3 zip（当前 `Image` + 模块），连同 Image/Image.lz4/SHA256SUMS
  发布到 `tag` 指定的 GitHub Release。
  boot 打包和 `finalize.sh` 需要 gitignored 的 stock `boot_b.img` 与模块
  manifest，仍只在本机执行。
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
- [FEATURES_SURVEY.md](FEATURES_SURVEY.md)：WildKernels/GKID 特性调查，
  实现可信度分级（官方/厂商/作者自研/来源不明）、与 dash 对照与决策台账
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

