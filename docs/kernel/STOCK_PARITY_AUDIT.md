# dash 实机 vs stock 6.6.118 特性核对（2026-10-30，构建 #29）

> 更新（2026-10-30 晚）：当前设备已到 `6.6.143-4k #3`（AOSP 2026-10_r2 +
> ThinLTO）。本文表格仍是 6.6.118 #29 快照；6.6.143 下 stock 的 1860 个
> traceiter 全部保留，另有 46 个上游新增，LZ4 事件已恢复；详见
> [TEST_REPORT.md](TEST_REPORT.md) §15。

对象：当前设备运行的自编内核 `6.6.118-4k #29`，对比设备 stock
`6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`。
结论只区分“已核对一致”“已实现但有行为差异”“未实现/阻塞”，不把
“模块能加载”当成“功能完全等价”。

## 1. 总览

| 项 | stock | 当前 #29 | 结论 |
|---|---|---|---|
| config | 2259 项 | 2266 项，0 个值冲突 | 仅 7 个缺失项，见 §2 |
| 已加载模块 | 585 | 585 | 唯一差异 `kernelsu` LKM → 内建 KSU + `mkp` |
| stock 模块符号 | 638 模块 | `hard_missing=0 weak_missing=0` | 可加载性一致 |
| core tracepoint | 1860 | 1860 | `__traceiter_*` missing=0/extra=0 |
| KCFI | — | 13/13 静态哈希 | OS4 hooks 全部匹配 |
| 启动 | stock | #29 已启动 | 无 KCFI/未知符号/panic |

## 1.1 安全补丁差异

本机 stock 的安全补丁是 `2026-10-01`（`ro.build.version.security_patch`）；
当前基线 tag 是 `android15-6.6-2026-01_r1`（6.6.118），缺少 2026-02..10 的
LTS/安全修复。
KMI 字符串仍是 `android15-8`，升级 sublevel 不改变 KMI；但需要重放补丁并复验。
详见 [UNRESOLVED_GAPS.md](UNRESOLVED_GAPS.md)。

## 2. config 差异

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
stock `zram` 默认算法是 `lz4`；但 stock zcomp 走 crypto API，本内核注册
`lz4kd-generic` 后可直接选中 `[lz4kd]`，不需要替换 zram。注意 stock 的
“内存扩展”是 ExtM（vendor_boot 里的 ExtM 版 zram.ko + xswapd），替换
zram 模块会破坏回写；见 [ZRAM_EXTM.md](ZRAM_EXTM.md)。

## 3. 已核对一致 / 已补齐

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

## 4. 已实现但与原厂行为有差异

### F2FS 增强 iostat

- sysfs 开关/窗口/日统计/阈值存在，单开关语义已修复。
- 当前是 5 类聚合（read/write_sync/write_async/meta），不是 stock 的
  20 槽窗口 + 每 10 档粒度 + per-CPU 布局；`iostat_window_latency` 的输出格式
  不保证逐字节等于 stock。

### F2FS VIP

- `vip_file_enable`、排序 manager、`f2fs_vip_bsearch/insert/remove` 存在。
- 当前选择策略是 hook + 保守 fallback（有用户地址空间的 RT/negative-nice
  写打开），上限 8192；stock 的原厂选择策略和 `f2fs_nm_info` 布局未复刻。
- 关闭开关时 manager 为空，开销为零。

### F2FS fault report

- 同步 `f2fs_handle_error()` 和 task context 的
  `f2fs_handle_error_async()` 都会触发；原子 end_io 路径由 `in_task()` 过滤，
  避免 fault_report.ko 回调在原子上下文做 `stack_trace_save()`/`queue_work()`。
- 与 stock 的差异：`f2fs_stop_checkpoint()` 等路径没有额外上报，stock 是否
  覆盖这些路径未确认。

### EROFS iostat

- 已改 per-CPU，sysfs 汇总；`iostat_config` 输出 `percpu=1`。
- stock 是每 CPU 10 个 window 槽 + 10 个 abnormal 槽 + 5 个 daily 槽 +
  5 档阈值；当前每 CPU 只有 1 个 aggregate bucket，统计粒度和输出格式不同。

### LZ4 tracepoint

- `lz4_decompress_start/end` 的字段/ABI 按 stock BTF 实现，但调用点只在
  EROFS 解压路径；stock 是否覆盖其它 LZ4 解压路径未确认，不能宣称全部覆盖。

## 5. 未实现 / 阻塞

### F2FS hybrid UFS（最大功能缺口）

- `hybrid`、`hybrid_free_ratio`、`hybrid_die_info` sysfs 存在，
  `f2fs_hw_support_hybrid()` 固定 false，`hybrid=1` 返回 `-EOPNOTSUPP`。
- 已从 stock BTF 恢复 `f2fs_hybrid_info` 192B 和 `f2fs_die_info` 72B 布局，
  但缺 ext LUN 映射、die 分区发现和 GC 分配策略；不能安全伪造地址映射。
- 详见 [UFS_HYBRID_EVIDENCE.md](UFS_HYBRID_EVIDENCE.md)。

### SCSI fastdiscard

- stock config 有 `CONFIG_SCSI_DISCARD`/`CONFIG_SCSI_FASTDISCARD`，当前缺。
- stock 的 `xiaomi_fastdiscard_info` 是 SCSI disk 层的多 descriptor UNMAP；
  当前 `sd.c` 只有单 descriptor `sd_setup_unmap_cmnd()`，
  `max_discard_segments=1`（实测），无法批量 UNMAP。
- 通用 discard 仍可用（`discard_max_bytes`/`discard_granularity` 正常），
  但 fastdiscard 的吞吐优化未实现；`persist.sys.stability.fastdiscard` 为空。

### UFS 官方 core

- MTK 官方 37 文件源已取到并被核对，且做了真实编译探针：
  `ufs-mediatek.c` 可在 AOSP 6.6.118 头文件下编译，但 modpost 缺
  `ufs_mtk_init_sysfs`、`ufs_mb_init` 等 sibling/vendor 符号；它是
  device_modules 模块形态，依赖 `DEVICE_MODULES_PATH`、MTK block/clk/power
  头文件，不能直接替换 AOSP core。
- stock 的 `ufs_mediatek_mod_ise.ko` 在当前 AOSP core 上可加载，因此没有把
  “整体替换 core”作为当前交付。
- 仍需在独立变体上做 UFS 初始化、monitor、电源/时钟路径 A/B。

### 7 个 export-only hook

已在 0008/0009 补上调用点：MMC attach/reset/cd、sdhci get_cd、dma-heap
alloc latency、lazy resched restore；`restore_curr_resched` 按 OnePlus 公开
lazy-resched 路径接入。剩余差异是这些调用点是否与 stock 私有 MTK 调用点
完全同序，当前 638 模块没有引用它们。

## 6. 有意保留的差异

- `CONFIG_VENDOR_KO_COMPAT=y` 跳过模块签名/vermagic/CRC/namespace/GKI
  protected-export 校验。这是为了加载 stock 厂商模块，不是 stock 行为；
  安全性低于原厂。
- 关闭 `LOCALVERSION_AUTO`/`MODULE_SCMVERSION` 是为了可复现构建；
  只影响版本元数据。
- `SUSFS`、内建 KSU、`vip_inode_count` 等是额外能力/调试 ABI，不是 stock
  原厂特性。

## 7. 仍未验证

- 长时压力、suspend/resume、异常进程退出下的 KCFI/模块稳定性。
- fsck、power-loss、F2FS/EROFS 故障注入。
- hybrid、fastdiscard、UFS core 变体的硬件 A/B。
- 性能/功耗 A/B（zram、node_cache、QoS、启动时延）。

## 8. 核对命令

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

## 9. 结论

当前实机与 stock 的主要剩余差异集中在 **F2FS hybrid / fastdiscard / EROFS
多桶粒度 / UFS core 变体**，而不是启动、模块加载、tracepoint 或基本
F2FS/EROFS 功能。`node_cache`、`os_cpu_qi`、`fault_report`、`io_monitor`
等 stock 模块链已实测工作；不能把 hybrid、fastdiscard 的“开关存在”误报为
“功能等价”。
