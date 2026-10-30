# dash 6.6.118 测试报告

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
