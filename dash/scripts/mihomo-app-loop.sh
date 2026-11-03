#!/system/bin/sh
# Run on the Android device as root.
# Usage: mihomo-app-loop.sh <apps.txt> [target] [dwell_seconds] [max_attempts]
#        [profile_dir] [profile_url]
# Opens each package once, verifies it reached the foreground, then spends the
# 5s dwell collecting a pprof piece. Failed apps are never retried. No app is
# force-stopped or its window closed. The last profile ends with the last app.
set -u
APPS="${1:-/data/local/tmp/mihomo_apps.txt}"
TARGET="${2:-60}"
DWELL="${3:-5}"
MAX_ATTEMPTS="${4:-75}"
PROFILE_DIR="${5:-/data/local/tmp/mihomo-profiles}"
PROFILE_URL="${6:-http://127.0.0.1:9090/debug/pprof/profile}"
APPS_FILE="$APPS"
BUSYBOX=/data/adb/ksu/bin/busybox

[ -f "$APPS_FILE" ] || { echo "missing app list: $APPS_FILE"; exit 1; }

# Keep the screen awake while the profile is collected.
svc power stayon true 2>/dev/null
wm dismiss-keyguard 2>/dev/null

current_pkg() {
    dumpsys window 2>/dev/null \
        | sed -n 's/.*mCurrentFocus=Window{[^ ]* u[0-9][0-9]* \([^\/]*\)\/.*/\1/p' \
        | head -1
}

theory=$((TARGET * (DWELL + 1)))
worst=$((MAX_ATTEMPTS * (DWELL + 1)))
echo "target=$TARGET dwell=${DWELL}s attempts<=$MAX_ATTEMPTS"
echo "theory=${theory}s (60*(5+1)) worst=${worst}s (75*(5+1))"
echo "start=$(date '+%F %T')"

start_epoch=$(date +%s)
success=0
attempt=0

while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    case "$pkg" in \#*) continue ;; esac
    [ "$attempt" -ge "$MAX_ATTEMPTS" ] && break
    attempt=$((attempt + 1))

    comp=$(cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$pkg" 2>/dev/null | tail -1)
    case "$comp" in
        */*) ;;
        *) echo "SKIP  $pkg  (no launcher activity)"; continue ;;
    esac

    echo "OPEN  [$attempt] $pkg -> $comp"
    timeout 8 am start -W -n "$comp" >/dev/null 2>&1
    sleep 1
    cur=$(current_pkg)
    if [ "$cur" = "$pkg" ]; then
        success=$((success + 1))
        piece="$PROFILE_DIR/piece-$(printf '%02d' "$success").pb"
        # The pprof request itself is the 5s dwell; no idle between apps.
        if "$BUSYBOX" wget -q -T $((DWELL + 10)) -O "$piece" \
            "${PROFILE_URL}?seconds=${DWELL}"; then
            echo "OK    [$success/$TARGET] $pkg profile=$piece"
        else
            echo "OK    [$success/$TARGET] $pkg profile=FAILED"
            sleep "$DWELL"
        fi
    else
        echo "SKIP  $pkg  (foreground=$cur)"
    fi
    [ "$success" -ge "$TARGET" ] && break
done < "$APPS_FILE"

end_epoch=$(date +%s)
elapsed=$((end_epoch - start_epoch))
echo "SUMMARY success=$success attempts=$attempt elapsed=${elapsed}s end=$(date '+%F %T')"
[ "$success" -ge "$TARGET" ] || exit 2
