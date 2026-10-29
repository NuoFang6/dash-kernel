# UFS / hybrid / fastdiscard 缺口证据（2026-10-30）

本文记录三项无法在“无原厂源码、无硬件故障注入”条件下安全完成全部实现的工作，
以及已经完成的源码核对和可复现证据。结论是：**不伪造功能，不替换已验证的启动链**。

## 1. UFS 官方源码：可用，但不能直接替换 AOSP core

### 已获取

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

### 为什么没有并入 `drivers/ufs`

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

### 编译探针

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

### 当前结论

stock 把 `ufs_mediatek_mod_ise.ko` 作为模块加载（13,885,440B），本内核已经能
加载这个 stock 模块（`/proc/modules` 可见，依赖 `rpmb_mtk`、`ise_trusty` 等）。
因此“UFS 官方源码”不是当前启动链的必需替换项；要做独立变体，应使用
device_modules 的 out-of-tree 构建和单独的 boot/DT 验证，而不是并入本内核。

## 2. hybrid UFS：布局已恢复，分配契约仍缺失

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

## 3. SCSI fastdiscard：只有 ABI 证据，没有公开实现

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

## 4. 可安全继续的边界

- UFS：只做 device_modules 独立变体；不改当前 core，不写 boot。
- hybrid：先恢复 `device_hybrid_capable`/die 发现，再做只读 A/B；未完成前保持
  `-EOPNOTSUPP`。
- fastdiscard：先实现并验证多 descriptor UNMAP 的命令构造和错误处理，再接入；
  未完成前保持通用 discard。
