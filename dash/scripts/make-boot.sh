#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_cmd python3
require_cmd unpack_bootimg
require_cmd sha256sum
require_cmd od

STOCK_BOOT_IMG="${STOCK_BOOT_IMG:-$DASH_ROOT/../handoff/dash-gap-handoff/boot/boot_b.img}"
KERNEL_IMAGE="${KERNEL_IMAGE:-$ARTIFACT_DIR/Image.lz4}"
OUTPUT="${OUTPUT:-$ARTIFACT_DIR/boot.img}"
WORK_DIR="$OUT_DIR/boot-package"

require_file "$STOCK_BOOT_IMG"
require_file "$KERNEL_IMAGE"

# dash stock boot expects a legacy LZ4 frame (magic 0x184C2102), not the
# standard LZ4 frame (0x184D2204).  Fail before touching the boot image.
lz4_magic="$(od -An -tx1 -N4 "$KERNEL_IMAGE" | tr -d ' \n')"
[[ "$lz4_magic" == "02214c18" ]] || \
	die "kernel is not legacy-LZ4 (magic $lz4_magic, expected 02214c18)"
mkdir -p "$WORK_DIR" "$ARTIFACT_DIR"

# Do not rebuild a boot image from scratch: preserve the stock header,
# OEM-signed vbmeta and AVB footer.  The dash bootloader in its hidden-unlock
# state accepts the unchanged signed metadata, but rejects an image with the
# metadata stripped or with a re-signed/modified vbmeta.
python3 "$DASH_ROOT/scripts/repack-boot.py" \
	--stock "$STOCK_BOOT_IMG" \
	--kernel "$KERNEL_IMAGE" \
	--output "$OUTPUT"

rm -rf "$WORK_DIR/check"
mkdir -p "$WORK_DIR/check"
unpack_bootimg --boot_img "$OUTPUT" --out "$WORK_DIR/check" \
	--format=mkbootimg > "$WORK_DIR/check.args"
grep -q -- '--header_version 4' "$WORK_DIR/check.args" || die "output is not header v4"
cmp -s "$KERNEL_IMAGE" "$WORK_DIR/check/kernel" || die "packed kernel mismatch"
[[ ! -s "$WORK_DIR/check/ramdisk" ]] || die "unexpected ramdisk in boot.img"
[[ "$(stat -c%s "$OUTPUT")" == "$(stat -c%s "$STOCK_BOOT_IMG")" ]] || \
	die "output size differs from stock partition image"

python3 - "$OUTPUT" <<'PY'
from pathlib import Path
import struct
import sys

b = Path(sys.argv[1]).read_bytes()
if b[:8] != b"ANDROID!" or b[-64:-60] != b"AVBf":
    raise SystemExit("missing Android header or AVB footer")
orig, vb_off, vb_size = struct.unpack_from(">QQQ", b, len(b) - 52)
if b[vb_off:vb_off + 4] != b"AVB0":
    raise SystemExit("OEM vbmeta block is missing")
if vb_off + vb_size + 64 > len(b):
    raise SystemExit("invalid AVB offsets")
print(f"AVB footer: original_image_size={orig} vbmeta={vb_off}+{vb_size}")
PY

sha256sum "$OUTPUT" > "$ARTIFACT_DIR/boot.img.sha256"
echo "boot image: $OUTPUT"
cat "$ARTIFACT_DIR/boot.img.sha256"
