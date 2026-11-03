#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Build the pinned HyNetworks/tcp-brutal out-of-tree module against the
# already-built dash kernel. The module is not part of the boot image; load it
# with insmod (see docs/kernel/MIHOMO_ANDROID.md).
require_cmd make
require_cmd modinfo
[[ -x "$TOOLCHAIN_DIR/bin/clang" ]] || die "run: make toolchain"
require_file "$OUT_DIR/.config"
require_file "$TCP_BRUTAL_DIR/Makefile"

current_brutal="$(git -C "$TCP_BRUTAL_DIR" rev-parse HEAD)"
[[ "$current_brutal" == "$TCP_BRUTAL_COMMIT" ]] || die \
	"tcp-brutal is at $current_brutal, expected $TCP_BRUTAL_COMMIT"

export PATH="$TOOLCHAIN_DIR/bin:$PATH"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-dash}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-mikernel}"
# Match build.sh: an empty LOCALVERSION suppresses the "-dirty"/"+" suffix.
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

# A stale kernel.release without LOCALVERSION would make the module vermagic
# "6.6.143-4k+". Regenerate it and the module linker script before building.
rm -f "$OUT_DIR/include/config/kernel.release" \
	"$OUT_DIR/include/generated/utsrelease.h"
"${MAKE[@]}" modules_prepare >/dev/null

"${MAKE[@]}" M="$TCP_BRUTAL_DIR" modules 2>&1 | tee "$OUT_DIR/build-tcp-brutal.log"

release="$(cat "$OUT_DIR/include/config/kernel.release")"
vermagic="$(modinfo -F vermagic "$TCP_BRUTAL_DIR/brutal.ko")"
[[ "$vermagic" == "$release"* ]] || die \
	"brutal.ko vermagic '$vermagic' does not match kernel release '$release'"

mkdir -p "$ARTIFACT_DIR"
cp "$TCP_BRUTAL_DIR/brutal.ko" "$ARTIFACT_DIR/brutal.ko"

# Sign the artifact (never the submodule copy, so reruns do not append a second
# signature). This is not required on the dash vendor-compat kernel, but makes
# the module usable on stricter builds.
sig_hash="$(sed -n 's/^CONFIG_MODULE_SIG_HASH="\(.*\)"/\1/p' "$OUT_DIR/.config")"
if [[ -n "$sig_hash" && -x "$OUT_DIR/scripts/sign-file" && \
	-f "$OUT_DIR/certs/signing_key.pem" && -f "$OUT_DIR/certs/signing_key.x509" ]]; then
	"$OUT_DIR/scripts/sign-file" "$sig_hash" \
		"$OUT_DIR/certs/signing_key.pem" \
		"$OUT_DIR/certs/signing_key.x509" \
		"$ARTIFACT_DIR/brutal.ko"
else
	echo "warning: module signing key/tool missing; shipping unsigned brutal.ko" >&2
fi
sha256sum "$ARTIFACT_DIR/brutal.ko" > "$ARTIFACT_DIR/brutal.ko.sha256"

echo "tcp-brutal: $ARTIFACT_DIR/brutal.ko (vermagic $vermagic)"
