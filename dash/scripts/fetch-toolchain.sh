#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ -x "$TOOLCHAIN_DIR/bin/clang" ]]; then
	echo "toolchain already available: $TOOLCHAIN_DIR"
	exit 0
fi

clone_dir="$DASH_ROOT/toolchains/clang-prebuilt"
rm -rf "$clone_dir"
mkdir -p "$DASH_ROOT/toolchains"

# The prebuilts/clang repo is shallow-cloned (--depth=1) with --sparse and
# --filter=blob:none, but blob filters do not filter TREE objects: the HEAD
# commit carries dozens of clang-* version dirs, so the tree metadata alone is
# a multi-hundred-MB download.  In a CI log (no tty) git prints no progress by
# default, which looks like a hang -- force progress, and abort instead of
# hanging forever when the connection stalls.
export GIT_HTTP_LOW_SPEED_LIMIT=1024
export GIT_HTTP_LOW_SPEED_TIME=120

git clone --depth=1 --single-branch -b "$CLANG_PREBUILT_BRANCH" \
	--filter=blob:none --sparse --progress \
	"$CLANG_PREBUILT_REPO" "$clone_dir"
git -C "$clone_dir" sparse-checkout set "clang-$CLANG_VERSION"

[[ -x "$TOOLCHAIN_DIR/bin/clang" ]] || die "clang not found after checkout: $TOOLCHAIN_DIR"
"$TOOLCHAIN_DIR/bin/clang" --version | head -1
