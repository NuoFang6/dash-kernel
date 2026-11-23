#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_cmd make
require_cmd pahole
[[ -x "$TOOLCHAIN_DIR/bin/clang" ]] || die "run: make toolchain"
require_file "$AOSP_DIR/scripts/config"
require_file "$AOSP_DIR/drivers/kernelsu/Kconfig"
verify_autofdo_profile

export PATH="$TOOLCHAIN_DIR/bin:$PATH"

# DASH_MLGO_REGALLOC is enabled by features.fragment.  Probe both places where
# register allocation runs: clang for NoLTO and LLD for Full LTO.  LLVM emits a
# hard diagnostic if the requested AOT advisor was not built into the toolchain.
probe_dir="$(mktemp -d)"
trap 'rm -rf "$probe_dir"' EXIT
probe_src="$probe_dir/mlgo.c"
cat > "$probe_src" <<'EOF'
long dash_mlgo_probe(long a, long b, long c, long d,
		     long e, long f, long g, long h)
{
	for (int i = 0; i < 100; i++) {
		a = (a * b + c) ^ (d + e);
		b = (b * c + d) ^ (e + f);
		c = (c * d + e) ^ (f + g);
		d = (d * e + f) ^ (g + h);
	}
	return a + b + c + d + e + f + g + h;
}
EOF
"$TOOLCHAIN_DIR/bin/clang" --target=aarch64-linux-gnu -O2 \
	-mllvm -regalloc-enable-advisor=release \
	-c "$probe_src" -o "$probe_dir/mlgo-nolto.o"
"$TOOLCHAIN_DIR/bin/clang" --target=aarch64-linux-gnu -O2 -flto=full \
	-c "$probe_src" -o "$probe_dir/mlgo-lto.o"
"$TOOLCHAIN_DIR/bin/ld.lld" -r --mllvm=-regalloc-enable-advisor=release \
	"$probe_dir/mlgo-lto.o" -o "$probe_dir/mlgo-linked.o"

MAKE=(
	make -C "$AOSP_DIR" O="$OUT_DIR"
	ARCH=arm64
	LLVM=1
	LLVM_IAS=1
	CROSS_COMPILE=aarch64-linux-gnu-
	CC=clang
	LD=ld.lld
	AR=llvm-ar
	NM=llvm-nm
	OBJCOPY=llvm-objcopy
	OBJDUMP=llvm-objdump
	READELF=llvm-readelf
	STRIP=llvm-strip
	HOSTCC=clang
	HOSTCXX=clang++
	HOSTLD=ld.lld
	KCFLAGS=-D__ANDROID_COMMON_KERNEL__
)

mkdir -p "$OUT_DIR"
require_file "$DASH_ROOT/configs/stock.config"
cp "$DASH_ROOT/configs/stock.config" "$OUT_DIR/.config"

# FAST=1 trades optimization for compile speed: skip ThinLTO entirely (the
# link stage dominates build time).  genksyms symbol CRCs are source-level
# and unaffected, so vendor .ko compat is not impacted by this knob.
FAST="${FAST:-0}"

CONFIG="$OUT_DIR/.config"
"$AOSP_DIR/scripts/config" --file "$CONFIG" \
	-d CONFIG_LOCALVERSION_AUTO \
	--set-str CONFIG_UNUSED_KSYMS_WHITELIST "$DASH_ROOT/configs/abi_symbollist.raw"

# features.fragment 是功能开关的唯一权威输入(此前它与本脚本重复维护,
# 曾被误当作纯文档)。此处将其合并进 .config(fragment 覆盖上面任何默认),
# 再由 olddefconfig 解析依赖;required 断言清单负责防静默丢开关。
# 本脚本只保留环境分支逻辑(FAST 的 LTO 取舍、DASH_PERF 的实验 fragment)
# 与白名单接线。
apply_fragment() {
	local fragment="$1" line opt val

	require_file "$fragment"
	while IFS= read -r line; do
		case "$line" in
			"#"*" is not set")
				opt="${line#\# }"
				opt="${opt% is not set}"
				"$AOSP_DIR/scripts/config" --file "$CONFIG" -d "$opt"
				;;
			""|\#*) continue ;;
			CONFIG_*=*)
				opt="${line%%=*}"
				val="${line#*=}"
				case "$val" in
					y|n|m)
						"$AOSP_DIR/scripts/config" --file "$CONFIG" --set-val "$opt" "$val"
						;;
					\"*\")
						val="${val%\"}"
						val="${val#\"}"
						"$AOSP_DIR/scripts/config" --file "$CONFIG" --set-str "$opt" "$val"
						;;
					*)
						# Integers/hex values must remain Kconfig scalar values.  Treating
						# 1024 as a string makes olddefconfig silently use its default.
						"$AOSP_DIR/scripts/config" --file "$CONFIG" --set-val "$opt" "$val"
						;;
				esac
				;;
		esac
	done < "$fragment"
}

apply_fragment "$DASH_ROOT/configs/features.fragment"

DASH_PERF="${DASH_PERF:-0}"
if [[ "$DASH_PERF" == "1" ]]; then
	apply_fragment "$DASH_ROOT/configs/perf.fragment"
fi

# DroidSpaces container runtime (official GKI fragment, 2026-11-21).  The
# SYSVIPC/IPC_NS fields land in ANDROID_KABI padding via the 090-droidspaces
# patch, so task_struct offsets and vendor .ko ABI stay stock.  These two DO
# resize scheduler/cgroup structs and are excluded on purpose (official docs):
# CFS_BANDWIDTH / CGROUP_PIDS would break every prebuilt vendor module.

if [[ "$FAST" == "1" ]]; then
	"$AOSP_DIR/scripts/config" --file "$CONFIG" \
		-d CONFIG_LTO_CLANG_THIN \
		-d CONFIG_LTO_CLANG_FULL \
		-e CONFIG_LTO_NONE
else
	# LTO Full(2026-11-21 起替代 ThinLTO):genksyms CRC 是源码级的,
	# 与 LTO 模式无关,vendor .ko 兼容不受影响。FAST 构建仍走 NoLTO。
	"$AOSP_DIR/scripts/config" --file "$CONFIG" \
		-e CONFIG_LTO_CLANG_FULL \
		-d CONFIG_LTO_CLANG_THIN \
		-d CONFIG_LTO_NONE
fi

"${MAKE[@]}" olddefconfig

required=(
	CONFIG_KSU CONFIG_KSU_SUSFS CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER CONFIG_VENDOR_KO_COMPAT
	CONFIG_MEMFD_ASHMEM_SHIM CONFIG_XIAOMI_ENHANCED_IOSTAT
	CONFIG_XIAOMI_EROFS_IOSTAT CONFIG_F2FS_VIP_FILE
	CONFIG_F2FS_FS_HYBRID_UFS CONFIG_BLOCK_HYBRID_UFS
	CONFIG_GKI_DYNAMIC_TASK_STRUCT_SIZE CONFIG_CRYPTO_LZ4KD
	CONFIG_NOMOUNT
	CONFIG_NETFILTER_XT_MATCH_ADDRTYPE
	CONFIG_IP6_NF_NAT CONFIG_IP6_NF_TARGET_MASQUERADE
	CONFIG_SYSVIPC CONFIG_POSIX_MQUEUE CONFIG_IPC_NS CONFIG_PID_NS
	CONFIG_DEVTMPFS CONFIG_USER_NS
	CONFIG_TMPFS_XATTR CONFIG_TMPFS_POSIX_ACL CONFIG_MACVLAN
	CONFIG_IP_SET CONFIG_IP_SET_HASH_IP CONFIG_IP_SET_HASH_NET
	CONFIG_NETFILTER_XT_SET
	CONFIG_TCP_CONG_BBR3 CONFIG_TCP_CONG_WESTWOOD CONFIG_TCP_CONG_BIC CONFIG_TCP_CONG_HTCP
	CONFIG_NET_SCH_CAKE CONFIG_NET_SCH_PIE CONFIG_NET_SCH_FQ_PIE
	CONFIG_IP_SET_BITMAP_IP CONFIG_IP_SET_BITMAP_IPMAC CONFIG_IP_SET_BITMAP_PORT
	CONFIG_IP_SET_HASH_IPMAC CONFIG_IP_SET_HASH_IPMARK CONFIG_IP_SET_HASH_IPPORT
	CONFIG_IP_SET_HASH_IPPORTIP CONFIG_IP_SET_HASH_IPPORTNET CONFIG_IP_SET_HASH_MAC
	CONFIG_IP_SET_HASH_NETIFACE CONFIG_IP_SET_HASH_NETNET CONFIG_IP_SET_HASH_NETPORT
	CONFIG_IP_SET_HASH_NETPORTNET CONFIG_IP_SET_LIST_SET
	CONFIG_RCU_LAZY CONFIG_WQ_POWER_EFFICIENT_DEFAULT
	CONFIG_NTSYNC CONFIG_MQ_IOSCHED_ADIOS CONFIG_MQ_IOSCHED_DEFAULT_ADIOS CONFIG_EVONIX_IO_PRIO
	CONFIG_DEFAULT_BBR3 CONFIG_NET_SCH_DEFAULT CONFIG_DEFAULT_FQ
	CONFIG_SECURITY_LANDLOCK CONFIG_RSEQ CONFIG_HUGETLBFS CONFIG_CGROUP_HUGETLB
	CONFIG_CGROUP_DEVICE CONFIG_VXLAN CONFIG_VHOST_NET
	CONFIG_ZRAM_DEF_COMP_LZ4KD
	CONFIG_BBG CONFIG_AUTOFDO_CLANG CONFIG_DASH_MLGO_REGALLOC CONFIG_DASH_ARM64_TUNE_A720
)
if [[ "$DASH_PERF" != "1" ]]; then
	required+=(CONFIG_KFENCE_DEFERRABLE)
else
	required+=(
		CONFIG_DASH_PERF_EXPERIMENT
		CONFIG_CRYPTO_SHA3_ARM64 CONFIG_CRYPTO_SM3_ARM64_CE
		CONFIG_CRYPTO_SM4_ARM64_CE CONFIG_CRYPTO_SM4_ARM64_CE_BLK
		CONFIG_CRYPTO_SM4_ARM64_CE_CCM CONFIG_CRYPTO_SM4_ARM64_CE_GCM
		CONFIG_CRYPTO_NHPOLY1305_NEON CONFIG_CRYPTO_AES_ARM64_CE_CCM
		# Runtime symbols / ABI imported by the stock vendor modules.
		CONFIG_KASAN CONFIG_KASAN_HW_TAGS
		CONFIG_FORTIFY_SOURCE CONFIG_HARDENED_USERCOPY CONFIG_LIST_HARDENED
		CONFIG_STACKPROTECTOR CONFIG_SHADOW_CALL_STACK CONFIG_CFI_CLANG
	)
fi
if [[ "$FAST" == "1" ]]; then
	required+=(CONFIG_LTO_NONE)
else
	required+=(CONFIG_LTO_CLANG_FULL)
fi
for opt in "${required[@]}"; do
	grep -q "^${opt}=y$" "$CONFIG" || die "$opt was not enabled"
done
grep -q '^CONFIG_DEFAULT_TCP_CONG="bbr3"$' "$CONFIG" || \
	die "CONFIG_DEFAULT_TCP_CONG must be bbr3"
grep -q '^CONFIG_DEFAULT_NET_SCH="fq"$' "$CONFIG" || \
	die "CONFIG_DEFAULT_NET_SCH must be fq"
grep -q '^CONFIG_ZRAM_DEF_COMP="lz4kd"$' "$CONFIG" || \
	die "CONFIG_ZRAM_DEF_COMP must be lz4kd"
for opt in CONFIG_CFS_BANDWIDTH CONFIG_CGROUP_PIDS CONFIG_MPTCP; do
	grep -q "^${opt}=y$" "$CONFIG" && die "$opt must stay off (kABI/vendor breakage)"
done
grep -q '^CONFIG_GKI_TASK_STRUCT_VENDOR_SIZE_MAX=1024$' "$CONFIG" || \
	die "CONFIG_GKI_TASK_STRUCT_VENDOR_SIZE_MAX must remain 1024"
if grep -q '^CONFIG_KSU_TRACEPOINT_HOOK=y$' "$CONFIG"; then
	die "tracepoint hook must be disabled when SUSFS inline hook is used"
fi

if [[ "$DASH_PERF" == "1" ]]; then
	for opt in CONFIG_UBSAN CONFIG_INIT_ON_ALLOC_DEFAULT_ON \
		   CONFIG_KFENCE CONFIG_SLAB_FREELIST_HARDENED; do
		grep -q "^${opt}=y$" "$CONFIG" && \
			die "$opt must stay off in the perf experiment"
	done
	grep -q '^CONFIG_INIT_STACK_NONE=y$' "$CONFIG" || \
		die "CONFIG_INIT_STACK_NONE was not enabled"
fi

echo "configured: $CONFIG"
