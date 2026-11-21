#!/system/bin/sh
# Manual apply from KSU manager (action button) or:
#   su -c '/data/adb/modules/dash_art_tune/action.sh'
MODDIR=${0%/*}
. "$MODDIR/common.sh"

log "manual action"
apply_bbr
apply_adios
exit 0
