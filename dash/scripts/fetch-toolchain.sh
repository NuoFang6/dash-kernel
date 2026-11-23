#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ -x "$TOOLCHAIN_DIR/bin/clang" && "${CLANG_UPDATE:-0}" != 1 ]]; then
	echo "toolchain already available: $TOOLCHAIN_DIR"
	exit 0
fi

clone_dir="$DASH_ROOT/toolchains/clang-prebuilt"

# Domestic mirrors first: android.googlesource.com is unreachable on the
# mainland-China dev host.  TUNA is the freshest reachable mirror; USTC is the
# fallback.  Set CLANG_UPDATE=1 to refresh an existing checkout to the latest
# snapshot of the pinned clang version (AOSP occasionally updates the prebuilt
# inside the same clang-rXXXXXX directory).
urls=()
[[ -n "${CLANG_PREBUILT_MIRROR_URL:-}" ]] && urls+=("$CLANG_PREBUILT_MIRROR_URL")
[[ -n "${CLANG_PREBUILT_MIRROR_URL_FALLBACK:-}" ]] && urls+=("$CLANG_PREBUILT_MIRROR_URL_FALLBACK")
urls+=("$CLANG_PREBUILT_REPO")

# The prebuilts/clang repo is shallow-cloned (--depth=1) with --sparse and
# --filter=blob:none, but blob filters do not filter TREE objects: the HEAD
# commit carries dozens of clang-* version dirs, so the tree metadata alone is
# a multi-hundred-MB download.  In a CI log (no tty) git prints no progress by
# default, which looks like a hang -- force progress, and abort instead of
# hanging forever when the connection stalls.
export GIT_HTTP_LOW_SPEED_LIMIT="${GIT_HTTP_LOW_SPEED_LIMIT:-1024}"
export GIT_HTTP_LOW_SPEED_TIME="${GIT_HTTP_LOW_SPEED_TIME:-120}"

if [[ "${CLANG_UPDATE:-0}" == 1 && -d "$clone_dir/.git" ]]; then
	updated=0
	for url in "${urls[@]}"; do
		echo "updating clang-$CLANG_VERSION from $url"
		if timeout "${CLANG_FETCH_TIMEOUT:-1800}" git -C "$clone_dir" fetch --depth=1 \
			"$url" "+refs/heads/$CLANG_PREBUILT_BRANCH:refs/dash/prebuilt"; then
			updated=1
			break
		fi
	done
	((updated)) || die "could not update clang prebuilts from: ${urls[*]}"
	git -C "$clone_dir" checkout --detach refs/dash/prebuilt
	git -C "$clone_dir" sparse-checkout set "clang-$CLANG_VERSION"
	[[ -x "$TOOLCHAIN_DIR/bin/clang" ]] || die "clang not found after checkout: $TOOLCHAIN_DIR"
	"$TOOLCHAIN_DIR/bin/clang" --version | head -1
	echo "toolchain updated: $(git -C "$clone_dir" rev-parse HEAD:clang-$CLANG_VERSION)"
	exit 0
fi

rm -rf "$clone_dir"
mkdir -p "$DASH_ROOT/toolchains"

cloned=0
for url in "${urls[@]}"; do
	echo "cloning clang-$CLANG_VERSION from $url"
	rm -rf "$clone_dir"
	if timeout "${CLANG_FETCH_TIMEOUT:-1800}" git clone --depth=1 --single-branch \
		-b "$CLANG_PREBUILT_BRANCH" --filter=blob:none --sparse --progress \
		"$url" "$clone_dir"; then
		cloned=1
		break
	fi
done
((cloned)) || die "could not clone clang prebuilts from: ${urls[*]}"

git -C "$clone_dir" sparse-checkout set "clang-$CLANG_VERSION"

[[ -x "$TOOLCHAIN_DIR/bin/clang" ]] || die "clang not found after checkout: $TOOLCHAIN_DIR"
"$TOOLCHAIN_DIR/bin/clang" --version | head -1
