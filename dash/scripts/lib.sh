#!/usr/bin/env bash
set -euo pipefail

DASH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "$DASH_ROOT/versions.env"

AOSP_DIR="$DASH_ROOT/src/aosp/common"
OUT_DIR="$DASH_ROOT/out/${DEVICE:-dash}"
ARTIFACT_DIR="$DASH_ROOT/out/artifacts"
TOOLCHAIN_DIR="$DASH_ROOT/toolchains/clang-prebuilt/clang-$CLANG_VERSION"
JOBS="${JOBS:-$(nproc)}"

if [[ "$BAKASU_DIR" != /* ]]; then
	BAKASU_DIR="$DASH_ROOT/$BAKASU_DIR"
fi
BAKASU_DIR="$(cd "$BAKASU_DIR" && pwd)"

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
