# Vendor source snapshots

这里保存用于**研究/对照**的厂商或用户提供源码。目录内容默认不参与
`make patches`、`make build` 或任何刷机流程；除非有单独文档明确说明。

## node_cache/node_cache.c

- 来源：用户于 2026-11-03 提供，原始路径 `/home/nuofang/下载/node_cache.c`。
- 大小/行数：23003 字节，827 行。
- SHA256：`fa3312097ce21232d5cf9e763a2c753f98c61011bb01eced6b4316d27e987e50`。
- 许可：文件头 `SPDX-License-Identifier: GPL-2.0-only`。
- 性质：文件自称是“保留 observable policy、改用 native 6.12 API、显式生命周期
  管理以支持 built-in”的实现；**不是**设备 stock `6.6.118` `node_cache.ko` 的
  原始源码。当前设备仍运行 stock 模块，本文件没有加载或编译。
- 分析、与 stock 二进制的差异、6.6.143 适配清单见
  [docs/kernel/NODE_CACHE_SOURCE.md](../../docs/kernel/NODE_CACHE_SOURCE.md)。

## 规则

- 优先逐字节保存原始文件；需要修改时另存副本，不要覆盖来源文件。
- 记录来源、哈希、许可和是否参与构建。
- 不要把厂商源码直接并入 GKI 树；需要内置时走 `dash/patches/` 的显式补丁，
  并在补丁说明中写明来源、许可和验证结果。
