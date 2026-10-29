# dash kernel

REDMI Turbo 5 Max（`dash` / 2602BRT18C / MT6991）的 GKI2.0 内核工作区。

当前目标基线是 **AOSP `android15-6.6-2026-01_r1`（6.6.118）**，不是早期
6.6.144 实验构建。设备 stock 为
`6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`，GKI 分支
`android15-6.6`，KMI 字符串 `android15-8`，4K 页。

## 目录

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

## 快速开始

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

## 当前功能

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

## 厂商 `.ko` 兼容

`0001-vendor-ko-compat.patch` 新增 `CONFIG_VENDOR_KO_COMPAT`，在模块加载路径跳过：

- 模块签名验证（保留 GKI 签名配置本身）
- vermagic 检查
- symbol CRC / `module_layout` 检查
- namespace import 检查
- GKI protected export 限制

符号仍然必须真实存在。`0004-susfs-bakasu-hooks.patch` 适配 BakaSU 三参数
`ksu_handle_sys_read`。关闭校验会降低安全性，仅用于已解锁的自有设备。

## 更新规则

- 更新 AOSP：改 `versions.env` 的 `AOSP_TAG`/`AOSP_COMMIT`，运行
  `make patches`；如果补丁冲突，在 `src/aosp/common` 修正后用 `git diff`
  重新导出对应补丁。
- 更新 BakaSU：更新子模块并改 `BAKASU_COMMIT`，然后 `make patches config build`。
- 更新 SUSFS：更新 `SUSFS_COMMIT`，重新取上游 patch 和
  `patches/susfs/{susfs.c,susfs.h,susfs_def.h}`。
- 源码目录可以随时由脚本重置；长期修改只保存在 `patches/`、`configs/` 和报告。

## 注意

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

