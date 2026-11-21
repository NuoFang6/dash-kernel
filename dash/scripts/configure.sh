#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_cmd make
require_cmd pahole
[[ -x "$TOOLCHAIN_DIR/bin/clang" ]] || die "run: make toolchain"
require_file "$AOSP_DIR/scripts/config"
require_file "$AOSP_DIR/drivers/kernelsu/Kconfig"

export PATH="$TOOLCHAIN_DIR/bin:$PATH"

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
	-e CONFIG_KSU \
	-e CONFIG_KSU_MULTI_MANAGER_SUPPORT \
	-e CONFIG_KSU_SUSFS \
	-e CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER \
	-d CONFIG_KSU_TRACEPOINT_HOOK \
	-d CONFIG_KSU_MANUAL_HOOK \
	-e CONFIG_VENDOR_KO_COMPAT \
	-e CONFIG_UDMABUF \
	-e CONFIG_MEMFD_ASHMEM_SHIM \
	-e CONFIG_XIAOMI_ENHANCED_IOSTAT \
	-e CONFIG_XIAOMI_EROFS_IOSTAT \
	-e CONFIG_F2FS_VIP_FILE \
	-e CONFIG_F2FS_FS_HYBRID_UFS \
	-e CONFIG_BLOCK_HYBRID_UFS \
	-e CONFIG_GKI_DYNAMIC_TASK_STRUCT_SIZE \
	--set-val CONFIG_GKI_TASK_STRUCT_VENDOR_SIZE_MAX 1024 \
	-e CONFIG_CRYPTO_LZ4KD \
	-e CONFIG_NOMOUNT \
	-e CONFIG_NETFILTER_XT_MATCH_ADDRTYPE \
	-e CONFIG_IP6_NF_NAT \
	-e CONFIG_IP6_NF_TARGET_MASQUERADE \
	-e CONFIG_SYSVIPC \
	-e CONFIG_POSIX_MQUEUE \
	-e CONFIG_IPC_NS \
	-e CONFIG_PID_NS \
	-e CONFIG_DEVTMPFS \
	-d CONFIG_DEVTMPFS_MOUNT \
	-e CONFIG_USER_NS \
	-e CONFIG_TMPFS_XATTR \
	-e CONFIG_TMPFS_POSIX_ACL \
	-e CONFIG_MACVLAN \
	-e CONFIG_IP_SET \
	-e CONFIG_IP_SET_HASH_IP \
	-e CONFIG_IP_SET_HASH_NET \
	-e CONFIG_NETFILTER_XT_SET \
	-e CONFIG_NETFILTER_XT_TARGET_LOG \
	-e CONFIG_NETFILTER_XT_MATCH_RECENT \
	-d CONFIG_LOCALVERSION_AUTO \
	--set-str CONFIG_UNUSED_KSYMS_WHITELIST "$DASH_ROOT/configs/abi_symbollist.raw"

# DroidSpaces container runtime (official GKI fragment, 2026-11-21).  The
# SYSVIPC/IPC_NS fields land in ANDROID_KABI padding via the 090-droidspaces
# patch, so task_struct offsets and vendor .ko ABI stay stock.  These two DO
# resize scheduler/cgroup structs and are excluded on purpose (official docs):
# CFS_BANDWIDTH / CGROUP_PIDS would break every prebuilt vendor module.

if [[ "$FAST" == "1" ]]; then
	"$AOSP_DIR/scripts/config" --file "$CONFIG" \
		-d CONFIG_LTO_CLANG_THIN \
		-e CONFIG_LTO_NONE
else
	"$AOSP_DIR/scripts/config" --file "$CONFIG" \
		-e CONFIG_LTO_CLANG_THIN \
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
	)
if [[ "$FAST" == "1" ]]; then
	required+=(CONFIG_LTO_NONE)
else
	required+=(CONFIG_LTO_CLANG_THIN)
fi
for opt in "${required[@]}"; do
	grep -q "^${opt}=y$" "$CONFIG" || die "$opt was not enabled"
done
for opt in CONFIG_CFS_BANDWIDTH CONFIG_CGROUP_PIDS CONFIG_MPTCP; do
	grep -q "^${opt}=y$" "$CONFIG" && die "$opt must stay off (kABI/vendor breakage)"
done
if grep -q '^CONFIG_KSU_TRACEPOINT_HOOK=y$' "$CONFIG"; then
	die "tracepoint hook must be disabled when SUSFS inline hook is used"
fi

echo "configured: $CONFIG"
