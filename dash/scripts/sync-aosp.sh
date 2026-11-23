#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Network policy: this tree is developed on a mainland-China host where
# android.googlesource.com is unreachable.  Fetch order is
# $AOSP_MIRROR_URL (if set) then $AOSP_REPO.
#
# The tree follows the moving AOSP_BRANCH (android15-6.6).  The exact branch
# tip is captured in versions.env as AOSP_COMMIT so builds stay reproducible:
#
#   make source                  reuse the pinned commit (works offline)
#   AOSP_UPDATE=1 make source    fetch the branch head and update the pin
#   AOSP_PIN=1   make source     never move off the pin even with AOSP_UPDATE=1
aosp_urls=()
[[ -n "${AOSP_MIRROR_URL:-}" ]] && aosp_urls+=("$AOSP_MIRROR_URL")
[[ -n "${AOSP_MIRROR_URL_FALLBACK:-}" ]] && aosp_urls+=("$AOSP_MIRROR_URL_FALLBACK")
aosp_urls+=("$AOSP_REPO")

fetch_timeout="${AOSP_FETCH_TIMEOUT:-900}"

pinned_locally() {
	git -C "$AOSP_DIR" cat-file -e "$AOSP_COMMIT^{commit}" 2>/dev/null
}

update_pin() {
	local commit="$1"
	echo "updating AOSP_COMMIT in versions.env: $AOSP_COMMIT -> $commit"
	sed -i "s/^AOSP_COMMIT=.*/AOSP_COMMIT=$commit/" "$DASH_ROOT/versions.env"
	AOSP_COMMIT="$commit"
}

mkdir -p "$(dirname "$AOSP_DIR")"

if [[ ! -d "$AOSP_DIR/.git" ]]; then
	cloned=0
	for url in "${aosp_urls[@]}"; do
		echo "cloning $AOSP_BRANCH from $url"
		if timeout "$fetch_timeout" git clone --depth=1 --single-branch \
			--branch "$AOSP_BRANCH" "$url" "$AOSP_DIR"; then
			cloned=1
			break
		fi
		rm -rf "$AOSP_DIR"
	done
	((cloned)) || die "could not clone AOSP $AOSP_BRANCH from: ${aosp_urls[*]}"
fi

if [[ "${AOSP_UPDATE:-0}" != 1 && "${FORCE_FETCH:-0}" != 1 ]] && pinned_locally; then
	echo "AOSP $AOSP_BRANCH pinned at $AOSP_COMMIT; skipping fetch (AOSP_UPDATE=1 to move)"
else
	# Fail fast instead of looking like a hang on a stalled international
	# connection; `timeout` covers the connect phase too.
	export GIT_HTTP_LOW_SPEED_LIMIT="${GIT_HTTP_LOW_SPEED_LIMIT:-1024}"
	export GIT_HTTP_LOW_SPEED_TIME="${GIT_HTTP_LOW_SPEED_TIME:-60}"

	fetched=0
	tip=""
	for url in "${aosp_urls[@]}"; do
		echo "fetching $AOSP_BRANCH from $url"
		if timeout "$fetch_timeout" git -C "$AOSP_DIR" fetch --depth=1 "$url" \
			"+refs/heads/$AOSP_BRANCH:refs/dash/$AOSP_BRANCH"; then
			tip="$(git -C "$AOSP_DIR" rev-parse "refs/dash/$AOSP_BRANCH")"
			fetched=1
			break
		fi
	done
	((fetched)) || die "could not fetch AOSP $AOSP_BRANCH (offline and not cached?)"

	if [[ "$tip" != "$AOSP_COMMIT" ]]; then
		if [[ "${AOSP_PIN:-0}" == 1 ]]; then
			die "AOSP $AOSP_BRANCH moved to $tip but AOSP_PIN=1 (pin is $AOSP_COMMIT)"
		fi
		update_pin "$tip"
	fi
fi

actual_commit="$(git -C "$AOSP_DIR" rev-parse "$AOSP_COMMIT^{commit}")"
[[ "$actual_commit" == "$AOSP_COMMIT" ]] || \
	die "AOSP commit resolves to $actual_commit, expected $AOSP_COMMIT"

git -C "$AOSP_DIR" checkout --detach "$AOSP_COMMIT"
git -C "$AOSP_DIR" reset --hard "$AOSP_COMMIT"
git -C "$AOSP_DIR" clean -fdx

echo "kernel source: $(git -C "$AOSP_DIR" rev-parse HEAD) ($AOSP_BRANCH)"