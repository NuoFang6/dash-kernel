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

CONFIG="$OUT_DIR/.config"
"$AOSP_DIR/scripts/config" --file "$CONFIG" \
	-e CONFIG_KSU \
	-e CONFIG_KSU_MULTI_MANAGER_SUPPORT \
	-e CONFIG_KSU_SUSFS \
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
	-d CONFIG_LOCALVERSION_AUTO \
	--set-str CONFIG_UNUSED_KSYMS_WHITELIST "$DASH_ROOT/configs/abi_symbollist.raw"

"${MAKE[@]}" olddefconfig

for opt in CONFIG_KSU CONFIG_KSU_SUSFS CONFIG_VENDOR_KO_COMPAT \
	CONFIG_MEMFD_ASHMEM_SHIM CONFIG_XIAOMI_ENHANCED_IOSTAT \
	CONFIG_XIAOMI_EROFS_IOSTAT CONFIG_F2FS_VIP_FILE \
	CONFIG_F2FS_FS_HYBRID_UFS CONFIG_BLOCK_HYBRID_UFS \
	CONFIG_GKI_DYNAMIC_TASK_STRUCT_SIZE; do
	grep -q "^${opt}=y$" "$CONFIG" || die "$opt was not enabled"
done
if grep -q '^CONFIG_KSU_TRACEPOINT_HOOK=y$' "$CONFIG"; then
	die "tracepoint hook must be disabled when SUSFS inline hook is used"
fi

echo "configured: $CONFIG"
