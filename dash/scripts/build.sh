#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_cmd make
require_cmd lz4
[[ -x "$TOOLCHAIN_DIR/bin/clang" ]] || die "run: make toolchain"
require_file "$OUT_DIR/.config"

export PATH="$TOOLCHAIN_DIR/bin:$PATH"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-dash}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-mikernel}"
# The source tree is intentionally dirty while patches are applied.  Setting an
# empty LOCALVERSION suppresses scripts/setlocalversion's "-dirty"/"+" suffix.
export LOCALVERSION=

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

mkdir -p "$OUT_DIR" "$ARTIFACT_DIR"
"${MAKE[@]}" -j"$JOBS" Image 2>&1 | tee "$OUT_DIR/build.log"

lz4 -l -12 -f "$OUT_DIR/arch/arm64/boot/Image" "$OUT_DIR/arch/arm64/boot/Image.lz4"
cp "$OUT_DIR/arch/arm64/boot/Image" "$ARTIFACT_DIR/Image"
cp "$OUT_DIR/arch/arm64/boot/Image.lz4" "$ARTIFACT_DIR/Image.lz4"
cp "$OUT_DIR/vmlinux" "$ARTIFACT_DIR/vmlinux"
cp "$OUT_DIR/System.map" "$ARTIFACT_DIR/System.map"
cp "$OUT_DIR/.config" "$ARTIFACT_DIR/config"

echo "artifacts: $ARTIFACT_DIR"
ls -lh "$ARTIFACT_DIR"
