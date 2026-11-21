#!/system/bin/sh
# Manual apply from KSU manager (action button) or:
#   su -c '/data/adb/modules/dash_art_tune/action.sh'
MODDIR=${0%/*}
. "$MODDIR/common.sh"

log "manual action"
apply_bbr
apply_adios
apply_wlan_privacy
setprop ctl.stop vendor_tcpdump 2>>"$LOG"
log "vendor_tcpdump: $(getprop init.svc.vendor_tcpdump)"
apply_zram_lz4kd
exit 0
