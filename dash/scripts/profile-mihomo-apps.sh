#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Open TARGET apps in usage order, one at a time, and collect a 5s pprof piece
# for each app that actually reaches the foreground. Pieces are merged into a
# single CPU profile suitable for Go PGO. No app is force-stopped; the profile
# request itself is the dwell, so there is no idle tail after the last app.
APPS_FILE="$DASH_ROOT/../handoff/mihomo_apps.txt"
PROFILE="$DASH_ROOT/../handoff/mihomo-alpha-cpu.pgo"
PROFILE_DIR_DEV=/data/local/tmp/mihomo-profiles
PROFILE_DIR_HOST="$DASH_ROOT/../handoff/mihomo-profiles"
LOOP_LOG="$DASH_ROOT/../handoff/mihomo-app-loop.log"
TARGET="${TARGET:-60}"
DWELL="${DWELL:-5}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-75}"
GO_BIN="${GO_BIN:-go}"
DEVICE_SCRIPT=/data/local/tmp/mihomo-app-loop.sh

require_cmd adb
require_cmd curl
command -v "$GO_BIN" >/dev/null 2>&1 || die "missing Go: $GO_BIN"
adb get-state >/dev/null 2>&1 || die "no adb device"

restore_config() {
	adb shell 'su -c "cp /data/adb/mihomo/config.profile.bak /data/adb/mihomo/config.yaml; \
		sh /data/adb/modules/mihomo_alpha/service.sh"' >/dev/null 2>&1 || true
	adb forward --remove tcp:19090 >/dev/null 2>&1 || true
}
trap restore_config EXIT

# Build a usage-ranked launchable app list on the host.
adb shell 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER' \
	> "$DASH_ROOT/../handoff/mihomo-launchable.txt"
adb shell 'dumpsys usagestats' > "$DASH_ROOT/../handoff/mihomo-usagestats.txt"
python3 - "$DASH_ROOT/../handoff/mihomo-launchable.txt" \
	"$DASH_ROOT/../handoff/mihomo-usagestats.txt" "$APPS_FILE" <<'PY'
import re, sys
launch, usage, out = sys.argv[1:4]
pkgs = set()
for line in open(launch, errors="ignore"):
    line = line.strip()
    if "/" in line and re.match(r"^[A-Za-z0-9_.]+/", line):
        pkgs.add(line.split("/", 1)[0])
counts = {}
for line in open(usage, errors="ignore"):
    if "ACTIVITY_RESUMED" not in line:
        continue
    m = re.search(r"package=([^ ]+)", line)
    if m:
        counts[m.group(1)] = counts.get(m.group(1), 0) + 1
skip = {
    "com.miui.home", "com.android.systemui",
    "com.android.permissioncontroller", "com.google.android.permissioncontroller",
}
pkgs -= skip
ordered = sorted(pkgs, key=lambda p: (-counts.get(p, 0), p))
with open(out, "w") as f:
    for p in ordered[:80]:
        f.write(p + "\n")
print(f"apps: {len(ordered[:80])} (launchable={len(pkgs)}), top={ordered[:5]}")
PY

# mihomo exposes pprof only when log-level is debug; restore in trap.
adb shell 'su -c "cp /data/adb/mihomo/config.yaml /data/adb/mihomo/config.profile.bak; \
	sed -i \"s/^log-level:.*/log-level: debug/\" /data/adb/mihomo/config.yaml; \
	sh /data/adb/modules/mihomo_alpha/service.sh"' >/dev/null
sleep 8
adb forward --remove tcp:19090 >/dev/null 2>&1 || true
adb forward tcp:19090 tcp:9090 >/dev/null
code=$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:19090/debug/pprof/" || true)
[[ "$code" == "200" ]] || die "pprof endpoint returned HTTP $code (is log-level debug?)"

adb shell 'su -c "rm -rf /data/local/tmp/mihomo-profiles; mkdir -p /data/local/tmp/mihomo-profiles; chmod 777 /data/local/tmp/mihomo-profiles"' >/dev/null
rm -rf "$PROFILE_DIR_HOST"
mkdir -p "$PROFILE_DIR_HOST"
adb push "$DASH_ROOT/scripts/mihomo-app-loop.sh" "$DEVICE_SCRIPT" >/dev/null
adb push "$APPS_FILE" /data/local/tmp/mihomo_apps.txt >/dev/null
adb shell 'su -c "chmod 755 /data/local/tmp/mihomo-app-loop.sh"' >/dev/null

echo "dwell=${DWELL}s target=$TARGET theory=$((TARGET*(DWELL+1)))s worst=$((MAX_ATTEMPTS*(DWELL+1)))s; profile ends with last app"
set +e
adb shell "su -c '/data/local/tmp/mihomo-app-loop.sh /data/local/tmp/mihomo_apps.txt $TARGET $DWELL $MAX_ATTEMPTS $PROFILE_DIR_DEV http://127.0.0.1:9090/debug/pprof/profile'" \
	2>&1 | tee "$LOOP_LOG"
LOOP_RC=${PIPESTATUS[0]}
set -e

adb pull "$PROFILE_DIR_DEV/." "$PROFILE_DIR_HOST/" >/dev/null 2>&1 || true
pieces=( "$PROFILE_DIR_HOST"/*.pb )
[[ -e "${pieces[0]}" ]] || die "no pprof pieces collected"
echo "pieces=${#pieces[@]}"
"$GO_BIN" tool pprof -proto -output "$PROFILE" "${pieces[@]}" >/dev/null
[[ -s "$PROFILE" ]] || die "empty merged profile"
ls -lh "$PROFILE"
"$GO_BIN" tool pprof -top -nodecount=30 "$PROFILE" | tee "$DASH_ROOT/../handoff/mihomo-profile-top.txt"
echo "loop_rc=$LOOP_RC profile=$PROFILE"
[ "$LOOP_RC" -eq 0 ] || echo "warning: target not reached; review $LOOP_LOG" >&2
