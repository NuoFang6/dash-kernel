# node_cache 源码评估：可借鉴点、stock 二进制差异与 6.6.143 适配

> 2026-11-03。对象是用户提供的 `node_cache.c`（827 行，GPL-2.0-only，
> SHA256 `fa3312097ce21232d5cf9e763a2c753f98c61011bb01eced6b4316d27e987e50`），
> 已原样保存到
> [`dash/vendor-src/node_cache/node_cache.c`](../../dash/vendor-src/node_cache/node_cache.c)。
>
> **结论先行**：这份文件是面向 **6.12 API 的重实现**，不是设备 stock
> `6.6.118` `node_cache.ko` 的原始源码。它把 F2FS `/data` 的 node 页在回收时
> 用 LZ4 压缩进 zsmalloc、再次访问时解压回 page cache；行为方向与 stock 一致，
> 但缺少 stock 二进制里的 4 项保护。当前设备继续运行 stock 模块，本文件没有
> 编译、加载或替换任何东西。

## 1. 它能带来什么

按“立刻可用”到“需要开发”排序：

1. **确认 hook 契约（零风险，已可用）**：模块需要的 5 个 hook 和参数类型与我们
   内核完全一致；其中 4 个是本仓库补的，`android_vh_do_new_mount_fc` 是 AOSP
   自带。调用点也已逐一对上（见 §4）。这为“stock 模块为什么能加载/工作”提供了
   源码级解释，而不只是 KCFI 哈希匹配。
2. **可维护的参考实现（中低风险）**：源码的 refcount + retired work + per-CPU
   压缩缓冲区 + radix tree 结构清晰，适合作为以后自建/内置版本的起点。
3. **运行时观测和调优依据（零风险）**：确认 `/sys/kernel/node_cache/` 每个
   旋钮的含义；stock 实测约 35k 条目、12.6MB 压缩数据、96k 次 swapin，说明它
   确实在高频工作，不应随意关闭（见 §5.B）。
4. **未来替代/内置（较高风险）**：如果 stock 模块在后续内核或 GKI 版本上失效，
   可以按 §6 适配后自建。收益是摆脱对厂商二进制和 hook 的依赖；代价是要补齐
   stock 的保护逻辑并处理“不能和 stock 模块同时跑”的问题。
5. **设计借鉴（间接）**：只缓存 F2FS node 页而不是数据页；压缩前做比例门限；
   用 per-CPU 缓冲区避免回收路径分配；用 shrinker 而不是硬上限。这些都可以
   用在类似“元数据压缩缓存”的场景，但不要直接扩到数据页。

不建议把这份源码原样加载：它有 §4 列出的 **构建阻断** 和 **正确性缺口**。

## 2. 它做什么

源码把 `/data`（F2FS）的 **node mapping** 当作缓存对象：

- 挂载 `/data` 时 attach 一个 `node_cache_instance`（`vh_do_new_mount_fc`，
  [L507](../../dash/vendor-src/node_cache/node_cache.c#L507)）。
- 页回收路径（`android_vh_remove_mapping`，`reclaimed=true`）把即将被移除的
  node folio 用 LZ4 压缩，写入 zsmalloc，并在 radix tree 中以 `nid`
  （`folio->index`）索引
  （[L323](../../dash/vendor-src/node_cache/node_cache.c#L323)）。
- 再次查找同一个 node 页时（`android_vh_filemap_get_folio_end`），如果 folio
  还不是 uptodate，就从 zsmalloc 取出、解压到 folio、标记 uptodate，然后释放
  缓存条目（[L435](../../dash/vendor-src/node_cache/node_cache.c#L435)）。
- 回收失败时（`android_vh_remove_mapping_failed`）删除刚插入的条目
  （[L413](../../dash/vendor-src/node_cache/node_cache.c#L413)）。
- 卸载 `/data` 时（`android_vh_put_super`）detach，并用 refcount + retired list
  + workqueue 延迟释放，避免 hook 正在使用时释放实例
  （[L525](../../dash/vendor-src/node_cache/node_cache.c#L525)）。
- 用 shrinker 在内存压力下按比例回收压缩条目
  （[L232](../../dash/vendor-src/node_cache/node_cache.c#L232)）。
- 通过 `/sys/kernel/node_cache/` 暴露 `stat`、`max_bytes`、`shrink_wmark`、
  `comp_ratio`、`comp_enable`、`trace_enable`
  （[L712](../../dash/vendor-src/node_cache/node_cache.c#L712)）。

默认值：`max_bytes=40MiB`、`shrink_wmark=75%`、`comp_ratio=50%`、
`comp_enable=1`、`trace_enable=0`（[L42](../../dash/vendor-src/node_cache/node_cache.c#L42)）。
`comp_ratio=50` 表示只有压缩后小于 2048 字节的页才值得缓存。

它缓存的是 **元数据**（inode、xattr、dentry 等 F2FS node 内容），不是文件数据；
因此不会改变文件读写带宽，也不会绕过 VFS/SUSFS 的路径隐藏逻辑。

## 3. 源码里的 5 个 hook

| Hook | 我们的调用点 | 源码用途 |
|---|---|---|
| `android_vh_do_new_mount_fc` | [`fs/namespace.c:3548`](../../dash/src/aosp/common/fs/namespace.c#L3548)，AOSP 自带 | 识别 `d_path == "/data"` 后 attach |
| `android_vh_filemap_get_folio_end` | [`mm/filemap.c:2061`](../../dash/src/aosp/common/mm/filemap.c#L2061) | 查找结束后解压缓存条目 |
| `android_vh_remove_mapping` | [`mm/vmscan.c:1430`](../../dash/src/aosp/common/mm/vmscan.c#L1430) | `reclaimed=true` 时压缩并插入 |
| `android_vh_remove_mapping_failed` | [`mm/vmscan.c:1524`](../../dash/src/aosp/common/mm/vmscan.c#L1524) | 回收失败时删除条目 |
| `android_vh_put_super` | [`fs/super.c:700`](../../dash/src/aosp/common/fs/super.c#L700) | 卸载时 detach 并延迟释放 |

本仓库补了 4 个：`filemap_get_folio_end`、`remove_mapping`、
`remove_mapping_failed`、`put_super`；`do_new_mount_fc` 在 AOSP 6.6 树里已有。
头文件原型在
[`patches/legacy-6.6.118/vendor-hooks/0001-trace-hooks-add-dash-os4-vendor-hooks.patch`](../../dash/patches/legacy-6.6.118/vendor-hooks/0001-trace-hooks-add-dash-os4-vendor-hooks.patch)
和 6.6.143 整树补丁中固定。源码里的回调签名与这些原型逐字一致：

```c
void (*)(void *, struct address_space *, struct folio *, bool);
void (*)(void *, struct address_space *, struct folio *);
void (*)(void *, struct path *, struct vfsmount *);
void (*)(void *, struct super_block *);
```

注意 `remove_mapping` 的 hook 是在 `__remove_mapping()` **真正移除之前**调用的；
这正是“先压缩、如果移除失败再 invalidate”的设计基础。`remove_mapping_failed`
只在 `cannot_free` 路径调用，不是所有失败路径。

## 4. 和 stock 6.6.118 二进制的差异

stock 模块在本机的位置是
`dash/out/device-audit/vendor_ramdisk_root/lib/modules/node_cache.ko`
（SHA256 `c1959f1f5943a7bb006294b30419d48d19599fc058bebaaced12ab759e15238b`，
vermagic `6.6.118-android15-8-g8c48da3c6848-4k`，`depends: zsmalloc`）。
以下差异来自 `readelf` / `llvm-objdump` / `strings` 的推断，不是原厂源码：

| 项目 | 提供的源码 | stock 6.6.118 二进制 |
|---|---|---|
| 目标 API | 6.12：`shrinker_alloc()` + `shrinker_register()` + `shrinker_free()` | 6.6：静态 `struct shrinker` + `register_shrinker()` / `unregister_shrinker()` |
| 实例分配 | `kzalloc(sizeof(*inst))`，字段到约 `0x5c` | `kmalloc_trace(..., 0x900, ...)`，实际分配 2304B |
| sysfs | 6 个：`stat/max_bytes/shrink_wmark/comp_ratio/comp_enable/trace_enable` | 8 个：额外 `reclaim_policy`、`avail_low_wmark_mb`；`stat` 还含 `total_ram_mb`、`lowmem_mode` |
| 低内存保护 | 无 | `lowmem_mode && avail_low_wmark_mb > si_mem_available()>>8` 时跳过压缩 |
| 容量上限 | 只在 `compressed_bytes > max_bytes` 时 shrink | 超过 `max_bytes * 80%` 就停止压缩，超过 `max_bytes` 再 shrink |
| 页有效性 | 只查 node mapping、order-0、非 swapcache | 额外要求 `folio_test_uptodate()`，并调用 `node_cache_valid_node_data()` |
| node 校验 | 无 | 读取页内 footer：`page+0xfe8 == nid`（`footer.nid`），并检查 `page+0xff0`（`footer.flag`） |
| 非回收移除 | 直接返回 | `reclaimed=false` 时删除已有缓存条目 |
| 回收策略 | 无 | `reclaim_policy` 0/1/2，默认 0；1/2 按当前任务上下文决定是否压缩 |
| 统计 | `swapin/invalid/shrink` | 同样统计，另加 `total_ram_mb`、`lowmem_mode`、`reclaim_policy` |
| attach 检查 | F2FS + `node_inode` | F2FS magic + `d_path("/data")`；`node_inode` 在 hook 路径里校验 |
| 生命周期 | refcount + retired + work | 同样有 refcount/retired 结构，实例更大 |

### 4.1 最影响正确性的两点

1. **非回收移除没有 invalidate**：源码的 `vh_remove_mapping` 在
   `reclaimed=false` 时直接返回
   （[L336](../../dash/vendor-src/node_cache/node_cache.c#L336)），
   `vh_remove_mapping_failed` 也要求 `reclaimed=true`。stock 会在
   `reclaimed=false`（如 truncate/invalidate）时删除缓存条目。若直接采用源码，
   旧 nid 的压缩数据可能在截断/复用后残留，存在读到陈旧 node 数据的风险。
2. **没有 uptodate / node footer 校验**：源码的 `node_cache_folio_eligible()`
   只检查 node mapping、order-0、非 swapcache
   （[L310](../../dash/vendor-src/node_cache/node_cache.c#L310)）；stock 还要求
   页是 uptodate，并校验页内 footer 的 nid 与索引一致。缺少这两层会把部分
   初始化或损坏的页也缓存起来。

### 4.2 最影响内存/CPU 的一点

源码只在 `compressed_bytes > max_bytes` 时调用 shrink，压缩前没有低内存门限，
也没有 80% 上限；stock 在可用内存低于 `avail_low_wmark_mb`（当前 500MB）时
直接跳过压缩，并在达到 80% 上限时停止继续压缩。回收路径里做 LZ4 是有 CPU
成本的，低内存时更应退让；源码的简化策略在高压力下可能增加 direct reclaim
延迟。

### 4.3 构建阻断

源码的 shrinker 调用是 6.12 API；我们的 6.6.143 只有
`register_shrinker(struct shrinker *, fmt, ...)` / `unregister_shrinker()`，
没有 `shrinker_alloc/register/free`。因此**当前源码不能直接在 6.6.143 编译**。

另一方面，`zs_create_pool(name)` 在我们的 6.6.143 已经是单参数
（`include/linux/zsmalloc.h:43`），`kmap_local_folio()`、`folio_test_large()`、
`folio_test_swapcache()`、`raw_spin_trylock_irqsave()`、radix tree API 都存在，
这些不需要改。

## 5. 建议的收益路径

### A. 现在：保留 stock 模块，不做替换（推荐）

- 设备已经在跑 stock `node_cache`，sysfs 证明有 35k 条目、96k 次 swapin，
  收益链是真实存在的。
- 我们补的 4 个 hook + AOSP 的 `do_new_mount_fc` 已被源码和二进制双重确认。
- 不需要为这份源码改内核；风险最低。

### B. 观测与调优 stock 模块（低风险，但必须先 A/B）

`/sys/kernel/node_cache/` 的可写旋钮及含义：

| 旋钮 | stock 当前值 | 含义 | 调整方向 |
|---|---|---|---|
| `max_bytes` | 41943040（40MiB） | 压缩缓存总上限 | 提高可缓存更多 node 页，但多占内存 |
| `comp_ratio` | 50 | 只有压缩后 < 50% 页大小才缓存 | 提高会增加条目/内存/CPU；降低更保守 |
| `shrink_wmark` | 75 | shrinker 目标水位 | 影响压力下的回收积极程度 |
| `comp_enable` | 1 | 总开关 | 关闭会失去缓存收益 |
| `trace_enable` | 0 | 仅调试日志 | 保持 0 |
| `reclaim_policy` | 0 | 压缩策略；1/2 增加任务上下文判断 | 默认 0；未完全恢复语义前不要改 |
| `avail_low_wmark_mb` | 500 | 低内存门限（配合 `lowmem_mode`） | 16GB 设备 `lowmem_mode=0`，当前不生效 |

实测历史值（2026-10-29 stock 运行态）：`cur_cnt≈35051`、
`cur_bytes≈13231761`（约 12.6MB）、`swapin_cnt≈96433`、`invalid_cnt=3`、
`shrink_cnt=0`、`total_ram_mb=15206`、`lowmem_mode=0`。数值见
[`DEVICE_MODULES.md`](../project/DEVICE_MODULES.md)。

**不要在没有 A/B 的情况下改默认值**；目前没有 stock vs 自编的 node_cache
命中率、UFS 读次数或 CPU 时间对比。合理的实验顺序是：只读采样 → 提高
`max_bytes` 观察 `swapin_cnt/cur_bytes` 增量 → 再决定是否值得多占内存。

### C. 自建/替换（中高风险，按 §6 适配后再说）

如果将来 stock 模块不可用，或需要一个可按内核版本维护的版本：

1. 适配 6.6 shrinker API；
2. 补齐 §4.1/§4.2 的保护；
3. 用不同模块名或先卸载 stock，避免两个缓存同时工作；
4. 保留 `depends: zsmalloc`，或改为 built-in + `CONFIG_ZSMALLOC=y`；
5. 做 §7 的验证。

收益：摆脱厂商二进制、可调、可在新内核上重建。代价：需要自己承担 F2FS
内部结构和回收路径的正确性。

### D. 内置进内核（仅在未来考虑）

把代码放进 `fs/f2fs/` 并加 Kconfig，可以完全去掉模块签名/vermagic/KCFI 和
vendor hook 依赖。但必须：

- `CONFIG_ZSMALLOC=y`（built-in 不能依赖 `zsmalloc.ko` 的导出符号）；
- 禁用 vendor_boot 里的 stock `node_cache.ko`，否则会双缓存；
- 接受 F2FS 内部结构变化带来的维护成本。

当前没有这个必要；风险高于收益。

## 6. 6.6.143 适配清单（如果决定自建）

### 6.1 shrinker API

把 [L763-L768](../../dash/vendor-src/node_cache/node_cache.c#L763) 和
[L806](../../dash/vendor-src/node_cache/node_cache.c#L806) 换成 6.6 写法：

```c
static struct shrinker node_cache_shrinker = {
	.count_objects = node_cache_shrink_count,
	.scan_objects = node_cache_shrink_scan,
	.seeks = DEFAULT_SEEKS,
};

/* init */
ret = register_shrinker(&node_cache_shrinker, "f2fs-node-cache");
if (ret)
	goto err_...;

/* exit */
unregister_shrinker(&node_cache_shrinker);
```

6.6 的 `count_objects`/`scan_objects` 返回 `unsigned long`，与源码一致；
`SHRINK_EMPTY` 也已存在。`shrinker_free()` 不需要。

### 6.2 正确性保护

- 在 `node_cache_folio_eligible()` 加 `folio_test_uptodate(folio)`。
- 增加 `node_cache_valid_node_data()` 等价逻辑：映射 folio，检查 F2FS node
  footer 的 nid（stock 在页内 `0xfe8`）等于 `folio->index`，并检查
  `0xff0` 处的 `footer.flag`（反汇编里与 `0xfffffff8` 比较）；不匹配就不缓存。
  built-in 可直接用 `fs/f2fs/f2fs.h` 的 `struct f2fs_node`；外部模块需要
  `fs/f2fs` 内部头文件，这是外部模块不干净的地方。
- 在 `vh_remove_mapping` 处理 `reclaimed=false`：查找并删除该 nid 的缓存条目。
- 压缩前加 `compressed_bytes >= max_bytes * 80 / 100` 早退，以及
  `lowmem_mode && avail_low_wmark_mb > si_mem_available() >> 8` 早退（如果要
  完整复刻 stock）。
- 保留 `comp_ratio` 门限；源码的默认 50% 与 stock 一致。

### 6.3 结构/配置

- `zs_create_pool("node_cache_pool")` 在 6.6.143 已匹配，无需改。
- 外部模块：保留 `MODULE_LICENSE("GPL")` 和 `depends: zsmalloc`；如果要替换
  stock，先 `rmmod node_cache` 再加载自建版本。不要换名后与 stock 并存，否则
  会有两个缓存。
- built-in：`CONFIG_ZSMALLOC=y`，并禁用 stock 模块加载；这一步比代码适配更
  容易出错，需单独方案。
- 如果沿用 `dash` 的 vendor-ko 兼容路径，注意自建模块也要过 KCFI/vermagic；
  不要把兼容绕过当作“已经安全”。

## 7. 验证计划

自建版本至少要做：

1. **编译**：对 6.6.143 树 `make M=...` 或 in-tree 编译；检查
   `modinfo`、`nm -u`、KCFI 原型。
2. **加载**：确认 `lsmod` 只有一个 node_cache；`/sys/kernel/node_cache/stat`
   出现且 `live_instances=1`。
3. **命中**：制造 F2FS node 页回收（大目录遍历、drop_caches、内存压力），
   观察 `cur_cnt`、`cur_bytes`、`swapin_cnt`、`shrink_cnt` 变化。
4. **正确性**：truncate/delete/rename 压力、`drop_caches` 后回读、
   fsck（只读或可回滚）、suspend/resume、模块卸载（若为模块）。
5. **性能**：UFS 读次数、CPU 时间、冷启动/应用切换 A/B；没有数据就不要写
   收益结论。

## 8. 不要做的事

- 不要把提供的源码原样编译/加载到 6.6.143：shrinker API 会编译失败；即使
  改完 API，也缺少 §4 的保护。
- 不要同时运行 stock `node_cache.ko` 和自建版本，否则双份 zsmalloc 和双份
  LZ4 开销，统计也失真。
- 不要根据这份源码声称“与 stock 逐行等价”；它只是行为级重实现。
- 不要在没有 A/B 的情况下改 `max_bytes`/`comp_ratio` 默认值。
- 不要把 node cache 扩展到文件数据页；那是另一类缓存，风险和收益都不同。

## 9. 证据

```bash
sha256sum /home/nuofang/下载/node_cache.c
# fa3312097ce21232d5cf9e763a2c753f98c61011bb01eced6b4316d27e987e50

modinfo dash/out/device-audit/vendor_ramdisk_root/lib/modules/node_cache.ko
# vermagic: 6.6.118-android15-8-g8c48da3c6848-4k ...
# depends: zsmalloc

readelf -sW dash/out/device-audit/vendor_ramdisk_root/lib/modules/node_cache.ko
# register_shrinker / unregister_shrinker / si_meminfo / si_mem_available
# node_cache_valid_node_data / node_cache_try_enter / node_cache_compress_folio

llvm-objdump -dr --no-show-raw-insn --disassemble-symbols=node_cache_compress_folio \
	dash/out/device-audit/vendor_ramdisk_root/lib/modules/node_cache.ko
# lowmem 判断、80% 上限、uptodate/valid_node_data 路径
```

输入源码和 stock 二进制都只用于静态对照；本文件没有产生内核或模块产物。
