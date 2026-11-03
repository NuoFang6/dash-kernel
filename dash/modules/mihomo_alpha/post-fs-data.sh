#!/system/bin/sh
MODDIR=${0%/*}
# Persist TCP Fast Open for mihomo: bit 0 = client, bit 1 = server.
chmod 755 "$MODDIR/bin/mihomo" "$MODDIR/action.sh" "$MODDIR/service.sh" 2>/dev/null
# Persist TCP Fast Open for mihomo: bit 0 = client, bit 1 = server.
echo 3 > /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null
