#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Build the pinned, unmodified MetaCubeX/mihomo Alpha submodule.
# Usage: build-mihomo.sh [pgo-profile] [output]
MIHOMO_SRC="$DASH_ROOT/../third_party/mihomo"
PGO_PROFILE="${1:-}"
OUTPUT="${2:-$DASH_ROOT/../handoff/mihomo-alpha-built}"
if [[ "$OUTPUT" != /* ]]; then
	OUTPUT="$DASH_ROOT/../$OUTPUT"
fi
GO_BIN="${GO_BIN:-go}"

require_file "$MIHOMO_SRC/go.mod"
current="$(git -C "$MIHOMO_SRC" rev-parse HEAD)"
[[ "$current" == "$MIHOMO_COMMIT" ]] || die \
	"mihomo is at $current, expected $MIHOMO_COMMIT"
command -v "$GO_BIN" >/dev/null 2>&1 || die "missing Go: $GO_BIN"

args=(
	build
	-tags with_gvisor
	-trimpath
	-buildmode=pie
	-ldflags "-s -w -X github.com/metacubex/mihomo/constant.Version=v1.19.33-alpha-ca8d7c4 -X github.com/metacubex/mihomo/constant.BuildTime=2026-10-30"
	-o "$OUTPUT"
)
if [[ -n "$PGO_PROFILE" ]]; then
	require_file "$PGO_PROFILE"
	PGO_PROFILE="$(realpath "$PGO_PROFILE")"
	args+=("-pgo=$PGO_PROFILE")
fi

(
	cd "$MIHOMO_SRC"
	CGO_ENABLED=0 GOOS=android GOARCH=arm64 "$GO_BIN" "${args[@]}" .
)
echo "built: $OUTPUT"
sha256sum "$OUTPUT"
"$OUTPUT" -v 2>/dev/null | head -2 || true
