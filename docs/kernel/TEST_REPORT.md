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
