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
	die "nomount is at $current_nomount, expected $NOMOUNT_COMMIT ($NOMOUNT_BRANCH; update versions.env or the submodule)"

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

# dash susfs overrides: dash-owned changes to the INSTALLED susfs files (not
# the submodule).  These apply AFTER the install above; gen-patches excludes
# fs/susfs*.c/h from the squash, so they are maintained by hand here.
# (nullglob is still on from the series walk above.)
for patch in "$DASH_ROOT/patches/susfs-overrides/"*.patch; do
	echo "applying susfs-overrides/$(basename "$patch")"
	(cd "$AOSP_DIR" && git apply "$patch")
done

# susfs4ksu f98f082 ("Sync with upstream") wraps the priority-uid filter
# (susfs_is_priority_uid_filtered and friends) in
# #ifdef CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER but ships no Kconfig entry for
# it, so the feature is unreachable and our gated call sites would fail to
# link.  Provide the entry here (idempotent; fs/Kconfig is reset with the
# tree and excluded from gen-patches, like the NoMount wiring below).
# features.fragment sets it =y to keep the on-device behavior of the
# previous SUSFS pin, where this code compiled unconditionally.
susfs_kconfig="$AOSP_DIR/fs/Kconfig"
if ! grep -q 'config KSU_SUSFS_PRIORITY_UID_FILTER' "$susfs_kconfig"; then
	awk '
		/^endmenu/ { last_match = NR }
		{ lines[NR] = $0 }
		END {
			for (i = 1; i <= NR; i++) {
				if (i == last_match) {
					print ""
					print "config KSU_SUSFS_PRIORITY_UID_FILTER"
					print "\tbool \"Enable SUSFS priority uid filter (setpriority/getpriority/ioprio)\""
					print "\tdepends on KSU_SUSFS"
					print "\tdefault n"
					print "\thelp"
					print "\t  susfs4ksu f98f082 gates susfs_is_priority_uid_filtered()"
					print "\t  behind this switch but provides no Kconfig entry for it."
					print "\t  Enable to keep hiding uids from the setpriority /"
					print "\t  getpriority / ioprio_set / ioprio_get syscall paths."
				}
				print lines[i]
			}
		}
	' "$susfs_kconfig" > "$susfs_kconfig.tmp" && mv "$susfs_kconfig.tmp" "$susfs_kconfig"
fi

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
