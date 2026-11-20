#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_file "$AOSP_DIR/.git"
require_file "$BAKASU_DIR/kernel/Kbuild"
require_file "$SUSFS_DIR/kernel_patches/fs/susfs.c"

current_bakasu="$(git -C "$BAKASU_DIR" rev-parse HEAD)"
[[ "$current_bakasu" == "$BAKASU_COMMIT" ]] || \
	die "BakaSU is at $current_bakasu, expected $BAKASU_COMMIT (update versions.env or the submodule)"

current_susfs="$(git -C "$SUSFS_DIR" rev-parse HEAD)"
[[ "$current_susfs" == "$SUSFS_COMMIT" ]] || \
	die "susfs4ksu is at $current_susfs, expected $SUSFS_COMMIT (update versions.env or the submodule)"

git -C "$AOSP_DIR" reset --hard "$AOSP_COMMIT"
git -C "$AOSP_DIR" clean -fdx

mkdir -p "$AOSP_DIR/drivers"
ln -sfn "$(realpath --relative-to="$AOSP_DIR/drivers" "$BAKASU_DIR/kernel")" \
	"$AOSP_DIR/drivers/kernelsu"

while IFS= read -r patch; do
	[[ -z "$patch" || "$patch" == \#* ]] && continue
	echo "applying $patch"
	git -C "$AOSP_DIR" apply --index "$DASH_ROOT/patches/$patch"
done < "$DASH_ROOT/patches/series"

# SUSFS kernel files are installed straight from the pinned susfs4ksu
# submodule (previously vendored copies under patches/susfs/, byte-identical
# to the pinned upstream).  A submodule bump therefore flows into the build
# without regenerating the squash patch.
install -D -m 0644 "$SUSFS_DIR/kernel_patches/fs/susfs.c" \
	"$AOSP_DIR/fs/susfs.c"
install -D -m 0644 "$SUSFS_DIR/kernel_patches/include/linux/susfs.h" \
	"$AOSP_DIR/include/linux/susfs.h"
install -D -m 0644 "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" \
	"$AOSP_DIR/include/linux/susfs_def.h"

echo "patches applied"
