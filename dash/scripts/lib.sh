#!/usr/bin/env bash
set -euo pipefail

DASH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "$DASH_ROOT/versions.env"

# GitHub Actions runners reach googlesource/GitLab directly; domestic mirrors
# only slow them down (and may be stale).  DASH_NO_MIRROR=1 does the same for
# local testing.
if [[ "${GITHUB_ACTIONS:-}" == "true" || "${DASH_NO_MIRROR:-0}" == "1" ]]; then
	AOSP_MIRROR_URL=
	AOSP_MIRROR_URL_FALLBACK=
	CLANG_PREBUILT_MIRROR_URL=
	CLANG_PREBUILT_MIRROR_URL_FALLBACK=
fi

# Shared paths consumed by every script that sources this library.
# AOSP_DIR_OVERRIDE lets verification run the same flow against a throwaway
# checkout (e.g. a git worktree at the pinned AOSP commit).
# shellcheck disable=SC2034
AOSP_DIR="${AOSP_DIR_OVERRIDE:-$DASH_ROOT/src/aosp/common}"
# shellcheck disable=SC2034
OUT_DIR="$DASH_ROOT/out/${DEVICE:-dash}"
# shellcheck disable=SC2034
ARTIFACT_DIR="$DASH_ROOT/out/artifacts"
# shellcheck disable=SC2034
TOOLCHAIN_DIR="$DASH_ROOT/toolchains/clang-prebuilt/clang-$CLANG_VERSION"
# shellcheck disable=SC2034
AUTOFDO_PROFILE="$AOSP_DIR/android/gki/aarch64/afdo/kernel.afdo"
JOBS="${JOBS:-$(nproc)}"

if [[ "$BAKASU_DIR" != /* ]]; then
	BAKASU_DIR="$DASH_ROOT/$BAKASU_DIR"
fi
BAKASU_DIR="$(cd "$BAKASU_DIR" && pwd)"

if [[ "$SUSFS_DIR" != /* ]]; then
	SUSFS_DIR="$DASH_ROOT/$SUSFS_DIR"
fi
SUSFS_DIR="$(cd "$SUSFS_DIR" && pwd)"

if [[ "$NOMOUNT_DIR" != /* ]]; then
	NOMOUNT_DIR="$DASH_ROOT/$NOMOUNT_DIR"
fi
NOMOUNT_DIR="$(cd "$NOMOUNT_DIR" && pwd)"

if [[ "$TCP_BRUTAL_DIR" != /* ]]; then
	TCP_BRUTAL_DIR="$DASH_ROOT/$TCP_BRUTAL_DIR"
fi
TCP_BRUTAL_DIR="$(cd "$TCP_BRUTAL_DIR" && pwd)"

die() {
	echo "error: $*" >&2
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

require_file() {
	[[ -e "$1" ]] || die "missing file: $1"
}

verify_autofdo_profile() {
	local profile_sha256

	require_file "$AUTOFDO_PROFILE"
	profile_sha256="$(sha256sum "$AUTOFDO_PROFILE" | cut -d' ' -f1)"
	[[ "$profile_sha256" == "$ACK_AUTOFDO_PROFILE_SHA256" ]] || die \
		"ACK AutoFDO profile hash mismatch: $profile_sha256"
}
