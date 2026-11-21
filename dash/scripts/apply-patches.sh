#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_file "$AOSP_DIR/.git"
require_file "$BAKASU_DIR/kernel/Kbuild"
require_file "$SUSFS_DIR/kernel_patches/fs/susfs.c"
require_file "$NOMOUNT_DIR/kernel/src/Kconfig"

current_bakasu="$(git -C "$BAKASU_DIR" rev-parse HEAD)"
[[ "$current_bakasu" == "$BAKASU_COMMIT" ]] || \
	die "BakaSU is at $current_bakasu, expected $BAKASU_COMMIT (update versions.env or the submodule)"

current_susfs="$(git -C "$SUSFS_DIR" rev-parse HEAD)"
[[ "$current_susfs" == "$SUSFS_COMMIT" ]] || \
	die "susfs4ksu is at $current_susfs, expected $SUSFS_COMMIT (update versions.env or the submodule)"

current_nomount="$(git -C "$NOMOUNT_DIR" rev-parse HEAD)"
[[ "$current_nomount" == "$NOMOUNT_COMMIT" ]] || \
	die "nomount is at $current_nomount, expected $NOMOUNT_COMMIT ($NOMOUNT_TAG; update versions.env or the submodule)"

git -C "$AOSP_DIR" reset --hard "$AOSP_COMMIT"
git -C "$AOSP_DIR" clean -fdx

mkdir -p "$AOSP_DIR/drivers"
ln -sfn "$(realpath --relative-to="$AOSP_DIR/drivers" "$BAKASU_DIR/kernel")" \
	"$AOSP_DIR/drivers/kernelsu"

# Walk patches/series: each entry is a feature directory (patches inside
# apply in lexical order) or a bare patch file.  Ownership is file-level
# (scripts/split-patches.py), so entries never touch the same file.
shopt -s nullglob
applied=0
while IFS= read -r entry || [[ -n "$entry" ]]; do
	[[ -z "$entry" || "$entry" == \#* ]] && continue
	entry_path="$DASH_ROOT/patches/$entry"
	if [[ -d "$entry_path" ]]; then
		for patch in "$entry_path"/*.patch; do
			echo "applying $entry/$(basename "$patch")"
			git -C "$AOSP_DIR" apply --index "$patch"
			applied=$((applied + 1))
		done
	else
		echo "applying $entry"
		git -C "$AOSP_DIR" apply --index "$entry_path"
		applied=$((applied + 1))
	fi
done < "$DASH_ROOT/patches/series"
echo "patch series applied: $applied patches"

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

# NoMount (VFS path redirection subsystem) is symlinked into fs/ and hooked
# into fs/Makefile + fs/Kconfig, mirroring upstream kernel/setup.sh but
# re-runnable after the reset/clean above.  Apply the series first, then
# hook: the series also touches fs/ and must see the pristine AOSP state.
nm_fs_mk="$AOSP_DIR/fs/Makefile"
nm_fs_kconfig="$AOSP_DIR/fs/Kconfig"
ln -sfn "$(realpath --relative-to="$AOSP_DIR/fs" "$NOMOUNT_DIR/kernel/src")" \
	"$AOSP_DIR/fs/nomount"
grep -q "CONFIG_NOMOUNT" "$nm_fs_mk" || \
	printf '\nobj-$(CONFIG_NOMOUNT) += nomount/\n' >> "$nm_fs_mk"
if ! grep -q 'fs/nomount/Kconfig' "$nm_fs_kconfig"; then
	awk '
		/^endmenu/ { last_match = NR }
		{ lines[NR] = $0 }
		END {
			for (i = 1; i <= NR; i++) {
				if (i == last_match) print "source \"fs/nomount/Kconfig\""
				print lines[i]
			}
		}
	' "$nm_fs_kconfig" > "$nm_fs_kconfig.tmp" && mv "$nm_fs_kconfig.tmp" "$nm_fs_kconfig"
fi

echo "patches applied"
