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
	for i in 1 2 3 4; do
		apply_bbr
		apply_adios
		sleep 10
	done
) &

exit 0
