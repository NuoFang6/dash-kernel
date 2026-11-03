#!/system/bin/sh
# mihomo Alpha service. The config is authoritative: this script never
# creates firewall/TUN rules. Only mihomo itself configures TUN when
# tun.enable: true in /data/adb/mihomo/config.yaml.
MODDIR=${0%/*}
CONFIG_DIR=/data/adb/mihomo
CONFIG="$CONFIG_DIR/config.yaml"
BIN="$MODDIR/bin/mihomo"
PIDFILE="$CONFIG_DIR/mihomo.pid"
LOG="$CONFIG_DIR/mihomo.log"

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

# Wait for Android's default route / physical interface. Starting mihomo
# before ccmni is ready makes auto-detect-interface return empty and the TUN
# listener unusable.
i=0
while [ "$i" -lt 60 ]; do
    if ip route get 1.1.1.1 2>/dev/null | grep -q ' dev '; then
        break
    fi
    i=$((i + 1))
    sleep 1
done
sleep 1

# Persist TFO after Android's network sysctls settle.
echo 3 > /proc/sys/net/ipv4/tcp_fastopen
chmod 755 "$BIN" "$MODDIR/action.sh" "$MODDIR/service.sh" 2>/dev/null

[ -x "$BIN" ] || { echo "$(date) missing $BIN" >> "$LOG"; exit 1; }
[ -f "$CONFIG" ] || { echo "$(date) missing $CONFIG" >> "$LOG"; exit 1; }
mkdir -p "$CONFIG_DIR"

# Avoid duplicate instances after module updates / manual starts.
if [ -f "$PIDFILE" ]; then
    old="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
        kill -TERM "$old" 2>/dev/null
        sleep 2
    fi
fi
for p in $(pidof mihomo 2>/dev/null); do
    kill -TERM "$p" 2>/dev/null
done
sleep 1
for p in $(pidof mihomo 2>/dev/null); do
    kill -KILL "$p" 2>/dev/null
done
rm -f "$PIDFILE"

cd "$CONFIG_DIR" || exit 1
nohup "$BIN" -d "$CONFIG_DIR" -f "$CONFIG" >> "$LOG" 2>&1 &
echo $! > "$PIDFILE"
echo "$(date) started mihomo pid=$(cat "$PIDFILE") config=$CONFIG" >> "$LOG"
