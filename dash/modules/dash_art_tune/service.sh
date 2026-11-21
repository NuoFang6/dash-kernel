#!/system/bin/sh
# Re-apply BBRv3 and ADIOS after boot. Some vendor services reset them during
# late boot; apply a few times without blocking the service stage.

MODDIR=${0%/*}
. "$MODDIR/common.sh"

(
	for i in 1 2 3 4 5 6; do
		[ "$(getprop sys.boot_completed)" = "1" ] && break
		sleep 5
	done
	# WLAN logging files can be created during boot; clean them and install
	# the cnss_diag.conf overlay once boot has settled.  vendor_tcpdump is a
	# disabled/oneshot init service started by sys.user.0.ce_available, and
	# its binary does not consult persist.vendor.tcpdump.enable, so stop it
	# explicitly (it will not restart this boot).
	apply_wlan_privacy
	setprop ctl.stop vendor_tcpdump 2>>"$LOG"
	log "vendor_tcpdump: $(getprop init.svc.vendor_tcpdump)"
	for i in 1 2 3 4; do
		apply_bbr
		apply_adios
		setprop ctl.stop vendor_tcpdump 2>>"$LOG"
		sleep 10
	done
) &

exit 0
