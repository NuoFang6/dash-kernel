#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

mkdir -p "$(dirname "$AOSP_DIR")"

if [[ ! -d "$AOSP_DIR/.git" ]]; then
	git clone --depth=1 --single-branch --branch "$AOSP_TAG" "$AOSP_REPO" "$AOSP_DIR"
fi

git -C "$AOSP_DIR" fetch --depth=1 origin \
	"refs/tags/$AOSP_TAG:refs/tags/$AOSP_TAG"
actual_commit="$(git -C "$AOSP_DIR" rev-parse "${AOSP_TAG}^{commit}")"
[[ "$actual_commit" == "$AOSP_COMMIT" ]] || \
	die "AOSP tag resolves to $actual_commit, expected $AOSP_COMMIT"

git -C "$AOSP_DIR" checkout --detach "$AOSP_COMMIT"
git -C "$AOSP_DIR" reset --hard "$AOSP_COMMIT"
git -C "$AOSP_DIR" clean -fdx

echo "kernel source: $(git -C "$AOSP_DIR" rev-parse HEAD)"
