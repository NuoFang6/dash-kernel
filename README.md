# mikernel — dash (REDMI Turbo 5 Max / MT6991) GKI 6.6 内核工作区

本仓库是 `dash`（2602BRT18C / MT6991）的 GKI2.0 内核构建工作区：以 AOSP
GKI 源码为基线，叠加 BakaSU、SUSFS、厂商 `.ko` 兼容层和 stock parity
补丁，并提供从同步源码到打包 boot 镜像的完整脚本。

当前内核为 **6.6.143**（AOSP `android15-6.6-2026-10_r2` / `bf768be0`），
clang **r614150**（23.0.1，PGO/BOLT/LTO 预编译），ThinLTO 已开启。
设备 stock 为 `6.6.118-android15-8-gb9cc6ec16bc8-abogki536571621-4k`。

## 当前状态

| 项 | 值 |
|---|---|
| 同步基线 | `android15-6.6-2026-10_r2`（6.6.143） |
| 工具链 | clang r614150 / LLD 23.0.1，构建全程 clang |
| 优化 | `CONFIG_LTO_CLANG_THIN=y`；AutoFDO 未启用（需要 profile） |
| Root | BakaSU 内建（`CONFIG_KSU=y`）+ SUSFS v2.3.0 |
| 厂商兼容 | 638 个 stock 模块 `hard_missing=0`，实机加载 586 个 |
| 内存扩展 | stock vendor zram + ExtM 保留；lz4kd 通过 crypto API 选中 |
| PID | `pid_max` 硬钳 32768（`PID_MAX_LIMIT`） |

详细状态、验证证据和剩余缺口见 [docs/README.md](docs/README.md)。

## 仓库结构

```text
dash/                      构建工作区
  configs/                 stock 配置、ABI 白名单、功能开关
  patches/                 有序补丁系列（series 为唯一顺序）
  scripts/                 同步、打补丁、配置、构建、打包、校验
  Makefile                 一键入口
docs/                      项目文档与实测报告
third_party/               上游/配套子模块
BakaSU/                    BakaSU 内核侧子模块
```

以下目录只在本地生成，不入库：

```text
dash/src/                  AOSP/MTK 源码浅克隆
dash/toolchains/           clang 预编译包
dash/out/                  构建产物与 artifacts
handoff/                   本地交接快照、boot 备份、日志、厂商二进制
```

## 快速开始

```bash
git clone --recurse-submodules <repo-url> mikernel
cd mikernel/dash

make deps       # 检查构建依赖（Arch/CachyOS）
make toolchain  # 下载固定 clang r614150
make source     # 浅克隆 AOSP 到 versions.env 指定 commit
make patches    # 重置源码、接入 BakaSU、按 series 打补丁
make config     # stock.config + features.fragment
make build      # Image / Image.lz4 / vmlinux / System.map / config
make boot       # 继承 stock boot header/vbmeta/AVB footer，只替换 kernel
bash scripts/finalize.sh   # KCFI、stock 模块、boot 校验，写 SHA256SUMS
```

> `make patches` 会把 `dash/src/aosp/common` 重置到固定 commit 并重新打补丁。
> 长期修改只保存在 `patches/`、`configs/` 和 `docs/`，不要直接改源码树。

产物位于 `dash/out/artifacts/`，构建日志位于 `dash/out/dash/build.log`。

## 子模块

`.gitmodules` 固定了 BakaSU、SUSFS、lz4kd、droidspaces、SukiSU patch 以及
Content-Creation-Club 的 dash 构建/模块仓库。克隆后执行：

```bash
git submodule update --init --recursive
```

补丁应用时会检查子模块 commit，具体 pin 见 `dash/versions.env`。

## 文档

- [docs/README.md](docs/README.md)：文档入口、权威顺序、当前状态
- [docs/kernel/README.md](docs/kernel/README.md)：构建流程、功能与更新规则
- [docs/kernel/TEST_REPORT.md](docs/kernel/TEST_REPORT.md)：真机验证与修复记录
- [docs/kernel/BOOT_PACKAGING.md](docs/kernel/BOOT_PACKAGING.md)：boot/AVB 封装硬规则
- [docs/kernel/OPEN_ISSUES.md](docs/kernel/OPEN_ISSUES.md)：剩余缺口与风险
- [docs/kernel/ZRAM_EXTM.md](docs/kernel/ZRAM_EXTM.md)：内存扩展与 lz4kd 实机结论
- [docs/kernel/LOG_AUDIT_20261030.md](docs/kernel/LOG_AUDIT_20261030.md)：系统日志审计

## 注意

- 仅用于自有、已解锁设备的实验性内核；刷写前务必备份 `boot`/`init_boot`
  和 vbmeta，并确认 AVB 封装规则。
- 不要刷写紧凑镜像或修改 vbmeta flags，否则可能 bootloop。
- 厂商 `.ko` 加载兼容会跳过签名/vermagic/CRC 检查，仅适用于自有设备。
- 仓库不包含 AOSP 源码、clang 预编译包、厂商二进制或设备备份。

## 许可

内核补丁与脚本遵循其上游许可证（GPL-2.0）。各子模块遵循各自仓库的许可证。
