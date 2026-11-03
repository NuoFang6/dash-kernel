# mihomo Alpha 在 dash 的 Android 运行支持

调查日期：2026-10-30。目标不是“能编译”，而是确认 MetaCubeX/mihomo 在
Android 用户态实际用到的内核能力，并用给定 Clash 配置在 dash 上跑通 TUN
代理链路。

## 1. 上游 pin 与运行方式

| 项 | 值 |
|---|---|
| mihomo | `MetaCubeX/mihomo` Alpha，commit `ca8d7c41bf620dbe41c8d221f35dc5435216def5`（2026-10-28） |
| 实测二进制 | 自建 clean Alpha `ca8d7c4`（`v1.19.33-alpha-ca8d7c4`，Go 1.26.10，`with_gvisor`）；官方 `v1.19.33` release 仅用于早期对比 |
| TUN 依赖 | `github.com/metacubex/sing-tun v0.4.28` |
| Android 构建 | `GOOS=android GOARCH=arm64`，release 使用 `with_gvisor` |
| 本机内核 | `6.6.143-4k #8`，boot_b `0dc871a5…`（IPv6 NAT + addrtype，MPTCP 关闭） |

mihomo 在 Android 有两条运行路径：

- **CMFA / VpnService 路径**：应用通过 `VpnService` 拿到 TUN fd，没有 root，
  不做自动 iptables；进程匹配受 Android netlink/SELinux 限制。
- **root CLI 路径**（本次实测）：直接打开 `/dev/tun`，通过 netlink 配置
  TUN 地址、MTU、策略路由和 auto-redirect；可读取 `/data/system/packages.xml`
  做包名/UID 规则。`su` 域为 `u:r:ksu:s0`。

## 2. 代码层面确认的 Android 行为

- `listener/sing_tun/server_android.go`：`BuildAndroidRules()` 使用
  `/data/system/packages.xml` 和 netlink，把 include/exclude package 转成
  UID 范围。
- `sing-tun/redirect_linux.go`：Android 分支**硬编码使用
  `/system/bin/iptables`**，并设置 `useNFTables=false`。因此 Android 上
  `auto-redirect` 不依赖 nftables。
- 同一文件的 Android 分支在设置 `nat OUTPUT -> tun REDIRECT` 后直接
  `return nil`：**Android 的 auto-redirect 只处理本机 IPv4 TCP 出站**，不做
  PREROUTING/FORWARD，也不做 IPv6。热点共享需要 VPNHotspot 一类方案。
- `sing-tun/redirect_iptables.go`：完整 iptables 规则会使用
  `-m addrtype`、`-m owner`、`-m socket`、`DNAT/REDIRECT/TPROXY`。
- `sing-tun/redirect_nftables.go`：只有非 Android 才走 nftables；
  `route-address-set` 在 Android 上是 no-op。
- `hub/executor/executor.go`：`iptables.enable` 只在
  `runtime.GOOS == "linux"` 时执行；**Android 的 `tproxy-port` 不会自动装
  iptables**，TProxy 需要外部脚本/手动规则。
- `component/process/process_linux.go`：Android 使用 `NETLINK_INET_DIAG`
  加 `/proc/net/{tcp,tcp6,udp,udp6}` 回退；需要 `CONFIG_INET_DIAG` 和
  `CONFIG_INET_UDP_DIAG`。
- TUN 打开路径：Android 使用 `/dev/tun`；`gso: true` 通过
  `TUNSETOFFLOAD` 打开 `TUN_F_CSUM/TSO4/TSO6/USO4/USO6`。
- mihomo 的 Hysteria2/ShadowQUIC `brutal` 是 **QUIC 用户态拥塞控制**，不使用
  `tcp-brutal` 内核模块；后者只影响 TCP 套接字。

## 3. 内核能力对照与本机结论

| 能力 | 内核配置 | dash 状态 |
|---|---|---|
| TUN / `/dev/tun` | `CONFIG_TUN=y` | 已有，`/dev/tun` + `/dev/net/tun` 均存在 |
| TUN GSO/USO/GRO | `CONFIG_TUN` + TUN offload | 已有，实测 `mtu 9000`、`gso_max_size 65536` |
| 策略路由 / UID 规则 | `CONFIG_IP_MULTIPLE_TABLES`、`CONFIG_IPV6_MULTIPLE_TABLES` | 已有 |
| NAT / REDIRECT / DNAT | `CONFIG_IP_NF_NAT`、`CONFIG_IP_NF_TARGET_REDIRECT`、`CONFIG_NF_NAT` | 已有 |
| TPROXY / socket / owner / mark | `CONFIG_NETFILTER_XT_TARGET_TPROXY`、`..._MATCH_SOCKET`、`..._MATCH_OWNER`、`..._MATCH_MARK` | 已有 |
| **addrtype** | `CONFIG_NETFILTER_XT_MATCH_ADDRTYPE` | **原 stock 关闭；本次启用** |
| BBR / fq | `CONFIG_TCP_CONG_BBR=y`、`CONFIG_NET_SCH_FQ=y` | 已有，可用 `bbr` |
| TCP Fast Open | 无独立内核开关；`net.ipv4.tcp_fastopen` | 已设 `3`（client+server） |
| inet diag / UDP diag | `CONFIG_INET_DIAG`、`CONFIG_INET_UDP_DIAG` | 已有 |
| inotify | `CONFIG_INOTIFY_USER` | 已有；packages.xml watcher 可用 |
| MPTCP | `CONFIG_MPTCP` | **未启用**：实测开启后内核在 userspace 启动前卡死/看门狗复位；addrtype-only 正常启动 |
| nftables | `CONFIG_NF_TABLES` | 未启用；mihomo Android 分支明确不用 |
| IPv6 NAT/REDIRECT | `CONFIG_IP6_NF_NAT` 等 | **#8 已启用并实测**：`ip6tables -t nat` 可用，IPv6 TCP REDIRECT 成功 |
| ipset/xt_set | `CONFIG_IP_SET`、`CONFIG_NETFILTER_XT_SET` | 未启用；mihomo 本身不用，外部分流脚本可能需要 |

### 3.1 内核改动

- `CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y`：让 TProxy/redir 脚本的
  `-m addrtype --dst-type LOCAL` / `! --src-type LOCAL` 可用。
- `CONFIG_IP6_NF_NAT=y` + `CONFIG_IP6_NF_TARGET_MASQUERADE=y`：启用
  IPv6 REDIRECT/ip6tables nat；#8 已刷入并实测 `ip6tables -t nat -L` 正常。
- `dash/configs/abi_symbollist.raw` 增加
  `tcp_prot`、`tcpv6_prot`、`tcp_register_congestion_control`、
  `tcp_unregister_congestion_control`，供外部 `tcp-brutal.ko` 链接。
- `CONFIG_MPTCP` 明确保持关闭；`features.fragment` 和 `configure.sh` 有说明。

## 4. TCP Brutal（HyNetworks/tcp-brutal v2.0.1）

上游：`https://github.com/HyNetworks/tcp-brutal`，pin
`d2397ff8bca04a29fd2de01cf7d2d4b825224de8`，v2.0.1，外部内核模块。

- 以 git submodule 放在 `third_party/tcp-brutal`，不并入内核源码树。
- 构建：`make -C dash brutal`（或 `bash dash/scripts/build-tcp-brutal.sh`）。
  脚本会用 dash 的 clang/LLD、正确的 `LOCALVERSION` 构建 `brutal.ko`，
  校验 vermagic，并用本次内核的 build-time key 签名，输出到
  `dash/out/artifacts/brutal.ko`。
- 因为 `TRIM_UNUSED_KSYMS` 会把没有 whitelist 的导出裁掉，必须在
  `abi_symbollist.raw` 保留上述 4 个符号；否则 modpost 报 undefined。
- 实机加载：`insmod /data/local/tmp/brutal.ko`；加载后
  `/proc/sys/net/ipv4/tcp_available_congestion_control` 包含 `brutal`，
  `/proc/net/tcp_brutal/rules` 存在。
- 应用接口：`setsockopt(TCP_CONGESTION, "brutal")`，再用
  `TCP_BRUTAL_PARAMS` 设置 rate/cwnd_gain/group_id。实测
  `getsockopt(TCP_CONGESTION)` 返回 `brutal`。
- v2 destination rules 依赖 `/proc/net/tcp_brutal/rules` 和
  `ip route ... congctl lock brutal`。Android toybox 的 `ip` 不一定支持
  `congctl`；上游 `brutalctl` 也需要 Android/bionic 构建。当前仓库只交付
  `brutal.ko`，没有伪造 `brutalctl` Android 支持。
- **许可**：上游 LICENSE 为 GPL-3.0，模块声明 `MODULE_LICENSE("GPL")`。
  本仓库按外部模块构建/加载，不并入 GPL-2.0 内核源码；再分发前请自行评估
  许可兼容性。

## 5. 实机运行结果（2026-10-30，#8）

配置来源为用户提供的 Clash 订阅（本地 `handoff/mihomo-test/config.yaml`，
不入库）；测试时仅做三处修改：

- `log-level: debug`
- `inbound-mptcp: false`（MPTCP 内核禁用）
- `tun.device: mihomo`（显式接口名）

关键结果：

- `[TUN] Tun adapter listening at: mihomo([198.18.0.1/30],
  [fdfe:dcba:9876::1/126]), mtu: 9000, auto route: true, auto redir: true,
  ip stack: Mips`。
- `ip -d link show mihomo`：`UP,LOWER_UP`，`mtu 9000`，`gso_max_size 65536`，
  `gso_max_segs 65535`。
- `ip rule`：9000/9001/9010 规则 + table 2022 default dev mihomo；
  `iptables -t nat -S OUTPUT` 有 `mihomo-output`：
  `-o mihomo -p tcp -j REDIRECT --to-ports <port>`。
- DNS hijack 生效（日志有 `[DNS] hijack udp:...:53`），进程/包名匹配生效
  （日志有 `bin.mt.plus`、`com.google.android.gms` 等）。
- `busybox wget` 实测：经 TUN 访问 `http://www.gstatic.com/generate_204`
  成功；经 `http://127.0.0.1:7890` 代理成功；HTTPS 经 TUN 成功；mihomo
  健康检查节点 alive（延迟约 70–82 ms）。
- 无 TUN/GSO/TPROXY 内核错误；`dmesg` 无 panic/BUG。
- 唯一 mihomo 错误是 `/data/system/packages.xml` 的 fswatch 被移除
  (`fswatch: watcher removed`)，不影响已建立的 TUN/规则，属于文件替换监听
  问题，不是内核缺失。
- **IPv6 TUN**：`ip -6 rule` 有 9000/9001/9002 规则，`ip -6 route get
  2606:4700:4700::1111` 指向 `dev mihomo table 2022`；`busybox wget
  http://[2606:4700:4700::1111]/` 的日志显示
  `[TCP] [fdfe...] --> [2606...]:80 match PROXY`（HTTP 400 是目标站点对
  IP/Host 的响应，不是链路失败）。

### 5.2 REDIRECT（IPv4/IPv6 TCP）

- `nat OUTPUT` 规则：IPv4 `1.1.1.1:80`、IPv6 `[2606:4700:4700::1111]:80`
  → `REDIRECT --to-ports 7892`，两条规则安装 rc=0。
- 日志：`[TCP] 172.51.232.88:... --> 1.1.1.1:80 match PROXY`；
  `[TCP] [240e:462:2b40:200::1]:... --> [2606:4700:4700::1111]:80 match PROXY`。
- 结论：**REDIRECT 的 IPv4/IPv6 TCP 均工作**。
- 限制：对 UDP 使用 nat REDIRECT 时，mihomo 的 redir UDP listener 收到的是
  `127.0.0.1:7892`（原始目的地址丢失），会触发 loopback 拒绝；因此
  REDIRECT 模式不能覆盖本机 UDP。UDP 必须用 TPROXY/TUN。

### 5.3 TPROXY（转发链）

- 用 veth + netns 模拟外部流量，`mangle PREROUTING` 的 `TPROXY` 规则命中。
- **IPv4 UDP 成功**：`[UDP] 10.200.0.2:... --> 1.1.1.1:53 match PROXY`。
- TCP 在该 veth/netns 测试中未完成：TPROXY 计数增长，但 mihomo TCP listener
  未 accept；本地为验证 `IP_TRANSPARENT` 的 bind 顺序构建过 patched mihomo
  （pre-bind + 强制 tcp4），仍未复现。该 netns 环境本身连
  netns→host 的普通 TCP 也不通，因此 **TPROXY TCP 结论暂不确定**，不能
  声称已验证。
- **本机 APP 的 OUTPUT 流量不能直接用 TPROXY target**：内核拒绝
  `OUTPUT -j TPROXY`，需要 TUN（或 REDIRECT 的 TCP）覆盖本机应用。
- IPv6 TPROXY UDP 受同一 netns IPv6 路径影响，未取得有效日志；内核
  `NF_TPROXY_IPV6` 已启用，待真实转发客户端复验。

### 5.4 TUN（完整覆盖）

- IPv4 `gstatic/generate_204` 成功；IPv6 目标链路成功进入代理（HTTP 400
  为目标响应）。
- TUN 的 IPv6 默认路由、DNS hijack、进程/包名匹配均生效。
- **只有 TUN 能覆盖本机 IPv4/IPv6 TCP/UDP/ICMP**；REDIRECT/TPROXY 的协议
  覆盖不完整，不能宣称“任何流量都不漏”。

其他回归：

- `iptables -t mangle` 的 `-m addrtype`、`-m socket`、`TPROXY`、`MARK`，
  以及 `nat` 的 `REDIRECT`、`DNAT` 规则安装均返回 0。
- `tcp_fastopen=3`；`tcp_available_congestion_control: reno bbr cubic brutal`。
- `brutal` 模块 `insmod` 成功；`/proc/net/tcp_brutal/rules` 可读。
- ExtM：`comp_algorithm` 为 `[lz4kd]`，`backing_dev=/dev/block/dm-71`，
  16 GiB swap；`pid_max=32768`；KCFI 13/13、586 个模块加载。

### 5.5 标准 KSU 模块

- 模块：`mihomo_alpha`，版本 `v1.19.33-alpha-ca8d7c4-r3`，已安装到
  `/data/adb/modules/mihomo_alpha`，KSU `action=true`。
- 文件：`dash/modules/mihomo_alpha/`；安装脚本
  `bash dash/scripts/install-mihomo-module.sh`。
- 二进制：clean upstream Alpha `ca8d7c4`，**没有源码修改**；构建参数为
  `GOOS=android GOARCH=arm64 CGO_ENABLED=0`, `-tags with_gvisor`,
  `-trimpath`, 版本 ldflags `v1.19.33-alpha-ca8d7c4`。
- 配置文件：`/data/adb/mihomo/config.yaml`，模块不覆盖它；service 只执行
  `mihomo -d /data/adb/mihomo -f /data/adb/mihomo/config.yaml`。
- **不自动配置防火墙**：`service.sh` 没有任何 iptables/ip rule 命令；
  `tun.enable: false` 时不会创建 TUN/规则，`tun.enable: true` 时完全由
  mihomo 自己的 auto-route/auto-redirect 配置。
- 启动：等待 `sys.boot_completed=1` 和默认路由 `ip route get 1.1.1.1`
  带 `dev` 后再启动，避免开机过早导致 auto-detect-interface 为空。
- TFO：`post-fs-data.sh` 和 `service.sh` 都执行
  `echo 3 > /proc/sys/net/ipv4/tcp_fastopen`；重启后实测值为 3。
- action.sh 已实测：10 秒无操作自动退出；音量上停止 mihomo（用
  `sendevent` 注入 KEY_VOLUMEUP 验证）；音量下**重启 mihomo**（停止后
  调用 service.sh，实测 PID 变化且 TUN 恢复，不重启设备）。

## 6. 运行与清理

```bash
# 主机侧
adb push mihomo config.yaml /data/local/tmp/mihomo-test/
adb shell su -c 'cd /data/local/tmp/mihomo-test && chmod 755 mihomo && \
  nohup ./mihomo -d . -f config.yaml > mihomo.log 2>&1 &'

# Android 侧观察
adb shell su -c 'ip -d link show mihomo; ip rule | head; \
  iptables -t nat -S OUTPUT'
adb shell su -c 'tail -f /data/local/tmp/mihomo-test/mihomo.log'

# 停止（触发 mihomo 清理规则）
adb shell su -c 'pkill -TERM -f /data/local/tmp/mihomo-test/mihomo'
```

如不使用 MPTCP，保持 `inbound-mptcp: false`；如需 TFO，先
`sysctl -w net.ipv4.tcp_fastopen=3`。可选的 BBR/fq：

```bash
sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr
```

TCP Brutal 不是 mihomo 默认需要的内核模块；如要启用：

```bash
adb push dash/out/artifacts/brutal.ko /data/local/tmp/
adb shell su -c 'insmod /data/local/tmp/brutal.ko'
```

## 7. 未完成/限制

- **MPTCP 未启用**：`CONFIG_MPTCP=y`（含 IPv6 + diag）实测启动失败（花屏后
  看门狗复位），随后已用 `addrtype-only` 内核恢复。没有继续把 MPTCP 作为
  默认项；`mihomo` 配置必须 `inbound-mptcp: false`。如后续要追，建议单独
  做 MPTCP-only / 去 IPv6 子项的隔离构建。
- **Android auto-redirect 仅本机 IPv4 TCP**；IPv6 与热点转发不覆盖。
- **REDIRECT 本机 UDP 不可用**：nat REDIRECT 丢失原目的地址，mihomo 会
  收到 127.0.0.1:7892 并拒绝 loopback；UDP 用 TPROXY/TUN。
- **TPROXY TCP/IPv6 尚未形成可信实测结论**：veth/netns 测试环境自身 TCP
  路径异常；需要真实外部客户端（热点/另一台设备）复验。
- **只有 TUN 是完整覆盖模式**；TPROXY/REDIRECT 不能覆盖 ICMP 和所有
  TCP/UDP 场景。
- **TProxy 不会由 mihomo 自动装规则**（executor 的 Linux 判断）；需要手动
  iptables/ip rule。
- **nftables 未启用**：mihomo Android 分支显式选择 iptables；`route-address-set`
  在 Android 无效。
- **ipset/xt_set 未启用**：外部按国家/域名分流脚本可能需要。
- **brutalctl** 没有 Android 构建产物；v2 的 per-destination rules 需要
  `ip route congctl`，Android toybox 不保证支持。
- **自动进 fastboot 不是内核能保证的**：见
  [BOOT_PACKAGING.md](BOOT_PACKAGING.md) 的“启动失败与 fastboot”一节。

## 8. 复现命令

```bash
cd dash
make build                 # 当前 config（无 MPTCP）
make brutal                # 外部 tcp-brutal 模块
bash scripts/finalize.sh   # KCFI/638 模块/boot 封装
```

产物：

- `dash/out/artifacts/Image` `53aef1a9…`
- `dash/out/artifacts/boot.img` `0dc871a5…`
- `dash/out/artifacts/config` `9b586a24…`
- `dash/out/artifacts/brutal.ko` `7832a603…`（签名后 hash）
- KSU 模块：`handoff/mihomo_alpha.zip`（本地构建，不入库）

## 9. Alpha 子模块、应用遍历与 PGO（2026-10-30）

### 9.1 未修改子模块

- `third_party/mihomo` 已加入为 git submodule，分支 `Alpha`，pin
  `ca8d7c41bf620dbe41c8d221f35dc5435216def5`；工作树干净，没有任何本地源码修改。
- `dash/versions.env` 增加 `MIHOMO_DIR` / `MIHOMO_COMMIT`。

### 9.2 性能构建参数

`dash/scripts/build-mihomo.sh` 从子模块构建：

```text
CGO_ENABLED=0 GOOS=android GOARCH=arm64 go build \
  -tags with_gvisor -trimpath -buildmode=pie \
  -ldflags "-s -w -X ...Version=v1.19.33-alpha-ca8d7c4 ..."
```

收集 profile 后追加 `-pgo=<merged cpu profile>`。基线二进制
`63,897,896 B`；PGO 二进制 `64,028,968 B`，均已实机启动。

### 9.3 应用遍历 + pprof 脚本

- 设备脚本：`dash/scripts/mihomo-app-loop.sh`
- 主机编排：`dash/scripts/profile-mihomo-apps.sh`
- 应用顺序：从 `cmd package query-activities` 的 launcher 列表与
  `dumpsys usagestats` 的 ACTIVITY_RESUMED 次数合并，按常用次数降序，
  取前 80 个候选。
- 每个包只启动一次；启动后 1s 检查 `mCurrentFocus`，只有目标包在前台才算
  成功；未前台/无 launcher 的包直接跳过，不重试。
- 成功前台的应用在**同一 5s 窗口内请求一次**
  `debug/pprof/profile?seconds=5`；profile 请求本身就是驻留时间，因此没有
  独立的无动作尾巴。脚本不 force-stop、不关闭应用窗口/小窗。
- 实测：目标 60，70 次尝试，60 成功，wall time 460s；理论
  `60*(5+1)=360s`，实际启动开销约 100s，作为余量。
- 60 个 5s profile 片段合并为 `dash/profiles/mihomo-alpha-cpu.pgo`
  （91 KiB）；合并后 `Duration=300.48s`，CPU samples=`47.25s`（15.72%），
  284 个节点；主要样本在 `rules/wrapper.Match`、进程解析
  (`component/process`)、netlink/syscall、TUN 连接处理，说明 profile 覆盖了
  TUN 代理主路径而不是纯空闲时间。
- `go tool pprof -top` 质量报告见
  `handoff/mihomo-profile-top.txt`；PGO 构建已使用该 profile。

### 9.4 KSU 模块更新

- 模块版本：`v1.19.33-alpha-ca8d7c4-r4-pgo`；`bin/mihomo` 已验证与
  `handoff/mihomo-alpha-pgo` sha256 一致：
  `6486910e6427b7ccd9a4e702feaa8d600f788881ed392368fa8f836a04670ace`。
- 模块仍通过 `/data/adb/mihomo/config.yaml` 自动启动；TUN 开关完全由配置
  决定，service 不添加防火墙。当前 TUN 运行正常，`tcp_fastopen=3`。
- 当前配置文件 `log-level: silent`；启动时 mihomo 仍会打印少量初始配置
  日志，之后运行期不再增长。pprof 采集时需要临时改为 debug，脚本会恢复。
