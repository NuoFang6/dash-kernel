#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Regenerate the feature patch series from the live src/aosp/common tree.
# Long-term edits belong in the source tree, never in patch files: edit src,
# run `make gen-patches`, review the diff of patches/.
require_file "$AOSP_DIR/.git"

squash="$(mktemp)"
trap 'rm -f "$squash"' EXIT

# Excludes: drivers/kernelsu is a symlink to the BakaSU submodule; SUSFS
# kernel files are installed from the pinned susfs4ksu submodule; fs/Kconfig
# (and the untracked fs/nomount symlink) carry the script-side NoMount
# wiring from apply-patches.sh.  Anything else unmapped makes
# split-patches.py fail, so nothing silently disappears.
git -C "$AOSP_DIR" diff "$AOSP_COMMIT" -- . \
	':(exclude)drivers/kernelsu' \
	':(exclude)fs/susfs.c' \
	':(exclude)include/linux/susfs.h' \
	':(exclude)include/linux/susfs_def.h' \
	':(exclude)fs/Kconfig' \
	> "$squash"

python3 -I "$DASH_ROOT/scripts/split-patches.py" write \
	--squash "$squash" --patches-dir "$DASH_ROOT/patches"
python3 -I "$DASH_ROOT/scripts/split-patches.py" check \
	--squash "$squash" --patches-dir "$DASH_ROOT/patches"

echo "gen-patches done; review with: git -C '$DASH_ROOT/..' diff -- dash/patches"
