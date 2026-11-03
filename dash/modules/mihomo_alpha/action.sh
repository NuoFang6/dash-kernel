#!/system/bin/sh
# KSU action button:
#   Volume Up   -> stop mihomo
#   Volume Down -> restart mihomo
#   no key for 10 seconds -> exit, leave mihomo running
MODDIR=${0%/*}
CONFIG_DIR=/data/adb/mihomo
PIDFILE="$CONFIG_DIR/mihomo.pid"
EVFILE=/data/local/tmp/mihomo_action.events
GETEVENT=/system/bin/getevent
DRY_RUN="${MIHOMO_ACTION_DRY_RUN:-0}"

stop_mihomo() {
    if [ -f "$PIDFILE" ]; then
        kill -TERM "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
    fi
    for p in $(pidof mihomo 2>/dev/null); do
        kill -TERM "$p" 2>/dev/null
    done
    sleep 2
    for p in $(pidof mihomo 2>/dev/null); do
        kill -KILL "$p" 2>/dev/null
    done
    rm -f "$PIDFILE"
}

echo "mihomo Alpha"
echo "音量上：停止 mihomo"
echo "音量下：重启 mihomo"
echo "10 秒无操作：退出（mihomo 继续运行）"

rm -f "$EVFILE"
"$GETEVENT" -ql > "$EVFILE" 2>/dev/null &
EVPID=$!
trap 'kill "$EVPID" 2>/dev/null; wait "$EVPID" 2>/dev/null; rm -f "$EVFILE"' EXIT INT TERM

start="$(date +%s)"
action=""
while [ $(( $(date +%s) - start )) -lt 10 ]; do
    if grep -q 'KEY_VOLUMEUP.*DOWN' "$EVFILE" 2>/dev/null; then
        action="up"
        break
    fi
    if grep -q 'KEY_VOLUMEDOWN.*DOWN' "$EVFILE" 2>/dev/null; then
        action="down"
        break
    fi
    sleep 1
done

kill "$EVPID" 2>/dev/null
wait "$EVPID" 2>/dev/null

case "$action" in
    up)
        if [ "$DRY_RUN" = "1" ]; then
            echo "[dry-run] would stop mihomo"
        else
            echo "停止 mihomo..."
            stop_mihomo
            echo "已停止"
        fi
        ;;
    down)
        if [ "$DRY_RUN" = "1" ]; then
            echo "[dry-run] would restart mihomo"
        else
            echo "重启 mihomo..."
            stop_mihomo
            if [ -x "$MODDIR/service.sh" ]; then
                sh "$MODDIR/service.sh"
            else
                cd "$CONFIG_DIR" || exit 1
                nohup "$MODDIR/bin/mihomo" -d "$CONFIG_DIR" -f "$CONFIG_DIR/config.yaml" >> "$CONFIG_DIR/mihomo.log" 2>&1 &
                echo $! > "$PIDFILE"
            fi
            sleep 2
            if pidof mihomo >/dev/null 2>&1; then
                echo "已重启 mihomo"
            else
                echo "mihomo 重启失败，请查看 $CONFIG_DIR/mihomo.log"
            fi
        fi
        ;;
    *)
        echo "10 秒无操作，退出"
        ;;
esac
