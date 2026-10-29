#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_file "$ARTIFACT_DIR/Image"
require_file "$ARTIFACT_DIR/Image.lz4"
require_file "$OUT_DIR/vmlinux"
require_file "$OUT_DIR/vmlinux.symvers"
require_file "$DASH_ROOT/scripts/verify-os4-kcfi.py"
require_file "$DASH_ROOT/scripts/check-vendor-modules.py"

"$DASH_ROOT/scripts/verify-os4-kcfi.py" "$OUT_DIR/vmlinux" "$OUT_DIR/.config"
python3 "$DASH_ROOT/scripts/check-vendor-modules.py" \
	--symvers "$OUT_DIR/vmlinux.symvers" \
	--manifest "$DASH_ROOT/../handoff/dash-gap-handoff/device/module_manifest.tsv" \
	--modules "$DASH_ROOT/../handoff/dash-gap-handoff/modules" \
	--json-out "$OUT_DIR/vendor-modules.json"

STOCK_BOOT_IMG="${STOCK_BOOT_IMG:-$DASH_ROOT/../handoff/dash-gap-handoff/boot/boot_b.img}" \
	"$DASH_ROOT/scripts/make-boot.sh"

kernel_version="$(strings "$ARTIFACT_DIR/Image" | sed -n 's/^Linux version \([^ ]*\).*/\1/p' | head -1)"
kernel_release="$(LOCALVERSION= make -s -C "$AOSP_DIR" O="$OUT_DIR" ARCH=arm64 kernelrelease 2>/dev/null || true)"
config_sha="$(sha256sum "$OUT_DIR/.config" | cut -d' ' -f1)"
aosp_commit="$(git -C "$AOSP_DIR" rev-parse HEAD)"
clang_version="$("$TOOLCHAIN_DIR/bin/clang" --version | head -1)"

{
	printf 'AOSP_TAG=%s\n' "$AOSP_TAG"
	printf 'AOSP_COMMIT=%s\n' "$aosp_commit"
	printf 'KERNEL_VERSION=%s\n' "$kernel_version"
	printf 'KERNEL_RELEASE=%s\n' "$kernel_release"
	printf 'CLANG=%s\n' "$clang_version"
	printf 'CONFIG_SHA256=%s\n' "$config_sha"
	printf 'BASH_VERSION=%s\n' "$(bash --version | head -1)"
} > "$ARTIFACT_DIR/BUILD_INFO"

(
	cd "$ARTIFACT_DIR"
	sha256sum Image Image.lz4 boot.img config System.map > SHA256SUMS
)
cp "$ARTIFACT_DIR/BUILD_INFO" "$ARTIFACT_DIR/SHA256SUMS" "$DASH_ROOT/out/dash/"

echo "final artifacts:"
ls -lh "$ARTIFACT_DIR"/Image "$ARTIFACT_DIR"/Image.lz4 \
	"$ARTIFACT_DIR"/boot.img "$ARTIFACT_DIR"/SHA256SUMS
echo
cat "$ARTIFACT_DIR/BUILD_INFO"
echo
cat "$ARTIFACT_DIR/SHA256SUMS"
