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

# Vendor WLAN diagnostics/logging:
#  - present cnss_diag.conf with LOG_PATH_FLAG=0 through a bind mount (the
#    module copy is the mount source; /data is not covered by module mounts)
#  - empty /data/vendor/wlan_logs and turn tcpdump.pcap0 into a directory so
#    tcpdump cannot create its capture file under that name
apply_wlan_privacy() {
	confdir=/data/vendor/wifi
	target=$confdir/cnss_diag.conf
	src=$MODDIR/cnss_diag.conf
	logdir=/data/vendor/wlan_logs
	expected=u:object_r:vendor_wifi_vendor_data_file:s0

	mkdir -p "$confdir" 2>/dev/null

	# The target may not exist on a ROM that never started cnss_diag. Create a
	# placeholder so we have a mountpoint, then overlay it.
	[ -e "$target" ] || : >"$target"
	chown wifi:wifi "$target" 2>/dev/null
	chmod 0660 "$target" 2>/dev/null
	chcon "$expected" "$target" 2>>"$LOG"

	chown root:root "$src" 2>/dev/null
	chmod 0444 "$src" 2>/dev/null
	chcon "$expected" "$src" 2>>"$LOG"

	if grep -q " $target " /proc/mounts 2>/dev/null; then
		log "cnss_diag: already mounted"
	elif mount -o bind "$src" "$target" 2>>"$LOG"; then
		log "cnss_diag: bind-mounted $src"
	else
		log "cnss_diag: bind mount failed, writing file directly"
		cp -f "$src" "$target" 2>>"$LOG"
		chown wifi:wifi "$target" 2>/dev/null
		chmod 0660 "$target" 2>/dev/null
		chcon "$expected" "$target" 2>>"$LOG"
	fi
	log "cnss_diag: $(tr '\n' ' ' <"$target" 2>/dev/null)"

	mkdir -p "$logdir" 2>/dev/null
	find "$logdir" -maxdepth 1 -type f -delete 2>/dev/null
	rm -rf "$logdir/tcpdump.pcap0" 2>>"$LOG"
	mkdir -p "$logdir/tcpdump.pcap0" 2>>"$LOG"
	chown root:shell "$logdir/tcpdump.pcap0" 2>/dev/null
	chmod 0777 "$logdir/tcpdump.pcap0" 2>/dev/null
	log "wlan_logs: [$(ls -A "$logdir" 2>/dev/null | tr '\n' ' ')]"
}
