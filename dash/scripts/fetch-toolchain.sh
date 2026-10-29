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

git clone --depth=1 --single-branch -b "$CLANG_PREBUILT_BRANCH" \
	--filter=blob:none --sparse \
	"$CLANG_PREBUILT_REPO" "$clone_dir"
git -C "$clone_dir" sparse-checkout set "clang-$CLANG_VERSION"

[[ -x "$TOOLCHAIN_DIR/bin/clang" ]] || die "clang not found after checkout: $TOOLCHAIN_DIR"
"$TOOLCHAIN_DIR/bin/clang" --version | head -1
