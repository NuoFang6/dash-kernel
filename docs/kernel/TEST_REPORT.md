# dash GKI 6.6 测试报告

> 本文件是**证据日志**：按日期追加实测、构建和失败复盘，不维护“当前状态”。
> 当前版本、哈希和结论见 [STATUS.md](../STATUS.md)；缺口见
> [OPEN_ISSUES.md](OPEN_ISSUES.md)。

测试日期：2026-10-29 起；2026-10-30 更新到 6.6.143 #8。当前结论分为：

- **6.6.143 #8（2026-10-30 晚）**：boot_b `0dc871a5…`，KCFI 13/13，
  638 stock 模块 `hard_missing=0`，586 个模块加载；mihomo TUN+GSO/
  auto-route/auto-redirect 与 tcp-brutal 实机通过，MPTCP 因启动失败关闭；
  详见 §18。
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

## 1. 环境与输入

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

## 2. 补丁应用

从 clean tag 执行：

```bash
bash scripts/apply-patches.sh
```

结果：16 个补丁全部按 `patches/series` 顺序 `git apply --index` 成功，无 reject、
无 offset 失败。应用后源码 HEAD 仍为 `f9c84f40b6ba6152b6f51daba0193c9564af4172`，
变更均为工作树/索引补丁。

## 3. 构建

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

## 4. 厂商模块静态兼容

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

## 5. KCFI 原型

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

## 6. boot 镜像

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


## 7. 产物校验和

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

## 8. 真机运行验证

最终镜像启动后的实测（全部只读采集；F2FS 写入仅使用
`/data/local/tmp` 临时文件并删除）：

### 8.1 内核、root 与模块

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

### 8.2 node_cache 与 QoS 数值

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

### 8.3 F2FS / EROFS 与数据校验

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


## 9. 实机启动与 AVB 踩坑总结

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

### 9.1 当前分区状态与 init_boot 差异

> 2026-10-30 晚更新：`init_boot_a/b` 已还原为 OS4.0.3.0 官方镜像
> （sha256 `3d2062ae…`）。下表是还原前 00:11 的历史快照，保留作对照。

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

## 10. dash-droidspaces 上游检查（2026-10-29）

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

## 11. Stock parity 修复（2026-10-30）

### 11.1 已补齐

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

### 11.2 本次实机验证

- 构建 #29，`boot_b` SHA256：
  `a28344f9296fb9796b2c8dc231812c59aa76770d069158897d1305dc55ab7cac`。
- 585 个模块（586 包括 `lsmod` 表头）；`fault_report`、`node_cache`、
  `os_cpu_qi`、`vip_sched` 等加载正常；dmesg 无 KCFI/未知符号/panic。
- `persist.sys.stability.fault_report=true` 仍在；`/proc/fault_report` 内容为
  1。`/dev/sys/fs/by-name/userdata/fault_report_enable` 这个 F2FS sysfs 节点仍
  不存在，stock init 对它的写入仍失败；`/proc/fault_report` 的功能已恢复。
- F2FS 数据写入测试只使用 `/data/local/tmp` 临时文件并已删除；未做 fsck、
  断电、压力或故障注入。

### 11.3 仍未补齐

- `hybrid=1` 仍 `-EOPNOTSUPP`；EROFS iostat 已 per-CPU，但仍是单 aggregate
  bucket，不是 stock 的 10/5 多桶布局。
- SCSI fastdiscard、UFS 官方 37 文件源仍未接入。
- 仍未做长时压力、suspend/resume、fsck/power-loss、性能/功耗 A/B。

## 12. F2FS lock / priority / VIP 实机验证（2026-10-30）

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


## 13. stock core tracepoint / dynamic task_struct（2026-10-30，构建 #29）

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

## 14. zram ExtM 内存扩展与 lz4kd（2026-10-30，实机 #4）

- 故障：为 lz4kd 曾 rmmod vendor zram 并 insmod 自编 zram.ko；自编模块只有
  AOSP writeback，没有小米 ExtM 的 `backing_dev`/`xswapd`/zgroup/mctrl/
  smart_cache，导致内存扩展失效。
- 恢复：回到 vendor_boot 自带的 ExtM 版 zram.ko，重新执行
  `/system_ext/xbin/system_perf_init`；`backing_dev=/dev/block/dm-71`，
  `xswapd0` 正常运行。
- lz4kd 不需要替换 zram：本内核把 lz4kd 注册为 crypto `compression`
  （`lz4kd-generic`），stock zram 的 zcomp 走 crypto API，直接
  `echo lz4kd > /sys/block/zram0/comp_algorithm` 成功；重启后
  `comp_algorithm` 为 `[lz4kd]`，`/proc/crypto` refcnt=9。
- 重启后完整链路：11.6s ExtM 绑定 dm-71、16 GiB swap（priority -2）；
  35.9s Scene 重置 zram、36.1s 恢复 dm-71、priority 0；xswapd0 存活。
- 回写验证：`echo all > idle; echo idle > writeback` →
  `ExtM: Flush finished. Mode 2, flush 497 pages`，`bd_stat=497 0 497 ...`，
  无 lz4kd 压缩/解压错误。
- 细节和恢复命令：[ZRAM_EXTM.md](ZRAM_EXTM.md)。

## 15. AOSP 6.6.143 + ThinLTO + pid_max clamp（2026-10-30，实机 #3）

- 源码：AOSP `android15-6.6-2026-10_r2`，commit `bf768be0`，SUBLEVEL=143；
  已确认这是当前 `android15-6.6` 最新 tag（r2）。
- 工具链：clang r614150 / LLD 23.0.1（当前 main-kernel 最新预编译），
  `HOSTCC=clang`、`LD=ld.lld`，构建 0 error / 0 warning。`versions.env`
  的 `CLANG_PREBUILT_BRANCH` 已修正为 `main-kernel`。
- ThinLTO：`CONFIG_LTO_CLANG_THIN=y`；`kernel/pid.o` 为 LLVM IR bitcode，
  `.pid.o.cmd` 含 `-flto=thin`；Image 38,316,544 B。AutoFDO 未启用
  （`# CONFIG_AUTOFDO_CLANG is not set`，缺少 profile，按约定跳过）。
  本次是在已有中间产物上完成 ThinLTO 链接/BTF，未单独记录 clean-build 耗时。
- pid_max clamp：`pid_max=32768`，`echo 100000 > /proc/sys/kernel/pid_max`
  与 `echo 40000` 均失败并保持 32768；dmesg 为
  `pid_max: default: 32768 minimum: 301`。该钳制来自 dash-droidspaces
  pid-max-clamp，用于规避 0x8000 PID 掩码 bug。
- core tracepoint：6.6.143 同步后曾丢失 #29 的 2 个 LZ4 事件，本次已恢复
  `include/trace/events/lz4.h` 和 EROFS 解压调用点。最终 System.map 中
  stock 的 1860 个 `__traceiter_*` 全部存在，另含 46 个 6.6.143 上游新增
  （合计 1906，missing=0）。实机 drop_caches 后读 APK 触发到成对事件：
  `inputsize=4096 outputsize=5613 ret=5613 bypass=0`。
- Zram ExtM：开机约 36 s 后 Scene 选中 `[lz4kd]`，
  `backing_dev=/dev/block/dm-71`，`xswapd0` 存活，swap 16 GiB priority 0；
  `writeback` 实测成功。
- 兼容性：KCFI 13/13；638 个 stock 模块 `hard_missing=0 weak_missing=0`；
  实机加载 586 个模块，`node_cache`/`zram`/`zsmalloc` 正常；KSU root 正常。
- 产物：Image `193908f7…`，Image.lz4 `cffe2e55…`，boot.img
  `5d4e1ab1…`；`boot_b` 已写入并与产物 hash 一致；可用
  `handoff/boot-6.6.143-4/boot.img` 回退到 LTO 前版本。

## 16. 6.6.143 补丁序列重生成（2026-10-30，离线）

- 当前 `patches/series` 改为单个
  `0000-6.6.143-dash-integration.patch`（84 个文件，6138 insertions /
  24 deletions），旧的 6.6.118 拆分系列和 vendor-hooks 移入
  `patches/legacy-6.6.118/` 仅作参考。
- 采用整树 squash 的原因：BakaSU/SUSFS/F2FS/EROFS/vendor-hook 的改动在
  VFS/security/core 文件交错，按旧系列拆分会产生不可独立应用的 hunk。
- 验证：在干净 AOSP `bf768be0` worktree 上执行
  `git apply --index 0000-6.6.143-dash-integration.patch`，再安装
  `patches/susfs/*`；补丁的 84 个文件加 3 个 SUSFS 文件共 87 个文件与当前
  构建工作树 sha256 全部一致，`git apply` 无 warning。
- 未重新从 clean 树跑整树编译；当前 Image 与补丁源码只差 3 个文件的 EOF
  空行清理，不含逻辑差异。`make patches` 现在可以从 bf768 重放，不再回退
  到 6.6.118。

## 17. init_boot 还原为 OS4 官方（2026-10-30，A/B 双槽）

- 还原前实测：`init_boot_a` = `6f8638fc…`（KernelSU patched 20261026），
  `init_boot_b` = `5bfcf159…`（KernelSU patched 20261028）；两者都**不是**
  官方 stock。
- 从 `/home/nuofang/t5m/os4_payload/payload.bin` 提取分区 `init_boot`，
  得到 8,388,608 B，sha256 `3d2062ae64992885cb4cfba19bac2699d1e07d7b7df91a8f0a770a493622b70a`；
  与 `/home/nuofang/t5m/os4_boot/init_boot.img` 一致，带 AVB footer。
- 用 fastboot 将同一官方镜像写入 `init_boot_a` 和 `init_boot_b`；重启后
  两槽 sha256 均为 `3d2062ae…`，`sys.boot_completed=1`，内核仍为
  `6.6.143-4k #3`。
- 还原后回归：内置 KSU root 正常（`uid=0 context=u:r:ksu:s0`）；
  `comp_algorithm` 在 Scene 启动后为 `[lz4kd]`，`backing_dev=/dev/block/dm-71`，
  `xswapd0` 存活；pid_max 仍为 32768 且不可上调。
- 还原前的 patched 镜像已备份为
  `/home/nuofang/t5m/backup/init_boot_a_current_20261030.img` 和
  `init_boot_b_current_20261030.img`，仅作回滚，不是原厂镜像。
- 注意：本次只还原 init_boot；`boot_b` 仍是自编 6.6.143 #3。

## 18. mihomo Alpha / TCP Brutal / IPv6 三模式实机（2026-10-30 晚）

- 内核：`6.6.143-4k #8`，boot_b `0dc871a520c39aa6cf57a177d3a78dd833b79a3bcfa14a5cca01985dacedc06e`；
  config sha256 `9b586a24…`；Image `53aef1a9…`；KCFI 13/13、638 stock
  模块 `hard_missing=0`、实机 586 模块。
- 相对 #3 的内核配置偏离：`NETFILTER_XT_MATCH_ADDRTYPE=y` 和
  `IP6_NF_NAT=y` + `IP6_NF_TARGET_MASQUERADE=y`。`ip6tables -t nat` 已实测
  可用。
  `CONFIG_MPTCP=y`（IPv6+diag）实测启动失败：花屏后看门狗复位，已回退；
  MPTCP 当前关闭。
- mihomo：Alpha `ca8d7c41` 调查，官方 Android arm64 `v1.19.33` 实测。
  TUN `mihomo` MTU 9000、`gso_max_size=65536`、auto-route table 2022、
  nat OUTPUT `mihomo-output` REDIRECT、DNS hijack、进程/包名匹配均生效。
  `inbound-mptcp: false`；`inbound-tfo: true` 配合
  `net.ipv4.tcp_fastopen=3`。
- 连通性：busybox wget 经 TUN HTTP/HTTPS、经 `127.0.0.1:7890` HTTP 代理均
  成功；mihomo 节点健康检查 alive（约 70–82 ms）。
- iptables 规则安装：`addrtype`、`socket`、`TPROXY`、`MARK`、`REDIRECT`、
  `DNAT` 全部 rc=0。
- tcp-brutal v2.0.1 外部模块：`brutal.ko` 签名/vermagic 匹配，`insmod`
  成功；`tcp_available_congestion_control` 含 `brutal`，
  `/proc/net/tcp_brutal/rules` 存在；socket `getsockopt(TCP_CONGESTION)`
  返回 `brutal`。ABI 白名单新增 `tcp_prot`、`tcpv6_prot`、
  `tcp_register_congestion_control`、`tcp_unregister_congestion_control`。
- ExtM/lz4kd 回归：`[lz4kd]`、`backing_dev=/dev/block/dm-71`、16 GiB swap；
  `pid_max=32768`。
- TFO 持久化：标准 `mihomo_alpha` KSU 模块安装后 #8 重启，
  `tcp_fastopen=3`；当前值 3。
- 标准 KSU 模块：`mihomo_alpha` r3，KSU `action=true`，自动启动等待默认路由；
  `tun.enable:false` 实测无 TUN、无 mihomo iptables/ip rule；
  `tun.enable:true` 自动 TUN 正常。action 10 秒无操作退出、音量上停止、
  音量下重启 mihomo（sendevent 注入验证；PID 变化且 TUN 恢复，不重启设备）。
- 三模式：
  - **TUN**：IPv4 204 成功；IPv6 `[2606:4700:4700::1111]:80` 进入
    `PROXY`（目标返回 400，不是链路失败）；`ip -6 rule`/table 2022 完整。
  - **REDIRECT**：IPv4 和 IPv6 TCP 均命中 `REDIRECT` 并进入 `PROXY`；
    nat REDIRECT 的 UDP 会丢失原始目的地址（mihomo 收到
    127.0.0.1:7892 并拒绝 loopback），所以本机 UDP 不可用。
  - **TPROXY**：IPv4 UDP 命中并进入 `PROXY`；TPROXY TCP 在 veth/netns
    测试环境未 accept，且该环境普通 netns→host TCP 本身也不通，结论暂不确定；
    本机 OUTPUT 不能用 TPROXY target。IPv6 TPROXY 未取得可信实测。
- 只有 TUN 覆盖本机 IPv4/IPv6 TCP/UDP/ICMP；“三模式都不漏流量”不成立，
  REDIRECT/TPROXY 有明确协议/转发范围限制。
- 已知非内核问题：mihomo 的 `/data/system/packages.xml` fswatch 报
  `watcher removed`；不影响 TUN/规则/连通性。
- 自动 fastboot：内核无法保证；见
  [BOOT_PACKAGING.md](BOOT_PACKAGING.md) §7。

## 19. mihomo Alpha 子模块、60 应用 pprof 与 PGO（2026-10-30）

- `third_party/mihomo` submodule 固定在 Alpha `ca8d7c4`，工作树无修改。
- 应用遍历脚本：`dash/scripts/mihomo-app-loop.sh`（设备）+
  `dash/scripts/profile-mihomo-apps.sh`（主机）。按 usage 排序，前 80 候选，
  每应用只启动一次；1s 后 `mCurrentFocus` 验证，非前台跳过；每个成功前台
  应用在 5s dwell 内请求 `pprof/profile?seconds=5`，因此没有尾部空闲窗口；
  不 force-stop、不关闭应用窗口。
- 结果：60 成功 / 70 尝试，wall 460s；理论 `60*(5+1)=360s`，余量约 100s。
  60 个片段合并为 `dash/profiles/mihomo-alpha-cpu.pgo`（91 KiB），
  Duration 300.48s，47.25s CPU samples（15.72%），284 节点；主要样本在
  process 解析、rule wrapper、netlink/syscall 和 TUN 连接路径，质量合格。
- PGO：`build-mihomo.sh` 使用上述 profile，`with_gvisor`、PIE、`-trimpath`、
  strip；PGO binary `64,028,968B`，sha256
  `6486910e6427b7ccd9a4e702feaa8d600f788881ed392368fa8f836a04670ace`，
  已替换模块 `bin/mihomo` 并重启；模块 `mihomo_alpha` r4-pgo，
  TUN、TFO、IPv6 回归正常。

## 20. 补丁系列按特性重拆分（2026-11-21，离线）

把 6.6.143 整树 squash `0000-6.6.143-dash-integration.patch`（84 个文件）
重拆为按功能特性分目录的补丁系列（11 个补丁、8 个特性目录），并给维护
流程加了机器校验。**纯仓库重组，不改任何内核代码，无需重新编译验证。**

- 拆分是文件级的：逐 hunk 分析确认每个文件只被一个特性触碰；BakaSU 与
  SUSFS 的 hook 调用点在 VFS/security/core 文件内交错（`fs/namei.c`、
  `block/ioprio.c`、`security/selinux/*` 等），整体归入
  `010-bakasu-susfs`，不做 hunk 级拆分。`fs/erofs/decompressor.c` 的改动
  是 LZ4 trace 事件打点，归 `050-lz4kd-zram/0002`；`mm/filemap.c`、
  `mm/vmscan.c` 相对上游只有 vendor hook 调用点后的空行，归
  `030-vendor-hooks-os4`。
- 新结构：`patches/<NNN-feature>/*.patch` + `patches/series`（每行一个
  特性目录）。归属唯一记录在 `dash/scripts/split-patches.py` 的 `SERIES`
  映射表；`check` 子命令校验 series/映射/补丁内容一致，`write` 从 squash
  再生成，树 diff 出现映射外文件会报错。`scripts/apply-patches.sh` 改为
  按 series 逐目录逐补丁 `git apply --index` 并打印每步进度；
  `scripts/gen-patches.sh`（`make gen-patches`）= src 树 diff → squash →
  拆分 → 校验。
- 验证 1（拆分保真）：`split-patches.py check --squash` 对比原 squash——
  11 个补丁的每个文件 diff 块与 squash 逐字节一致，84 文件全覆盖。
- 验证 2（应用结果）：在干净 `bf768be0` worktree（`git worktree add`）上
  用新 `apply-patches.sh` 完整应用：11 个补丁全部 `git apply --index`
  成功、无 warning；变更文件集（85 个，含 NoMount 的 `fs/Kconfig`）+
  3 个 SUSFS 安装文件与当时构建工作树 sha256 逐一相同；`drivers/kernelsu`
  与 `fs/nomount` 符号链接解析到相同真实目标。
- 验证 3（维护闭环）：`make gen-patches` 从 src 树重新生成，`check`
  （含与新生成 squash 的逐字节比对）通过，产出与现存补丁一致。
- 局限：本次只做离线校验，未重新编译；CI `patch-series` job 的
  `make source patches` 重放是后续每次构建的常设门禁。旧的 6.6.118 系列
  与 6.6.143 squash 从仓库删除，git 历史保留。

## 21. DroidSpaces 内建：云端 FAST 构建 + ABI 逐项核查（2026-11-21，构建级）

**证据分级：构建级（未实机）。** 上游配方来自 Droidspaces-OSS 官方
`Kernel-Configuration.md`（GKI below-6.12 路线）与同设备参考内核
`third_party/dash-droidspaces`（marble 配方已 7 轮 CI + 实机验证）。

- 提交 `dd656e2`：官方 SYSVIPC kABI 补丁的 6.6.143 适配（本树 slot 1-2 已被
  AOSP 占用，故 sysvsem→slot 6、sysvshm→slot 7+8）+ 官方 GKI fragment 全套
  配置；`f3dfc6f` 修 workflow 补 nomount 子模块；`f16afd5` 修 runner zram
  预配置（zram-generator 已激活 zram0 时 comp_algorithm/disksize EBUSY，
  需先 reset）。提交 `522403c` 是补丁拆分 + NoMount 固化。
- 云端构建：[kernel-build run 44873892086](https://github.com/NuoFang6/dash-kernel/actions/runs/44873892086)
  （`fast=true`，LTO_NONE），17 分钟成功；版本串 `6.6.143-4k` 正常；
  build.log 仅 2 条上游 `sorttable.c` 历史 warning，sched.h/kABI 相关 0。
- 配置核查（artifact config）：SYSVIPC/POSIX_MQUEUE/IPC_NS/PID_NS/DEVTMPFS/
  USER_NS/TMPFS_XATTR/TMPFS_POSIX_ACL/MACVLAN/IP_SET/NETFILTER_XT_SET 全部
  `=y`；`DEVTMPFS_MOUNT`/`CFS_BANDWIDTH`/`CGROUP_PIDS`/`MPTCP` 保持 off。
- **task_struct 布局核查（pahole，新 vmlinux vs 本地 #8 旧 vmlinux）**：
  `sysvsem` @ 3616、`sysvshm` @ 3624，与旧构建 `android_kabi_reserved6/7+8`
  的偏移完全一致；layout diff 除该 union 替换外 0 行差异，hole 布局相同
  （forced holes: 32）。
- **符号 CRC 核查（写 12 字节 `kernel_symbol`{value,name,ns} 解析器，
  以本地 #8 `Module.symvers` 校准：9106/9106 名称解析且 CRC 全匹配）**：
  新旧 vmlinux 的 `__ksymtab`/`__ksymtab_gpl`×`__kcrctab`/`__kcrctab_gpl`
  按符号名对齐——9106 个公共符号 **CRC 0 mismatch、0 移除**；多重集比对
  独立复核 0 丢失。仅新增 6 个导出：`from_kuid/from_kgid`（含 `_munged`）、
  `make_kuid/make_kgid`——`CONFIG_USER_NS=y` 的 uid/gid 映射辅助函数，
  纯增量、不动既有条目。
- 结论：vendor `.ko` 依赖的 task_struct 偏移与导出符号 CRC 在构建级均已
  实证不变；kABI 补丁按设计工作。**实机验证缺口仍在**：586 模块加载、
  `droidspaces check`、genksyms 抽查需刷机后复核（见 OPEN_ISSUES §3）。

## 22. r4 基线 + BakaSU/SUSFS bump + mihomo 模块移除 + 实机稳定性（2026-11-21）

**证据分级：实机运行稳定性为真机实测；r4/bump 为构建级（CI fast 待过）。**

### 实机稳定性（真机实测，6.6.143-4k #8）

- 连续运行 23h51m 后审计：`dmesg`（77k 行）0 条 panic/Oops/OOM/stall、
  0 条 f2fs/ext4/erofs 错误、0 条 UFS 错误、0 条 KASAN/kfence；
  `logcat -b crash` 为空。SUSFS 伪装下 `uname` 显示 stock 串
  `6.6.118-...-gc44b714366cc`，实际为自编 #8（正常）。
- 模块加载核对：`hma_uidfake`（外部 HMA LKM，vermagic 6.6.127-dirty，经
  vendor-ko-compat 加载）、`os_cpu_qi/qs/perf_actuator`、`node_cache`、
  vendor 638 清单均正常；`nomount` LKM 为模块自带旧版行为（手机上的
  NoMount metamodule 还没更新到检测内建的版本），与本内核 #8 未内建
  NoMount 一致，非重复 hook。

### 上游同步（构建级）

- AOSP 基线 `2026-10_r2 (bf768be0)` → `2026-10_r4 (e6c23f62)`；SUBLEVEL
  仍为 143（GKI 分支跟 ASB release，LTS bump 由 Google 管理）。r4 带入
  新 ANDROID 补丁与符号（如 Zebra 符号清单更新）。
- BakaSU `d5e9e02` → `7b65bde`；SUSFS `0606e19` → `f98f082`；
  nomount/tcp-brutal/lz4kd pin 无漂移；clang r614150 (23.0.1) 仍为
  main-kernel 最新，不动。
- 12 个特性补丁在 r4 干净树上重放 0 冲突（apply-patches 输出
  `patch series applied: 12 patches`）。
- `third_party/sukisu-patch` 子模块不被构建链引用（仅 README 提及），
  保留观察，暂不删除。

### mihomo_alpha KSU 模块移除（决策记录）

- 手机端已卸载 `mihomo_alpha`；代理客户端统一改用 AsteriskMETA
  （GUI，自带 mihomo core / asteriskd / bpf2socks / bpfmatcher /
  AsteriskEnhance）。仓库侧删除：`dash/modules/mihomo_alpha/`、
  4 个 mihomo 脚本、`dash/profiles/mihomo-alpha-cpu.pgo`、
  `third_party/mihomo` 子模块、versions.env pin、bump-submodule.yml
  选项、各 README/STATUS/AGENTS 索引引用。内核 TUN/TPROXY/netfilter
  能力与 `tcp-brutal` 外部模块保留。

### AsteriskMETA 内核能力核对（静态核对，源码克隆核验）

- bpf2socks：`BPF_PROG_TYPE_CGROUP_SOCK_ADDR`（connect4/6/sendmsg4/6）、
  `SCHED_CLS`（tc ingress/egress classifier）、`SK_REUSEPORT` +
  `REUSEPORT_SOCKARRAY`、LPM_TRIE/LRU_HASH/PERCPU_ARRAY/HASH map 类型。
- bpfmatcher：`SOCKET_FILTER` + LPM_TRIE/HASH。
- config 核查（out/dash/.config）：`BPF/BPF_SYSCALL/BPF_JIT(ALL_ON/
  DEFAULT_ON)/CGROUP_BPF/BPF_LSM/XDP_SOCKETS/NET_CLS_BPF/NET_ACT_BPF/
  NET_SCH_INGRESS/TUN/VETH` 全部 `=y`；TPROXY/REDIRECT/socket/IPRANGE/
  MULTIPORT/CONNMARK match-target 齐；`addrtype` 由本树启用。
- 结论：**无需新增内核配置**。

### CPU 特性编译期利用核查（静态核对）

- 已启用：LSE atomics（`ARM64_USE_LSE_ATOMICS`）、PAC（`PTR_AUTH_KERNEL`）、
  BTI、Kernel-mode NEON、ARM64 crypto 加速全套（AES-CE/CE-BLK、SHA1/SHA2/
  SHA512-CE、CHACHA20-NEON、POLY1305-NEON、POLYVAL-CE）、
  `CC_OPTIMIZE_FOR_PERFORMANCE`、ThinLTO。stock KMI 约束下无未利用的
  硬件 ISA 开关。

## 23. SUSFS f98f082 bump 链接失败与修复（2026-11-21）

**证据分级：CI 失败日志 + 本地 FAST 构建通过（真机构建级）。**

- **失败**：CI run 44878359543（r4 + BakaSU 7b65bde + SUSFS f98f082）链接
  `ld.lld: error: undefined symbol: susfs_is_priority_uid_filtered`
  （引用于 kernel/sys.c setpriority/getpriority、block/ioprio.c
  ioprio_set/getpriority）。
- **根因**：f98f082（"Sync with upstream"）把 priority-uid filter 实现
  （susfs.c 的 app-strings worker / bitmap / `susfs_is_priority_uid_filtered`）
  包进新的 `#ifdef CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER`（susfs.c
  1785-2209 / 2317-2321），官方 50_add_susfs gki patch 的调用点门控也同步
  改为该 CONFIG（带 `#else` 分支）；但**上游没有为它提供任何 Kconfig 条目**
  （susfs4ksu 子模块、BakaSU kernel/Kconfig 均无）。本仓库固化补丁
  010-0002 的调用点门控仍是旧版 `#ifdef CONFIG_KSU_SUSFS`（=y）→ 函数
  不编译而调用点编译 → 链接失败。旧 pin 0606e19 的实现无门控（无条件
  编译），故此前构建从未暴露。
- **修复（补丁不可手改，走树 + gen-patches）**：
  - 树内 kernel/sys.c（extern + 2 调用点）、block/ioprio.c（extern + 2
    调用点）门控改为 `CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER`，与 f98f082
    官方 patch 对齐；sys.c 中 `ksu_handle_setresuid` 两处保持
    `CONFIG_KSU_SUSFS`（BakaSU hook，与 susfs 无关）。
  - `apply-patches.sh` 幂等注入 `config KSU_SUSFS_PRIORITY_UID_FILTER`
    （depends on KSU_SUSFS，default n）到 fs/Kconfig（借 NoMount 注入
    先例；fs/Kconfig 被 gen-patches 排除，重放安全）。
  - `configure.sh`：`-e CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER` + required
    校验防回归（configure.sh 不读 features.fragment，实际开关以它为准）。
  - features.fragment 同步 =y（保持与旧 pin 行为一致：过滤功能可用）。
- **验证**：12 patches 重放 0 冲突、gen-patches check 通过（12/85 文件）；
  本地 `make config FAST=1 build` 通过（Image.lz4 17M，无 undefined）；
  CI fast 复跑见 §22 提交链接。
- 附带：CI 工具链 cache key 从 `hashFiles(versions.env)` 改为
  `CLANG_VERSION`（本轮 pin bump 无关变动曾每次逐出 1.99GiB clang
  cache）；artifact 收集增强（final-config、build-inputs.tar.gz、
  build-info.txt，`if: always()` 保留失败产物）；Image.lz4 超 64MiB
  boot 预算（67098176 B）时 fail 但不丢弃产物。

## 24. FEATURES_SURVEY 落地批次：NoLTO 构建、CRC/KMI 与 Full LTO 边界（2026-11-21）

**证据分级：补丁重放 + 构建级 + 静态 ABI；未刷机、运行时未验证。**
本节只记录本轮新增证据；功能来源与逐项决策见 `FEATURES_SURVEY.md`。

### 补丁与配置闭环

- `features.fragment` 改为功能开关唯一权威输入；`configure.sh` 合并 fragment、
  执行 `olddefconfig` 后逐项 required 断言。修复解析器把未加引号整数 `1024`
  误传为字符串的问题，并新增
  `CONFIG_GKI_TASK_STRUCT_VENDOR_SIZE_MAX=1024` 强断言；字符串 `CONFIG_LSM`
  和 `# CONFIG_X is not set` 语义均实测生效。
- 固定 AOSP r4 `e6c23f621ca6e839abdeca58957bbc529536cff1` 干净树完整重放：
  28 个普通补丁、140 个唯一归属文件，以及 1 个 SUSFS 安装后 override；
  `apply-patches.sh` 输出零 warning/error。`split-patches.py check` 确认 series、
  文件归属和 source-tree squash 逐字节一致。
- BakaSU 与 `third_party/susfs4ksu` 子模块工作树均为空；没有修改 BakaSU。
  SUSFS override 只作用于 apply 后安装到 AOSP 树的副本。

### NoLTO 全量构建

- 最终门禁按机主 2026-11-21 新策略使用 `FAST=1`（NoLTO）；仅明确要求
  “产出最终生产级内核”时才运行 Full LTO。NoLTO 不改变源码级 genksyms CRC。
- 全新 `out/features-final` 从上述干净重放树配置并编译；配置至少包含：
  BBRv3、NTSync、ADIOS（非默认）、BBG、AutoFDO 构建支持、A720 tune、
  `GKI_TASK_STRUCT_VENDOR_SIZE_MAX=1024`；MPTCP、BBG boot/recovery 拦截保持关闭。
- 构建日志除 ACK `scripts/sorttable.c` 两条既有 host warning 外无编译/链接错误；
  `vmlinux`、BTF、`Image` 与 `Image.lz4` 均生成。产物没有打包为 boot，也没有
  写入任何手机分区。`DEVICE=features-final` 最初暴露出 `build.sh` 会把验证
  变体复制到共享 `out/artifacts/`；现已改为只有默认 `DEVICE=dash`（或显式
  `PUBLISH_ARTIFACTS=1`）才发布。共享目录已从当前 boot/备份恢复 manifest 可
  校验的 Image/Image.lz4/config，删除不匹配的 vmlinux/System.map；其中 #8
  System.map 的本地副本已无，仅 `SHA256SUMS` 保留目标哈希，不以别的构建冒充。

### CRC、结构与厂商模块门禁

以已实机运行的 #8 历史 `handoff/boot-6.6.143-4/vmlinux` 为旧基准，读取
新旧 ELF 的 `__crc_*` 地址及 `__kcrctab{,_gpl}` 中实际 32 位值，按符号名比较：

```text
old=9102 new=9112 common=9102 mismatch=0 removed=0 added=10
```

新增 10 个导出为 USER_NS uid/gid 映射辅助函数 6 个与 BBRv3 所需 TCP 导出
4 个（`tcp_prot`、`tcpv6_prot`、congestion-control register/unregister）；旧导出
无 CRC 变化、无移除。

- 初次检查曾发现 3 个真实漂移并已修复：整数 fragment 解析错误令
  `vendor_data_pad` 从 1024 回落 512；新增 PREEMPT_SHORT 令导出的
  `sched_feat_keys/names` 数组边界进入 genksyms。前者修 parser + 强断言，
  后者用 `__GENKSYMS__` 隐藏新增 feature 条目但保留运行时条目；复验归零。
- `pahole -C task_struct`：新旧均 4800B；`sysvsem` @3616、`sysvshm` @3624，
  对应原 `android_kabi_reserved6` 与 `reserved7/8`，关键偏移不变。
- 638 个 stock `.ko` 离线符号集合检查：
  `modules=638 kernel_exports=9112 hard_missing=0 weak_missing=0`。这是符号解析
  门禁，不替代运行时加载或 CRC 检查。
- `verify-os4-kcfi.py`：13/13 vendor-hook 原型与 stock KCFI hash 一致。

### Full LTO 调查与停止点

- 首次全新 Full LTO 构建先因主机 OpenSSL 4.1 移除 ENGINE 符号而失败；
  `certs/extract-cert.c` 现按 `OPENSSL_NO_ENGINE` 禁用仅 PKCS#11 ENGINE 分支，
  普通 PEM 路径可构建。
- 随后最终链接暴露 arm64 typed assembly 的
  `__kcfi_typeid_idmap_cpu_replace_ttbr1` 未生成。根因是函数 typedef/extern 仅在
  inline caller 函数体内，Full LTO 丢弃 address-taken 类型元数据；提升到文件
  作用域后，三个调用对象均实测生成该弱 type-id 定义。
- 修复后重链接进入 `LD vmlinux.o` 且无新错误，但 15 GiB 主机大量 swap、链接
  约 12 分钟仍未完成。机主要求停止，并定下“日常验证一律 NoLTO，只有明确要求
  最终生产级内核才 Full LTO”的规则；任务已停止并确认无残留进程。因此本节
  **不声明 Full LTO 构建通过**，只声明配置和两个已发现阻塞已落地修复。

### 运行时缺口

设备在验证期间由机主断开，本轮本来也明确禁止刷机。BBRv3 `ss -i`、
ADIOS 与 mq-deadline A/B、hide_adb/JDWP、BBG、NTSync、F2FS/Unicode、
suspend/resume 及 638 模块实机加载均保持“未实机”；AutoFDO 仅有构建支持，
此前实机只确认当前运行内核未暴露 `arm_spe_*` 或 `cs_etm` PMU,且主机未安装
profile 转换工具;README 中转换命令只作为未验证 CLI 的流程示意。后续静态复核
已确认 arm64 AutoFDO 也可走 ETM/ETE,且 MT6991 厂商 DTS 已有完整 ETE→ETR
拓扑,但 stock `CONFIG_CORESIGHT=n`;故优先路线改为单独启用 CoreSight 的实验
构建,不先修改 DT 猜测 SPE 中断。

## 25. MLGO regalloc 与 ACK 预制 AutoFDO profile 接线（2026-11-21，构建级）

**证据分级：构建级 + 静态工具链核查；未刷机、未做性能 A/B；Full LTO 全量构建
未运行（按机主“除非授权不跑 Full LTO”的规则）。**

### MLGO 调查结论修正

- 此前“r614150 不支持 MLGO”的判断来自过时参数
  `-mlgo-regalloc-forcing-model`；该工具链实际接受现行参数
  `-regalloc-enable-advisor=release`。
- 本机探针中 `release` 顾问可成功创建；若工具链未编入对应模型，LLVM 会明确
  报错并回退，而本轮配置与全量构建均未出现该诊断。结论：r614150 自带 MLGO
  寄存器分配 eviction advisor，WildKernels 的 MGLO 即此项，不包含内联 MLGO。
- 接线：`CONFIG_DASH_MLGO_REGALLOC`（默认 y）经 `arch/arm64/Makefile`
  同时写入 `KBUILD_CFLAGS`（clang，NoLTO/ThinLTO）与 `KBUILD_LDFLAGS`
  （LLD，Full LTO 的寄存器分配在链接期）；`configure.sh` 以真实
  NoLTO（clang 编译）与 Full LTO（clang bitcode + `ld.lld -r`）双路径探针
  断言 advisor 可创建。

### AutoFDO 改用 ACK 预制 profile

- ACK 树自带 `android/gki/aarch64/afdo/kernel.afdo`（6.6.142 采集，约
  4.0 MiB），`BUILD.bazel` 即用它给 `kernel_aarch64` 接线。
- `dash/versions.env` 钉死
  `ACK_AUTOFDO_PROFILE_SHA256=b27ba364e664c5d83daae4cece90dffe95b6388bc2c214c2b2e1a5f35b0654b2`；
  `lib.sh::verify_autofdo_profile` 在 `configure.sh`、`build.sh`、
  `build-tcp-brutal.sh` 构建前校验，不匹配即失败。
- `build.sh` / `build-tcp-brutal.sh` 的 MAKE 数组传入
  `CLANG_AUTOFDO_PROFILE="$AUTOFDO_PROFILE"`，由 ACK
  `scripts/Makefile.autofdo` 为每个 TU 注入 `-fprofile-sample-use`。

### NoLTO 全量构建实证

`FAST=1`（NoLTO）构建，`out/features-mlgo-afdo`，`.config` 确认
`CONFIG_LTO_NONE=y`：

```text
cmd_total=6258
fprofile-sample-use=3188
mtune=cortex-a720=3188
regalloc-enable-advisor=3230
vmlinux.o LDFLAGS advisor=1
Image=38877696 B
Image.lz4=18366486 B
build.log=5433 lines, error=0（仅 scripts/sorttable.c 两条既有 host warning）
```

计数方法：遍历全部 `*.cmd` 后按参数子串 `grep -l`；`.vmlinux.o.cmd`
另含 `--mllvm=-regalloc-enable-advisor=release`。构建 exit 0，无 profile
mismatch/invalid，无 advisor fallback 诊断。

### Full LTO 下 profile 是否生效

ACK `scripts/Makefile.autofdo:16` 只在 `CONFIG_LTO_CLANG_THIN` 分支传
`--lto-sample-profile`，Full LTO 分支不传。以最小 Full LTO 样例对照验证：
sample profile 权重已作为 `!prof` 元数据写入每个 TU 的 bitcode，exe 级
Full LTO 链接即使不带该参数，hot/cold 两份 profile 仍生成不同代码，说明
profile 在编译期已应用。因此“缺参数”不是功能缺口；但 **Full LTO 全量构建
本身本轮未跑完，不声明生产配置端到端通过**。

### 运行时缺口

MLGO 与 AutoFDO 的收益均未测量；未刷机，未做 A/B。AutoFDO 使用 6.6.142
采集的 profile 编译 6.6.143 源码，版本接近但不完全一致，效果需实机验证。

## 26. 调试用 NoLTO 构建与 boot_a 封装（2026-11-21，构建级）

**证据分级：构建级 + 主机侧 boot 结构校验；未刷机。**

### 构建

`DEVICE=debug-nolto FAST=1 make config build`，输出在
`dash/out/debug-nolto/`。`.config` 关键项：

```text
CONFIG_LTO_NONE=y
CONFIG_AUTOFDO_CLANG=y
CONFIG_DASH_MLGO_REGALLOC=y
CONFIG_DASH_ARM64_TUNE_A720=y
CONFIG_KFENCE_DEFERRABLE=y
CONFIG_RCU_LAZY=y
CONFIG_WQ_POWER_EFFICIENT_DEFAULT=y
CONFIG_MQ_IOSCHED_ADIOS=y
CONFIG_NTSYNC=y
CONFIG_BBG=y
```

`6258` 个 `.cmd` 中：`-fprofile-sample-use` 3188、`regalloc-enable-advisor`
3230、`-mtune=cortex-a720` 3188；构建日志仅 `scripts/sorttable.c` 两条既有
host warning，无 error。产物：

```text
Image      = 38877696 B  sha256 62b57de74a6dca0ab4c8ba0724f88805f3a84d0d60e361690fea40368f48d173
Image.lz4  = 18366486 B  sha256 6ddf9c53fa92d20776739253706779318de86de03ac4805980f616beb9a1a265
kver       = 6.6.143-4k #1 SMP PREEMPT Sat Nov 21 21:57:31 CST 2026
```

### boot_a 封装

以 stock `handoff/dash-gap-handoff/boot/boot_b.img`（6.6.118，OEM 元数据）为
基底，用 `repack-boot.py` 只替换 kernel：

```text
boot_a.img = 67108864 B  sha256 1b5af31a873687eb6cc5c78fba19f3f8a134db020e75e43a22e0f7f24b7d05ef
unpack_bootimg: header v4，kernel 与 Image.lz4 cmp 一致，ramdisk 为空
AVB: original_image_size=18374656，vbmeta=18374656+2432，OEM 字节保留
```

### 设备与备份

- 设备 `dash` / serial `9XIBH6KJPFS4IZGQ`，激活槽位 `_a`
  （`boot_a -> /dev/block/sdc37`）。
- 刷前备份：`dash/out/device-backup/20261121-215639-pre-nolto-slot_a/boot_a.img`，
  64 MiB，SHA256 `0dc871a520c39aa6cf57a177d3a78dd833b79a3bcfa14a5cca01985dacedc06e`；
  主机与设备端哈希一致。
- 备份镜像解包后为 `6.6.143-4k #8`；但采集时设备 `uname -a` 仍为 stock
  `6.6.118-android15-8-...`，说明 #8 已写入 boot_a 但尚未重启生效。
- 本轮未刷机。后续只写激活槽位 `_a`；刷入后重启并先记录 `dmesg`/模块加载
  结果，再按 `OPEN_ISSUES.md` §3.1 清单执行。

## 27. NoLTO 调试内核首刷实机启动（2026-11-21，真机）

**证据分级：真机实测（首次启动 + 只读检查）；未做压力、suspend、性能 A/B。**

### 刷写与启动

- 仅写激活槽位 `boot_a`：`fastboot flash boot_a boot_a.img`，镜像
  SHA256 `1b5af31a…7d05ef`；刷后设备端 `sha256sum /dev/block/by-name/boot_a`
  一致。未触碰 `lk`/`vbmeta`/`super`/`boot_b`。
- 重启后 `sys.boot_completed=1`，`ro.boot.slot_suffix=_a`，
  `ro.boot.verifiedbootstate=green`；SELinux `Enforcing`，`su -c id` 为 root
  （`u:r:ksu:s0`）。机主确认正常开机到桌面。
- **`uname` 不可作为版本依据**：SUSFS `SPOOF_UNAME` 把 `uname -a` 伪装成
  stock `6.6.118-android15-8-...`。真实启动行来自 `/dev/kmsg`：

  ```text
  Linux version 6.6.143-4k (dash@mikernel) ... #1 SMP PREEMPT Sat Nov 21 21:57:31 CST 2026
  ```

- `zcat /proc/config.gz` 确认运行配置：`CONFIG_LTO_NONE=y`、
  `CONFIG_TCP_CONG_BBR3=y`、`CONFIG_DASH_MLGO_REGALLOC=y`、
  `CONFIG_KFENCE_DEFERRABLE=y`、`CONFIG_RCU_LAZY=y`。

### 功能抽查（运行时）

- `/proc/sys/net/ipv4/tcp_available_congestion_control` =
  `reno bbr bbr3 bic cubic westwood htcp`；切到 `bbr3` 成功并读到 `bbr3`。
  随后回写 `cubic` 初次失败是 KSU `su -c` 只对 `;` 链首个命令提权、后续命令
  落到 shell 域所致，不是 SELinux 策略；用单独 `su -c` 已恢复 `cubic`。
  这个 su 链行为是本轮排查的关键坑，后续多命令统一用 `su -c 'sh -c "..."'`。
- 调度：实际 debugfs 挂在厂商隐藏路径
  `/dev/wrob_xkc/qebsxhwy`；`sched/features` 含 `PREEMPT_SHORT` 与
  `NO_CACHE_HOT_BUDDY`（即 CACHE_HOT_BUDDY 关闭），与构建意图一致。
- ADIOS：`io scheduler adios registered`；`mq-deadline` 同时注册。
- KFENCE：`kfence: initialized - using 524288 bytes for 63 objects`。
- zRAM/ExtM/lz4kd：`ExtM: Added device: zram0`，swap 16 GiB 已启用；
  `/proc/crypto` 含 `lz4kd-scomp`/`lz4kd-generic`。
- SUSFS：`ksu_susfs show version` = `v2.4.0`；`show enabled_features` 返回
  SUS_PATH、SUS_MOUNT、SUS_KSTAT、SPOOF_UNAME、ENABLE_LOG、
  HIDE_KSU_SUSFS_SYMBOLS、SPOOF_CMDLINE_OR_BOOTCONFIG、OPEN_REDIRECT、
  SUS_MAP、PRIORITY_UID_FILTER 共 10 项。
- 模块：`/proc/modules` 584 个；与历史 stock 清单 585 行逐名比较，
  当前少了 `kernelsu`/`nomount` 两个 LKM、多了 `mkp`。KSU 与 NoMount 已
  内建，故 584 与历史 586 口径等价；无 `Unknown symbol`/vermagic/CRC 加载错误。
- `node_cache`、`os_cpu_qi`、`zsmalloc`、`zram` 均加载。
- DroidSpaces 用户态工具已在后续步骤安装并通过检查，见
  `FEATURES_SURVEY.md` 的「实机核对与运行记录」。

### 日志异常核对

- 内核日志仅 1 条 `WARNING: CPU`：
  `proc_dir_entry '/proc/mtk_cmdq_debug' already registered`
  （`mtk_cmdq_drv_ext`）。该警告在 2026-10-30 #3 历史启动日志中同样存在，
  属于厂商模块重复注册，不是本构建新增。
- 无 `BUG:`、panic、`brk #0x8228`（KCFI）、模块签名/CRC 失败。
- BT 固件下载报错 819 条，历史 #3 日志为 831 条（同类 `tty write failed`），
  `ready_retry` 25 vs 历史 27，属于既有厂商行为，未发现新增回归。
- 本节记录的是 `#1` 首次启动；后续 `#2`（NTSync 修复）、DroidSpaces 与
  逐项实机核对结果见 `FEATURES_SURVEY.md` 的「实机核对与运行记录」。

## 28. Full LTO 生产构建与 idmap CFI typeid 链接修复（2026-11-22，构建级 + CI 发布）

**证据分级：CI 构建/链接/打包实测；未刷机，未做性能 A/B。**

### 失败现象

Full LTO 生产构建（run 44918126681、44920896595）在 `LD vmlinux.o`
之后、最终 `LD .tmp_vmlinux.btf`/`vmlinux` 阶段失败：

```text
ld.lld: error: undefined symbol: __kcfi_typeid_idmap_cpu_replace_ttbr1
>>> referenced by ld-temp.o
>>>               vmlinux.o:(.idmap.text+0x510)
ld.lld: error: .btf.vmlinux.bin.o: unknown file type
```

第二条是第一条导致 BTF 链接失败的级联。`SYM_TYPED_FUNC_START()` 在
`arch/arm64/mm/proc.S` 里只产生对 typeid 的引用，定义需由 clang 在 C TU
中生成。

### 根因

clang 对“取过函数地址”的 TU 各生成一份 **弱绝对符号**：

```text
module asm ".weak __kcfi_typeid_idmap_cpu_replace_ttbr1"
module asm ".set __kcfi_typeid_idmap_cpu_replace_ttbr1, 0x3e7ff605"
```

`cpu_replace_ttbr1()` 是头文件 inline，被 `mmu.c`、`kasan_init.c`、
`suspend.c`、`cpufeature.c` 四个 TU 实例化并取地址，于是产生四份重复弱定义。
**Full LTO 合并模块时会把这个重复的弱绝对符号整体丢弃**，最终链接
无法解析 proc.S 的引用。之前加的 `DEFINE_CFI_TYPE`（只让 mmu.c 再生成
一份）因此无效，反而增加重复。

最小复现（本机 toolchain，`ld.lld -r` + LTO）：

- 单 TU 取地址 → 输出保留 `W __kcfi_typeid_...`
- 两 TU 取地址 + 一个 native 引用 → 输出变成 `U __kcfi_typeid_...`，
  最终链接报同样错误

### 修复（commit `b6aac16`）

- `arch/arm64/include/asm/mmu_context.h`：把符号声明改为不透明对象类型
  `extern char idmap_cpu_replace_ttbr1[];`，使 inline 调用方不再触发
  clang 生成 typeid；`__pa_symbol()` 用法与运行时代码不变。
- 新增 `arch/arm64/mm/idmap_cfi.c`：唯一一次按真实函数原型取地址并
  `DEFINE_CFI_TYPE()`，保证全内核只有一份 typeid 定义。
- `arch/arm64/mm/Makefile`：`obj-$(CONFIG_CFI_CLANG) += idmap_cfi.o`。

Full LTO 探针验证（不跑全量构建）：

```text
mmu.o / kasan_init.o / suspend.o: 无 typeid
idmap_cfi.o: W __kcfi_typeid_idmap_cpu_replace_ttbr1
proc.o:      U __kcfi_typeid_idmap_cpu_replace_ttbr1
LTO -r 链接后: 000000003e7ff605 W __kcfi_typeid_idmap_cpu_replace_ttbr1
```

### CI 生产构建结果（run 44923883114，commit `b6aac16`）

- 构建 26 分钟；`LD vmlinux.o` 约 10 分钟；`BTF`、`.tmp_vmlinux.kallsyms1/2`、
  `LD vmlinux`、`OBJCOPY arch/arm64/boot/Image` 全部通过。
- smoke：`kernel: 6.6.143-4k (dash@mikernel) ... # SMP PREEMPT`。
- `Image` 47,684,096 B；`Image.lz4` 22,808,794 B
  （flashable limit 67,098,176 B）；`vmlinux` 151 MiB、`System.map` 4.8 MiB。
- 仅既有警告：`scripts/sorttable.c` 两个 host 侧 unused 警告、浅克隆 tag 警告。
- Release `dash-6.6.143-prod` 已发布：
  `Image` `93efcf83…a7dcd`、`Image.lz4` `59b10ded…713ad`、
  `dash_art_tune-ak3-v1.2.zip` `05ea72fc…2115e`、
  `dash_art_tune-v1.2.zip` `07f391e6…a439c`。
- AK3 包内 `Image` 哈希与 Release `Image` 一致；`block=boot`、
  `is_slot_device=auto`，只 `dump_boot`/`write_boot`，不写 `init_boot`；
  包内含 `module/`（KSU 调优模块）。
- 发布 tag 指向实际构建 commit `b6aac16`；此后 `34bf436` 只补了
  `DASH_ARM64_TUNE_X925` 的 Kconfig 默认值（本次未选 X925，不影响产物）。
- 未刷入设备；生产内核的实机启动、模块兼容与稳定性仍待验证。

### 顺带结论

同轮排查确认 clang r614150 的 MLGO inliner 可用
（`-enable-ml-inliner=release`），但 help 明示其模型
“trained for -Oz only”，属体积模型；未加入 O2 生产构建。

## 29. Full LTO 生产内核首刷实机启动（2026-11-22，真机）

**证据分级：真机实测（首次启动 + 只读检查 + DroidSpaces check）；未做长时压测。**

### 刷写与身份

- 仅写 `boot_a`：`fastboot flash boot_a`，镜像 SHA256
  `d0cdd6ad…9b6be2`；刷后设备端 `sha256sum /dev/block/by-name/boot_a`
  完全一致。刷前已备份当前 NoLTO `#2`（`3d0d4245…`）到
  `dash/out/device-backup/20261122-004847-pre-prod-slot_a/`。
- `uname` 仍被 SUSFS 伪装；真实版本行来自 `dmesg`：

  ```text
  Linux version 6.6.143-4k (dash@mikernel) ... #1 SMP PREEMPT Sat Nov 21 16:44:37 UTC 2026
  ```

  构建时间与 CI 最终 `LD vmlinux`/`OBJCOPY Image` 时间吻合。
- `sys.boot_completed=1`，槽位 `_a`，verified boot `green`，8 核全部 online。

### 配置核对（`/proc/config.gz`）

`CONFIG_LTO_CLANG_FULL=y`、`CONFIG_CFI_CLANG=y`、`CONFIG_AUTOFDO_CLANG=y`、
`CONFIG_DASH_MLGO_REGALLOC=y`、`CONFIG_DASH_ARM64_TUNE="cortex-a720"`、
`CONFIG_TCP_CONG_BBR3=y`、`CONFIG_MQ_IOSCHED_ADIOS=y`、`CONFIG_RCU_LAZY=y`、
KSU + SUSFS 全套。与生产配置一致。

### 启动日志

- 无 `Kernel panic`、`BUG:`、真实 Oops、`brk #0x8228`（KCFI）、
  `Unknown symbol`、`invalid module format`、`disagrees about version`。
- 唯一 `WARNING: CPU` 仍是 `fs/proc/generic.c:398` 的
  `'/proc/mtk_cmdq_debug' already registered`（厂商模块重复注册，历史
  #1/#2 与 stock 时代同有）。12 条 `Call trace` 均为厂商日志
  （cmdq 寄存器 dump、conninfra BT/WiFi pwr_on 回调、该 WARNING 栈）。
- 无 OOM/LMK、无 I/O error、无 hung task/RCU stall。F2FS 仅 1 条
  `Unexpected flush for atomic writes`（小米 F2FS 常见提示，非错误）。
- 未发生 Linux `PM: suspend entry`（0 次）；日志中的 `SPM mcusys_off`
  是 MTK 深空闲唤醒记录，不是 suspend 失败。

### 模块与功能

- `/proc/modules` 584 个；`zram`/`zsmalloc`/`cfg80211`/
  `wlan_drv_gen4m_6991_6639_new9gen2`/`btmtk`/`conninfra`/`node_cache`/
  `os_cpu_qi`/`mkp` 均加载；`kernelsu`/`nomount` 已内建；模块校验失败 0。
- BBRv3 为默认拥塞控制，`fq_codel` 为默认 qdisc；`adios` 在 `sdc`
  为当前调度器。
- zram0 16 GiB swap 已启用，压缩算法 `lz4kd`，ExtM backing `dm-71`；
  `mm_stat` 492 MB 原始 / 140 MB 压缩 / 160 MB 实占。本轮未触发回写
  （`bd_stat` 全 0），未为验证再制造 UFS 写入。
- SUSFS `v2.4.0`，`enabled_features` 10 项；KSU root `u:r:ksu:s0`。
- `dash_art_tune` v1.2 生效：BBRv3/fq_codel 持续保持，ADIOS 已选；
  ART `features=runtime`、`variant=cortex-a55`、`dex2oat-threads=8`、
  `boot-dex2oat-threads=8`、CPU set 0–7、后台 4 线程/0–3。
- DroidSpaces CLI `check`：required 全绿；可选 FUSE/TUN/OverlayFS/
  netns/bridge/veth/macvlan/IPv6 NAT/mem+swap limit/sandbox 全绿；
  `CFS_BANDWIDTH`/`CGROUP_PIDS` 按设计关闭（`--cpus`/`--pids-limit`
  不可用）。
- UFS health：`eol_info=0x01`、`life_time_estimation_a/b=0x01`
  （0–10%），与刷前一致。
- USB：connected/configured/charging、Type-C sink、adb 正常；日志中
  `mtk-xsphy/mtk-extcon-usb failed to ...` 为启动期厂商 DT 探测信息，
  未见 USB 崩溃或 ANR。

### 待办

- 生产内核只做了首次启动检查，未做长时稳定性、zram 回写压力、
  suspend/resume 与性能/功耗 A/B。

## 30. OTA payload 解包与 init_boot 在用性核对（2026-11-22，只读）

- 源包：`dash-ota_full-OS4.0.4.0.XPLCNXM-user-17.0-81a5c2e9c7.zip`
  （8,644,649,513 B，A/B full OTA，`post-build=Redmi/dash/dash:17/
  CP2A.260605.016/17OS4.0.261028.233904816.MTPECN.S`，安全补丁 2026-10-01）。
- `payload.bin` 用 payload-dumper-go 2.1.0 提取（manifest SHA256 默认校验）：
  - `boot.img` 64 MiB，SHA256 `f8f0de69…f2b3c`（OS4.0.4.0 stock）
  - `init_boot.img` 8 MiB，SHA256 `ded406b1…001ebd`
- 实机（槽位 `_a`）：`init_boot_a` = `ded406b1…001ebd`，**与 OTA 包内
  `init_boot.img` 完全一致**；`init_boot_b` = `3d2062ae…22b70a`（OS4.0.3.0，
  未随 OTA 更新）。
- 实机 `boot_a` = `d0cdd6ad…`（本仓库 Full LTO 生产内核）；`boot_b` =
  `0dc871a5…`（历史自编 `#8`，不是 stock）。OTA stock `boot.img` 已放到
  `/storage/emulated/0/Download/boot.img`，哈希回读一致。
- 未刷写任何分区，仅提取与比对。

## 31. dash_art_tune v1.3：WLAN 日志关闭（2026-11-22，真机 + 模块）

**证据分级：真机实测（属性、bind mount、目录状态）；模块安装为 KSU 暂存，重启后正式生效。**

### 变更

- `post-fs-data.sh` 通过 property_service 设置并持久化：
  `persist.vendor.performance.disable.wlan_logs=true`、
  `persist.vendor.cnss_diag.enable=false`、
  `persist.vendor.tcpdump.enable=false`（写入
  `/data/property/persistent_properties`）。
- `cnss_diag.conf`：模块内自带 `LOG_PATH_FLAG=0` 副本，`service.sh` 在
  `/data/vendor/wifi/cnss_diag.conf` 不存在时先创建占位文件，再
  `mount -o bind` 覆盖；挂载失败则回退为直接写文件。
- `/data/vendor/wlan_logs`：删除一级普通文件，`rm -rf tcpdump.pcap0` 后
  重建为同名目录；`vendor_tcpdump` 用 `setprop ctl.stop` 显式停止。

### 实测

- 手动（不经模块）创建 `cnss_diag.conf`（原文件不存在）：
  `LOG_PATH_FLAG=0`、`wifi:wifi 0660`、label
  `u:object_r:vendor_wifi_vendor_data_file:s0`。
- 三个 persist 属性当前值与持久化存储均正确。
- 应用模块 action 后 `/proc/mounts` 出现
  `/data/vendor/wifi/cnss_diag.conf`（源为模块内副本），读取为
  `LOG_PATH_FLAG=0`；`/data/vendor/wlan_logs` 只剩 `tcpdump.pcap0/` 目录。
- `vendor_tcpdump`（pid 6097，init 服务 `disabled`+`oneshot`，由
  `sys.user.0.ce_available=true` 启动）停止前仍在向已删除的 pcap0 写入
  （fd pos 持续增长）；`ctl.stop` 后服务状态 `stopped`、进程消失，
  30 秒内无新日志文件。Wi-Fi 保持连接（SSID 9529，866 Mbps）。
- 厂商 `android.hardware.wifi-service-lazy`、`wlan_assistant`、
  `tcpdump-vendor` 的字符串中均未发现上述三个 persist 属性名；本 ROM 上
  tcpdump 的关闭实际由模块的 `ctl.stop` + `pcap0` 目录保证，cnss_diag
  当前未运行，配置/属性未被厂商代码读取验证。
- `ksud module install` 将 v1.3 放入 `modules_update/`，当前运行目录仍是
  v1.2 加上 `update` 标记；重启后切换到 v1.3，`service.sh` 会在每次启动
  重新建立挂载、清理日志并停止 tcpdump。

## 32. SUSFS 最佳伪装配置（2026-11-22，真机）

**依据：OS4.0.4.0 OTA `boot.img` 内 stock kernel 字符串 + 设备指纹
`Redmi/dash/dash:17/CP2A.260605.016/OS4.0.4.0.XPLCNXM`。**

- 官方 stock 值（`strings /tmp/ub-boot/kernel`）：
  - release `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`
  - version `#1 SMP PREEMPT Mon Jul 20 11:15:20 UTC 2026`
- 原伪装是旧构建（`6.6.118-…gc44b714366cc-abogki519650608`，Jun 4），
  已替换为 OTA 4.0.4.0 的对应值。
- `ksu_susfs config`（持久化到 `/data/adb/ksu/.susfs.json`，ksud 在
  init_event 阶段应用）现在为：

  ```json
  {
    "enabled": true,
    "cmdline_or_bootconfig": "/data/adb/susfs_bootconfig.txt",
    "avc_log_spoofing": true,
    "logging": false,
    "hide_sus_mnts_for_non_su_procs": true,
    "uname": {
      "release": "6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k",
      "version": "#1 SMP PREEMPT Mon Jul 20 11:15:20 UTC 2026"
    },
    "sus_path": [], "sus_kstat": [], "open_redirect": [], "sus_map": []
  }
  ```

- `/proc/bootconfig` spoof 文件由官方 bootconfig 复制，仅把
  `vbmeta.device_state` 改为 `locked`、`verifiedbootstate` 改为 `green`
  （与 `getprop ro.boot.verifiedbootstate=green` 一致）。
- 实测：`uname -a` = 官方 release/version；`/proc/bootconfig` 显示
  green/locked；`enable_log 0`；AVC log spoofing 与 SUS mount 隐藏已开。
- 未添加 `sus_path`/`sus_kstat`/`open_redirect`/`sus_map` 条目：本机
  `/data/adb` 为 0700 root，普通 app 无法遍历，且没有需要重定向/隐藏的
  具体目标；乱加路径可能破坏 KSU 管理器或模块功能。
- 残留暴露（SUSFS 运行时不覆盖）：`/proc/version` 仍为
  `6.6.143-4k (dash@mikernel) … Nov 21 16:44:37 UTC 2026`；
  `/proc/config.gz` 仍是自编配置；`/proc/modules` 含非 stock 模块名。
  这些需要内核侧硬编码/stock defconfig 才能处理。
- 备份：旧配置在 `/tmp/susfs-backup.json`（主机），可用
  `ksu_susfs config restore` 恢复。

## 33. zram 消失 / Scene 附加模块失效排查（2026-11-22，真机）

**结论：不是内核或 zram 驱动丢失，是 Scene 附加模块在配置文件缺失时主动
`swapoff` 了 zram。**

### 证据链

- `zram0` 一直存在：`disksize=16 GiB`、`backing_dev=/dev/block/dm-71`；
  但 `/proc/swaps` 为空，`mm_stat` 只剩 4 KiB 原始数据。
- Scene 应用在 `2026-11-22 01:05:47` 更新到 `N1 2026.11 PreRelease 5`；
  其附加模块文件时间为 `01:24:31`（应用随更新重装模块）。
- 模块 `uninstall.sh` 第一段会 `rm -f /data/swap_config.conf`；模块重装后
  该文件一直缺失（`swap.xml` 最后写入 04:10，配置仍不存在）。
- `/cache/lmkd_opt.log`（04:12 一次模块运行）：

  ```text
  没有找到配置文件 /data/swap_config.conf
  等待解锁屏幕
  关闭ZRAM
  未配置ZRAM
  ```

- `startup.sh` 主逻辑：`$zram` 未定义时既不是 `"false"` 也不是 `"true"`，
  走 else 分支 → `wait_until_login; sleep 10; swapoff /dev/block/zram0`；
  随后 `set_zram` 因 `$zram != true` 只打印“未配置ZRAM”，不会重建 swap。
- 另有两类 SELinux 拒绝，属于 Scene app（`untrusted_app_34`）直接读
  `/sys/block/zram0`、`/proc/sys/vm/swappiness` 的正常限制，不是本内核
  新引入的策略问题。

### 处置

- 按 `swap.xml` 当前设置重建 `/data/swap_config.conf`（root 600）：
  `zram=false`、`zram_size=16384`、`comp_algorithm=zstd`、`swap=false`、
  `swap_priority=-2`、`swappiness=125`、`watermark_scale_factor=50`、
  `extra_free_kbytes=131072`。`zram=false` 时模块走“ZRAM将保持系统默认
  配置”，不再关闭厂商 ExtM 的 zram。
- 手动恢复 swap：`mkswap /dev/block/zram0` + `swapon -p 0`，当前
  `/proc/swaps` 为 zram0 16 GiB（priority 0），实测可用。
- 再次执行模块 `startup.sh` 验证：日志为
  `ZRAM将保持系统默认配置` / `未配置ZRAM`，swap 仍在，未再出现“关闭ZRAM”；
  `swappiness=125`、`watermark_scale_factor=50`、`extra_free_kbytes=131072`
  按 `swap.xml` 生效。

### lz4kd 补充（同日）

- 厂商 init 明确写死 `init.mt6991.rc:191 write /sys/block/zram0/comp_algorithm lz4`，
  所以重启后默认就是 `lz4`，并非 ExtM 自动恢复 `lz4kd`。
- 先前的 `lz4kd` 来自 Scene 模块旧配置的 `comp_algorithm`；`lz4kd` 不在
  zram 的可用算法探测列表里，但 vendor zram 在 disksize 为 0（reset 后）
  仍接受写入。实测 `hot_add` 的临时 zram 上 `echo lz4kd > comp_algorithm`
  成功，而 `lz4kd-scomp` 失败。
- 因此 `dash_art_tune` v1.4 增加 `apply_zram_lz4kd`：开机 `boot_completed`
  后，若 Scene 未接管 zram（配置缺失或 `zram=false`），则
  `swapoff → reset → comp_algorithm=lz4kd → 恢复 backing_dev/writeback_limit
  → disksize → mkswap → swapon`。若 Scene 配置为 `zram=true` 则跳过，尊重
  Scene 自己的算法选择。
- 实测模拟厂商默认 `lz4` 后执行模块 action：comp 变为 `[lz4kd]`、swap
  恢复为 16 GiB（priority -2）、`backing_dev=/dev/block/dm-71` 保留。
- 注意 Scene 应用会在其设置变化时重写 `/data/swap_config.conf`
  （04:27 一次写入把 `zram` 改回 `false`、`comp_algorithm=zstd`），因此
  以模块开机钩子作为最终保证；Scene 模块自动更新删配置的问题仍需
  在 Scene 内重新“应用”一次或避免自动更新。

### 重启后复核（2026-11-22 04:43，真机）

- Scene 配置现为 `zram=true` / `comp_algorithm=lz4kd` / `zram_writeback=default`；
  `dash_art_tune` v1.4 日志为 `zram: Scene-managed, skip lz4kd`（按设计让位），
  zram 实际 `[lz4kd]`，swap 16 GiB、priority 0。
- ExtM 回写正常：`Flush finished. Mode 2, flush 51209 pages ...`；
  `bd_writes` 持续增长，无 I/O error/SCSI/F2FS error。
- 内存：MemAvailable 3.6 GiB，PSI memory `full avg10≈1%`，无 OOM/LMK；
  swap 使用约 12.4 GiB 属当前多后台应用场景，压力指标不高。
- SUSFS 配置重启后仍生效：uname/bootconfig spoof、AVC log spoofing、
  SUS mount 隐藏、logging off；`/data/adb/ksu/.susfs.json` 保持。
- 模块 584 个；`zram`/`zsmalloc`/`node_cache`/`os_cpu_qi`/`mkp`/`cfg80211`
  均加载；`dash_art_tune` v1.4 已正式生效（无 `modules_update` 残留）。
- Wi-Fi 关闭是用户设置（`wifi_on=0`）；临时开启后成功连接 SSID `9529`
  （866 Mbps），随后恢复关闭。WLAN 日志目录仅 `tcpdump.pcap0/` 目录，
  `vendor_tcpdump` stopped，`cnss_diag.conf` bind mount 为 `LOG_PATH_FLAG=0`。
- UFS health `eol_info=0x01`、`life_time_estimation_a/b=0x01` 未变；
  电池 50%、35.4 °C、充电中。
- 仅见两条良性日志：`vold: open /sys/block/zram0/idle error:-1`（idle 为
  只写节点）、Scene 对 dm-71 `mkswap: xwrite: No such file or directory`
  （dm-swapfile 不接受该格式化，ExtM flush 不受影响）。

## 34. 实验性 perf 构建（DASH_PERF=1）：本地编译器行为验证（2026-11-22，构建级）

目标：在不破坏 584 个已加载厂商模块的前提下，做一版可选的全量性能构建。
CI 入口 `kernel-build` 新增 `perf` 布尔输入；`DASH_PERF=1` 合并
`configs/perf.fragment`，默认路径不受影响。

### 配置取舍

- 关闭仅影响内核自身 instrumentation、且没有 stock `.ko` 导入的项：
  `UBSAN`、`KFENCE`、`INIT_ON_ALLOC_DEFAULT_ON`、`INIT_STACK_ALL_ZERO`、
  `SLAB_FREELIST_HARDENED`。
- 保留（模块依赖其导出符号/ABI）：`KASAN`（34 个模块导入
  `kasan_flag_enabled`）、`FORTIFY_SOURCE`（217）、`HARDENED_USERCOPY`
  （156）、`LIST_HARDENED`（298）、`STACKPROTECTOR`（523）、
  `SHADOW_CALL_STACK`（x18）、`CFI_CLANG`（KCFI typeid）。
- KASAN 运行时默认改为 `KASAN_ARG_OFF`（保留 runtime 与导出符号），
  需要时仍可用命令行 `kasan=on` 覆盖；list.h 的内联检查在实验配置下
  直接返回 true，`lib/list_debug.c` 的导出函数保留。
- 打开未启用的 arm64 Crypto Extensions：SHA3、SM3/SM4 CE（含 BLK/CCM/GCM）、
  NH Poly1305 NEON、AES CCM。

### 编译器/链接器

- `KCFLAGS`（最后追加，覆盖内核通用 hardening flag）：
  `-march=armv9.2-a+nosve2+nosve+aes+sha2+sha3+sm4+fp16fml`、
  `-mbranch-protection=none`、`-fno-stack-protector`、
  `-fomit-frame-pointer -foptimize-sibling-calls`；无全局 `-O3`。
- `KBUILD_LDFLAGS`（仅 Full LTO）：`--lto-O3`、
  `-enable-ext-tsp-block-placement`、`-enable-split-machine-functions`、
  `-enable-mergeicmps`。

### 本地验证（非全编）

- `FAST=1 DASH_PERF=1` 实际 kbuild 编译 `mm/slub.o`、`kernel/fork.o`、
  `net/core/dev.o`、`fs/read_write.o`、`drivers/block/zram/zram_drv.o`、
  `crypto/lz4kd/lz4kd_encode.o`、`kernel/panic.o`、`lib/list_debug.o`、
  `lib/string_helpers.o`、`mm/usercopy.o`、`mm/kasan/hw_tags.o`：
  `ubsan=0`、`__stack_chk_fail` 引用=0、`paciasp=0`、`v/z/p` 寄存器=0、
  `__list_*_valid_or_report` 引用=0。
- 模块符号存在：`panic.o` 定义并导出 `__stack_chk_fail`；
  `list_debug.o` 导出两个 report 函数；`string_helpers.o` 导出
  `fortify_panic`；`usercopy.o` 导出 `__check_object_size`；
  `hw_tags.o` 仍导出 `kasan_flag_enabled`，`.data` 中 `kasan_arg=1`
  （`KASAN_ARG_OFF`）。
- `FAST=0 DASH_PERF=1` 配置确认 `CONFIG_LTO_CLANG_FULL=y`；
  `make -n vmlinux` 的命令行包含 `--lto-O3`、ext-TSP、MFS；
  独立 LTO 小样例验证 `ld.lld` 接受这些参数。

### CI Full LTO 结果（run 44985627545，commit `6665b50`）

- 工作流 `kernel-build`：`fast=false`、`perf=true`、`release=false`；
  成功，23 分 26 秒，未创建/更新 GitHub Release。
- `Image` 47,036,928 B、`Image.lz4` 23,155,441 B（限 67,098,176 B）；
  相比生产 `#1`：Image -647,168 B，Image.lz4 +346,647 B。
- `final-config` 与 `config` 一致：`CONFIG_DASH_PERF_EXPERIMENT=y`、
  `CONFIG_LTO_CLANG_FULL=y`、`UBSAN/KFENCE/SLAB_FREELIST_HARDENED/
  INIT_ON_ALLOC/INIT_STACK_ALL_ZERO` 均关；KASAN/FORTIFY/USERCOPY/
  LIST/STACKPROTECTOR/SCS/CFI 与新增 Crypto CE 均开。
- `check-vendor-modules.py`：`modules=638 kernel_exports=9111
  hard_missing=0 weak_missing=0`。
- `verify-os4-kcfi.py`：13/13 vendor-hook KCFI hash 与 stock 一致。
- vmlinux 符号：`__ubsan_*` 0 个；`__stack_chk_fail` 仍定义并导出，但
  `.text` 中无调用点；`kasan_flag_enabled`、`kasan_mode`、`fortify_panic`、
  `__check_object_size`、两个 list report 函数均导出。KASAN 初始化函数在
  vmlinux 中直接返回（默认 off）。
- 反汇编函数代码无 SVE/SME；`z/p` 正则在 `__kvm_nvhe_$d`/`__pi_$d`
  局部数据符号（literal pool）上命中，属数据误判。`paciasp` 仅 1 处，
  位于 `poly1305_blocks_neon` 汇编（`SYM_FUNC_START` 宏），C 代码已无 PAC。
- MFS pass 已被 LLD 调度（小样例可见 Machine Function Splitter），但
  最终 vmlinux 没有 `.text.unlikely`，本次 profile 未产生实际冷块拆分。
- 构建日志 0 error；2 条 host 工具 `sorttable.c` 未使用变量 warning。

## 35. 非 CPU 硬件加速实机调查（2026-11-22，生产内核 + adb root）

当前实机仍运行生产内核 `6.6.143-4k #1`（SUSFS 伪装 6.6.118），不是本轮实验
内核。调查来源：`/sys/firmware/fdt`、`/proc/config.gz`、`/proc/modules`、
`/proc/crypto`、`/proc/devices`、`/sys/class/*`、`/dev`、`dmesg`。

### 已启用的非 CPU 加速器

- GPU：`mali_kbase_mt6991_r49`、`mali_mgm`、`mali_prot_alloc`、
  `mtk_gpufreq_wrapper`/`mtk_gpueb`；`/dev/mali0`；
  `devfreq/48000000.mali` 最高 1.612 GHz（空闲 26 MHz）。
- NPU/APU：`apusys`、`apu_top`、`apu_aov`、`sapu`；`/dev/apusys`、
  `/dev/apusys_sapu`；dmesg 有 APU power/IPI 活动。
- Camera/ISP：`mtk_cam_isp8`、`mtk_imgsys_isp8`、`imgsensor_isp8`、
  `seninf`、`camsv`、`mraw`；dmesg 有 ISP/CSI 活动。
- Video：`mtk_vcodec_dec_v2`、`mtk_vcodec_enc_v2`、`vdec_fmt`、
  `mtk_jpeg`/`jpeg_driver`；`/dev/video*`，dmesg 有 VDEC 解码活动。
- Display：`mediatek_drm`、`mtk_disp_sec`、`mdp_drv_mt6991`、
  `mtk_vdisp_v2`、`mtk_disp_notify`；`/dev/dri/card0`，DSI-1 connected，
  DP-1 connector 存在（当前 disconnected），`usb-dp-selector` 已加载。
- Audio DSP：`adsp`、`adsp_v2`、`audio_ipi`、`mtk_afe_external`、
  `snd_soc_mtk_scp_ultra`；`/dev/adsp`、`/dev/snd`。
- SCP/SSPM/MCUPM：`scp`、`sspm_v3`、`mcupm`、`mtk_scp_ultra`、
  `mtk_tinysys_ipi`。
- TEE/虚拟化：`mitee`、`gz_*`、`gzvm`；`/sys/class/tee/tee0`、
  `teepriv0`；`ro.vendor.mtk_svp_on_mtee_support=1`。
- UFS：`phy_mtk_ufs`、`ufs_mediatek_mod_ise`、`ufs_mediatek_dbg`、
  `rpmb`；`queue/crypto/max_dun_bits=64`、`num_keyslots=32`
  （inline encryption 已启用）；`devfreq/16810000.ufshci` 273/499.2 MHz。
- Crypto：`/proc/crypto` 显示 `aes-ce`、`sha1/256/512-ce`、
  `gcm-aes-ce`、`polyval-ce`、`poly1305-neon`、`chacha20-neon`。
- RNG：`/dev/hw_random`（prng_seeder）、`cctrng`、
  `CONFIG_HW_RANDOM_ARM_SMCCC_TRNG=y`。
- PMU：`armv8_pmuv3`、`armv9_cortex_a720`、`armv9_cortex_x4`、
  `arm_dsu_0`，以及 SMMU MPAM/PMCG event sources。
- DMA/IOMMU：4 个 SMMU、12 个 APDMA 通道、CMDQ 模块。
- 连接/外设：`wlan_drv_gen4m_6991_6639_new9gen2`、`bluetooth`、
  `btmtk_uart_unify`、`conninfra`、`connscp`、`gps_scp`/`gps_pwr`、
  `nfc`（`nfc.initialized=true`）、`ccci_*` 调制解调器通道。
- 安全视频：`mtee-svp`/`SecureVideoPath`、`mm-smmu-svp-disp` 均 okay；
  `/dev/dma_heap` 有 `mtk_svp_page-uncached`、`mtk_prot_region`、
  `mtk_tui_region` 等。

### 未启用/受限项

- **SHA3/SM3/SM4/NH Poly1305/AES-CCM**：生产 `/proc/crypto` 只有
  `sha3-*-generic`（priority 0）、`nhpoly1305-generic`，没有 SM3/SM4；
  实验配置已启用对应 ARM64 CE/NEON 实现。
- **Coresight/ETM/STM**：DT 有 `funnel@d041000`、`etf@d044000`、
  `etr@d07d000` 与 dummy source，但 `CONFIG_CORESIGHT=n`、`CONFIG_STM=n`；
  且没有 CPU ETM4x/STM 节点，开启只能覆盖 TMC/funnel/dummy，profiling
  价值低，未启用。
- **SPE**：`/proc/cpuinfo` 无 `spe`，`CONFIG_ARM_SPE_PMU=n`，硬件/固件
  不暴露，无法启用。
- **MTE**：`/proc/cpuinfo` 无 `mte`，KASAN HW_TAGS 在这台机器上不会激活；
  实验配置保留 KASAN runtime 符号但没有实际 MTE 开销。
- **UFS WriteBooster/HPB**：`/sys/block/sda/device` 未暴露 `wb_*`/`hpb_*`，
  `cdl_supported=0`、`dyn_cap_needed_attribute=0`；属设备/固件/vendor 驱动
  范畴，内核侧没有可切换开关。
- **pKVM**：DT `/pkvm` 为 disable；GenieZone `/hypervisor` okay，
  `gzvm`/`mitee` 已加载，因此不是缺失，只是换了 hypervisor 方案。
- **DT 明确关闭的接口**：USB1/2、外部 PCIe、MMC、Ethernet、
  eDP/DSI1/2、camfe、fan-cooler、IVI、UFCS、`vhost-*`。这些是硬件未
  布线/未使用或虚拟化用途，不建议仅凭 DT 打开。
- **可选但无消费者**：`CRCT10DIF_ARM64_CE`（T10 DIF 未启用）、
  `AEGIS128_SIMD`（AEGIS 未启用）；未加入实验配置。
- **硬件压缩**：未发现内核可见的压缩加速器节点；zram 仍为软件
  `lz4kd`，没有可打开的硬件压缩开关。

结论：GPU/NPU/ISP/VPU/JPEG/VDEC/VENC/ADSP/SCP/TEE/UFS inline crypto
等主要加速器都由 MediaTek 厂商模块提供并已加载；没有发现因内核配置缺失
而整体不可用的高价值加速器。实验内核相对生产内核新增的硬件加速主要是
SHA3/SM3/SM4/NH Poly1305/AES-CCM CE。

## 36. CPU 特性与 HWCAP 实机核对（2026-11-22，生产内核）

- 8 个核的 Features 完全相同；MIDR part 为 4×`0xd81`、3×`0xd82`、
  1×`0xd85`，不存在异构特性差异，`-march=armv9.2-a` 对全部核心一致。
- userspace HWCAP：`0xefffffff`；HWCAP2：`0x801af3ff`。
- HWCAP 已置位：FP/ASIMD/EVTSTRM/AES/PMULL/SHA1/SHA2/CRC32/ATOMICS/
  FPHP/ASIMDHP/CPUID/ASIMDRDM/JSCVT/FCMA/LRCPC/DCPOP/SHA3/SM3/SM4/
  ASIMDDP/SHA512/SVE/ASIMDFHM/DIT/USCAT/ILRCPC/FLAGM/SB/PACA/PACG；
  仅 **SSBS** 未置位（硬件 Features 同样没有 ssbs）。
- HWCAP2 已置位：DCPODP/SVE2/SVEAES/SVEPMULL/SVEBITPERM/SVESHA3/
  SVESM4/FLAGM2/FRINT/SVEI8MM/SVEBF16/I8MM/BF16/DGH/BTI/ECV/AFP/WFXT。
- HWCAP2 未置位：RNG、MTE、SME/SME2 系列、CSSC、RPRFM、SVE2P1、
  MOPS、HBC、EBF16/SVE_EBF16 等。这些与 `/proc/cpuinfo` 的缺失一致，
  属于硬件不提供，不是内核隐藏。
- 内核配置：`ARM64_SVE=y`、`ARM64_MTE=y`、`ARM64_PTR_AUTH(_KERNEL)=y`、
  `ARM64_BTI=y`、`ARM64_USE_LSE_ATOMICS=y`、`ARM64_AMU_EXTN=y`、
  `ARM64_RAS_EXTN=y`、`ARM_PMUV3=y`、`HW_PERF_EVENTS=y`。
- 注意：`CONFIG_ARM64_MTE=y` 但 HWCAP2_MTE 未置位，KASAN HW_TAGS 在
  本机不会激活；`CONFIG_ARM64_BTI_KERNEL` 未开，userspace BTI 可用但内核
  自身没有 BTI；生产内核有 kernel PAC，实验内核用 `-mbranch-protection=none`
  主动关闭了 C 代码 PAC（userspace PACA/PACG 不受影响）。
- 实验内核的 `-march=...+nosve2+nosve` 只影响内核 C codegen；SVE/SVE2
  对 userspace 仍由 HWCAP 暴露，内核本来也不使用 SVE。
- 加速/监控：cpufreq `sugov_ext` 活跃；available 最高
  CPU0 2.4 GHz / CPU4 3.3 GHz / CPU7 3.73 GHz，但当前 policy 上限为
  1.4/1.9/2.0 GHz（厂商 thermal/power 策略，当前电量 34%），不是内核
  未启用；cpuidle 6 个状态；PMU event sources 有 `armv8_pmuv3`、
  `armv9_cortex_a720`、`armv9_cortex_x4`、`arm_dsu_0` 和 SMMU
  MPAM/PMCG。主线的 `ARM_DSU_PMU`/`ARM_SMMU_V3_PMU` 配置虽为 n，但
  厂商模块已注册对应 event source，不算缺失。
- 未启用/不可用：`ARM_SPE_PMU=n` 且硬件无 `spe`；Coresight 只有
  funnel/TMC/dummy、无 CPU ETM/STM 且 `CONFIG_CORESIGHT=n`；CPU MPAM
  未见；RNDR 指令未暴露（硬件 RNG 由 CCTRNG/SMCCC TRNG 提供）。
- 安全侧提示：`spectre_v2` 当前为 “Vulnerable: Unprivileged eBPF enabled”，
  属内核安全配置，不是性能加速缺失。

结论：**userspace 可见的 CPU 特性与硬件一致，没有发现被内核配置隐藏的
CPU 加速能力**；内核侧 LSE/CRC/Crypto CE/PMU 均已启用。剩余差异是硬件
本身没有的 SPE/MTE/SME/CSSC 等，以及有意取舍的 kernel BTI、实验内核
kernel PAC 和 Coresight。

## 37. AnyKernel3 v1.2 刷入中止排查与 kernel-only 修复（2026-11-22，真机只读）

**结论：用户设备没有被写入；AnyKernel3 在 `unpack_ramdisk()` 就 abort 了，
`write_boot()` 从未执行。根因是 dash boot 为 `ramdisk_size=0`，而标准
AnyKernel3 要求 boot 内有 ramdisk。**

### 现场日志

第三方用户用 Release 的 `dash_art_tune-ak3-v1.2.zip` 刷入，AnyKernel3 输出：

```text
Parsing boot image: [/data/user/0/.../AnyKernel3/boot.img]
HEADER_VER      [4]
KERNEL_SZ       [17317780]
RAMDISK_SZ      [0]
KERNEL_FMT      [lz4_legacy]
No ramdisk found to unpack. Aborting...
```

- `64+0 records` 是把 `boot_a` 读出 64MiB 的只读 dd；`split_boot` 成功。
- abort 在 `ak3-core.sh:160`（`unpack_ramdisk`），位于 `dump_boot()` 内；
  `write_boot()`（repack + `cat boot-new.img /dev/zero > $BLOCK`）未执行，
  KSU 模块安装也在 `write_boot()` 之后，同样未执行。
- `KERNEL_SZ=17,317,780` 与原厂 boot 的 kernel 大小完全一致（本机
  `device-backup/boot_b.img`），说明该设备仍是原厂 boot，这是首次安装。
- `unexpected ASN.1 DER tag` 与 `VBMETA` 是 magiskboot 解析 AVB 的正常输出，
  不是失败原因。

### 修复

`dash/ak3/anykernel.sh` 改为先 `split_boot`，再按 `$SPLITIMG/ramdisk.cpio`
是否存在分支：有 ramdisk 走 `unpack_ramdisk` + `write_boot`；没有则直接
`flash_boot` 只替换 kernel。该写法与 `third_party/dash-droidspaces` 中已在
dash 实机验证过的 AnyKernel3 模板一致。

### 只读验证（未写分区）

在设备上用 Release 包内同源的
`third_party/sukisu-patch/AnyKernel3/tools/magiskboot`（770,632 B；用户日志里的
`unexpected ASN.1 DER tag` 即该版本输出）对原厂 boot 执行 `unpack`，把
`kernel` 换成自编 `Image` 后 `repack`：

- 输出 64MiB，`HEADER_VER 4` / `KERNEL_SZ 17,905,953` / `RAMDISK_SZ 0`；
  kernel 与 `out/artifacts/Image.lz4` 字节完全一致。
- 原厂 vbmeta 字节不变（sha256 `67fc0027…`），footer
  `original_image_size == vbmeta_offset == 0x1115000`，与 `repack-boot.py`
  生成的生产 boot 布局（`0x15c2000`、同一 vbmeta）一致。
- 因此 `split_boot` + `flash_boot` 的产物与本机可开机的生产 boot 结构等价；
  仍需一次真机刷入确认才可称为启动验证。

### 发布命名

Release 的安装包统一写全称 `AnyKernel3`（例如
`dash_art_tune-AnyKernel3-<ver>.zip`），不再缩写为 AK3。

## 38. DASH_PERF 改标准 Full LTO：NoLTO/Full LTO 双双实机启动（2026-11-22，真机）

**结论：移除 `--lto-O3`/ext-TSP/MFS/mergeicmps 后，标准 Full LTO 的 DASH_PERF
内核可以正常启动；此前 Full LTO 的 BPF 加载失败和 mtk_mbraink 崩溃都不再出现。**

### 构建与产物

- CI run `45000486463`（commit `ebfc285`，`fast=false, perf=true,
  release=false`），23m14s。
- `arch/arm64/Makefile` 的 perf LDFLAGS 已全部移除；`build-inputs.tar.gz`
  内补丁对 `lto-O3|ext-tsp|split-machine|mergeicmps` 的匹配数为 0。
- `final-config`：`CONFIG_LTO_CLANG_FULL=y`、`CONFIG_DASH_PERF_EXPERIMENT=y`。
- `Image` 45,857,280 B；`Image.lz4` 22,288,250 B（sha256 `53120fd3…`），
  远低于 67,098,176 B 上限。
- 封装 boot：以生产 `boot_a` 备份（`d0cdd6ad…`）为底，kernel 字节与
  `Image.lz4` 一致，vbmeta 字节不变，footer 仍为
  `original_image_size=vbmeta_offset=0x15c2000`；boot 镜像 sha256
  `221cad2d…`。

### 实机启动

- adb 18s 上线，`sys.boot_completed=1`（14s），`bootanim=stopped`。
- `bpfloader` 正常结束（`init.svc.bpfloader=stopped`），logcat 只有良性的
  `taskRename.bpf` 不存在提示，**没有**之前的
  `schedcls_tether_downstream6_ether` EINVAL / CRITICAL FAILURE。
- `mtk_mbraink` 在 23.15s 正常打印 feature enable，未再触发
  `freq_qos_min_notifier_call+0x114` 的 NULL deref（帧指针修复在标准 Full
  LTO 下同样有效）。
- 585 个模块加载；218s 后仍稳定；严格匹配
  `Unable to handle kernel|Internal error:|Kernel panic|Oops:` 无结果；
  KASAN/KFENCE 无运行期输出。

### 新启用特性复核

- 同配置下 `/proc/crypto` 已注册并优先使用 CE 实现：`sm3-ce`(400)、
  `sm4-ce`(300) 及 ecb/cbc/ctr/cfb/cts/xts/cmac 系列(400)、
  `ccm(sm4)`/`gcm(sm4)`(400)、`sha3-*`(200，generic 0)、
  `nhpoly1305-neon`(200，generic 100)、`ccm(aes)`/`gcm(aes)`(300)、
  `aes-ce`(250，generic 100)。
- `# CONFIG_UBSAN is not set`、`# CONFIG_KFENCE is not set`、
  `# CONFIG_INIT_ON_ALLOC_DEFAULT_ON is not set`、
  `# CONFIG_SLAB_FREELIST_HARDENED is not set`、`CONFIG_INIT_STACK_NONE=y`；
  厂商模块依赖的 KASAN/FORTIFY/USERCOPY/LIST/STACKPROTECTOR/SCS/CFI 仍为 y；
  `CONFIG_FRAME_POINTER=y`。

### 发布包命名

- `dash_art_tune-AnyKernel3-v1.4.zip`（sha256 `f25b24fc…`）。
- `dash_art_tune-v1.4.zip` 内 `module.prop`：`name=内核附加模块`，说明为简体中文。
- 本轮 CI `release=false`；随后手动发布为 `dash-6.6.143-prod`，见 §39。

## 39. 实验收尾：生产发布、NoMount 重置与教训（2026-11-22，真机）

### 生产发布

- `dash-6.6.143-prod` tag 已移到 `ebfc285`；Release 标题改为
  「dash 6.6.143 生产版」，正文写明 AnyKernel3/fastboot 两种刷入方法。
- 资产：`Image` 45,857,280 B、`Image.lz4` 22,288,250 B
  （sha256 `53120fd3…`）、`dash_art_tune-AnyKernel3-v1.4.zip`
  （`f25b24fc…`）、`dash_art_tune-v1.4.zip`（`2f5ad5e6…`）、`SHA256SUMS`。
- 旧的 `dash_art_tune-ak3-v1.2.zip` / `dash_art_tune-v1.2.zip` 已从生产
  Release 移除，避免继续下载到会 abort 的旧安装包。

### NoMount 旧状态重置

- 设备上的 NoMount 模块曾显示 `description=[🚨 Bootloop Prevented] ...`，且
  `/data/adb/nomount/disable` 存在。原因是实验内核阶段的非正常重启触发了
  NoMount 自带的 `bootloop_check()`。
- 已恢复 upstream 描述
  `A metamodule that replaces OverlayFS/MagicMount with VFS path redirection.`，
  删除 `/data/adb/nomount/disable`，未动其 `boot-completed.sh`/LKM 逻辑。
- 重启后 dmesg 显示 `nomount: Injection completed` 与
  `nomount: boot completed safely.`，模块 API 工作正常，未再次 disable。

### 设备与模块收尾

- 用 `ksud module install` 安装新 `dash_art_tune-v1.4.zip`；重启后
  `/data/adb/modules/dash_art_tune/module.prop` 显示
  `name=内核附加模块`，`modules_update` 已清空。
- 当前设备：生产 DASH_PERF 标准 Full LTO 内核，585 模块，`bpfloader`
  正常，无 Oops/panic；bbr3/ADIOS/lz4kd 正常；KSU root 正常。

### 教训

1. **AnyKernel3 不能直接用于 ramdisk-less boot**：`dump_boot()` 会无条件
   `unpack_ramdisk()` 并 abort。必须先 `split_boot`，按
   `split_img/ramdisk.cpio` 是否存在分支；没有 ramdisk 时直接 `flash_boot`。
2. **不要覆盖内核的 `-fno-omit-frame-pointer` / `-fno-optimize-sibling-calls`**：
   厂商模块（`mtk_mbraink`）会用 x29 帧链取返回地址，核心函数省略帧指针会
   让模块 NULL deref。
3. **自定义 LTO flags 会破坏 Full LTO 的 BPF 加载**：`--lto-O3`/ext-TSP/MFS/
   mergeicmps 组合下 `schedcls_tether_downstream6_ether` 返回 EINVAL；标准
   Full LTO 正常。
4. **NoLTO + AutoFDO 存在编译器病态**：clang r614150 的
   `llvm::applyFlowInference` 在 `mm/swap.c` 上长时间不收敛；用 kbuild 的
   per-file `AUTOFDO_PROFILE_swap.o=n` 只关闭该文件。
5. **分支与命名**：实验结果及时合回 `main`，不长期保留多分支；发布包写
   `AnyKernel3` 全称，模块显示名与说明使用简体中文。
6. **第三方 bootloop 保护会留下状态**：实验内核非正常重启会让 NoMount 自行
   disable 并改描述；恢复稳定后要清理 `disable` 标记并还原描述。

## 40. 跟随 android15-6.6 分支：6.6.144 重基线 + NoLTO 构建（2026-11-24，构建级）

### 目标与结果

2026-11-24 按要求把仓库从固定发布 tag 改为跟随 AOSP `android15-6.6`
开发分支，同步全部源码/子模块/工具链，并在新基线上完成 NoLTO 全量构建。
**未刷机**，未发布 artifacts（产物隔离在 `dash/out/dash/`）。

### 上游版本判定

- `android.googlesource.com` 直连仍不可达；GitLab/GitHub 在该网络下也曾
  长时间不可用，后恢复。
- 同一时刻各镜像的分支头不一致，必须比对后取最新：
  - TUNA `a5c942b8c`（2026-11-23，`Merge tag 'android15-6.6.144_r01'`）→ 采用
  - USTC `9347319`（2026-11-21）→ 落后
  - BFSU `9e7deb2`（2026-11-18）→ 更旧
  - 发布 tag 仍为 `android15-6.6-2026-10_r4`（6.6.143），没有 2026-11 发布
- `versions.env` 改为 `AOSP_BRANCH=android15-6.6` + `AOSP_COMMIT=a5c942b8c`；
  `AOSP_UPDATE=1 make source` 刷新 pin，`AOSP_PIN=1` 冻结。镜像顺序改为
  TUNA → USTC → 上游。
- AutoFDO profile 随 6.6.144 更新，`ACK_AUTOFDO_PROFILE_SHA256` 改为
  `2aa4fc6e…`。

### 子模块与工具链

| 组件 | 同步结果 |
|---|---|
| BakaSU | `de80463`（main 最新，含 SELinux sid 回归修复） |
| SUSFS | `f98f082`（官方 GitLab `gki-android15-6.6` 分支头，与 pin 相同） |
| NoMount | `6849f00`（master 最新，虚拟 backing path 修复） |
| tcp-brutal | `d2397ff`（master 头，未变） |
| clang | r614150 版本未变，但同版本目录内容更新：刷新到 `main-kernel`
  `74fa19d5` 的 tree `9258d46`（build 16836431） |

### 补丁重放与适配

- 30 个补丁在 `a5c942b8c` 上重放；唯一冲突为 `fs/f2fs/super.c`：
  上游新增挂载选项 `Opt_resizable_tail_secno`，与 dash `Opt_hybrid` 同位置，
  两者并存解决。
- **BakaSU 新版链接失败（重要）**：新版把 `my_write_context/my_write_access/
  my_setprocattr` 改成 static 并改用 `ksu_patch_text` 运行时 auto hook；
  `susfs_compat.mk` 通过 grep `hooks.c` 里的 `ksu_selinux_hide_running` 判断
  是否存在“手动 hook”。旧 AOSP 侧集成仍在，触发手动 hook 分支却引用已不存在的
  符号，`vmlinux` 链接报 undefined。解决：回退我们新增的
  `security/selinux/hooks.c` / `selinuxfs.c` 改动（保留 `avc.c` 的 SUSFS
  AVC 日志伪装），让 BakaSU 走 auto hook；映射表同步移除这两个文件，补丁
  文件数 145→143。
- **ADIOS 更新**：EVONIX 自调查快照 `3aca65c` 后新增 3 个 ADIOS 修复
  （starvation recovery、Tier-1 计数并发、pq1 reset 的 `pq_lock`），取
  `901a0cf` 的 `block/adios.c` 全量替换（diff 仅 5 处，均在 dispatch 路径）。
- 参考仓库其余检查：WK-P `70c394f`、GKID `ef6c99d` 与快照相同；WK BBRv3
  15-6.6 补丁最后更新于 2026-06-24；`lakitu12/kernel_dash_droidspaces` 新提交
  主要是 ACK 2026-10_r3 迁移、CI/docs、trusty-rescue 与资源限制探针关闭，
  其 hook export 结论与我们现有 decl-only TU 方案一致，无需采纳。

### 构建结果

- `FAST=1`（NoLTO）+ AutoFDO + MLGO + A720 tune，**4m17s**，exit 0，
  `warning:` 计数 0。
- 版本 `6.6.144-4k`。
- `Image` 38,943,232 B，SHA256
  `589643bf0faf46489528f0ae52d0430334622f8be990adb04fe7bfbeb731c4b0`。
- `Image.lz4` 18,395,427 B，SHA256
  `47b2cbcd8a5d41cba4b59d6db9cf30f4bd293da6b157bb8e89c2ba9e934ee046`。
- `vmlinux` 181,397,160 B；`vmlinux.symvers` 550K、9112 个导出符号。
- OS4 KCFI：13/13 原型哈希与 stock 一致。
- 厂商模块静态核对：638 个模块，`hard_missing=0 weak_missing=0`。
- `.config`：`CONFIG_LTO_NONE=y`、`CONFIG_AUTOFDO_CLANG=y`、
  `CONFIG_DASH_MLGO_REGALLOC=y`、`CONFIG_DASH_ARM64_TUNE_A720=y`。

### 教训

1. 国内镜像不是同一时刻的快照：跟随移动分支时必须比对多个镜像的 head，
   并记录 commit；本次 TUNA 比 USTC/BFSU 新 1–5 天。
2. 分支跟随后 AutoFDO profile 与代码一起变化，profile 哈希必须同步更新，
   否则 configure 会按设计拒绝构建。
3. 子模块升级不是“只换 SHA”：BakaSU 移除手动 hook 导出后，AOSP 侧旧调用
   会造成 vmlinux 链接失败；升级后要按上游 compat 探测逻辑重新确认 hook 归属。
4. NoLTO 构建快但依赖增量对象；出现链接错误时应先 `grep undefined symbol`
   定位类别，不要直接全量重编。

### 40.1 同日后补：EVONIX stable 回移与运行时能力（未重编）

- **回移来源**：EVONIX `hyperos/ksu-susfs`（tip `901a0cf`，基于 6.6.144）。
  逐补丁 `git apply --check` 后按上游时序合并：
  - UDP：`efef513`（tunnel segmentation UAF）
  - IPv6：`180b3a5`（`ipv6_find_hdr()` 越界）、`5780267`（`SEG6_ATTR_DST`
    长度）、`9ff62f1`（`skb_checksum_setup_ipv6()` pull 下溢）
  - DAMON：`a65fe34/eaf86c5/8b524b6/06a6377/c38ab6f/783936f/bc5352d/79e82f4`
    （另有 `74d90fa/c0ead64/fa02385` 已被 6.6.144 基线收录）
  - writeback：`3bfa5fe/5a4d6f3/a5c927f/8384a54/c9c6c96`，ext4
    writeback `6bebd13`；TLB `b6bb0e7` 已被 6.6.144 基线收录。
  - 18 个补丁按序全部 clean apply；新增 `180-stable-backports`（5 个补丁、
    13 个文件），总序列 35 补丁/156 文件，干净重放通过。
- **KMI 处理**：writeback 组新增 `bdi_writeback.switch_work/switch_wbs_ctxs`。
  为尽量不移动既有字段，两个字段已从 `offline_node` 后移到既有 union 之后
  （既有命名字段偏移不变，仍记 KMI 观察项）。
- **ADIOS IO_PRIO**：补上 EVONIX Kconfig（`config EVONIX_IO_PRIO`，default y）
  并在 `features.fragment` 设 `=y`；同日按机主要求把 ADIOS、BBR3、fq 设为内核默认（`MQ_IOSCHED_DEFAULT_ADIOS=y`、`CONFIG_DEFAULT_TCP_CONG="bbr3"`、`CONFIG_DEFAULT_NET_SCH="fq"`），附加模块改为检测到已是默认值时跳过。
- **默认策略**：ADIOS（`MQ_IOSCHED_DEFAULT_ADIOS`）、BBR3
  （`DEFAULT_TCP_CONG="bbr3"`）、fq（`DEFAULT_NET_SCH="fq"`）、
  zram lz4kd（`ZRAM_DEF_COMP_LZ4KD`）设为默认；附加模块检测到已生效时跳过。
  sing-box 的 TUN/TPROXY/mangle/策略路由/BPF/tc/WireGuard 原本具备；
  **nftables 按机主要求未引入**。
- **运行时配置**：新增并经 `make config FAST=1` olddefconfig 验证为 `=y`：
  `SECURITY_LANDLOCK`（ABI v3）、`RSEQ`、`HUGETLBFS`/`CGROUP_HUGETLB`、
  `CGROUP_DEVICE`、`VXLAN`、`VHOST_NET`。
  **按机主要求回退**：`NF_TABLES`/`NFT_*` 与 `BRIDGE_NETFILTER` 保持关闭
  （Docker 仅走 iptables-legacy；sing-box 走 xt/TPROXY 或 TUN）。
  `CFS_BANDWIDTH`/`CGROUP_PIDS` 保持关闭。
- **AFDO 核对**：AOSP dev tip `a5c942b8c` 的
  `android/gki/aarch64/afdo/kernel.afdo` blob 与 afdo 更新提交 `9347319`
  完全相同（`415d6c49…`），即 6.6.144 最新预制 profile；本地 SHA256
  `2aa4fc6e…` 已是该文件，无需更换。
- **Re:Kernel**：官方支持 GKI 6.6.x（LKM 11.5），本内核已具备
  `MODULES/BTF/BPF_SYSCALL/kprobes/netfilter` 与 vendor-ko-compat，可直接
  加载其 LKM 或 eBPF 变体；不内建（其初始化/Netlink 服务属于外部模块）。
- **状态**：以上均**未编译、未刷机**；现有 `out/dash` 产物对应较早的
  30 补丁配置。

## 41. 6.6.144 花屏重启定位：原厂 ABI 对齐（2026-11-24，真机）

### 现象

6.6.144 基线上的四个构建全部“花屏后重启、无启动动画”：CI `7391add`
（35 补丁 + 新运行时配置）、`test-noadios`（关闭 ADIOS 默认与 IO_PRIO）、
`fix-rseq`（关闭 RSEQ）、`no-wb`（再摘除 writeback 回移 0004）。而同一
6.6.144 基线的 30 补丁、旧配置对照构建可正常启动，pstore/ramoops 无记录
（更像看门狗复位而非 panic）。

### 方法：直接读工厂镜像的 BTF

`/storage/emulated/0/Download/boot.img`（原厂，SHA256
`f8f0de691b66b22f45ed102b88416267b327841a4267c88a562788d5f39f2b3c`）解出
arm64 Image 后，在偏移 `24222976` 找到唯一一段 BTF（6,127,622 B，SHA256
`5cf08b333a9e4e20b15b67e104d815c5b290417f6b02863c27290aaff931f8b2`），
按 BTF 规范解析出原厂结构布局；各次构建的 `vmlinux` 用 `pahole`/BTF 对照。

原厂关键值：

| 项 | 原厂 |
|---|---|
| `task_struct` | 4800 |
| `android_vendor_data1` 偏移 | 3008 |
| `android_oem_data1` 偏移 | 3520 |
| `cgroup` | 1920（7 个控制器） |
| `bdi_writeback` / `backing_dev_info` | 904 / 1336 |

### 两处 ABI 破坏

1. **`CONFIG_RSEQ`（连带 `SCHED_MM_CID`）**：`task_struct` 4800→4864、
   vendor data 3008→3064、OEM data 3520→3576。`mi_game.ko`
   `__get_mi_task_struct` 反汇编显示硬编码 `task+0xdc0`(3520) 写 magic、
   `task+0xdc8` 存指针（正是 OEM data 槽），偏移漂移后会写进内核 vendor
   data 尾部。
2. **`CONFIG_CGROUP_DEVICE` + `CONFIG_CGROUP_HUGETLB`**：`cgroup`
   1920→1984，且 `enum cgroup_subsys_id` 编号变化。原厂 7 个控制器为
   `cpuset0 / cpu1 / cpuacct2 / io3 / memory4 / freezer5 / net_prio6`；
   `devices` 插在 `memory` 之后、`hugetlb` 在 `net_prio` 之后，导致
   `freezer` 5→6、`net_prio` 6→7。厂商预编译模块用 stock 常量做
   `task_css(task, freezer_cgrp_id)` 之类的内联访问时会拿到错误的
   `cgroup_subsys_state`。

### 二分结果（每次一个变量）

| 变体 | 与对照的差异 | 结果 |
|---|---|---|
| `out/dash` 对照 | 30 补丁、旧配置 | **正常启动** |
| `out/fix-rseq` | +回移、+新配置，关 RSEQ | 花屏重启 |
| `out/no-wb` | 同上去掉 writeback 回移 0004 | 花屏重启 |
| `out/no-cg` | 再关 `CGROUP_DEVICE`/`CGROUP_HUGETLB` | **正常启动** |

`no-cg` 的六项 ABI 全部与原厂一致（`task_struct` 4800 / vendor 3008 /
OEM 3520 / `cgroup` 1920 / `bdi_writeback` 904 / `backing_dev_info` 1336），
实机正常开机。结论：**根因是配置把原厂 ABI 改坏，且以 cgroup 子系统编号
为主**；`CONFIG_RSEQ` 同时修掉（它是真实的 task_struct 破坏，只是不是本轮
唯一原因）。

### 处置

- 保持关闭：`CONFIG_RSEQ`、`CONFIG_SCHED_MM_CID`、`CONFIG_CGROUP_DEVICE`、
  `CONFIG_CGROUP_HUGETLB`。相应地从 `features.fragment` 与 `configure.sh`
  的 required 列表移除。
- writeback 回移 0004 暂不启用：它会让 `bdi_writeback` 904→960、
  `backing_dev_info` 1336→1392，与“ABI 对齐原厂”冲突；除该补丁外的
  UDP/IPv6/DAMON/ext4 回移保留（当前序列 34 补丁）。
- 新增门禁：`dash/scripts/check-abi.py` + `dash/configs/abi-baseline.json`，
  `build.sh` 在生成 `Image.lz4` 后自动运行；`task_struct`（大小、vendor
  data、OEM data）、`cgroup`、`bdi_writeback`、`backing_dev_info` 为硬门禁，
  `kmem_cache` 为软观察项。

### 生产构建的性能开关（机主要求）

关闭：`UBSAN`、`UBSAN_TRAP`、`INIT_ON_ALLOC_DEFAULT_ON`、`KFENCE`（含
`KFENCE_DEFERRABLE` 要求从 configure 移除）、`SLAB_FREELIST_HARDENED`、
`SLUB_DEBUG`。代价是失去这些运行期检测/加固，热路径少掉分支与额外清零；
`kmem_cache` 布局会因 `SLAB_FREELIST_HARDENED`/`SLUB_DEBUG` 关闭而变小，
记入软门禁观察（厂商模块只持有 `kmem_cache` 指针）。

### 教训

1. 任何“看起来只是开个功能”的配置都要先跑 ABI 门禁：`task_struct` 字段、
   cgroup 控制器数量都会直接破坏预编译厂商模块。
2. 原厂 ABI 必须从工厂镜像自身取，而不是“用 stock.config 重建一个”：
   BTF 布局还受编译器/补丁影响。
3. 花屏+看门狗复位且 pstore 为空时，优先按 ABI 破坏/早期死锁排查，
   二分时要保证每次只动一组变量。

### 41.1 生产构建与实机验证（2026-11-24）

按机主要求用生产全优化配方本地构建并刷机：

- 配方：`LTO_CLANG_FULL` + MLGO regalloc advisor + ACK 预制 AutoFDO +
  A720 tune；34 补丁（writeback 0004 仍禁用）；ABI 对齐原厂的配置。
- 构建：`Image` 47,626,752 B（`d158e0a0…`）、`Image.lz4` 22,724,893 B
  （`4a5d2672…`）、`boot.img` 67,108,864 B（`e12ff624…`）；零 warning；
  `check-abi.py` 六项硬校验通过（`kmem_cache` 240≠248 软偏差）；
  KCFI 13/13、638 模块 `hard_missing=0 weak_missing=0`。
- 刷入 `boot_a` 后正常开机，`/proc/version` = `6.6.144-4k #15`。
- 开机后核查：
  - `dmesg` 无 `BUG:`/`WARNING:`/panic/`brk #0x8228`/`Unknown symbol`/
    `module verification failed`/rcu stall；`avc: denied` 0 条。
    （上一版 6.6.143 日志里有 2 条 `WARNING:`——`proc_register` 重复注册与
    eBPF Spectre 提示；本版 `proc_register` 那条不再出现。）
  - 584 个模块加载，`node_cache`/`os_cpu_qi`/`mtk_mbraink`/`cam_fs`/
    `mi_game`/`task_turbo` 均在；taint 组合 `G O` / `G W O` / `P W O`
    与上一版生产一致（`W` 来自 `cam_fs` 模块 init 返回 1 的既有提示）。
  - `landlock: Up and running`；LSM 链
    `capability,landlock,selinux,bpf,baseband_guard,integrity`；
    KernelSU `lsm_hook` 正常 patch。
  - `cc=bbr3`；`sdc scheduler=none [adios] mq-deadline kyber bfq cpq`；
    `io scheduler adios registered`；zram0 swap 正常建立。
- 发现并修复：实机 `dash_art_tune` 仍是旧 v1.4，启动时把
  `net.core.default_qdisc` 写回 `fq_codel` 且没有 4 个 TCP sysctl。已构建
  v1.5（`fq` + sysctl + 幂等）并用 `ksud module install` 安装（下次重启
  生效），同时手动应用当前值：
  `tcp_mtu_probing=1`、`tcp_ecn=1`、`tcp_slow_start_after_idle=0`、
  `tcp_notsent_lowat=16384`、`default_qdisc=fq`。
- 未做：suspend/resume、长时压力、性能/功耗 A/B（本轮只验证启动与错误面）。

### 41.2 内存扩展 dm 回写退化为 loop 的根因（2026-11-24，真机）

- 现象：`backing_dev=/dev/block/loopNN`（16 GiB loop over
  `/data/extm/extm_file`），而 6.6.143 生产日志里是
  `ExtM: setup backing device /dev/block/dm-71`。
- 取证：从 `system_perf_init` 反汇编出 dm 优先/loop 回退逻辑；自建
  FIEMAP 探针测得文件 944 个 extent（2 MB–1.9 GB、全部按 512B 对齐、
  flags `0x1088`）——均远低于二进制的 50000 上限，extent 检查通过。
- 关键日志（`logcat -s PerfInit`）：
  `Failed write to /dev/sys/fs/by-name/userdata/gc_pin_file_thresh:
  Invalid argument`。
- 源码对比（本地 AOSP tag `android15-6.6-2026-10_r4` vs 6.6.144）：
  - 6.6.143：`strcmp(a->attr.name, "gc_pin_file_threshold")`（拼写错误，
    永远不匹配实际属性 `gc_pin_file_thresh`），写入落到通用 setter，
    4294967295 被截断成 65535；
  - 6.6.144：拼写修正为 `gc_pin_file_thresh`，于是
    `t > MAX_GC_FAILED_PINNED_FILES(USHRT_MAX)` → `EINVAL`。
- 验证：设备上 `echo 4294967295 > gc_pin_file_thresh` 返回失败，
  `echo 65535 > ...` 成功并与当前值一致。
- 结论：这是 6.6.144 上游 f2fs 拼写修复引起的**厂商用户态兼容性回退**，
  不是 ABI 问题；回写功能本身仍可用，只是从 dm-linear 退化为 loop。
  可选修复：在 `gc_pin_file_thresh` 分支把超限值截断为 `USHRT_MAX`。

#### 41.2.1 兼容补丁（2026-11-24）

在 `fs/f2fs/sysfs.c` 的 `gc_pin_file_thresh` 分支把超限值截断为
`USHRT_MAX`（不再返回 `EINVAL`），代码内带 `DASH-EXTM-COMPAT` 标记与移除
条件；补丁由 `patches/060-f2fs-xiaomi/0001-f2fs-xiaomi-features.patch` 承载，
`make gen-patches` 校验通过（34 补丁/152 文件）。重建生产 Full LTO 内核后
需复核：`backing_dev` 恢复为 `/dev/block/dm-71`，且 `logcat -s PerfInit`
不再出现 `gc_pin_file_thresh: Invalid argument`。

#### 41.2.2 验证结果（2026-11-24，真机 #16）

- 构建：`Image` 47,626,752 B（`fdf3b294…`）、`Image.lz4` 22,724,910 B
  （`206d66a3…`）、`boot.img` 67,108,864 B（`7e36a974…`）；ABI 六项硬校验
  通过（`kmem_cache` 240 软偏差）、KCFI 13/13、638 模块
  `unresolved_hard=0/unresolved_weak=0`、零 warning。
- 刷入后 `/proc/version` = `6.6.144-4k #16`，正常开机。
- `dmesg`：`ExtM: setup backing device /dev/block/dm-71`（不再是 loop），
  无 panic/BUG/WARNING/模块加载错误。
- `echo 4294967295 > /sys/fs/f2fs/dm-67/gc_pin_file_thresh` 返回 0，
  读回 65535；`PerfInit` 日志不再出现 `Invalid argument`。
- `dash_art_tune` v1.5 已在本次重启后生效：`tcp_mtu_probing=1`、
  `tcp_ecn=1`、`tcp_slow_start_after_idle=0`、`tcp_notsent_lowat=16384`、
  `default_qdisc=fq`、`cc=bbr3`。

## 42. #16 生产版整机健康检查（2026-11-24，真机）

对象：`6.6.144-4k #16`（Full LTO + MLGO + AutoFDO + A720 tune + ExtM
兼容补丁），`boot_a` 为 `7e36a974…`。检查时开机约 3 分钟、机主正在使用
（Bilibili，load 18.9）。

### 内核日志（dmesg 67486 行）

| 项 | 结果 |
|---|---|
| `Kernel panic` / `Internal error` / `Unable to handle` / `Oops` / `SError` / `MCE` / `brk #0x8228` | 0（`Oops`/`SError` 的计数是 `mtdoops`/`FSERROR` 子串误匹配） |
| `BUG:` / `WARNING:` | 无内核 BUG；唯一 `WARNING:` 是 GPS 驱动 `POS_CHECK` 的厂商提示 |
| `rcu stall` / `hung task` / `soft lockup` / OOM / `page allocation failure` | 0 |
| `I/O error` / `F2FS-fs ... error` / `EXT4-fs error` / `device-mapper: error` | 0 |
| 模块：`Unknown symbol` / `module verification failed` / `invalid module format` | 0 |
| `avc: denied` | 0 |
| `Call trace:` | 12 处，全部是厂商 `dump_stack()`（`cmdq_proc_create` 重复 proc 目录、`cam_fs` init 返回 1），与上一版一致 |
| `FSERROR`（fs3002 触觉芯片 i2c 读 ID 失败） | 2 条，`#15`/上一版同样 2 条，属基线行为 |

### 模块与 ExtM

- `/proc/modules` 584 个；`node_cache`/`os_cpu_qi`/`mtk_mbraink`/`cam_fs`/
  `mi_game`/`task_turbo` 均在。
- `ExtM: setup backing device /dev/block/dm-71` 出现两次（12.7s 由
  `system_perf_init` 建立；42.9s Scene 重置 zram 后恢复），均为 dm。
- zram0 swap 16 GiB 建立；`SwapFree≈SwapTotal`（几乎未使用）；
  `xswapd0` pid 370；`memory.xswapd.quota≈7 GiB`。
- `Memory.xswapd.umrenable=0`、`/sys/fs/pstore` 无新记录。

### 内存 / 温度

- `MemAvailable≈7.9 GiB`、`Cached≈7.0 GiB`；`free` 里的 “free 121 MB” 是
  缓存占满的正常表现。
- logcat 里 `lowmemorykiller: Attempt to wait for a kill...` 是开机期厂商
  lmkd 状态提示，实际 `lmkd Kill` 计数为 0。
- 电池 55%、32.4 °C、状态充电中（机主在用手机，负载不代表待机）。

### 运行时配置

- `/proc/config.gz`：`LTO_CLANG_FULL`/`AUTOFDO_CLANG`/`DASH_MLGO_REGALLOC`/
  `DASH_ARM64_TUNE_A720`/`SECURITY_LANDLOCK`/`VXLAN`/`VHOST_NET` = on；
  `RSEQ`/`CGROUP_DEVICE`/`CGROUP_HUGETLB`/`UBSAN`/`KFENCE`/`SLUB_DEBUG`/
  `SLAB_FREELIST_HARDENED`/`INIT_ON_ALLOC_DEFAULT_ON` = off。
- SELinux `Enforcing`；`ro.boot.verifiedbootstate=green`（SUSFS spoof）。
- `dash_art_tune` v1.5 日志显示全部幂等命中：
  `bbr3/fq already kernel defaults`、`tcp sysctls already applied`、
  `sdc scheduler already adios`。

### logcat 噪声（均为既有厂商项）

相机 HAL（`HalIspPluginC3DTBL`/`mtkcam`）、`system_server setState` 时间戳、
`TEES` 找 TA 路径、`libsensor-parseRGB`、`libPowerHal notifyWriteFail`、
`MI-SF` 图层检查、`ComNxpNfc` 扩展缺失等，与内核无关。

原始日志：`dash/out/evidence/20261124-6.6.144-final/`
（`final-dmesg.txt`、`logcat-ef-top.txt`、`system.txt`、`extm-modules.txt`）。
