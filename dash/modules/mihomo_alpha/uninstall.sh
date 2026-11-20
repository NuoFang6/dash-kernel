#!/system/bin/sh
MODDIR=${0%/*}
CONFIG_DIR=/data/adb/mihomo
CONFIG="$CONFIG_DIR/config.yaml"
PIDFILE="$CONFIG_DIR/mihomo.pid"

TUN="$(awk '
    /^tun:[[:space:]]*$/ { in_tun = 1; next }
    /^[^[:space:]#]/ { in_tun = 0 }
    in_tun && $1 == "device:" { gsub(/"/, "", $2); print $2; exit }
' "$CONFIG" 2>/dev/null)"
[ -n "$TUN" ] || TUN=mihomo
for ipt in iptables ip6tables; do
    command -v "$ipt" >/dev/null 2>&1 || continue
    "$ipt" -D FORWARD -o "$TUN" -j ACCEPT 2>/dev/null
    "$ipt" -D FORWARD -i "$TUN" -j ACCEPT 2>/dev/null
done

if [ -f "$PIDFILE" ]; then
    kill -TERM "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
fi
for p in $(pidof mihomo 2>/dev/null); do
    kill -TERM "$p" 2>/dev/null
done
rm -f "$PIDFILE"
