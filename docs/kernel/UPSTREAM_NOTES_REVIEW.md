# 上游/参考仓库工作笔记核对（2026-10-30）

范围：先读导航中每个带工作笔记/AGENTS 的仓库，再补读一批小米 MTK/OS3/OS4
内核构建仓库的 README、build guide、context/perf 笔记。目的不是照搬，而是找
**我们文档/实现中需要纠正或可优化**的点。

## 1. 已读的仓库内笔记

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

## 2. 补读的小米 MTK/OS3/OS4 仓库

优先热度 + 小米 + 可能 MTK + OS3/OS4；没有工作笔记的仓库只做交叉验证，不照搬。

### 2.1 [Re-s/Mi15-Droidspaces-Kernel](https://github.com/Re-s/Mi15-Droidspaces-Kernel)

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

### 2.2 [omajili-manbu/Xiaomi_Rodin_Kernel_Enhance](https://github.com/omajili-manbu/Xiaomi_Rodin_Kernel_Enhance)

- 设备：Redmi Turbo 4 / POCO X7 Pro（rodin，MT6899，HyperOS 3/Android 16）。
- 有价值笔记：`BUILD-GUIDE.md`、README。
- 可借鉴：
  - `.config` 必须从 `gki_defconfig` 生成（其 BSP 树经验）；我们用 stock.config
    + olddefconfig，已实测，不能直接套用，但其“不要混 defconfig”原则一致。
  - `Image.lz4` 必须是 **legacy LZ4**：magic `0221 4c18`，不是标准帧
    `0422 4d18`；我们已把该检查加入 `make-boot.sh`。
  - 性能选项：ThinLTO、AutoFDO、BBRv3、ZSTD 1.5.7、Cortex-A725 编译优化。
    ThinLTO 已应用并实机启动；AutoFDO 因缺少 profile 未启用；BBRv3/ZSTD
    等仍未应用；见 §4。
  - 防格机 Baseband-guard LSM、vendor 模块兼容修复；我们已有 vendor-ko 兼容，
    BBG 不是 stock 特性，未引入。
- 其 `dash-w-oss` 分支没有可用的额外笔记（README 是 AOSP 通用补丁指南）。

### 2.3 [ZxAlif-ID/Flavenz-Kernel-Peridot](https://github.com/ZxAlif-ID/Flavenz-Kernel-Peridot)

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

### 2.4 [2824799/droidspaces-xiaomi-17-kernel](https://github.com/2824799/droidspaces-xiaomi-17-kernel)

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

### 2.5 其他

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

## 3. 已应用的纠正/优化

1. **KMI 表述纠正**：文档从“KMI `android15-6.6`”改为“GKI 分支 `android15-6.6`，
   KMI 字符串 `android15-8`”。依据：我们的 stock `uname -r` 与 Mi15 研究一致。
2. **LZ4 legacy 检查**：`make-boot.sh` 在打包前检查 `Image.lz4` magic 必须是
   `0221 4c18`；当前产物通过。这是 Rodin 构建笔记中很有价值的一条。
3. **UFS monitor 路径纠正**：stock 内核/模块字符串只有 `monitor`，当前
   `/monitor/monitor_enable` 与模块一致；`/ufs_monitor` 只在 vendor_file_contexts，
   不再列为已确认缺口。
4. **7 个 export-only hook** 已补调用点（0008/0009），不再悬空。
5. **F2FS fault report** 增加 task-context 异步上报；同步路径保留。

## 4. 建议但未应用的优化（含风险）

| 优化 | 收益 | 不应用的原因 |
|---|---|---|
| 升级到 6.6.143（2026-10_r2 tag） | 补 2026-02..10 LTS/安全修复 | **已应用并启动**；KMI 仍 android15-8；仍需用新基线复跑完整 stock parity |
| ThinLTO / AutoFDO | 3-5% 级内核路径优化 | ThinLTO **已开启并实机启动**（`-flto=thin`，pid.o 为 bitcode）；AutoFDO 未启用，缺 profile；仍缺 A/B |
| BBRv3 / ZSTD 1.5.7 / zstd zram 默认 | 网络/压缩吞吐 | 不是 stock 默认（stock zram 运行 lz4）；会改变行为，需 A/B |
| `KBUILD_BUILD_TIMESTAMP` 同步 ROM | 降低完整性检测/时间漂移异常 | 改变 `/proc/version` 和可复现构建；是否追求 stealth 需设备所有者决定 |
| dash-droidspaces `pid_max` clamp 32768 | 规避 0x8000 掩码类 bug | **已应用并实机验证**：pid_max=32768，写 40000/100000 均失败；不是 stock 行为 |
| DroidSpaces SYSVIPC kABI 6/7/8 + namespace 配置 | 容器支持 | 不是 stock 配置；会改变 kABI/启动行为，应做独立变体 |
| Baseband-guard LSM | 防格机 | 额外 LSM，非 stock；需要白名单和设备验证 |
| SUSFS README 删除 protected exports | 避免 WiFi 模块被拦 | 我们已用 `CONFIG_VENDOR_KO_COMPAT` 绕过；删除会降低/改变 ABI 保护，不必要 |

## 5. 已验证无需改动

- stock 基线 `android15-6.6-2026-01_r1` == 6.6.118；当前自编已同步到
  `2026-10_r2`（6.6.143），clang r614150、4K、ThinLTO、CFI、boot v4 已在
  实机验证。
- stock zram 默认算法是 `lz4`；lz4kd 通过 crypto API 可被 stock zram 选中，
  不需要替换 zram 模块；ExtM 内存扩展保留，见
  [ZRAM_EXTM.md](ZRAM_EXTM.md)。
- `SUSFS`/内建 KSU 的集成方式与 BakaSU/上游说明一致；SUSFS 版本 **v2.4.0**（pin `f98f082`；§1 快照曾误记 2.3.0，见 [STATUS.md](../STATUS.md)）。
- 我们的 boot 封装是完整 64MB 继承 + OEM vbmeta/footer，不使用 AK3；Flavenz 的
  slot/bootconfig 修补不适用。

## 6. 下一步优先级

1. **安全/LTS**：基线已升到 2026-10_r2（6.6.143）；仍需按新基线复核
   `ro.build.version.security_patch` 与 token 差异，并重跑完整 stock parity。
2. **性能 A/B**：ThinLTO 已实测可启动，但尚无收益/功耗数据；AutoFDO 需先采集
   profile；BBRv3/ZSTD 仍待 A/B。
3. **DroidSpaces**：若确实需要容器，单独变体加 SYSVIPC kABI 6/7/8 + namespace
   配置，不混入 stock parity。
4. **hybrid/fastdiscard/UFS core**：继续按 [OPEN_ISSUES.md](OPEN_ISSUES.md) §2 表格（E1–E3 行）
   的证据路线推进。

## 7. 全部来源仓库总清单（截至 2026-11-28；覆盖上文各节及本仓库所有调查）

> §1–§6 是 2026-10-30 快照，仅覆盖当时读过笔记的仓库。本节补充此后以及本轮
> （2026-11-28 小米特性调查 + 最后一轮全关键词搜索）读到/参考/取用过的**全部**外部
> 来源。用途分类：**子模块**=已纳入 `third_party/`（pin 见 `dash/versions.env`、表见
> [NAVIGATION.md](../project/NAVIGATION.md)）；**API 取用**=按需 API 取单文件，
> 未入库；**阅读参考**=读过源码/笔记用于判断或交叉验证。§7.5 为 2026-11-28
> 最后一轮搜索新增。

### 7.1 已纳入子模块的仓库（本地完整副本）

- `Baka-SU/BakaSU`（`BakaSU/`）— KSU 内核源码
- `SukiSU-Ultra/SukiSU_patch`（`third_party/sukisu-patch`）— lz4k/lz4kd 参考
- `simonpunk/susfs4ksu`（GitLab，`third_party/susfs4ksu`）— SUSFS（v2.4.0）
- `lakitu12/kernel_dash_droidspaces`（`third_party/dash-droidspaces`）— dash OS4 hooks/boot 笔记
- `2108282/hyperos-lz4kd`（`third_party/hyperos-lz4kd`）— LZ4KD/AVB/CFI 参考
- `Content-Creation-Club/android_kernel_xiaomi_dash`（主内核，LineageOS 6.6.144 方向）、`Content-Creation-Club/android_kernel_xiaomi_dash_build`、`Content-Creation-Club/android_kernel_xiaomi_dash_device_modules`（DTS/触摸/热管理/millet/mi_memory/UFS 重实现）、`Content-Creation-Club/android_kernel_xiaomi_dash_bazel_mgk_rules`、`Content-Creation-Club/android_kernel_xiaomi_dash_mtk_modules`（4 个 `third_party/cc-dash-*` + 主内核）— 构建脚本/设备模块/MTK 模块；注意 2026-11-21 起私有化 404
- `HyNetworks/tcp-brutal`（`third_party/tcp-brutal`）— TCP Brutal
- `maxsteeel/nomount`（`third_party/nomount`）— NoMount
- `klarnet2009/dada-closed-modules`（`third_party/xiaomi-dada-closed-modules`）— Xiaomi 15/SM8750 闭源模块逆向重建（146 模块，等价性核验方法）
- `donothavename/opt_gki_kernel_android13-5.15`（`third_party/xiaomi-opt_gki_kernel_android13-5.15`）— OS4 内存/调度 `sew_*` 移植
- `NikoRurQwQRuaaMeow/chirunoneko_gki_android13-5.15_kernel_module_opensource`（`third_party/xiaomi-chirunoneko-gki-5.15-modules`）— 小米特性 Kconfig 清单（源码被挖空）
- `Project-Hikari-Liella/MTK_kernel_device_modules-50da8b3c19a331c676dcaa1334fa3b49e4b1a531`（`third_party/mtk-device-modules-hikari`）— **dash 实际厂商 zram/内存后端源码（XRING zgroup/mctrl/xswapd/smart_cache）+ `kernel/configs/dash.config`**
- `hushangda/android_kernel_xiaomi_sm8350_venus`（`third_party/xiaomi-venus-memcg`）— 小米 memcg 策略 + 官方 `xiaomi-memcg.rst` 协议文档

### 7.2 按需 API 取用（未入库，pin 见 `dash/versions.env` 末段）

- `android-kernels/xiaomi-bixi-v-oss`（MiCode 6.6.56 开源镜像，~30 GB）— **MFZ / `mi_wmark` 权威来源**，取 `drivers/block/zram/zram_drv.c`、`drivers/staging/mi-perf/mi_wmark/`
- `OneFeiFan/gki-kernel-5.10-xiaomi-pad6max`（~200 MB）— `patches/xiaomi/0047-zram-xiaomi-extm.patch`、`0048-zram-xiaomi-memory-freeze.patch` + `docs/features.md`、`docs/notes/extm-research.md`
- `xiaomi-dash-dev/redmi_dash_dump` — 本机 stock `ikconfig`（用于确认 `MI_MEMORY_FREEZE=n` + XRING 配置）

### 7.3 阅读/交叉验证参考（读过 README/笔记/源码/配置用于判断）

- 特性调查来源（[FEATURES_SURVEY.md](FEATURES_SURVEY.md)）：`WildKernels/GKI_KernelSU_SUSFS`、`WildKernels/OnePlus_KernelSU_SUSFS`、`WildPlusKernel/kernel_patches`、`ahmed-alnassif/GKID-Kernels`、`NEESCHAL-3/EVONIX-Kernel`、`zen-kernel/zen-kernel`
- 上游笔记核对（§2，2026-10-30）：`Re-s/Mi15-Droidspaces-Kernel`、`omajili-manbu/Xiaomi_Rodin_Kernel_Enhance`、`ZxAlif-ID/Flavenz-Kernel-Peridot`、`2824799/droidspaces-xiaomi-17-kernel`、`XagaForge/android_kernel_xiaomi_mt6895`、`JuanArton/xiaomi_peridot_kernel`、`degas-developers/android_device_xiaomi_degas-kernel`、`xiaomi-mediatek-devs/android_kernel_xiaomi_mt6877`
- 缺口调研（[GAP_RESEARCH.md](../project/GAP_RESEARCH.md)）：`MiCode/Xiaomi_Kernel_OpenSource`（`mist-w-oss`/`dada-v-oss`/`dash-w-oss`）、`MiCode/MTK_kernel_device_modules`（`dash-w-oss` UFS 37 文件）、`MiCode/MTK_kernel_modules`、`android-kernels/xiaomi-dash-w-oss`、`Content-Creation-Club/android_kernel_xiaomi_dash`、`donyanchen/android_kernel_xiaomi_sm8850`、`hgn284/xiaomi_17pro_max_sm8850`、`Apr-YT/gg-rwproc33-driver`、`wfqefwqf/share-poc-XRing-O1`、`YuKongA/ghostlock-app`、`oss-dash/poco_dash_dump`、`xiaomi-mt6991/poco_dash_dump`、`HexaUnion/redmi_dash_dump`
- 运行/生态：[Asterisk4Magisk/AsteriskMETA](MIHOMO_ANDROID.md)（mihomo 客户端）；`tiann/KernelSU`、`5ec1cff/KernelSU`、`Dominium-Apum/kernel_xiaomi_chime`（DEV_NOTES 内附带的第三方 README 署名，非我们主动研究）
- 自建：[NuoFang6/dash-kernel](https://github.com/NuoFang6/dash-kernel)（本仓库 CI/Release）

### 7.4 已确认无价值 / 仅一次性查证

- `piano-LAB/android_kernel_xiaomi_sm8750-modules`、`lrqtech/android_kernel_xiaomi_warsaw_lineage24`：本轮搜索命中但无所需特性源码（仅 extmem 无关文件），未采用。
- `NikoRurQwQRuaaMeow` 名下其余 30+ 仓库（ROM 移植/SM8250 老内核/Action）与本机 MT6991/6.6 无关，未展开。

### 7.5 2026-11-28 最后一轮全关键词搜索新增来源

> 7 轮关键词族搜索（`gh search code`/`repos`/`commits`/`issues`，详见
> [FEATURES_SURVEY.md §2026-11-28 最后一轮](FEATURES_SURVEY.md)）。结论：**XRING
> 源码面无遗漏，无需新增子模块**；新增以下**只读/取码**来源。

**取码（唯一公开的 XRING 补全源码）**

- `Pzqqt/android_kernel_xiaomi_marble`（Melt Kernel，Redmi Note 12 Turbo / MT6878）—
  **唯一同时带 XRING `lib/lz4p/`（12 文件，含 `lz4p_encode.S`/`lz4p_decode.S`）与
  `drivers/staging/kshrink_slabd/` 完整源码的公开树**；`lib/lz4p/lz4p.h` 头注明
  `X-Ring technologies Inc.`。按需 `gh api` 取单文件，不整仓克隆（2.4 GB）。
- `ShriHari33/mt6991-ufs-gear-lane`（MT6991 UFS gear/lane 实机工程，4.7 MB）—
  `power_mode` debugfs + W-LUN 唤醒修复（Linux 5.14 起 W-LUN 独立 resume）+ G5 时钟分析；
  `current_vs_proposed/proposed/000{1,2,3}*.patch` 附源码副本与 PDF。

**交叉验证（证明 XRING 是小米专有）**

- `OnePlusOSS/android_kernel_oneplus_mt6991`（`oneplus/mt6991_b_16.0.0_oneplus_ace5_ultra`，
  6.6.118，2.3 GB）与 `oppo-source/android_kernel_oppo_mt6991`（6.6.30，2.2 GB）—
  `drivers/block/zram` 均为纯 AOSP（无 XRING/lz4p）。
- MiCode `Xiaomi_Kernel_OpenSource` 的 `yili-w-oss`（6.12.38）/`piano-w-oss`（6.6.57）—
  zram 均为上游形态，无 XRING。旁证：MiCode issue **#41194**（2026-11-21）仍在请求
  公开 `turner-w-oss`（K Pad，MT6991/OS4），**尚未发布**。
- 字节核验：`third_party/mtk-device-modules-hikari/drivers/ufs/ufs-mediatek.c` 与
  MiCode `MTK_kernel_device_modules` `dash-w-oss` 分支 **`diff -q` 完全一致** →
  我们的 XRING/UFS 源码是官方 stock，非逆向重实现。

**读思路（非 dash 适用）**

- `bocchi810/mt6991-kernel-ci` — OnePlus Ace 5 Ultra MT6991 6.6.118 CI；
  `hybridswap_lpc` NULL-deref 的 kprobe 守卫思路（OPLUS hybridswap 后端，dash 不适用）。
- `dongyanchen-dev/android_kernel_xiaomi_sm8850` — 小米 17/K90 Pro Max GKI 构建器，
  含约 60 个 f2fs/ufs/fscrypt/erofs/mglru 安全 backport 补丁（SM8850 6.12，非 dash）。
- `liudaoziwa/mainline-mt6991`（Linux 7.3 主线 MT6991）、
  `localhosts-A/UniXNU-MT6991-Common`（MT6991 硬件输入 + dtsi，XNU 方向）、
  `SHuiTU68/android_kernel_oplus_common`（OPLUS f2fs `DEDUP`/`COMPRESS_FIXED_OUTPUT`/
  `lz4armv8`，6.6.114）— 均观察，暂不使用。
