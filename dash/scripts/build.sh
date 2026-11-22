#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_cmd make
require_cmd lz4
[[ -x "$TOOLCHAIN_DIR/bin/clang" ]] || die "run: make toolchain"
require_file "$OUT_DIR/.config"
verify_autofdo_profile

export PATH="$TOOLCHAIN_DIR/bin:$PATH"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-dash}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-mikernel}"
# The source tree is intentionally dirty while patches are applied.  Setting an
# empty LOCALVERSION suppresses scripts/setlocalversion's "-dirty"/"+" suffix.
export LOCALVERSION=

# KCFLAGS is appended last in the top-level Makefile, after the generic
# stack-protector/frame-pointer/branch-protection flags and after the
# arch/arm64 CFLAGS.  That makes it the safe place for the experiment's
# negative overrides: the configs stay enabled (vendor modules import their
# runtime symbols and rely on the x18/KCFI conventions), but kernel code no
# longer pays for the instrumentation.
kcflags="-D__ANDROID_COMMON_KERNEL__"
if grep -q '^CONFIG_DASH_PERF_EXPERIMENT=y$' "$OUT_DIR/.config"; then
	# v9.2-A plus every codegen-relevant optional extension this SoC has.
	# SVE/SVE2 stay disabled: kernel mode does not preserve SVE state.
	# Optional features the SoC does NOT have (cssc/mops/lse128/rcpc3/
	# ls64/gcs/pauth-lr) are deliberately not enabled.
	kcflags+=" -march=armv9.2-a+nosve2+nosve+aes+sha2+sha3+sm4+fp16fml"
	kcflags+=" -mbranch-protection=none -fno-stack-protector"
	kcflags+=" -fomit-frame-pointer -foptimize-sibling-calls"
fi

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
	CLANG_AUTOFDO_PROFILE="$AUTOFDO_PROFILE"
	KCFLAGS="$kcflags"
)

# clang r614150 does not finish AutoFDO profile loading for mm/swap.c in NoLTO
# perf builds: llvm::applyFlowInference (MIRProfileLoader) burns 100% CPU for
# tens of minutes, make waits on that one TU, and the log stops on an unrelated
# parallel AR line.  Use kbuild's per-file AutoFDO opt-out for this single
# file; the rest of the kernel keeps the profile.  target-stem for mm/swap.o
# is "swap" (scripts/Makefile.lib strips $(obj)/ and the .o suffix).
if grep -q '^CONFIG_DASH_PERF_EXPERIMENT=y$' "$OUT_DIR/.config" &&
   grep -q '^CONFIG_LTO_NONE=y$' "$OUT_DIR/.config"; then
	MAKE+=(AUTOFDO_PROFILE_swap.o=n)
fi

mkdir -p "$OUT_DIR"
"${MAKE[@]}" -j"$JOBS" Image 2>&1 | tee "$OUT_DIR/build.log"

lz4 -l -12 -f "$OUT_DIR/arch/arm64/boot/Image" "$OUT_DIR/arch/arm64/boot/Image.lz4"

# Only the canonical dash build publishes to the shared artifact directory.
# Validation variants (DEVICE=features-*) must not mix their Image/config with
# the current production BUILD_INFO, SHA256SUMS, or boot.img.  A deliberate
# variant promotion can opt in with PUBLISH_ARTIFACTS=1.
publish="${PUBLISH_ARTIFACTS:-}"
if [[ -z "$publish" ]]; then
	[[ "${DEVICE:-dash}" == "dash" ]] && publish=1 || publish=0
fi
if [[ "$publish" == "1" ]]; then
	mkdir -p "$ARTIFACT_DIR"
	cp "$OUT_DIR/arch/arm64/boot/Image" "$ARTIFACT_DIR/Image"
	cp "$OUT_DIR/arch/arm64/boot/Image.lz4" "$ARTIFACT_DIR/Image.lz4"
	cp "$OUT_DIR/vmlinux" "$ARTIFACT_DIR/vmlinux"
	cp "$OUT_DIR/System.map" "$ARTIFACT_DIR/System.map"
	cp "$OUT_DIR/.config" "$ARTIFACT_DIR/config"

	echo "artifacts: $ARTIFACT_DIR"
	ls -lh "$ARTIFACT_DIR"
else
	echo "build outputs: $OUT_DIR (shared artifacts not published)"
fi
