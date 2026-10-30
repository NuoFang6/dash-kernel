# dash boot 封装与 AVB 踩坑记录

日期：2026-10-29；2026-10-30 更新到构建 #29。适用范围：dash / REDMI Turbo 5 Max
（MT6991），stock `6.6.118`，当前设备的“隐藏解锁”状态。以下结论均来自本机实测，
不是推断。

## 1. 原厂 boot 的真实结构

原厂 `boot_b` 分区是 **64MB**，不是 17MB 的紧凑镜像：

```text
0x00000000 - 0x00000fff   Android boot header v4（1584B）
0x00001000 - 0x1088fff    LZ4 kernel + 零填充
0x1089000 - 0x108997f     原厂 AVB vbmeta（0x980 = 2432B）
...........................零填充
0x3ffffc0 - 0x3ffffff     AVB footer（AVBf）
```

关键字段：

- header version 4，page size 4096，ramdisk_size 0，cmdline 为空
- kernel LZ4 legacy，stock 压缩后 17,317,780B
- AVB footer：`original_image_size = 0x1089000`，
  `vbmeta_offset = 0x1089000`，`vbmeta_size = 0x980`
- vbmeta 起始 magic 为 `AVB0`，签名链为 OEM 签名

## 2. 三次失败及原因

| 尝试 | 结果 | 原因 |
|---|---|---|
| `mkbootimg` 重建的 17MB 自编 boot | 花屏、bootloop | 未保留 64MB 分区布局和 AVB footer；fastboot 写入后尾部校验结构不完整/被破坏 |
| stock kernel + 补齐 64MB、清零 AVB 尾部 | 花屏、bootloop | 明确去掉 AVB footer 和 vbmeta，bootloader 不接受 |
| 原厂 vbmeta 上直接改 `--disable-verity --disable-verification` | 花屏、bootloop | fastboot 只改 offset 120 的 flags，破坏 OEM vbmeta 签名；bootloader 拒绝签名已损坏的 vbmeta |
| **保留原厂 header+vbmeta+footer，仅替换 kernel** | **成功开机** | 见第 3 节 |

`fastboot boot` 在该 LK 上直接返回 `unknown command`，没有 RAM 临时启动这一
条路。`fastboot getvar unlocked` 虽然返回 yes，但系统属性是
`ro.boot.vbmeta.device_state=locked`、`ro.boot.verifiedbootstate=green`、
`ro.boot.flash.locked=1`；这不是标准 Orange State，不能按普通真解锁设备处理。

## 3. 通过的封装方式

最终 boot 由 [scripts/repack-boot.py](../../dash/scripts/repack-boot.py) 生成：

1. 复制整个 stock 64MB boot 作为底包。
2. 保留 header 的 v4 字段和 cmdline，只更新 `kernel_size`，`ramdisk_size=0`。
3. 在 offset 0x1000 写入新的 LZ4 kernel；kernel 结束后到 `original_image_size`
   之间清零。
4. **逐字节保留**原厂 vbmeta（`0x1089000..0x108997f`）和 AVB footer。
5. 如果新 kernel 超过原厂 17,338,368B 的 original image 空间，脚本会把原厂
   vbmeta 搬到新位置并更新 footer 的 original_image_size/vbmeta_offset；footer
   本身不是签名的一部分，vbmeta 字节仍保持原厂签名。

当前最终产物（构建 #29，2026-10-30）：

- `Image.lz4`：17,348,138B
- `boot.img`：64MB，SHA256
  `a28344f9296fb9796b2c8dc231812c59aa76770d069158897d1305dc55ab7cac`
- 新 kernel（17,348,138B）超过原厂 original_image_size 17,338,368B，
  repack 脚本把原厂 vbmeta 从 `0x1089000` 搬到 `0x108d000` 并把 footer 的
  original_image_size 更新为 `0x108d000`；vbmeta 字节和 OEM 签名未变
- boot 内 kernel 与 `out/artifacts/Image.lz4` 字节一致
- 自编内核实机启动成功：`6.6.118-4k #29`，KernelSU built-in，SUSFS 2.3.0，
  node_cache/os_cpu_qi 整条模块链加载；F2FS 单开关 iostat、
  `f2fs_fault_report`、lock/priority trace 与 VIP 已补；stock core
  tracepoint 1860/1860 和 GKI dynamic task_struct 已对齐

## 4. 为什么 LunarKernel 能开机

只读检查
`/storage/emulated/0/Download/QQ/LunarKernel6.6-V2.1.5-canary.zip`
（没有刷它）：

- zip 中**没有 boot.img**，只有裸 `Image`（38,914,560B）；用 lz4 legacy -12
  压缩后约 18,590,000B，已经超过 stock 的 original-image kernel 空间
  （17,334,272B）。
- 安装器是标准 AnyKernel3，调用 `split_boot` + `flash_boot`。
- `flash_boot` 使用包内 `magiskboot repack <当前 boot> boot-new.img`，没有改
  `vbmeta` 分区。
- 包内没有 OEM 私钥，也没有把 vbmeta 重新签成原厂链。
- 它把 `boot-new.img` 用 `cat boot-new.img /dev/zero > $BLOCK` 写满整个 boot
  分区，避免旧 footer 残留。
- magiskboot 必须保留 signed vbmeta 字节，并把 vbmeta/footer 重新定位到新
  kernel 之后（或生成等价的 AVB 结构）；否则 18.6MB 的 kernel 会覆盖原
  vbmeta。该结构在本机隐藏解锁状态下被接受。

结论：不是 Lunar 的内核比我们的“更有特权”，而是它的安装器保留了 stock boot 的
AVB/分区结构；我们最初的 mkbootimg 镜像把它丢了。它不违反 AVB，刚好相反，是
依赖原厂 AVB 元数据。

## 5. 后续硬性规则

1. **不要用 mkbootimg 重建 dash boot 作为最终产物。** 必须从 stock boot
   继承，保留 64MB 分区、header、vbmeta 和 AVB footer。
2. **不要把 boot.img 做成 17MB。** fastboot 写短镜像会留下旧尾部或破坏校验结构。
3. **不要为了自定义 kernel 改 vbmeta flags 或重签 vbmeta。** 本机 bootloader
   拒绝签名被修改的 vbmeta；`--disable-verity --disable-verification` 不是本机
   可行路线。
4. `vendor_boot_b`、`dtbo_b`、`vbmeta_b` 保持本次操作前的状态；本方案只替换
   `boot_b` 中 kernel。`init_boot_a/b` 已于 2026-10-30 还原为 OS4.0.3.0 官方
   镜像（sha256 `3d2062ae…`）；KernelSU patched 旧副本只作历史回滚，不要再用
   它当原厂恢复源。
5. kernel 压缩后必须能放进 stock original-image 空间；脚本支持把 vbmeta 搬迁到
   新位置，但如果超过分区可用空间会明确失败，不能截断。
6. 任何写入前备份完整 `boot_b`/`vbmeta_b`，不要碰 `lk`、`super` 或用户数据。
7. 这不是通用签名绕过方案：在其他安全策略更严格的 bootloader 上，保留旧
   vbmeta 但 hash 不匹配也可能被拒绝。本结论只对当前设备状态有效。

## 6. 恢复命令

```bash
fastboot flash vbmeta_b out/device-backup/vbmeta_b.img
fastboot flash boot_b out/device-backup/boot_b.img
fastboot reboot
```

两个文件的 SHA256 已记录在
[out/device-backup/SHA256SUMS](../../dash/out/device-backup/SHA256SUMS)。恢复不涉及
`lk` 或用户数据。官方 init_boot 可从 OS4 OTA 的 `payload.bin` 提取
（`init_boot`，sha256 `3d2062ae…`）；还原前的 KernelSU patched 副本只作历史
回滚，不要用于恢复原厂 init_boot。
