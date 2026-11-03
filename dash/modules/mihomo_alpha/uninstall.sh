#!/system/bin/sh
MODDIR=${0%/*}
CONFIG_DIR=/data/adb/mihomo
PIDFILE="$CONFIG_DIR/mihomo.pid"
if [ -f "$PIDFILE" ]; then
    kill -TERM "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
fi
for p in $(pidof mihomo 2>/dev/null); do
    kill -TERM "$p" 2>/dev/null
done
rm -f "$PIDFILE"
