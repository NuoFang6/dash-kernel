#!/system/bin/sh
# Shared helpers for dash_art_tune.

MODDIR=${MODDIR:-${0%/*}}
LOG=/data/local/tmp/dash_art_tune.log

log() {
	echo "$(date '+%F %T') $*" >>"$LOG" 2>/dev/null
}

apply_bbr() {
	if ! grep -qw bbr3 /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
		log "bbr3 unavailable; leaving congestion control"
		return 1
	fi
	echo bbr3 >/proc/sys/net/ipv4/tcp_congestion_control 2>>"$LOG"
	echo fq_codel >/proc/sys/net/core/default_qdisc 2>>"$LOG"
	log "bbrv3: cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null) qdisc=$(cat /proc/sys/net/core/default_qdisc 2>/dev/null)"
}

apply_adios() {
	# sdc is the primary UFS LUN on dash. Only switch if adios is offered.
	for dev in sdc; do
		sched=/sys/block/$dev/queue/scheduler
		[ -f "$sched" ] || continue
		grep -qw adios "$sched" 2>/dev/null || continue
		echo adios >"$sched" 2>>"$LOG"
		log "$dev scheduler=$(cat "$sched" 2>/dev/null)"
	done
}
