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

**决策语义**:`✅ 已落地(未实机)` = 代码/配置与适用的构建级门禁已完成、运行时
待未来刷入后验证;仅完成部分能力时必须明确写成「部分落地」,Full LTO 等特殊
构建状态以行内限制为准;`⏳ 等待 ACK tag` = 已按规则排程但上游基线尚未到货,
不手动 backport;`不做(原因)` = 定案;`待定` = 需进一步调查/实测;`✅` = dash 已有。

**结构**:§决策总表 是唯一权威台账(每行一项);细节机制集中在文末
**调查纪要 R1–R8**,行内以 `→ R#` 指向。各「做」项的实施落点见文末
**实施状态(2026-11-21)**。

## 决策总表

### 网络

| 特性 | 性质 | 说明 | dash 现状 | 决策 |
|---|---|---|---|---|
| BBR v1 / CUBIC / WireGuard / IPsec ESP / FQ / FQ-CoDel / SCH_INGRESS | 🔧 | 上游自带 | ✅ | — |
| BBRv3 | 🏷️+✍️ | ACK 6.6 现存 TCP_CONG_BBR 是 v1;采用 WK android15-6.6 KABI 版 → R1 | ⚠️ | **✅ 已落地(未实机)**——`110-net-bbrv3`(WK android15-6.6 KABI 版);静态已核→构建 CRC 零漂移见 TEST_REPORT §24;实机 ss -i/mihomo 回归待刷后 |
| Westwood+/BIC/HTCP | 🔧 | 上游 Kconfig,CC 状态全存 icsk_ca_priv,不触 ABI,默认仍 cubic | ⚠️ 仅 CUBIC+BBR | **✅ 已落地(未实机)**——批次1 config,默认仍 cubic |
| CAKE / PIE / FQ-PIE qdisc | 🔧 | 上游 Kconfig(stock 未开;`NET_SCH_FQ_PIE` 可同批) | ⚠️ | **✅ 已落地(未实机)**——批次1 config,均内建,不设默认 |
| IP Set 全家桶 | 🔧 | 16 种 set 类型,现仅 HASH_IP/HASH_NET → 补齐其余 14 种 | ⚠️ | **✅ 已落地(未实机)**——批次1 config,补齐其余 14 种(含 bitmap:ipmac/list:set) |
| TTL / HL target | 🔧 | iptables 改 TTL/Hop-Limit(热点共享检测对抗用) | ⚠️ | **不做**——无此需求,要时再开 |
| CIFS(SMB) | 🔧 | 上游 Kconfig | ❌ | **不做**——手机无场景,体积/攻击面 |
| IPv6_NAT_FIX | ✍️ | 实为 config_data 伪装(藏 config.gz 里的 IP6_NF_NAT)→ R5 | ❌ | **不做**——正常启用无需藏;单条伪装无意义 |
| force_tcp_nodelay | 👤 | 实为 setsockopt 劫持 → R5 | ❌ | **不做**——吞掉合法 TCP 选项;Go/mihomo 已默认 nodelay |
| TCP 重传生命周期/urgent data 修复 | 🏷️ | 主线修复;urgent data 已进 stable 6.6.157,重传生命周期仍不在 → R7 | ❌ | **✅ 已落地(未实机)**——重传生命周期 = `tcp: fix use-after-free of retransmit_skb_hint`(fe99bbeee5c5,EVONIX d450c2a2dadf 同源,入 110-net-bbrv3);urgent data 部分仍批次0 |
| UDP tunnel segmentation UAF 修复 | 🏷️ | 主线内存安全修复;UDP tunnel/GSO 组已进 6.6.151–161(大概率覆盖) → R7 | ❌ | **⏳ 等待 ACK tag**——截至 2026-11-21 最新为 2026-10_r4(6.6.143);按既定规则随 ACK 2026-11+ 基线到货,不手动 backport |
| IPv6 checksum bounds/ext 扩展头/SR 校验修复 | 🏷️ | 主线解析加固;checksum bounds 已进 6.6.158 → R7;IP6_NF_NAT=y 在用 | ❌ | **⏳ 等待 ACK tag**——同批次0,随 ACK 2026-11+ 到货;当前没有可 bump 的 tag |

### 性能 / 调度

| 特性 | 性质 | 说明 | dash 现状 | 决策 |
|---|---|---|---|---|
| HMBIRD SCX(sched_ext 移植) | 🏭 | OnePlus fengchi;HyperOS 无 hmbird daemon → R6 | ❌ | **不做**——零收益,与 MTK EAS/HyperOS 冲突 |
| CPU 扫描顺序修正 | 🏷️ | Hao Jia 上游提交,1 行;stable 6.6 已含,ACK 树未含 = 补齐上游 → R2 | ❌ | **✅ 已落地(未实机)**——WK-P 原版(=上游 20e508d375c0),入 100-sched-eevdf |
| CACHE_HOT_BUDDY 关闭 | 👤 | Sultan 1 行(features.h);DSU 同簇迁移不掉局部性 → R2 | ❌ | **✅ 已落地(未实机)**—— Sultan 原版,SCHED_FEAT(false);与 MTK EAS 叠加实测待刷后 |
| PREEMPT_SHORT backport | 🏷️ | 上游 v6.12 EEVDF 特性:短 slice eligible 任务可抢占长任务 → R2 | ❌ | **✅ 已落地(未实机)**——上游 85e511df3cec 适配(did/do_preempt_short + vlag 保护取消),保留 android_rvh_update_deadline/android_vh_resched_curr_lazy;feature 默认 true |
| mem_opt_prefetch | 🏭 | Motorola 2015:copy_template.S +2 条 prfm(=GKID 0007 同补丁) → R3 | ❌ | **✅ 已落地(未实机)**——WK-P 原版,入 120-arm64-perf |
| arm64 memcmp(0008) | 🏷️+👤 | 直接取自 WK-P/GKID 补丁;代码本体是 Arm optimized-routines 用户态库 7a9fd1603e 的 SIMD 实现,不是 Linux 内核上游补丁 → R3 | ❌ | **✅ 保留(未检查、待验证)**——WK-P 原版;≥160B SIMD 路径无 kernel_neon_begin 保护,内核 FPSIMD 上下文安全性尚未完成专项检查;按机主决策保留,刷机前后需做调用上下文审计与压力回归,当前不宣称安全性已验证 |
| arm64 clear_page 16B 对齐(0017) | 👤 | Sultan 1 行 `.p2align 4`;INIT_ON_ALLOC=y 故为热路径 → R3 | ❌ | **✅ 已落地(未实机)**——适配为 GKI 的 `__pi_clear_page` 符号前 .p2align 4 |
| int_sqrt 3x | 👤 | StatixOS 起源,微基准 3x → R3 | ❌ | **✅ 已落地(未实机)**——WK-P 原版(lib/math/int_sqrt.c) |
| file_struct 8B 对齐 / fs cache pressure | ✍️ | → R3 | ❌ | **不做**——收益趋零 + CRC 风险 / 运行时 sysctl 即可 |
| 300Hz timer | 🔧 | stock 250Hz | ⚠️ | **不做**——收益边际,功耗回归风险大 |
| Fake config | ✍️ | 伪装 /proc/config* | ❌ | **不做**——已有 SUSFS spoof_cmdline |
| hide_adb_jdwp_sockets | ❓/✍️ | 对 app-UID 四层隐藏 adbd/jdwp-control → R5;依赖 helper 已自带 | ❌ | **✅ 已落地(未实机)**——readdir/avc 半入 010-bakasu-susfs,af_unix 半入 115-hide-appsockets;fs/susfs.c+SUSFS_FILLDIR_SKIP 经 `patches/susfs-overrides/`(apply-patches.sh 安装后套用);shell(2000)/root 调试不受影响,adb 回归待实机 |
| 模块强制加载(fail signature) | 👤 | Pzqqt | ✅ 超集 | **不做**——vendor-ko-compat 更全 |
| LTO Full | 🔧 | `CONFIG_LTO_CLANG_FULL`(arch/Kconfig:770;stock 本身 LTO_NONE) | ✅ ThinLTO | **配置/阻塞修复已落地,完整构建未完成**——默认生产配置为 LTO_CLANG_FULL;日常编译/CRC/KMI 验证统一 FAST=1 NoLTO;本轮已修 OpenSSL 4 host-tool 与 arm64 idmap KCFI 阻塞,最终重链接因耗时由机主要求停止,不宣称构建通过 |
| RCU lazy callbacks | 🔧 | 上游 Kconfig;批量延后 RCU callback 以争取 idle/省电 | ⚠️ stock 有能力但 DEFAULT_OFF | **✅ 已落地(未实机)**——`CONFIG_RCU_LAZY=y`,并关闭 `RCU_LAZY_DEFAULT_OFF`;异常时 `rcutree.enable_rcu_lazy=0` 回退 |
| Power-efficient workqueue 默认启用 | 🔧 | 上游 Kconfig;把标记为 power-efficient 的工作导向 unbound 队列 → R6 | ❌ | **✅ 已落地(未实机)**——`CONFIG_WQ_POWER_EFFICIENT_DEFAULT=y`;`workqueue.power_efficient=0` 回退 |
| KFENCE deferrable timer | 🔧 | 上游 Kconfig;允许 KFENCE sample timer 在 idle 时延后 → R6 | ❌ | **✅ 已落地(未实机)**——`CONFIG_KFENCE_DEFERRABLE=y`;等价运行时参数 `kfence.deferrable=1`,本仓未开会与该模式冲突的 KFENCE KUnit 自测 |
| ARM64 `-mtune` | 🔧+✍️ | 只改指令调度/延迟模型,不改 ISA/ABI;实机 4×A720+3×A725+1×X925 | ❌ | **✅ 已落地(未实机)**——自加 `DASH_ARM64_TUNE` choice,默认保守选最大同构能效簇 A720;可切 A725/X925/无 |
| AutoFDO 构建支持 | 🏷️+🔧 | LLVM sample-profile 优化,与 MLGO 相互独立;arm64 profile 可由 SPE 或 ETM/ETE 采集 | ❌ | **✅ 已落地——直接用 pinned ACK 自带预制 profile**——取仓库内 `android/gki/aarch64/afdo/kernel.afdo`(6.6.142 采集,4.0MiB),SHA256 写入 `versions.env` 并由 `verify_autofdo_profile` 每次构建前校验;`CONFIG_AUTOFDO_CLANG=y`+`CLANG_AUTOFDO_PROFILE` 自动接线,NoLTO 全量构建实测 3188 个 TU 带 `-fprofile-sample-use`。自采(SPE/ETE)降为可选项,不再阻塞;未刷机、未做性能 A/B |
| MGLO(=LLVM MLGO) | 🏷️/🔧 | WK 实际仅加 LLVM MLGO regalloc release advisor;本仓 AOSP clang r614150 已带 MLGO 模型 → R4 | ⚠️ | **✅ 已落地(未实机)**——新增 `CONFIG_DASH_MLGO_REGALLOC`(默认 y)经 `KBUILD_CFLAGS` 与 `KBUILD_LDFLAGS`(Full LTO 的 LLD 后端)注入 `-regalloc-enable-advisor=release`;`configure.sh` 以真实 NoLTO/LTO 双路径探针断言 advisor 可创建,全量构建实测 3230 个 TU 带该参数。AutoFDO 已拆为独立一行 |
| schedutil 限流溢出/policy init 修复 | 🏷️ | 主线修复;限流溢出已进 stable 6.6.157,policy init 不在 → R7 | ❌ | **✅ policy init 已落地(未实机)**——`cpufreq: initialize policy rwsem before sysfs publication`(3e5d1bf4bd68)+`zero-initialize policy cpumask`(54d37bcf2f49);限流溢出仍批次0 |
| uclamp DVFS 通知/EAS carryover 修复 | 🏷️ | 主线修复,不在 stable;MTK EAS 高相关 | ❌ | **✅ uclamp DVFS 通知已落地(未实机)**——EVONIX cf8010f36cdb(`uclamp_update_active` 尾部比较 rq min/max 变化后 `cpufreq_update_util`);**更正**:「EAS carryover」在 EVONIX/主线均无对得上号的 commit,无实装对象(见落地批次注) |
| misfit 迁移/CPU-group 选择修复 | 🏷️ | 主线 EAS 修复;同族已进 6.6.158 → R7 | ❌ | **✅ 已落地(未实机)**——`58eeb2d79b54`(misfit 失败不入 backoff)+`0fbd428d0788`(dst CPU 无容量收益时不计 misfit);同族 6.6.158 部分仍批次0 |
| RT push-IPI livelock 修复 | 🏷️ | 主线 RT 均衡修复,不在 stable | ❌ | **✅ 已落地(未实机)**——`sched/rt: Have RT_PUSH_IPI be default off for non PREEMPT_RT`(dd29c017aed6) |
| POSIX CPU-timer 竞态/PID 泄漏修复 | 🏷️ | 6.12+ 重构系列;CVE-2026-98260 同族,exec cleanup 已进 6.6.158 → R7 | ❌ | **不做**——不手动管理:等 stable 自行下发(公开利用族系 stable 会追),重构主体审计面过大 |
| timer slack RT 继承修复 | 🏷️ | 主线修复,不在 stable | ❌ | **✅ 已落地(未实机)**——stable e8bbcc00760d + chenguanyou RT 父继承修正(EVONIX 84b614906274 同源,init_task/fork/core) |
| arm64 per-cpu write 修复 | 🏷️ | 主线 arch/arm64 修复,零 ABI,不在 stable | ❌ | **✅ 已落地(未实机)**——`this_cpu_and` 掩码(44274c657256)+`this_cpu_write` 括号(885bff055a0f) |
| OPP/EM 解析修复 | 🏷️ | 主线修复;OPP 竞态已进 6.6.160,EM 不在 → R7 | ❌ | **✅ 已落地(未实机)**——`opp: fix memory leak in supply parsing`(f0776d142e53)+`prevent frequency calculation overflow`(dcaa77d10ea1);竞态(932ebfad767b)仍批次0 |
| MGLRU suspend 可中断 | 🏷️ | 主线修复,不在 stable;MGLRU 已启用 | ❌ | **✅ 已落地(未实机)**——上游 dc37771a43d4(经 ACK b61e79936c0b),memcg fairness guard 前查取消,mm/memcontrol.c+mm/vmscan.c(后者与 030 hooks 交错归 030) |
| DAMON 修复组(6.6.145 收录) | 🏷️ | stable 官方下发 → R7 | ❌ | **⏳ 等待 ACK tag**——随 ACK 基线 bump 到货;当前 r4 仍为 6.6.143 |
| TLB/writeback 修复组(6.6.145 收录) | 🏷️ | stable 官方下发;此前误写含 PSI,复核 6.6.145 changelog 未见 PSI 条目 → R7 | ❌ | **⏳ 等待 ACK tag**——复核过主动 backport 的四提交依赖链与 GKI KMI 适配成本后,机主决定放弃主动移植,继续随 ACK 基线 bump 到货;当前 r4 仍为 6.6.143 |

### 文件系统 / I/O

| 特性 | 性质 | 说明 | dash 现状 | 决策 |
|---|---|---|---|---|
| F2FS GC 50ms / uncongestion 6ms / min_fsync_blocks 20 | ✍️/👤 | 三件套 → R5;OPPO/Huawei 量产同款 | ❌ | **✅ 已落地(未实机)**——gc.h/segment.h 入 130-f2fs-perf,f2fs.h 的 6ms 与 file.c move-range 修复并入 060 文件块;060 回归=构建级通过,运行时待实机 |
| ext4 commit age 5→30s | ✍️/👤 | Arjan distro tweak → R5 | ❌ | **不做**——rw ext4 少;可用挂载参数 `commit=` 调 |
| SK_MEM_PACKETS 256→1024 | ✍️ | 即 net.core.wmem/rmem_max 默认 ×4 → R5 | ❌ | **不做**——运行时 sysctl 可调(同 cache pressure 立场) |
| ADIOS I/O 调度器 | 🏷️ | 独立上游(Masahito Suzuki 2025);EVONIX 用于 UFS 4.0 MCQ 默认 | ❌ | **✅ 已落地(未实机)**——EVONIX 当前 6.6 API 版入 `160-block-adios`,`CONFIG_MQ_IOSCHED_ADIOS=y`;保持非默认,刷入后再与 mq-deadline A/B |
| zRAM LZ4 回写 / mq-deadline / schedutil | 🔧 | stock | ✅ 超集 | —(lz4kd+ExtM 实跑) |
| ext4 orphan 泄漏/DIO fallback 修复 | 🏷️ | 主线修复;orphan 已进 6.6.157 → R7 | ❌ | **⛔ orphan 部分批次0;DIO fallback 无已合并主线修复(2026-09 RFC 仅 atomic write,6.6 无该路径)且 EVONIX 亦未实装——无对象,不再追** |
| F2FS move-range 校验/writeback 报错修复 | 🏷️ | 主线修复,不在 stable;HyperOS 文件管理走 move-range | ❌ | **✅ 已落地(未实机)**——`f2fs: reject overlapping move range after len expansion`(28c1ef094e7c,fs/f2fs/file.c 归 060) |
| swap readahead ceiling 修复 | 🏷️ | 主线修复,不在 stable;swap=zRAM | ❌ | **✅ 已落地(未实机)**——EVONIX ca0a0229886b(mm/swap_state.c;作者自述为本地 policy-bound 修正,非上游 cherry-pick) |

### 电池 / 电源

| 特性 | 性质 | 说明 | dash 现状 | 决策 |
|---|---|---|---|---|
| Freezer timeout 20s→1s | 👤 | Sultan;还锁死 sysfs 写入口 → R5 | ❌ | **不做**——与厂商冻结策略交叉,收益仅死锁场景 |
| alarmtimer 唤醒窗口收敛 | ✍️ | 固定 2s → 最近到期+1ms → R5 | ❌ | **✅ 已落地(未实机)**——WK-P minimise_wakeup_time 原版 |
| s2idle 单次唤醒 | 👤 | Sultan:pm_abort_suspend 到 1 才调 s2idle_wake → R5 | ❌ | **✅ 已落地(未实机)**——WK-P avoid_extra_s2idle_wake_attempts 原版(drivers/base/power/wakeup.c) |
| wakelock 全局 500ms cap | 👤 | 无超时 wake_lock 强制过期 → R5 | ❌ | **不做**——HyperOS critical 路径依赖无超时 wake_lock |
| SDP 900mA 充电 | ✍️ | 纯 oplus/高通方案(DT 属性) → R5 | ❌ | **不做**——MTK 充电栈不可移植 |

### 安全 / 隐藏

| 特性 | 性质 | 说明 | dash 现状 | 决策 |
|---|---|---|---|---|
| SUSFS 全套 | 🏷️ | simonpunk;pin f98f082 实为 **v2.4.0**(STATUS 曾误标 v2.3.0 已订正) | ✅ v2.4.0;实机 10 项 enabled_features(含 priority-uid filter) | — |
| SUSFS priority-uid filter | 🏷️ | f98f082 门控,apply-patches.sh 注入 Kconfig | ✅ 2026-11-21 启用 | — |
| maps 伪装(maphide) | 👤 | backslashxx,WK-P 归档 → R8 | ✅ SUSFS sus_map 已启用(`SUS_MAP=y`) | **不做**——sus_map 覆盖同域 |
| Baseband Guard(BBG LSM) | 🏷️ | vc-teahouse 上游(EVONIX 按 commit `a54e0dc6cf0a` 集成) | ❌ | **✅ 已落地(未实机)**——LSM 本体通用(allowlist=boot/dtbo/userdata/super/vbmeta 等 Android 分区,无高通依赖;efisp 为 WK 另发的高通向补丁,未采用);`CONFIG_BBG=y`+CONFIG_LSM 末尾追加 baseband_guard(与 EVONIX 相同);BBG_BLOCK_BOOT/RECOVERY 保持 n,不影响刷机 |
| Unicode bypass fix(零宽字符) | ❓/✍️ | casefold 空分解边界修复;上游从未采纳 → R5 | ❌ | **✅ 已落地(未实机)**——WK-P unicode_bypass_fix_6.1+(fs/unicode/utf8-norm.c);casefold 回归待实机 |
| AVC log spoofing | ✍️ | KSU 触发路径 avc 日志伪装 | ❌ | **✅ 已有(SUSFS v2.4.0 自带,无需移植)**——avc.c audit 回调已按 `susfs_ksu_sid→priv_app_sid` 伪装,sid 由 KSU susfs 集成注入;开关=`ksu_susfs enable_avc_log_spoofing`,当前 `.susfs.json` 为 `false`(默认关);gkid 版为其 KSU fork 专属实现,与 SUSFS 上游同域,不重复移植 |
| throne_tracker kthread / supercall pull-list | ✍️ | gkid KSU fork 专属 → R5 | ❌ | **不做**——跟 BakaSU 上游 |
| Multiple Managers | ✍️/🔧 | BakaSU 已带 | ✅ | — |
| ptrace leak fix(<5.16) / vendor modules blacklist / uname 自定义伪装串 | ✍️/🏷️ | — | ❌ | **不做**(6.6 不适用 / dash 无对应模块 / 我们伪装 stock 串更优) |

### 容器 / 驱动 / 生态

| 特性 | 性质 | 说明 | dash 现状 | 决策 |
|---|---|---|---|---|
| DroidSpaces | 🏷️ | 官方配方(与我们 090 同源) | ✅ 内核 + 用户态 v7.2.0；`droidspaces check` 全绿；Alpine NAT 容器冒烟通过 | — |
| NoMount / Mountify | 🏷️ | 上游 metamodule | ✅ 内建 v2.3.1 | —(已选型 NoMount) |
| ZeroMount(NoMount 替代) | 🏷️ | 自研 VFS 驱动+Rust,3 策略回退+WebUI+bootloop guard → R8 | ❌ | **不做**——只用 NoMount;bootloop guard/策略回退仅作思路参考 |
| NTSync | 🏷️+🔧 | 主线驱动(Wine)backport,/dev/ntsync | ❌ | **✅ 已落地(未实机)**——WK-P ntsync_base+compat_android15-6.6(主线 v6.14 驱动),`CONFIG_NTSYNC=y` 内建 |
| NetHunter + WirelessKSU | 🔧+✍️ | 渗透驱动 + monitor-mode patch | ❌ | **不做**——维护面大,需要时单独评估 |
| ReSuSFS / apply_kernel_compat.py / usbadb_gate | ✍️ | 用户态/反纪律/自写驱动 | ❌ | **不做**(管理器生态 / 与"补丁可审"相反 / 无场景) |
| 多 Root 变体 | 🏷️ | 各上游 fork | ✅ 已选 BakaSU | — |

## 实施状态(2026-11-21;构建落地与等待项分层,实机验证待刷)

> 本轮原台账 67 行候选曾全部定案(38 行「做」+21 行「不做」+8 行
> 调查前已具备);实施时另发现并补入 5 个实际落地项(RCU_LAZY、WQ、KFENCE、
> ARM64_TUNE、AutoFDO),故当前总表共 72 行。原 38 行「做」中:29 行自有部分
> 已完成、4 行整行等待 ACK tag、5 行已处置自有/无对象部分但 stable 子项仍等待。
> `memcmp` 已按机主决策保留,标记为未检查、待专项验证;Full LTO 的最终链接
> 未完成(配置与已知阻塞修复已完成);MLGO 与 AutoFDO 已接入构建并跑通 NoLTO
> 全量构建。补丁级静态核查和 NoLTO 开发构建已完成,9102 个历史公共
> 导出 CRC 零漂移;**调查阶段未刷机——原「未实机」标注指当时运行时行为未经
> 真机回归**。
>
> **2026-11-21 首刷后更新**:NoLTO `6.6.143-4k #2` 已实机启动(含 NTSync
> 2026 修复),逐项核对、DroidSpaces 安装、供应链审计与源码新鲜度记录统一见
> 本文末「实机核对与运行记录」。表中行内「未实机」是调查时状态,现以该节为准;
> 已确认运行项包括 BBRv3、CACHE_HOT_BUDDY、PREEMPT_SHORT、RCU_LAZY、WQ、
> KFENCE、hide_adb_jdwp、ADIOS、F2FS 默认值、BBG LSM、NTSync 与
> DroidSpaces。

- **批次 0:随基线 bump 自动到货(继续等待,勿手动 backport)**:
  DAMON 组、TLB/writeback 组(6.6.145 整行);schedutil 限流溢出(157)、
  TCP urgent data(157)、IPv6 checksum bounds(158)、misfit 同族(158)、
  ext4 orphan(157)、OPP 竞态(160)、UDP tunnel/GSO 组(151–161)、
  posix-timer exec cleanup(158)。`git ls-remote` 确认 AOSP android15-6.6
  最新仍为 2026-10_r4(6.6.143)。
- **批次 1:纯 config(已全部落地,configs/features.fragment 为唯一权威输入,
  scripts/configure.sh 负责 fragment 合并 + required 断言)**:
  Westwood+/BIC/HTCP、CAKE/PIE/FQ-PIE、IP Set 全家桶、
  RCU_LAZY(`rcutree.enable_rcu_lazy=0` 回退;DEFAULT_OFF 显式关闭)、
  WQ_POWER_EFFICIENT_DEFAULT(`workqueue.power_efficient=0` 回退)、
  KFENCE_DEFERRABLE(`kfence.deferrable=1` 等价)、LTO Full(生产配置
  LTO_CLANG_FULL;日常验证按策略统一 NoLTO)、ARM64_TUNE(实机 MIDR:
  cpu0-3 = A720 @2.4GHz,cpu4-6 = A725 @3.3GHz,cpu7 = X925 @3.73GHz →
  默认以最大同构簇/能效簇的 `-mtune=cortex-a720` 为保守模型;
  `DASH_ARM64_TUNE` choice 可切 a725/x925/无)、AutoFDO(直接使用 pinned
  ACK 自带预制 profile,见批次 3)、DASH_MLGO_REGALLOC
  (`-regalloc-enable-advisor=release` 同时进 `KBUILD_CFLAGS` 与
  `KBUILD_LDFLAGS`;`configure.sh` 双路径探针断言 advisor 可创建)。
- **批次 2:一行/小型补丁(全部落地,零 ABI)**:CPU 扫描顺序
  (100-sched-eevdf)、CACHE_HOT_BUDDY(100-sched-eevdf)、mem_opt_prefetch/
  memcmp/clear_page 16B/int_sqrt(120-arm64-perf)、alarmtimer 唤醒窗口/
  s2idle 单次唤醒(140-power-mm)。
- **批次 3:中型 backport/移植(全部落地,除注明的两项)**:
  BBRv3(WK android15-6.6 KABI 版 → 110-net-bbrv3)、PREEMPT_SHORT
  (85e511df3cec 适配)、ADIOS(EVONIX HEAD 版 → 160-block-adios,
  非默认)、uclamp DVFS 通知(EVONIX cf8010f36cdb)、misfit ×2
  (58eeb2d79b54+0fbd428d0788)、RT push-IPI(dd29c017aed6)、timer slack
  (e8bbcc00760d+lore 继承修正,rt_or_dl_task_policy 以 6.6 policy 检查
  等价替换)、arm64 per-cpu write(44274c657256+885bff055a0f)、
  OPP/EM 解析(f0776d142e53+dcaa77d10ea1)、TCP retransmit_skb_hint UAF
  (fe99bbeee5c5)、F2FS 三件套(130-f2fs-perf + 060 文件块)、
  F2FS move-range(28c1ef094e7c)、swap readahead(EVONIX ca0a02)、
  MGLRU suspend(dc37771a43d4)、Unicode bypass(WK-P)、hide_adb_jdwp
  (010+115+susfs-overrides)、NTSync(WK-P 主线 backport)、BBG(LSM 本体
  通用,无 MTK 适配负担)、AutoFDO(使用 pinned ACK 自带
  `android/gki/aarch64/afdo/kernel.afdo`,SHA256 钉死,替代自采 profile)。
  **未实装(无对象,行内已注)**:「EAS carryover」无对得上号的主线/EVONIX
  commit;ext4 DIO fallback 无已合并主线修复(2026-09 RFC 仅 atomic write,
  6.6 无该路径)。

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

无待机主决策行——原台账 67 行均已定案:38 行「做」、21 行「不做」、8 行调查前
已具备。`arm64 memcmp(0008)` 经实施复核提示 SIMD 上下文风险后,机主于
2026-11-21 决定保留并标记「未检查、待验证」。实施阶段另发现并补入总表 5 行
实际落地项,故当前总表共 72 行;新增行不倒改原调查决策计数。完成状态按上节
分层,不得再概括为「38 项全部落地」。

**仍需研究/专项验证(非决策项,按优先级)**:

1. **arm64 memcmp SIMD 上下文审计(高)**:≥160B 路径直接使用 `q0–q5` 且没有
   `kernel_neon_begin/end`;`memcmp` 是全局弱别名,理论调用面覆盖整个内核,
   需确认不会从 hardirq/atomic 等禁止 FPSIMD 的上下文进入。静态穷举困难;
   若不能给出可信边界,生产版本应换回无 SIMD 实现,不能只靠实机正确性测试。
2. **PREEMPT_SHORT 非 1:1 backport 语义复核(中)**:对照上游 85e511df3cec
   逐段核对 `did/do_preempt_short`、vlag 保护取消与 Android
   `android_rvh_update_deadline`/`android_vh_resched_curr_lazy` 的交互;目前
   只有适配记录与构建级验证。
3. **AutoFDO 自采路线(低,可选)**:pinned 预制 profile 已解除阻塞;只有需要
   针对 dash 真实负载重新训练时,才另做启用 CoreSight/ETE 的实验构建,验证
   `cs_etm` 可用性与 trace→profile 转换链。该路线需要刷机,不影响当前生产
   构建。
4. **ACK stable 批次 0 跟踪(例行)**:定期 `git ls-remote` 检查
   android15-6.6 是否出现含 6.6.145+ 的新 tag;到货后按行删除/更新,不主动
   backport。

Full LTO 整链构建不属于研究项:它是需要机主本次明确授权的构建动作,日常与
验证一律 `FAST=1`(NoLTO),规则见 `AGENTS.md` 与 `docs/kernel/README.md`。

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
- **0008**:本仓直接采用 WK-P/GKID 的内核补丁;其函数体来自 Arm 官方
  optimized-routines 用户态库 commit 7a9fd1603e(Wilco Dijkstra,2021):<16B
  用 ldr/ldp+ccmp,≥160B 走 Advanced SIMD 64B/迭代(eor+umaxp)。Arm 原仓长期
  维护且有自动测试/半年发布,算法来源成熟;WK-P/GKID 也有社区采用史,但两者都
  **不能证明内核上下文安全**。用户态原作无需 `kernel_neon_begin/end`,移入
  通用内核 `memcmp` 后可能从 hardirq/atomic 等禁止 SIMD 的上下文进入;普通
  正确性测试或量产使用史无法排除 FPSIMD 状态破坏。机主已决定保留该实现,当前
  明确标为「未检查、待验证」;后续只记录专项审计/压力回归证据,不预先宣称安全。
- **0017**:Sultan 一行,`__pi_clear_page` 前 `.p2align 4`;我们
  `INIT_ON_ALLOC_DEFAULT_ON=y`,clear_page 确为热路径。
- **int_sqrt**:StatixOS(Vaisakh Murali)起源,WK(FlyFrog)/GKID(Ahmed)同一
  补丁:固定 BITS_PER_LONG 循环二位开方,微基准 3x,内核调用点少。

### R4 编译优化:MGLO=MLGO 实测 + AutoFDO 分界

WK-OP13 所称 "MGLO = Machine Learning-Guided Optimization" 实际实现只有一条
`KCFLAGS`: `-mllvm -regalloc-enable-advisor=release`,即 LLVM **MLGO** 的
register-allocation eviction advisor;没有内核 patch,也没有启用 ML inliner。
此前用旧参数 `-mlgo-regalloc-forcing-model` 测 r614150 并据此判断「不支持」是
错误的:该参数已过时,不能代表现行 advisor 能力。

对本仓固定的 AOSP clang r614150 已作三层核对:①工具链自带
`clang_source_info.md` 明示构建选项 `+mlgo`;② hidden help 列出
`regalloc-enable-advisor={default,release,development}`;③在有实际寄存器分配的
样例上 `release` 成功创建预编译 advisor,没有触发 LLVM 在缺模型时必报的
`Requested ... could not be created. Using default`。因此**不需换编译器或自训模型**。

**已接入构建(2026-11-21)**:新增 `CONFIG_DASH_MLGO_REGALLOC`(默认 y),
`arch/arm64/Makefile` 同时写 `KBUILD_CFLAGS += -mllvm -regalloc-enable-advisor=release`
与 `KBUILD_LDFLAGS += --mllvm=-regalloc-enable-advisor=release`。两者都要:
NoLTO/ThinLTO 的寄存器分配在 clang 里跑,而 **Full LTO 的寄存器分配在 LLD 后端**,
只用 `KCFLAGS` 覆盖不到链接期。`configure.sh` 用真实编译+链接探针断言两条路径
都能创建 advisor(缺模型时 LLVM 会硬报错)。全量构建实测:3230 个编译单元带该
参数,`.vmlinux.o.cmd`(LTO 链接)带 `--mllvm=-regalloc-enable-advisor=release`。
剩余工作是刷机后的性能 A/B。若想再启用 ML inliner,那是另一模型与 selector,
不属于 WK 当前 MGLO 范围,也不建议在未验证前捆绑。

**AutoFDO 与 MLGO 无替代关系**:AutoFDO 是基于运行时 sample profile 的 PGO。
同款 r614150+ThinLTO+`AUTOFDO_CLANG=y` 已由 EVONIX 实证;本仓现已直接使用
ACK 自带的 6.6.142 预制 profile(`android/gki/aarch64/afdo/kernel.afdo`,
SHA256 钉死)接通 NoLTO/生产构建,自采 profile 降为可选实验路线。此前只记录到
「无 `arm_spe_*`」并误写成 arm64 必须 SPE;内核文档实际支持 **SPE 或 ETM/ETE**。
进一步静态核查发现 stock 同时关闭 `CONFIG_ARM_SPE_PMU` 与 `CONFIG_CORESIGHT`,
且 MT6991 厂商 DTS 没有 SPE 节点,却已提供 8 个 CPU 的 ETE 节点和
funnel→ETF→ETR 完整 CoreSight 拓扑。因此将来若要自采,优先路线不是猜测
SPE PPI/修改 DT,而是先构建启用 `CORESIGHT`、`CORESIGHT_SOURCE_ETM4X`、
`CORESIGHT_LINK_AND_SINK_TMC`(及依赖),刷入后验证 `cs_etm`/ETE trace 能否
采集并转换 AutoFDO profile。只有 ETE 路线被固件权限或驱动阻断时,才继续调查
SPE:先读 CPU `ID_AA64DFR0_EL1.PMSVer`、确认 EL2 未占用 PMB、取得真实
per-CPU PPI,然后再决定是否加 `ARM_SPE_PMU` 和 DT 节点;不能凭空补一个节点。

**不推荐全局 O3**:本仓实际全局为 `-O2 -mtune=cortex-a720`,仅 lz4/lz4kd
等少数自带 Makefile 热点使用 O3。r614150 的 ML inliner 模型明确只为 `-Oz`
训练,不适合拿来弥补 O2/O3;同域 EVONIX 最终也使用 O2。除非有 profile 与整机
A/B 证明,不把全内核切到 O3,避免镜像/I-cache 膨胀和早期启动/BPF 回归面。

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

- **已进 stable(官方下发,bump 即得)**:DAMON 修复组(6.6.145,以 sysfs
  错误路径、区间边界和极端 interval 正确性为主)、TLB/writeback 组(6.6.145;
  含 deferred TLB 在释放 large folio 前 flush、inode wb 切换 UAF/竞态与
  `wb->list_lock` 竞争优化;此前写入的 PSI 经 changelog 复核无对应项,已删除)、
  `cpufreq: schedutil: Fix rate limit overflow`(6.6.157;仅 32-bit 系统且
  rate_limit_us 写到约 4295s 才溢出,dash arm64 正常值不受影响)、
  `tcp: fix corruption of urgent data on multi-segment retransmit`(6.6.157)、
  `net: skbuff: fix pull-bound underflow in skb_checksum_setup_ipv6()`(6.6.158)、
  misfit 同族 `Reject misfit pulls onto busy SMT siblings on
  asym-capacity`(6.6.158;dash 无 SMT,不影响本机调度性能)、
  `exec: Cleanup POSIX timers right after de_thread()`(6.6.158)、ext4 orphan
  组(6.6.157;坏 orphan 元数据错误路径的 buffer_head 泄漏等)、动态加 OPP
  竞态(6.6.160)、UDP tunnel/GSO 组(6.6.151–161;UAF/内存泄漏、checksum 与
  特定 SCTP/GTP/act_csum 丢包正确性)。
- **等待对性能的影响**:正常手机负载下基本无可感知性能损失;未到货项绝大多数
  是安全/正确性和罕见错误路径。仅 writeback 组含锁竞争与无关 RCU callback
  等待的性能修正,主要影响 cgroup inode wb 切换/卸载;不是日常 UI、游戏或
  mihomo 的核心性能增益。
- **仍不在 stable(EVONIX 自行挑选的主线 backport)**:uclamp DVFS 通知/
  EAS carryover、schedutil policy init、TCP 重传生命周期、POSIX CPU-timer
  重构主体、swap readahead、MGLRU suspend、timer slack RT 继承、ext4 DIO
  fallback、F2FS move-range、arm64 per-cpu write、EM 解析、RT push-IPI。
- **跟踪规则**:纯 stable 项整行列行(标"ACK tag 含 6.6.145 后删除此行");
  混合行(部分在 stable)到货后更新行说明,不删整行。writeback 组曾评估主动
  backport,但其性能重构后串联两项竞态修复及清理提交,且新增 `bdi_writeback`
  字段需 GKI KMI sidecar 适配;机主定案不做,继续等待 ACK。
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
  侧无新特性;AVC tcontext 伪装与 SUSFS 已有的 AVC log spoofing 同方向。
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

## 实机核对与运行记录(2026-11-21,NoLTO `6.6.143-4k #2`)

本节是本轮实机结果、供应链审计和源码新鲜度的**集中记录**;行内状态以本节为准。
设备 dash / serial `9XIBH6KJPFS4IZGQ`,激活槽 `_a`;当前刷入镜像 SHA256
`3d0d4245…7a50dba`,`#2` 含 NTSync 2026 修复;只写 `boot_a`,未触碰
`lk`/`vbmeta`/`super`/`boot_b`。首刷 `#1` 的镜像哈希为 `1b5af31a…7d05ef`。

### 启动与日志

- 真实启动行来自 `/dev/kmsg`:`Linux version 6.6.143-4k ... #2`;`uname` 显示
  stock 是 SUSFS `SPOOF_UNAME`,不能作为版本依据。
- `sys.boot_completed=1`,SELinux `Enforcing`,root 正常;`/proc/config.gz`
  关键项与构建配置一致。
- 机主操作 WiFi/蓝牙/移动数据后,`/dev/kmsg` 增量 80,518 条:新增
  `WARNING: CPU`/`BUG:`/panic/`brk #0x8228` 均为 0;Android crash buffer 为空。
- 唯一内核 WARNING 是 `mtk_cmdq_debug` 重复注册,历史 #3 日志同样存在。
- BT 固件报错 819 条 vs 历史 831 条,`ready_retry` 25 vs 27,同一既有行为。
- 移动数据 10.0.158.101 可用,ping 1.1.1.1 0% 丢包;蓝牙 ON;WiFi 当时关闭。

### 原厂模块兼容

- `#2` 实机加载 584 个模块。与历史 stock 清单 585 行逐名比较:仅少了
  `kernelsu`/`nomount` 两个 LKM(KSU/NoMount 已内建),多了 `mkp`;
  没有厂商模块缺失。
- 全量 `/dev/kmsg` 无 `Unknown symbol`、`disagrees about version`、
  `invalid module format`、`module verification failed`、CRC/vermagic 类报错。
- 关键厂商链均在:`node_cache`、`os_cpu_qi`(cpq/mi_reclaim/task_turbo/
  os_cpu_qs)、`zram`、`zsmalloc`、`mtk_cmdq_drv_ext`、`mtk_iommu_util`、
  `mtk_disp_sec`、`cam_fs`、`btmtk_uart_unify`、`wlan_drv_gen4m_6991`。
- KCFI 无 `brk #0x8228`;`tainted=4609` 来自厂商 out-of-tree 模块、强制加载
  和既有 cmdq WARNING,不是新增 oops。
- `CONFIG_VENDOR_KO_COMPAT=y`、`CONFIG_MODVERSIONS=y`、`CONFIG_MODULE_SIG=y`
  但 `MODULE_SIG_FORCE=n`:加载成功是行为级兼容,不等于签名有效。CRC/KMI
  静态门禁仍以历史 9102 个公共导出零漂移、task_struct 4800B 为准。

### 逐项核对

| 项 | 结果 | 证据 / 限制 |
|---|---|---|
| BBRv3 | ✅ 实机 | `tcp_available_congestion_control` 含 bbr3;bbr3/cubic 切换成功 |
| Westwood+/BIC/HTCP | ✅ 实机 | 三种 CC 均切换成功,最终恢复 cubic |
| CAKE/PIE/FQ-PIE | ✅ 实机 | `tc qdisc add dev lo root {pie,fq_pie,cake}` 均成功 |
| IP Set 全家桶 | ✅ 配置 | 14 种 set 类型全部 `=y`;设备无 `ipset` 工具 |
| TCP 重传 UAF | ✅ 静态 | 补丁/符号在树;未做故障注入 |
| CPU 扫描顺序 | ✅ 静态 | `for_each_cpu_wrap` 从 target+1 起扫 |
| CACHE_HOT_BUDDY | ✅ 实机 | `sched/features` 含 `NO_CACHE_HOT_BUDDY` |
| PREEMPT_SHORT | ✅ 实机 | `sched/features` 含 `PREEMPT_SHORT` |
| mem_opt_prefetch | ✅ 静态 | `copy_template.S` 两处 `prfm pldl1strm` |
| arm64 memcmp | ⚠️ 可用未审计 | 运行正常;FPSIMD 上下文审计未完成 |
| clear_page 16B | ✅ 静态 | `__pi_clear_page` 地址 16B 对齐 |
| int_sqrt 3x | ✅ 静态 | 符号存在;未做微基准 |
| hide_adb_jdwp | ✅ 实机 | app UID 10249 看 `/proc/net/unix` 无 adbd/jdwp、`/dev/socket` 无 adbd;shell/root 正常 |
| RCU_LAZY | ✅ 实机 | `enable_rcu_lazy=Y` |
| WQ power-efficient | ✅ 实机 | `power_efficient=Y` |
| KFENCE deferrable | ✅ 实机 | `deferrable=Y`;KFENCE 已初始化 |
| ARM64 -mtune | ✅ 构建 | 3188 TU `-mtune=cortex-a720`;未 A/B |
| AutoFDO | ✅ 构建 | 3188 TU `-fprofile-sample-use`;未 A/B |
| MLGO regalloc | ✅ 构建 | 3230 TU advisor;未 A/B |
| schedutil policy init | ✅ 静态 | 补丁在树;未触发错误路径 |
| uclamp DVFS | ✅ 静态 | EVONIX 补丁在树;需调度压力 |
| misfit ×2 | ✅ 静态 | 补丁在树;需调度压力 |
| RT push-IPI | ✅ 实机 | `sched/features` 含 `NO_RT_PUSH_IPI` |
| timer slack RT 继承 | ✅ 静态/实机代码 | `sched_fork` 恢复 `timer_slack_ns` 在树 |
| arm64 per-cpu write | ✅ 静态 | 两个补丁在树 |
| OPP/EM 解析 | ✅ 静态 | 两个补丁在树;6.6 代码路径不含上游 2026 UAF 重构 |
| MGLRU suspend | ⚠️ 未验证 | 补丁在树;suspend 未完成 |
| F2FS GC/min_fsync | ✅ 实机 | `gc_urgent_sleep_time=50`、`min_fsync_blocks=20`;64 MiB 写入 + drop_caches 后 SHA256 一致 |
| ADIOS | ✅ 实机 | 已注册且出现在 scheduler 列表;当前 `cpq`,未 A/B |
| F2FS move-range | ⚠️ 未验证 | 函数在树;未做 HyperOS 大文件移动 |
| swap readahead | ⚠️ 部分 | 16 GiB zram swap 已启用;未测 readahead |
| alarmtimer | ⚠️ 未验证 | 补丁在树;suspend 未完成 |
| s2idle | ⚠️ 未验证 | 门控在树;suspend 未完成 |
| BBG LSM | ✅ 实机 | LSM 含 `baseband_guard`;BLOCK_BOOT/RECOVERY 均 n;未做实际拦截 |
| Unicode bypass | ⚠️ 未验证 | 补丁在树;F2FS features 无 `casefold` |
| AVC log spoofing | ✅ 代码 | `enable_avc_log_spoofing` 存在;`.susfs.json` 当前 false |
| NTSync | ✅ 实机 | `/dev/ntsync` 存在;已补 2026 time-namespace/零-owner 修复,并在 `#2` 启动验证 |
| DroidSpaces | ✅ 实机 | 用户态 v7.2.0;check 全绿;Alpine PID ns + NAT ping/DNS 通过 |

### DroidSpaces 用户态

- 官方 `Droidspaces v7.2.0` APK(SHA256
  `b1499be2448641ffd6fc7305fd2f60fb5266fef4845c39263714f6e74568d1d2`)已安装;
  后端在 `/data/local/Droidspaces/bin`,启动模块已注册,`.daemon_mode=1`。
- `droidspaces check`:MUST HAVE/RECOMMENDED 全过;仅 `CPU limit`
  (`CFS_BANDWIDTH`)与 `Process limit` (`CGROUP_PIDS`)不支持,属永久限制。
- Alpine 3.24.4 容器:`--net=none` 的 PID 1/主机名/rootfs 正常;`--net=nat`
  的 veth、`udhcpc` 172.28.77.67/16、ping 1.1.1.1、DNS 解析均通过。
- 测试容器已停止,无残留运行实例。

### 供应链与恶意 I/O 审计

- 补丁新增行扫描:`filp_open`/`kernel_write`/`vfs_write`/`call_usermodehelper`/
  `request_module`/`do_execve`/`commit_creds`/`override_creds`/
  `kallsyms_lookup_name`/`submit_bio` 写路径/`set_memory_*`/`ioremap`/
  `request_mem_region` 均为 0。
- 唯一块设备访问是 BBG 的 `blkdev_get_no_open`/`blkdev_get_by_dev(FMODE_READ)`
  读取分区元数据用于 allowlist;BBG 自身只拒绝 `BLKDISCARD`/`BLKZEROOUT`/
  `BLKPG`/`BLKRRPART` 等破坏性 ioctl,不执行写/擦除。
- 网络调用仅 AF_UNIX `hide_adb_jdwp` 包装;无 AF_INET/connect/sendmsg 外联。
  补丁中的 URL 均为注释/出处(BBG repo、ARM optimized-routines、BBR 论坛)。
- DroidSpaces 静态二进制:`file` 为 stripped aarch64;字符串只有自身 GitHub
  地址、DNS 默认 1.1.1.1/8.8.8.8、NAT 172.28.0.0/16、`/dev/block/loop%ld`;
  无 `curl`/`wget`/`lk`/`super`/`vbmeta`/`boot_a` 访问。
- 未发现后门、隐蔽外联或越界设备写。

### 上游补丁与源码新鲜度

- **组件 pin 全部为最新**:AOSP `android15-6.6-2026-10_r4`;BakaSU
  `7b65bde` = HEAD;SUSFS `f98f082` = `gki-android15-6.6` HEAD;
  NoMount `v2.3.1` = 最新 tag;tcp-brutal `d2397ff` = HEAD;DroidSpaces
  `v7.2.0` = 最新 release。
- **参考仓库**:WK-P `70c394f` 最新(新提交仅 usbadb_gate);WK-GKI
  `439c573` 最新(相对本地 `383de65` 仅 CI);EVONIX `3aca65c` 最新(相对
  `4dfb129` 仅 FUNDING);GKID `ef6c99d` 最新。
- **dash-droidspaces**:本地 `6039943`(10-29),上游 main `70f67cc`
  (11-17)。上游已改为树内 delta;我们已具备 kABI padding、13 hooks、
  `dash_os4_decl_exports.c` 的 2 条 decl-only export、pid 32768、
  DroidSpaces 7.1/7.2 探测项与 `CFS_BANDWIDTH`/`CGROUP_PIDS` 关闭。
  **未采用**:trusty-rescue + `kvm-arm.mode=nvhe`(仅 gz/Trusty 被擦除时
  需要,本机 gz 在位)、KernelPatch/KPM 实验项。无必需补丁缺失。
- **ADIOS**:3.3.0,与 Pzqqt/firelzrd 最新一致。
- **BBG**:我们基于 EVONIX `a54e0dc6-evonix1`(标准 LSM cred blob、policy
  代际 SID、拒绝日志限流、双槽 allow),上游 vc-teahouse HEAD `028ff7f`
  另有 dev 缓存与 cmdline slot 解析。两者不是字节相同;当前实现工作正常,
  未发现缺失的安全修复,记录为**有意分叉**。
- **memcmp**:算法与 ARM optimized-routines 最新 `20859d3` 的
  `string/aarch64/memcmp.S` 一致;文件头仍引用 2021 的 `7a9fd1603e`。
- **主线上游新修复核查**:NTSync 的 2026 两项适用修复
  (`timens_ktime_to_host`、零 owner 拒绝)已补入并随 `#2` 实机启动;
  PREEMPT_SHORT 的 2026 buddy 修复、RT pushable、cache-aware misfit、
  swap cache memcg、OPP `clk_get_optional` UAF 均针对 6.12+/新重构,
  6.6 树无对应代码路径,不适用;schedutil 限流溢出已进 stable 6.6.157,
  按批次 0 等待 ACK。
- Full LTO 未运行;按 `AGENTS.md` 需机主单次授权。
