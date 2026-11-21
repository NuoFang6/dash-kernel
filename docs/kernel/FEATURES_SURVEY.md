# 特性调查:WildKernels / GKID / EVONIX vs dash

调查日期:2026-11-21(当日完成补丁级核查与决策定案)。来源(均为当日浅克隆
核对源码/补丁签名):

- `WK-GKI` = [WildKernels/GKI_KernelSU_SUSFS](https://github.com/WildKernels/GKI_KernelSU_SUSFS)
- `WK-OP13` = [WildKernels/OnePlus_KernelSU_SUSFS](https://github.com/WildKernels/OnePlus_KernelSU_SUSFS)
- `WK-P` = [WildPlusKernel/kernel_patches](https://github.com/WildPlusKernel/kernel_patches)(WK 通用补丁本体,已逐个通读)
- `GKID` = [ahmed-alnassif/GKID-Kernels](https://github.com/ahmed-alnassif/GKID-Kernels)
- `EVONIX` = [NEESCHAL-3/EVONIX-Kernel](https://github.com/NEESCHAL-3/EVONIX-Kernel)(同域:POCO X7 Pro/Turbo 4 `rodin`/MT6899,HyperOS,GKI 6.6.144,同 root 栈,同款 clang r614150+ThinLTO)
- 本仓内核树 `dash/src/aosp/common`(android15-6.6 @ e6c23f621,**6.6.143**)

**验证等级**:全部为静态核查(补丁通读 / 代码逐行比对 / changelog 比对),未实测。

## 使用方式

**性质图例**:

| 图标 | 含义 |
|---|---|
| 🔧 | 纯 Kconfig 开关——上游已有特性,零源码风险 |
| 🏷️ | 官方/上游——主线内核、Google backport、知名独立上游 |
| 🏭 | 厂商补丁——Motorola / OnePlus OSS 导出 |
| ✍️ | 仓库作者自研(fatalcoder524 / Ahmed Al-Nassif) |
| 👤 | 社区知名作者——Sultan(kerneltoast)/ Panchajanya1999 等 |
| ❓ | 来源不明——无签名,社区流传 |

**决策语义**:`做(未开始)` = 机主已拍板、尚未动工;`不做(原因)` = 定案;
`待定` = 需进一步调查/实测;`✅` = dash 已有。

**结构**:§决策总表 是唯一权威台账(每行一项);细节机制集中在文末
**调查纪要 R1–R8**,行内以 `→ R#` 指向。`做(未开始)` 的动手顺序见
**落地批次**。

## 决策总表

### 网络

| 特性 | 性质 | 说明 | dash 现状 | 决策 |
|---|---|---|---|---|
| BBR v1 / CUBIC / WireGuard / IPsec ESP / FQ / FQ-CoDel / SCH_INGRESS | 🔧 | 上游自带 | ✅ | — |
| BBRv3 | 🏷️+✍️ | ACK 6.6 现存 TCP_CONG_BBR 是 v1;采用 WK android15-6.6 KABI 版 → R1 | ⚠️ | **做(未开始)**——按 R1 三层验证(静态已核→构建 CRC 零漂移→实机) |
| Westwood+/BIC/HTCP | 🔧 | 上游 Kconfig,CC 状态全存 icsk_ca_priv,不触 ABI,默认仍 cubic | ⚠️ 仅 CUBIC+BBR | **做(未开始)**——仅打开支持;Westwood 主打弱网 |
| CAKE / PIE / FQ-PIE qdisc | 🔧 | 上游 Kconfig(stock 未开;`NET_SCH_FQ_PIE` 可同批) | ⚠️ | **做(未开始)**——不设默认,按需 `tc qdisc add` |
| IP Set 全家桶 | 🔧 | 16 种 set 类型,现仅 HASH_IP/HASH_NET → 补齐其余 14 种 | ⚠️ | **做(未开始)**——配 DroidSpaces 防火墙 |
| TTL / HL target | 🔧 | iptables 改 TTL/Hop-Limit(热点共享检测对抗用) | ⚠️ | **不做**——无此需求,要时再开 |
| CIFS(SMB) | 🔧 | 上游 Kconfig | ❌ | **不做**——手机无场景,体积/攻击面 |
| IPv6_NAT_FIX | ✍️ | 实为 config_data 伪装(藏 config.gz 里的 IP6_NF_NAT)→ R5 | ❌ | **不做**——正常启用无需藏;单条伪装无意义 |
| force_tcp_nodelay | 👤 | 实为 setsockopt 劫持 → R5 | ❌ | **不做**——吞掉合法 TCP 选项;Go/mihomo 已默认 nodelay |
| TCP 重传生命周期/urgent data 修复 | 🏷️ | 主线修复;urgent data 已进 stable 6.6.157,重传生命周期仍不在 → R7 | ❌ | **做(未开始)** |
| UDP tunnel segmentation UAF 修复 | 🏷️ | 主线内存安全修复;UDP tunnel/GSO 组已进 6.6.151–161(大概率覆盖) → R7 | ❌ | **做(未开始)** |
| IPv6 checksum bounds/ext 扩展头/SR 校验修复 | 🏷️ | 主线解析加固;checksum bounds 已进 6.6.158 → R7;IP6_NF_NAT=y 在用 | ❌ | **做(未开始)** |

### 性能 / 调度

| 特性 | 性质 | 说明 | dash 现状 | 决策 |
|---|---|---|---|---|
| HMBIRD SCX(sched_ext 移植) | 🏭 | OnePlus fengchi;HyperOS 无 hmbird daemon → R6 | ❌ | **不做**——零收益,与 MTK EAS/HyperOS 冲突 |
| CPU 扫描顺序修正 | 🏷️ | Hao Jia 上游提交,1 行;stable 6.6 已含,ACK 树未含 = 补齐上游 → R2 | ❌ | **做(未开始)** |
| CACHE_HOT_BUDDY 关闭 | 👤 | Sultan 1 行(features.h);DSU 同簇迁移不掉局部性 → R2 | ❌ | **做(未开始)**——与 MTK EAS 叠加实测 |
| PREEMPT_SHORT backport | 🏷️ | 上游 v6.12 EEVDF 特性:短 slice eligible 任务可抢占长任务 → R2 | ❌ | **做(未开始)**——同批实测 |
| mem_opt_prefetch | 🏭 | Motorola 2015:copy_template.S +2 条 prfm(=GKID 0007 同补丁) → R3 | ❌ | **做(未开始)**——收录一份 |
| arm64 memcmp(0008) | 🏷️ | ARM 官方 optimized-routines 新版(SIMD) → R3 | ❌ | **做(未开始)**——一次性正确性验证 |
| arm64 clear_page 16B 对齐(0017) | 👤 | Sultan 1 行 `.p2align 4`;INIT_ON_ALLOC=y 故为热路径 → R3 | ❌ | **做(未开始)** |
| int_sqrt 3x | 👤 | StatixOS 起源,微基准 3x → R3 | ❌ | **做(未开始)**——微收益零风险 |
| file_struct 8B 对齐 / fs cache pressure | ✍️ | → R3 | ❌ | **不做**——收益趋零 + CRC 风险 / 运行时 sysctl 即可 |
| 300Hz timer | 🔧 | stock 250Hz | ⚠️ | **不做**——收益边际,功耗回归风险大 |
| Fake config | ✍️ | 伪装 /proc/config* | ❌ | **不做**——已有 SUSFS spoof_cmdline |
| hide_adb_jdwp_sockets | ❓/✍️ | 对 app-UID 四层隐藏 adbd/jdwp-control → R5;依赖 helper 已自带 | ❌ | **做(未开始)**——实测 adb 调试不受影响 |
| 模块强制加载(fail signature) | 👤 | Pzqqt | ✅ 超集 | **不做**——vendor-ko-compat 更全 |
| LTO Full | 🔧 | `CONFIG_LTO_CLANG_FULL`(arch/Kconfig:770;stock 本身 LTO_NONE) | ✅ ThinLTO | **做(未开始)**——零 ABI;构建时长↑,CI fast 保持 NoLTO |
| MGLO(=LLVM MLGO) | ❓ | MLGO 需带模型 clang(实测 r614150 不支持) → R4 | ⚠️ | **做(未开始)**——以 AutoFDO 落地(工具链已实证);MLGO 列后续 |
| schedutil 限流溢出/policy init 修复 | 🏷️ | 主线修复;限流溢出已进 stable 6.6.157,policy init 不在 → R7 | ❌ | **做(未开始)** |
| uclamp DVFS 通知/EAS carryover 修复 | 🏷️ | 主线修复,不在 stable;MTK EAS 高相关 | ❌ | **做(未开始)**(实机核 EAS) |
| misfit 迁移/CPU-group 选择修复 | 🏷️ | 主线 EAS 修复;同族已进 6.6.158 → R7 | ❌ | **做(未开始)**(实机核 EAS) |
| RT push-IPI livelock 修复 | 🏷️ | 主线 RT 均衡修复,不在 stable | ❌ | **做(未开始)** |
| POSIX CPU-timer 竞态/PID 泄漏修复 | 🏷️ | 6.12+ 重构系列;CVE-2026-98260 同族,exec cleanup 已进 6.6.158 → R7 | ❌ | **不做**——不手动管理:等 stable 自行下发(公开利用族系 stable 会追),重构主体审计面过大 |
| timer slack RT 继承修复 | 🏷️ | 主线修复,不在 stable | ❌ | **做(未开始)** |
| arm64 per-cpu write 修复 | 🏷️ | 主线 arch/arm64 修复,零 ABI,不在 stable | ❌ | **做(未开始)** |
| OPP/EM 解析修复 | 🏷️ | 主线修复;OPP 竞态已进 6.6.160,EM 不在 → R7 | ❌ | **做(未开始)** |
| MGLRU suspend 可中断 | 🏷️ | 主线修复,不在 stable;MGLRU 已启用 | ❌ | **做(未开始)** |
| DAMON 修复组(6.6.145 收录) | 🏷️ | stable 官方下发 → R7 | ❌ | **做(未开始)**——随 bump 到得;**ACK tag 含 6.6.145 后删除此行** |
| TLB/writeback/PSI 修复组(6.6.145 收录) | 🏷️ | stable 官方下发 → R7 | ❌ | **做(未开始)**——随 bump 到得;**ACK tag 含 6.6.145 后删除此行** |

### 文件系统 / I/O

| 特性 | 性质 | 说明 | dash 现状 | 决策 |
|---|---|---|---|---|
| F2FS GC 50ms / uncongestion 6ms / min_fsync_blocks 20 | ✍️/👤 | 三件套 → R5;OPPO/Huawei 量产同款 | ❌ | **做(未开始)**——各一行零 ABI;与 060-f2fs-xiaomi 回归 |
| ext4 commit age 5→30s | ✍️/👤 | Arjan distro tweak → R5 | ❌ | **不做**——rw ext4 少;可用挂载参数 `commit=` 调 |
| SK_MEM_PACKETS 256→1024 | ✍️ | 即 net.core.wmem/rmem_max 默认 ×4 → R5 | ❌ | **不做**——运行时 sysctl 可调(同 cache pressure 立场) |
| ADIOS I/O 调度器 | 🏷️ | 独立上游(Masahito Suzuki 2025);EVONIX 用于 UFS 4.0 MCQ 默认 | ❌ | **做(未开始)**——实测对照 mq-deadline 后定默认 |
| zRAM LZ4 回写 / mq-deadline / schedutil | 🔧 | stock | ✅ 超集 | —(lz4kd+ExtM 实跑) |
| ext4 orphan 泄漏/DIO fallback 修复 | 🏷️ | 主线修复;orphan 已进 6.6.157 → R7 | ❌ | **做(未开始)** |
| F2FS move-range 校验/writeback 报错修复 | 🏷️ | 主线修复,不在 stable;HyperOS 文件管理走 move-range | ❌ | **做(未开始)** |
| swap readahead ceiling 修复 | 🏷️ | 主线修复,不在 stable;swap=zRAM | ❌ | **做(未开始)** |

### 电池 / 电源

| 特性 | 性质 | 说明 | dash 现状 | 决策 |
|---|---|---|---|---|
| Freezer timeout 20s→1s | 👤 | Sultan;还锁死 sysfs 写入口 → R5 | ❌ | **不做**——与厂商冻结策略交叉,收益仅死锁场景 |
| alarmtimer 唤醒窗口收敛 | ✍️ | 固定 2s → 最近到期+1ms → R5 | ❌ | **做(未开始)**——一两行省电零风险 |
| s2idle 单次唤醒 | 👤 | Sultan:pm_abort_suspend 到 1 才调 s2idle_wake → R5 | ❌ | **做(未开始)** |
| wakelock 全局 500ms cap | 👤 | 无超时 wake_lock 强制过期 → R5 | ❌ | **不做**——HyperOS critical 路径依赖无超时 wake_lock |
| SDP 900mA 充电 | ✍️ | 纯 oplus/高通方案(DT 属性) → R5 | ❌ | **不做**——MTK 充电栈不可移植 |

### 安全 / 隐藏

| 特性 | 性质 | 说明 | dash 现状 | 决策 |
|---|---|---|---|---|
| SUSFS 全套 | 🏷️ | simonpunk;pin f98f082 实为 **v2.4.0**(STATUS 曾误标 v2.3.0 已订正) | ✅ v2.4.0 九特性 | — |
| SUSFS priority-uid filter | 🏷️ | f98f082 门控,apply-patches.sh 注入 Kconfig | ✅ 2026-11-21 启用 | — |
| maps 伪装(maphide) | 👤 | backslashxx,WK-P 归档 → R8 | ✅ SUSFS sus_map 已启用(`SUS_MAP=y`) | **不做**——sus_map 覆盖同域 |
| Baseband Guard(BBG LSM) | 🏷️ | vc-teahouse 上游(EVONIX 按 commit `a54e0dc6cf0a` 集成) | ❌ | **做(未开始)**——MTK 适配需评估(efisp 是高通向) |
| Unicode bypass fix(零宽字符) | ❓/✍️ | casefold 空分解边界修复;上游从未采纳 → R5 | ❌ | **做(未开始)**——采纳前 casefold 回归 |
| AVC log spoofing | ✍️ | KSU 触发路径 avc 日志伪装 | ❌ | **做(未开始)**——需移植到 BakaSU 路径 |
| throne_tracker kthread / supercall pull-list | ✍️ | gkid KSU fork 专属 → R5 | ❌ | **不做**——跟 BakaSU 上游 |
| Multiple Managers | ✍️/🔧 | BakaSU 已带 | ✅ | — |
| ptrace leak fix(<5.16) / vendor modules blacklist / uname 自定义伪装串 | ✍️/🏷️ | — | ❌ | **不做**(6.6 不适用 / dash 无对应模块 / 我们伪装 stock 串更优) |

### 容器 / 驱动 / 生态

| 特性 | 性质 | 说明 | dash 现状 | 决策 |
|---|---|---|---|---|
| DroidSpaces | 🏷️ | 官方配方(与我们 090 同源) | ✅ CRC 零漂移实证 | — |
| NoMount / Mountify | 🏷️ | 上游 metamodule | ✅ 内建 v2.3.1 | —(已选型 NoMount) |
| ZeroMount(NoMount 替代) | 🏷️ | 自研 VFS 驱动+Rust,3 策略回退+WebUI+bootloop guard → R8 | ❌ | **不做**——只用 NoMount;bootloop guard/策略回退仅作思路参考 |
| NTSync | 🏷️+🔧 | 主线驱动(Wine)backport,/dev/ntsync | ❌ | **做(未开始)**——EVONIX 已实证;纯新增驱动零 ABI |
| NetHunter + WirelessKSU | 🔧+✍️ | 渗透驱动 + monitor-mode patch | ❌ | **不做**——维护面大,需要时单独评估 |
| ReSuSFS / apply_kernel_compat.py / usbadb_gate | ✍️ | 用户态/反纪律/自写驱动 | ❌ | **不做**(管理器生态 / 与"补丁可审"相反 / 无场景) |
| 多 Root 变体 | 🏷️ | 各上游 fork | ✅ 已选 BakaSU | — |

## 做(未开始)——落地批次(38 项)

- **批次 0:随基线 bump 自动到货**(等 ACK 2026-11+ tag;到货后删/改行,勿手动 backport):
  DAMON 组、TLB/writeback/PSI 组(6.6.145 整行);
  schedutil 限流溢出(157)、TCP urgent data(157)、IPv6 checksum bounds(158)、
  misfit 同族(158)、ext4 orphan(157)、OPP 竞态(160)、UDP tunnel/GSO 组(151–161)、
  posix-timer exec cleanup(158)——以上为混合行的 stable 部分,到货后更新行说明。
- **批次 1:纯 config(features.fragment 即可)**:Westwood+/BIC/HTCP、
  CAKE/PIE/FQ-PIE、IP Set 全家桶、RCU_LAZY 启用(`rcutree.enable_rcu_lazy=0` 回退)、
  WQ_POWER_EFFICIENT_DEFAULT(`workqueue.power_efficient=0` 回退)、
  KFENCE_DEFERRABLE(`kfence.deferrable=1` 等价)、LTO Full(CI fast 保持 NoLTO)、
  ARM64_TUNE(**先读实机 `/proc/cpuinfo` CPU part/DTB 定核心型号再选 `-mtune` 自加 Kconfig**,不照搬 rodin A725)。
- **批次 2:一行/小型补丁(零 ABI)**:CPU 扫描顺序、CACHE_HOT_BUDDY、
  mem_opt_prefetch、memcmp、clear_page 16B、int_sqrt、alarmtimer 唤醒窗口、s2idle 单次唤醒。
- **批次 3:中型 backport/移植(逐条审 + 实测)**:BBRv3(三层验证 R1)、
  PREEMPT_SHORT、ADIOS、uclamp/EAS 组、misfit CPU-group、RT push-IPI、
  timer slack、arm64 per-cpu write、OPP/EM、TCP 重传生命周期、F2FS 三件套(与 060 回归)、
  F2FS move-range、swap readahead、MGLRU suspend、Unicode bypass(casefold 回归)、
  hide_adb_jdwp(adb 回归)、NTSync、BBG(MTK 适配评估)、AVC log spoofing(移植 BakaSU)、
  AutoFDO(profile 采集流程,见 R4)。

## 不做——原因速查

| 项 | 一句话原因 |
|---|---|
| TTL/HL target | 无对抗需求 |
| CIFS | 手机无场景 |
| IPv6_NAT_FIX | config_data 伪装,无意义 |
| force_tcp_nodelay | setsockopt 劫持;Go 已默认 nodelay |
| HMBIRD SCX | HyperOS 无 daemon 零收益 + EAS 冲突 |
| file_struct 8B 对齐 | 收益趋零 + genksyms CRC 风险 |
| fs cache pressure 50 | 运行时 sysctl 即可 |
| 300Hz timer | 收益边际,功耗风险 |
| Fake config | 已有 SUSFS spoof_cmdline |
| 模块强制加载 | vendor-ko-compat 更全 |
| POSIX CPU-timer 重构 | 不手动管理,等 stable 下发;审计面过大 |
| ext4 commit age 30s | 掉电窗口大,rw ext4 少 |
| SK_MEM_PACKETS | 运行时 sysctl |
| Freezer timeout 1s | 与厂商冻结策略交叉 + 锁 sysfs |
| wakelock 500ms cap | 破坏框架 critical 路径 |
| SDP 900mA | oplus/高通栈不可移植 |
| maps 伪装(maphide) | SUSFS sus_map 已覆盖 |
| throne_tracker / supercall pull-list | gkid fork 专属,跟 BakaSU 上游 |
| ptrace leak fix / vendor blacklist / uname 串 | 不适用 / 无对应模块 / 已有更优 |
| ZeroMount | 只用 NoMount(思路仅参考) |
| NetHunter + WirelessKSU | 维护面大 |
| ReSuSFS / apply_kernel_compat.py / usbadb_gate | 生态 / 反纪律 / 无场景 |

## 待定

无——决策总表 59 行全部定案(38 行做 + 21 行不做;合并行按行计,
如"ptrace/blacklist/uname"合为一行),另有 12 项 `✅` 已有。

## 调查纪要

以下为决策总表的细节依据;验证等级均为静态核查。

### R1 BBRv3 兼容性:根源与三层确认

**"BBRv3 与原厂模块不兼容"的技术根源**:BBRv3 `struct bbr` 约 140B,超出
GKI 预留 `icsk_ca_priv`(104B)。两种实现路线:

- **google/bbr 原系**(GKID `kernel-patches/bbrv3/bbrv3.patch`,0ctobot 自
  google/bbr@cb31f3d 的 backport):`inet_connection_sock.h` 直接
  `#define ICSK_CA_PRIV_SIZE (144)`(13→18×u64)。`tcp_sock` 首成员就是
  `inet_connection_sock`,其后字段全部 +40 偏移 → 引用 tcp_sock 的 genksyms
  CRC 全变 → **厂商 .ko 全部加载失败**。这就是传闻的根源(同类讨论:
  [zen-kernel#406](https://github.com/zen-kernel/zen-kernel/issues/406))。
- **WK android15-6.6 版**(fatalcoder524,KABI compliance):`struct bbr3`
  (实测 sizeof=152B)由 `kmalloc(GFP_ATOMIC)` 外置,ca_priv 只存指针;
  tcp_sock 唯一改动是把 `unused:5` 位域填入 fast_ack_mode/
  tlp_orig_data_app_limited(同一 u8,size/offset 不变)并以
  `#ifndef __GENKSYMS__` 保 CRC;**未触碰 ICSK_CA_PRIV_SIZE/ANDROID_KABI_USE**。
  依赖 `proc_dou8vec_minmax`,6.6 已自带。

**旁证**:EVONIX 的 BBRv3 走 inline 144 路线且无 guard,其"100% KMI
compatibility"说法在源码层面不成立(rodin 厂商模块恰好少引用 tcp 符号才没炸);
本仓 KMI 清单含 **286 条 tcp 相关符号** → 必须走 WK KABI 版路线。

**确认三层(做之前按序)**:①静态——查未 guard 的 struct 实布局变化 /
ICSK_CA_PRIV_SIZE / ANDROID_KABI_USE(WK 6.6 版已核:均无);②构建——复用
090-droidspaces CRC 零漂移流程;③实机——对照 `device-audit/lsmod.txt` 全量
加载 + dmesg 无 ABI 报错 + `ss -i` 看 bbr3 状态机 + mihomo 回归。

**残余风险**:WK 版仍改 tcp_input/output/rate 行为(PLB、fast_ack、
TCP_USEC_TS、RTAX_FEATURE_ECN_LOW、丢包响应),作用于全部 TCP 连接;
每连接额外 kmalloc ~152B。

### R2 调度补丁:扫描顺序 / CACHE_HOT_BUDDY / PREEMPT_SHORT

- **CPU 扫描顺序**(GKID 0018/WK-P):实为 Hao Jia(字节)上游提交
  ([lore](https://lore.kernel.org/r/20221216062406.7812-3-jiahao.os@bytedance.com),Peter Zijlstra 签收):`select_idle_capacity()`
  的 `for_each_cpu_wrap` 从 `target+1` 起扫(target 已查过)。stable 6.6.143
  已含(fair.c:7462),ACK 树未含(:7549)→ 补齐上游,零风险。
- **CACHE_HOT_BUDDY**(GKID 0020/WK-P):Sultan 一行 `SCHED_FEAT(...,false)`。
  该 feature 把"buddy 任务"视为 cache-hot 阻止迁移;关闭后 buddy 可迁往
  idle CPU。DSU 同簇 L2/L3 共享,同簇迁移不掉局部性 → 唤醒延迟↓、idle
  利用率↑;跨簇迁移仍有其他 gate。与 MTK EAS/scheduler.ko 叠加需实测。
- **PREEMPT_SHORT**(上游 v6.12,stable 6.6 无):EEVDF 唤醒抢占——请求
  slice 更短的 eligible 唤醒任务可取消当前任务的 slice 保护并抢占
  (`do_preempt_short`;被 SHORT 抢占的任务不按"未运行"惩罚,
  `did_preempt_short`)。上游默认 true。零结构/KABI;6.6 无 RESPECT_SLICE,
  backport 非 1:1 需审;与 MTK EAS 叠加实测。

### R3 fs/性能杂项:file_struct / cache pressure / arm64 mem / int_sqrt

- **file_struct 8B 对齐**(Sultan):`struct file` aligned(4)→(8)。4.x 时代
  收益(hackbench +5%)来自 slab 对象落 4 mod 8;6.6 上尾部 ANDROID_KABI_RESERVE×2
  保证 sizeof≡0 mod 8,收益消失;而 fs.h 属性改动可能变 genksyms CRC。
- **fs cache pressure**(Tyler Nijmeh):默认 100→50,本就是运行时 sysctl
  (`/proc/sys/vm/vfs_cache_pressure`),不需要改内核。
- **0004**(=WK optimized_mem_operations):Matteo Croce 上游 lib/string.c
  系列——**arm64 上 no-op**(arm64 定义 `__HAVE_ARCH_MEM*` 走汇编,generic
  版不编译)。签名齐全(并非"无签名")。
- **0007**(=WK mem_opt_prefetch):Motorola(Hong-Mei Li 2015)copy_template.S
  +2 条 `prfm pldl1strm`(入口 + 64B 主循环)。prfm 是 hint 不 fault,零 ABI;
  2015 实测 +15%,现代硬件预取下收益缩水。
- **0008**:ARM 官方 optimized-routines 新版 memcmp(7a9fd1603e):<16B 用
  ldr/ldp+ccmp,≥160B 走 NEON 64B/迭代(eor+umaxp)。同符号同语义零 ABI;
  需一次性正确性验证(上游代码可信)。
- **0017**:Sultan 一行,`__pi_clear_page` 前 `.p2align 4`;我们
  `INIT_ON_ALLOC_DEFAULT_ON=y`,clear_page 确为热路径。
- **int_sqrt**:StatixOS(Vaisakh Murali)起源,WK(FlyFrog)/GKID(Ahmed)同一
  补丁:固定 BITS_PER_LONG 循环二位开方,微基准 3x,内核调用点少。

### R4 编译优化:MGLO=MLGO 实测 + AutoFDO 旁证

WK-OP13 自述"MGLO = Machine Learning-Guided Optimization" = LLVM **MLGO**
(ML 引导内联/寄存器分配,`-mllvm -enable-ml-inliner` /
`-mlgo-regalloc-forcing-model` + 预训练模型),纯编译器优化,无内核 patch。
实测 AOSP clang r614150:`-mlgo-regalloc-forcing-model` 报 **Unknown command
line argument** → 官方 prebuilt 不含 MLGO 模型;复现需自带模型的第三方
clang 或自编 LLVM。WK-GKI 主文档无此词,营销名成色有限。

**AutoFDO 可行性已被 EVONIX 实证**:同款 r614150+ThinLTO+`AUTOFDO_CLANG=y`
在 rodin 实跑;`CONFIG_AUTOFDO_CLANG` 在我们 arch/Kconfig:804 本就存在,差的
只是 config+profile 采集。**其教训**:`O3` 候选导致 Android 早期 BPF load
探测失败,回退 O2——与我们 fast(NoLTO)路线互为参照。

### R5 补丁级核查:网络 / fs / 电源 / KSU 系(机制与兼容性)

- **IPv6_NAT_FIX**:不是功能修复——kernel/Makefile 注入 sed,把 IKCONFIG
  config_data 的 `CONFIG_IP6_NF_NAT=y` 改显示为 `=n`(功能保留),反"读
  config.gz 判内核"检测。我们 IKCONFIG_PROC=y 且正常启用,不跟。
- **force_tcp_nodelay**(Panchajanya1999):do_tcp_setsockopt 开头
  `optname=TCP_NODELAY`——**所有 SOL_TCP setsockopt**(CONGESTION/KEEPIDLE/
  MSS/FASTOPEN_CONNECT 等)被静默改写。Go/mihomo 默认已 SetNoDelay(true)。
- **hide_adb_jdwp_sockets**(无签名):对 app-UID 四层隐藏 ADB/JDWP:
  ①readdir 三个 filldir 回调跳过名为 `adbd` 的 socket 目录项;②
  `susfs_is_inode_sus_path` 把 `/dev/socket/adbd` 的 socket inode 标记
  sus_path(连 stat/access 一起挡);③af_unix bind/connect 包装——app 连
  `/dev/socket/adbd` 或抽象 `@jdwp-control` 返回 EACCES/ENOENT/ECONNREFUSED
  (抽象 jdwp-control 的 bind 假装成功返回 0);④/proc/net/unix 过滤这两类
  地址行。零结构/KABI(静态 ops 指针替换);依赖的 `susfs_is_current_app_uid()`
  我们 SUSFS v2.4.0 已自带(susfs_def.h:114);仅影响 app UID,shell(2000)/
  root 调试不受影响。
- **F2FS 三件套**:①GC urgent sleep 500→50ms(0012,Panchajanya1999,基于
  topjohnwu Magisk PR#5462——vold IdleMaint 本会运行时设 50ms,未设成的设备
  默认 500ms 太慢);②congestion wait 20→6ms(0014,Park Ju Hyung +
  Danny Lin/kdrag0n,IO 关键路径少等,250Hz 下 8ms);③min_fsync_blocks 放大
  20(0016,OPPO/Huawei 量产同款,fsync 攒批减次数)。
- **ext4 commit age**(0021):JBD2 默认 5→30s(Arjan van de Ven,distro
  tweak);掉电丢 30s 窗口(原 5s)。
- **SK_MEM_PACKETS**(0022):`_SK_MEM_PACKETS` 256→1024(Colin Ian King)
  = SK_WMEM/SK_RMEM_MAX ×4 = sysctl 默认。
- **Freezer timeout**(gkid 0015=Sultan 原作):20s→1s + **锁死
  pm_freeze_timeout sysfs 写入口**;理由=Android 冻结通常 <100ms,拖到超时
  的都是死锁。
- **alarmtimer**(0009,Andrzej Perczak):suspend 失败路径强制唤醒窗口从固定
  2s → 最近到期+1ms(实测均值 2s→1.5s)。
- **s2idle**(0019=Sultan):`pm_system_wakeup()` 仅在 `pm_abort_suspend`
  增到 1 时调一次 `s2idle_wake()`(免重复唤醒尝试;s2idle 机制自带同步)。
- **wakelock cap**(Panchajanya1999):无超时 `pm_wake_lock` 从 stay-awake
  改 500ms 自动过期(动机=卡死 wakelock 如 tx_swr_ctrl)。
- **SDP 900mA**(fatalcoder524):纯 oplus/高通——early_initcall 用
  of_update_property 把 DT `qcom,input_current_usb_ma` 500→900,oplus_chg.ko
  自读,不 kprobe。
- **throne_tracker kthread**(gkid):其 KSU fork 的 throne_tracker 加
  `KSU_THRONE_TRACKER_ALWAYS_THREADED`——kthread 运行(含首跑)+packages.list
  打开重试;FDE/FBEv1 下 crowning 可能略延迟。
- **supercall pull-list**(gkid):其 KSU fork 的 supercall dispatch 加
  `KSU_UMOUNT_GETSIZE/GETLIST`,userspace 可读回 umount 列表。
- **Unicode bypass fix**:casefold UTF-8 归一化对"分解结果为空(零宽字符)"
  的游标状态处理;本仓/stable 6.6.144/mainline v6.12 逐字一致(上游未采纳,
  社区自研);`CONFIG_UNICODE=y` 路径存在。

### R6 EVONIX(rodin)对比要点

同域(MT6899 vs MT6991,HyperOS MTK 4K GKI 6.6,同 root 栈)。除已列行项外:

- **EVONIX rodin 自研**(`CONFIG_EVONIX_*`:增强 schedutil/动态 headroom/UI
  线程识别/SCHED_RESPONSIVE/MM_ADAPTIVE/IO_PRIO/PM_WQ 等):设备专属调参,
  动调度与 VM 行为 → **不做**。
- 其 NoMount(fs/nomount 内建)与我们选型一致;BakaSU SELinux 桥
  (`ksu_security_context_to_sid`)我们 pin 已含——**无缺口**。
- **MTE 分歧**:EVONIX 关 MTE 规避 Dimensity 8400 vendor 冲突;我们 stock
  `CONFIG_ARM64_MTE=y` 实机正常——按设备实况,不动。
- **WQ/KFENCE/RCU_LAZY/PREEMPT_SHORT/ARM64_TUNE 的机制细节**已并入
  总表与 R2;`WQ_POWER_EFFICIENT` 受影响面=本仓仅
  `system_power_efficient_wq`/`system_freezable_power_efficient_wq`
  两队列(81 个 .c 驱动使用),`workqueue.power_efficient=0` 可回退;
  `KFENCE_DEFERRABLE` 在 lib/Kconfig.kfence:48(上游自带,KUnit 自测在该
  模式必失败);RCU_LAZY stock 已有仅 `DEFAULT_OFF=y`。

### R7 stable 6.6.144–162 分类与 bump 跟踪(2026-11-21 二次复核)

对 EVONIX 发行日志(v1.0→V4.6)全量核对 + 与 stable changelog
(**截至 2026-11-21 最新 6.6.162**,6.6.163 已 404)逐项比对。注:EVONIX v3.5
自述"cherry-pick kernel.org stable 6.6.143–6.6.156",其区间与实际节奏存疑,
以逐项核对为准。

- **已进 stable(官方下发,bump 即得)**:DAMON 修复组(6.6.145,1226 commit
  大版本)、TLB/writeback/PSI 组(6.6.145)、
  `cpufreq: schedutil: Fix rate limit overflow`(6.6.157)、
  `tcp: fix corruption of urgent data on multi-segment retransmit`(6.6.157)、
  `net: skbuff: fix pull-bound underflow in skb_checksum_setup_ipv6()`(6.6.158)、
  misfit 同族 `Reject misfit pulls onto busy SMT siblings on
  asym-capacity`(6.6.158)、`exec: Cleanup POSIX timers right after
  de_thread()`(6.6.158)、ext4 orphan 组(6.6.157)、动态加 OPP 竞态(6.6.160)、
  UDP tunnel/GSO 组(6.6.151–161)。
- **仍不在 stable(EVONIX 自行挑选的主线 backport)**:uclamp DVFS 通知/
  EAS carryover、schedutil policy init、TCP 重传生命周期、POSIX CPU-timer
  重构主体、swap readahead、MGLRU suspend、timer slack RT 继承、ext4 DIO
  fallback、F2FS move-range、arm64 per-cpu write、EM 解析、RT push-IPI。
- **跟踪规则**:纯 stable 项整行列行(标"ACK tag 含 6.6.145 后删除此行");
  混合行(部分在 stable)到货后更新行说明,不删整行。
- **EVONIX v2.0/v1.0 早期项**(conntrack 超时、TCP buffer、hung_task、PELT x4、
  HZ=300 等):多为 sysctl 或已被其 v1.5 自回退,均不新增。

### R8 gh 热门 GKI 项目扫描(2026-11-21)

gh 搜索(topic=android-kernel/susfs、"GKI KernelSU SUSFS"/"kernel patches
android"/"gki kernel",star 排序)结论:**除已调查的 WildKernels/GKID/EVONIX
外,无遗漏的高星特性源**。记录:

- **Enginex0/zeromount**(146★,beta):NoMount 从零重写替代(VFS 驱动+Rust
  用户态+3 策略回退+WebUI+bootloop guard)——机主定案**不做,只用 NoMount**。
- **Lw5959/xring-cve-2026-98260**(20★):fs/exec.c POSIX CPU timer UAF 公开
  利用研究(XRING O1/6.18)——证实族系现实威胁,POSIX 行维持"等 stable"。
- **rrr333nnn333/BRENE**(442★):用户态 ksu_susfs 工具(藏 /data/local/tmp、
  Android/data|obb、字体/Zygisk 痕迹、spoof su tcontext)——管理器生态,内核
  侧无新特性;AVC tcontext 伪装与 AVC log spoofing(做未开始)同方向。
- **nullptr-t-oss/Dragonw1nd-Kernels**(106★):特性集与我们决策一致;其
  docs/a16_fix.md(A16 超长开机修复)留作将来升 A16 参考。
- 不列行:Konoha-kernel-gki(34★)、NoMount-Suite(28★)、MakoSU(22★,KMI-aware
  LKM root)、RootShield(27★,LSM 防护与 BBG 同方向)、构建基建(JackA1ltman
  373★、Super-Builders 95★、lemniskett 85★)、旧 GKI1 5.15、
  rogxo/kernel_hack(195★,内存读写,方向相反)。

## HMBIRD SCX 与 HyperOS(结论记录)

- fengchi patch 把 sched_ext(6.12 主线)backport 到 6.6/6.12 ACK + OPPO 私有
  proc 接口;调度策略本体在**用户态 hmbird daemon + BPF 调度器**(ColorOS
  内置,闭源)。
- 内核侧:MT6991 配方仅 A16/6.12(`fengchi_OP-PAD-2-MT6991_A16.patch`);我们
  KABI 槽 1/2 已被 AOSP 占用(用了 6/7/8),需重排;patch 含高通专属改动
  (`msm_drv.c`)需剔除。工程量中等,动 `sched.h`/`vmlinux.lds`。
- HyperOS **无 hmbird daemon**:装内核只得 SCX 能力,无 BPF 调度器运行,
  零收益;社区调度器(scx_lavd 等)可跑但与 MTK EAS / `scheduler.ko` /
  `os_cpu_qi` / HyperOS miqi 冲突,功耗温控回归风险大。
- **决策(2026-11-21 机主定案):不做。**
