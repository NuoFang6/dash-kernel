# zram 内存扩展（ExtM）与 lz4kd

2026-10-30 实机复核。结论先行：

- 本机“内存扩展”是小米 **ExtM**，主体在 vendor_boot 里的
  `zram.ko`（带 ExtM 补丁），不是普通 AOSP zram。
- **不能 rmmod/替换 vendor zram.ko**。替换后 `backing_dev`、`xswapd`、
  zgroup/mctrl/smart_cache 全部消失，内存扩展失效。
- lz4kd 不需要替换 zram 模块：stock vendor zram 的 zcomp 走 crypto API，
  而本内核已注册 `lz4kd-generic`（type=compression），所以执行
  `echo lz4kd > /sys/block/zram0/comp_algorithm` 即可选中。
- 当前实机：stock vendor zram + `[lz4kd]` + ExtM，重启后仍然成立；回写
  497 页已验证。

## 1. 组件与启动链路

| 组件 | 位置/形态 | 作用 |
| --- | --- | --- |
| `extm_file` | `/data/extm/extm_file`，16 GiB 文件 | 回写 backing store |
| `dm-swapfile` | `/dev/block/dm-71`，16 GiB dm-linear | ExtM 的首选 backing device |
| vendor `zram.ko` | vendor_boot ramdisk（269480 B） | ExtM 主体：backing_dev、idle/writeback、zgroup、mctrl、smart_cache、xswapd、zram-control |
| `system_perf_init` | `/system_ext/xbin/system_perf_init` | 创建 dm/loop backing、写 backing_dev、设 disksize、mkswap、swapon |
| `xswapd0` | kernel thread（vendor zram 创建） | ExtM 的后台换出/回写线程 |
| `mmd_setup` | AOSP 6.6.143 新组件 | 本机与厂商 `swapon_all`/ExtM 冲突，会报 `Cannot change disksize`，可忽略 |

一次正常启动（6.6.143 #4）：

```text
4.3s   persist.miui.extm.* 属性（enable=1, bdsize=16384）
7.7s   /data/extm 重新创建并设置加密策略
11.58s ExtM: setup backing device /dev/block/dm-71
11.59s zram0 16 GiB，swapon priority -2
20.7s  mmd_setup / swapon_all 尝试重复初始化，mkswap 失败（无害）
35.9s  Scene swap controller 重置 zram，恢复 backing_dev
36.1s  ExtM: setup backing device /dev/block/dm-71
36.2s  swapon priority 0（Scene 配置）
```

关键属性：

```text
persist.miui.extm.enable=1
persist.miui.extm.bdsize=16384
persist.miui.extm.version=4.0
persist.sys.zram_enabled=1
```

## 2. 本次故障原因

为让 lz4kd 可选，曾用 `/data/local/tmp/testzram.sh`：

```sh
swapoff /dev/block/zram0; echo 1 > /sys/block/zram0/reset
rmmod zram; insmod zram-lz4kd.ko
```

自编 zram 模块只带 AOSP writeback，没有 ExtM：

- `backing_dev=none`，没有 dm-71；
- 无 `xswapd0`、`zgroup_wb`、`mctrl`、`smart_cache`；
- `/dev/memcg/memory.xswapd.*` 全部消失；
- 因此“内存扩展”显示/实际回写失效。

`system_perf_init` 对自编模块仍能设置 backing_dev 和 swap，但后台换出线程
不在，不能等同于原厂内存扩展。

## 3. 正确配置（已验证）

### 3.1 保持 stock vendor zram

不要 rmmod、不要覆盖 `/system_dlkm/lib/modules/zram.ko`、不要把自编
`zram.ko` 放进开机脚本。stock 模块在 vendor_boot 首阶段加载，ExtM 由
`system_perf_init` 自动完成。

### 3.2 lz4kd

本内核把 lz4kd 同时注册为 `compression` 和 `scomp`：

```text
/proc/crypto:
  name lz4kd, driver lz4kd-generic, type compression, selftest passed
  name lz4kd, driver lz4kd-scomp,   type scomp
```

stock zram 的 `zcomp.c` 使用 `crypto_alloc_comp()`，并通过
`crypto_has_comp()` 接受任意已注册压缩算法；`comp_algorithm` 的静态列表
不显示它，但选中后会显示 `[... lz4kd]`。因此只需在 zram 未初始化时写：

```sh
echo lz4kd > /sys/block/zram0/comp_algorithm
```

Scene swap controller 的 `/data/swap_config.conf` 已经是：

```ini
zram=true
zram_size=16384
comp_algorithm=lz4kd
zram_writeback=default
```

它在开机 service 阶段 reset zram → 选 lz4kd → 恢复 `backing_dev` →
mkswap/swapon，正好保留 ExtM。`zram_writeback=default` 是关键，不能改成
`false`。

如果手动改算法且 zram 已初始化（`initstate=1`），必须：

```sh
swapoff /dev/block/zram0
echo 1 > /sys/block/zram0/reset
echo lz4kd > /sys/block/zram0/comp_algorithm
/system_ext/xbin/system_perf_init
```

### 3.3 当前实机结果（2026-10-30，重启后）

```text
comp_algorithm: lzo lzo-rle lz4 zstd [lz4kd]
backing_dev:    /dev/block/dm-71
disksize:       17179869184
swapon:         16777212K, priority 0
xswapd0:        running
/proc/crypto:   lz4kd-generic refcnt=9
```

回写测试：

```sh
echo all > /sys/block/zram0/idle
echo idle > /sys/block/zram0/writeback
```

结果：

```text
ExtM: Mark IDLE finished. Mark 497 pages
ExtM: Parse succeed. wb_max: 18446744073709551615, wb_idle_min: 1
ExtM: Flush finished. Mode 2, flush 497 pages, flush count 16
bd_stat: 497 0 497 0 0 0
```

## 4. 诊断命令

```sh
cat /sys/block/zram0/comp_algorithm
cat /sys/block/zram0/backing_dev
cat /sys/block/zram0/disksize
cat /proc/swaps
ps -A | grep -E 'xswapd|zram'
ls /dev/memcg/ | grep xswapd
dmesg | grep -iE 'ExtM|zram|zgroup|xswapd|smart_cache|mctrl'
cat /proc/crypto | grep -A8 lz4kd
```

正常应看到 `[lz4kd]`、`backing_dev=/dev/block/dm-71`、`xswapd0` 和
`ExtM: setup backing device`。如果 `backing_dev=none`，说明 zram 被替换
或 reset 后没有恢复 backing device。

## 5. 相关产物

- `handoff/stock-zram/zram-stock.ko`：system_dlkm 的原厂 AOSP 版（无 ExtM）。
- `handoff/dash-gap-handoff/modules/vendor_ramdisk/zram.ko`：vendor_boot 的
  ExtM 版（269480 B，sha256 `21d0c6c666c455645906943ef603f5cfc9081076dffdb5ad3169127826887429`）。
- `handoff/zram-lz4kd/zram.ko`：自编模块，仅作逆向/实验参考，**不要用于开机**。
- `handoff/vendor-zram-src/`：公开可得的 ExtM/厂商 zram 参考源码
  （Pissarro、Onyx、MiCode，均不完整，缺少 zgroup/xswapd 的精确组合）。
