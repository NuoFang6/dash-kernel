# 特性调查:WildKernels / GKID vs dash

调查日期:2026-11-21。来源(均为当日浅克隆核对源码/补丁签名):

- `WK-GKI` = [WildKernels/GKI_KernelSU_SUSFS](https://github.com/WildKernels/GKI_KernelSU_SUSFS)(docs/features.md)
- `WK-OP13` = [WildKernels/OnePlus_KernelSU_SUSFS](https://github.com/WildKernels/OnePlus_KernelSU_SUSFS)(OP13-6.6.30 实配 + kernel_patches 仓库)
- `GKID` = [ahmed-alnassif/GKID-Kernels](https://github.com/ahmed-alnassif/GKID-Kernels)(kernel-patches + configs + patches)

**实现性质图例**(每项已核对补丁 `From:` 签名或 config 落点):

| 图标 | 含义 |
|---|---|
| 🔧 | 纯 Kconfig 开关——上游 Linux/ACK 已有特性,零源码风险 |
| 🏷️ | 官方/上游——主线内核、Google 官方 backport、知名独立上游项目 |
| 🏭 | 厂商补丁——Motorola / OnePlus OSS 内核树导出 |
| ✍️ | 作者自研——仓库作者亲写源码(fatalcoder524 / Ahmed Al-Nassif) |
| 👤 | 社区知名作者——Sultan(kerneltoast)/ Panchajanya1999 / Pzqqt / FlyFrog |
| ❓ | 来源不明——无签名,社区流传 |

**使用方式**:"决策"列由机主决定是否吸收;建议值写在括号里,定案后替换为
`做` / `不做(原因)`。`dash 现状` 与本仓库 STATUS/DESIGN 冲突时以
[STATUS.md](../STATUS.md) 为准。

## 网络

| 特性 | 实现 | 说明与来源 | dash 现状 | 决策 |
|---|---|---|---|---|
| BBR v1 / CUBIC | 🔧 | `TCP_CONG_BBR/CUBIC=y` 上游自带 | ✅ | — |
| BBRv3 | 🏷️ | Google TCP 团队(Mubashir Adnan Qureshi)官方 backport,WK 含 `android15-6.6` 专版 patch | ⚠️ 未做 | 待定(建议:做,可信度高) |
| Westwood+/BIC/HTCP | 🔧 | 上游 Kconfig | ⚠️ 仅 CUBIC+BBR | 待定(建议:Westwood 做,弱网 WiFi 收益) |
| CAKE / PIE qdisc | 🔧 | 上游 Kconfig | ⚠️ 未开 | 待定(热点转发场景可实测) |
| TTL / HL target | 🔧 | `IP_NF_TARGET_TTL` / `IP6_NF_TARGET_HL` | ⚠️ 未开 | 待定(纯开关,低风险) |
| IP Set 全家桶(bitmap/list/HASH_IPMARK/MAC/NETIFACE/NETPORTNET) | 🔧 | 上游 Kconfig,GKID 全开 | ⚠️ 仅 HASH_IP/HASH_NET | 待定(建议:做,配 DroidSpaces 防火墙) |
| WireGuard / IPsec ESP / FQ / FQ-CoDel / SCH_INGRESS | 🔧 | 上游自带 | ✅ | — |
| CIFS(SMB) | 🔧 | 上游 Kconfig | ❌ | 待定(建议:不做,手机场景) |
| IPv6_NAT_FIX | ✍️ | fatalcoder524 自写 | ❌ 不需要 | 不做(IP6_NAT 实测已通) |
| force_tcp_nodelay | 👤 | Panchajanya1999,强制 TCP_NODELAY | ❌ | 待定(延迟↓吞吐可能↓,需实测) |

## 性能 / 调度

| 特性 | 实现 | 说明与来源 | dash 现状 | 决策 |
|---|---|---|---|---|
| HMBIRD SCX(sched_ext 移植) | 🏭 | OnePlus OSS fengchi 导出;`ANDROID_KABI_USE(1/2)` 放 scx 指针;MT6991 配方仅 A16/6.12 | ❌ 未做 | 待定(建议:不做主内核,见文末;实验分支另议) |
| BBRv3 外调度魔改(CPU 扫描顺序 / CACHE_HOT_BUDDY) | ✍️/👤 | gkid 0018/0020 Ahmed 自研;WK 版是 Sultan 原作 | ❌ | 待定(建议:只考虑 Sultan 版,需 EAS 实测) |
| mem_opt_prefetch | 🏭 | Motorola(Hong-Mei Li)官方补丁 | ❌ | 待定 |
| arm64 mem 优化(memcpy/memset/memcmp/clear_page 16B) | ✍️/❓ | gkid 0004/0007/0008/0017 Ahmed 自研;WK optimized_mem_operations 无签名 | ❌ | 待定(建议:做,纯汇编无 ABI 风险,但需读码审查) |
| int_sqrt 3x | ✍️/👤 | gkid 0010 Ahmed 自研;WK 版 FlyFrog | ❌ | 待定(微收益) |
| file_struct 8B 对齐 / fs cache pressure 降低 | ✍️ | gkid 0005/0006 Ahmed 自研,改核心结构布局 | ❌ | 待定(建议:不做,与我们 vendor-ABI 纪律冲突) |
| MGLRU | 🔧 | `LRU_GEN+LRU_GEN_ENABLED` | ✅ | — |
| 300Hz timer(HZ_300) | 🔧 | config;我们 stock 250Hz | ⚠️ | 待定(功耗权衡,建议实测) |
| Fake config(动态伪装 /proc/config*) | ✍️ | fatalcoder524 自写 | ❌ | 不做(已有 SUSFS spoof_cmdline) |
| hide_adb_jdwp_sockets | ❓/✍️ | 无签名 | ❌ | 待定(检测对抗项) |
| 模块强制加载(fail signature) | 👤 | Pzqqt | ✅ 超集 | 不做(vendor-ko-compat 更全:签名+vermagic+CRC+namespace) |
| LTO Full/Thin/No 变体 | 🔧 | config | ✅ ThinLTO(fast=NoLTO) | — |
| MGLO | ❓ | WK 营销名,无独立源码 ≈ PGO/AutoFDO 类 | ⚠️ | 待定(并入编译优化方向,见 TEST_REPORT §23 后续) |

## 文件系统 / I/O

| 特性 | 实现 | 说明与来源 | dash 现状 | 决策 |
|---|---|---|---|---|
| F2FS GC 50ms / uncongestion timeout / min_fsync_blocks=20 | ✍️ | gkid 0012/0014/0016 Ahmed 自研 | ❌ | 待定(建议:逐项实测对照 stock) |
| ext4 commit age 延长 | ✍️/👤 | gkid 0021 Ahmed 自研 | ❌ | 待定(掉电风险) |
| SK_MEM_PACKETS 等 socket 微调 | ✍️ | gkid 0022 Ahmed 自研 | ❌ | 待定 |
| zRAM LZ4 回写 | 🔧 | config | ✅ 超集 | —(lz4kd+ExtM+回写实跑) |
| mq-deadline / schedutil | 🔧 | stock | ✅ | — |

## 电池 / 电源

| 特性 | 实现 | 说明与来源 | dash 现状 | 决策 |
|---|---|---|---|---|
| Freezer timeout 20s→1s | ✍️/👤 | gkid 0015 Ahmed 自研;WK 版 Sultan 原作 | ❌ | 待定(建议:不做主内核) |
| alarmtimer / s2idle 唤醒收敛 | ✍️ | gkid 0009/0019 Ahmed 自研 | ❌ | 待定 |
| wakelock 全局 timeout(cap) | 👤 | Panchajanya1999 | ❌ | 待定(建议:不做,厂商功耗策略冲突) |
| SDP 900mA 充电 | 🏭 | oplus 补丁导出 | ❌ | 待定(MTK 充电栈需重写) |

## 安全 / 隐藏

| 特性 | 实现 | 说明与来源 | dash 现状 | 决策 |
|---|---|---|---|---|
| SUSFS 全套(sus_path/mount/kstat/uname/open_redirect/cmdline/symbols/log) | 🏷️ | simonpunk 上游 | ✅ v2.3.0 九特性 | — |
| SUSFS priority-uid filter | 🏷️ | f98f082 新门控;上游无 Kconfig 条目(我们 apply-patches.sh 注入) | ✅ 2026-11-21 修复启用 | — |
| Baseband Guard(BBG LSM) | 🏷️ | vc-teahouse 独立上游;WK 附 efisp 设备适配 | ❌ | 待定(建议:评估,防恶意应用写关键分区) |
| Unicode bypass fix | ❓/✍️ | 无签名,实验性 | ❌ | 待定 |
| AVC log spoofing | ✍️ | gkid:Ahmed 对 KSU 源码自研 | ❌ | 待定(取证场景) |
| throne_tracker / persistent_allow_list 卸载 kthread | ✍️ | gkid:Ahmed 自研 KSU 补丁 | ❌ | 待定(建议:跟 BakaSU 上游,不直接引入) |
| supercall pull-list | ✍️ | gkid:Ahmed 自研 KSU 补丁 | ❌ | 待定 |
| Multiple Managers | ✍️/🔧 | gkid patch;BakaSU 已带 `KSU_MULTI_MANAGER_SUPPORT` | ✅ | — |
| ptrace leak fix | 🏷️ | 针对 <5.16 | ❌ | 不做(6.6 不适用) |
| vendor modules blacklist | ✍️ | fatalcoder524 条件黑名单 | ❌ | 不做(dash 无对应模块) |
| uname 自定义伪装串(OP-WILD) | ✍️ | WK | ❌ 不需要 | 不做(我们伪装 stock 串,更优) |

## 容器 / 驱动 / 生态

| 特性 | 实现 | 说明与来源 | dash 现状 | 决策 |
|---|---|---|---|---|
| DroidSpaces | 🏷️ | 官方配方(gkid KABI 补丁与我们 090 同源) | ✅ CRC 零漂移实证 | — |
| NoMount | 🏷️ | 上游 metamodule | ✅ 内建 v2.3.1 | — |
| Mountify(OverlayFS metamodule) | 🏷️ | backslashxx 上游,WK 推荐 NoMount 二选一 | ✅ 已选 NoMount | — |
| NTSync | 🏷️+🔧 | 主线驱动(Wine/Elizabeth Figura)Android backport + config | ❌ | 待定(Windows 模拟器场景) |
| NetHunter(无线渗透驱动)+ WirelessKSU | 🔧+✍️ | 上游驱动 + 社区 monitor-mode patch | ❌ | 待定(建议:不做,低优先) |
| ReSuSFS(WebUI 管理) | ✍️ | gkid:Ahmed 用户态 | ❌ | 不做(管理器生态,内核无关) |
| apply_kernel_compat.py | ✍️ | WK 声明式源码文本改写引擎(绕过 patch) | ❌ | 不做(与"补丁可审"纪律相反) |
| usbadb_gate.c | ✍️ | fatalcoder524 自写驱动 | ❌ | 不做 |
| 多 Root 变体(KSU/Next/FinaSU/SukiSU/KowSU) | 🏷️ | 各上游 fork | ✅ 已选型 BakaSU | — |

## HMBIRD SCX 与 HyperOS(结论记录)

- fengchi patch 把 sched_ext(6.12 主线)backport 到 6.6/6.12 ACK + OPPO
  私有 proc 接口;调度策略本体在**用户态 hmbird daemon + BPF 调度器**
  (ColorOS 内置,闭源)。
- 内核侧:MT6991 配方仅 A16/6.12(`fengchi_OP-PAD-2-MT6991_A16.patch`);
  我们 KABI 槽 1/2 已被 AOSP 占用(用了 6/7/8),需重排;patch 含高通专属
  改动(`msm_drv.c`)需剔除。工程量中等,动 `sched.h`/`vmlinux.lds`。
- HyperOS **无 hmbird daemon**:装内核只得 SCX 能力,无 BPF 调度器运行,
  零收益;社区调度器(scx_lavd 等)可跑但与 MTK EAS / `scheduler.ko` /
  `os_cpu_qi` / HyperOS miqi 冲突,功耗温控回归风险大。
- **建议**:不作主内核特性;实验走独立分支(fast 构建验证 + 单独刷机),
  主线保持 KMI 零漂移纪律。
