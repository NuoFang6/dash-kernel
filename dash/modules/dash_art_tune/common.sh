#!/system/bin/sh
# Shared helpers for dash_art_tune.

MODDIR=${MODDIR:-${0%/*}}
LOG=/data/local/tmp/dash_art_tune.log

log() {
	echo "$(date '+%F %T') $*" >>"$LOG" 2>/dev/null
}

apply_bbr() {
	cc=/proc/sys/net/ipv4/tcp_congestion_control
	qdisc=/proc/sys/net/core/default_qdisc
	cur_cc=$(cat "$cc" 2>/dev/null)
	cur_q=$(cat "$qdisc" 2>/dev/null)
	changed=0

	if grep -qw bbr3 /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
		if [ "$cur_cc" != bbr3 ]; then
			echo bbr3 >"$cc" 2>>"$LOG"
			changed=1
		fi
	else
		log "bbr3 unavailable; leaving congestion control"
	fi
	if [ "$cur_q" != fq ]; then
		echo fq >"$qdisc" 2>>"$LOG"
		changed=1
	fi
	if [ "$changed" -eq 0 ]; then
		log "bbr3/fq already kernel defaults; leaving unchanged"
	fi
	log "bbrv3: cc=$(cat "$cc" 2>/dev/null) qdisc=$(cat "$qdisc" 2>/dev/null)"
}

apply_adios() {
	# sdc is the primary UFS LUN on dash. Only switch if adios is offered.
	for dev in sdc; do
		sched=/sys/block/$dev/queue/scheduler
		[ -f "$sched" ] || continue
		# Kernel now defaults to ADIOS; do not rewrite when it is already
		# selected (keeps the module a no-op on the tuned kernel).
		if grep -q "\[adios\]" "$sched" 2>/dev/null; then
			log "$dev scheduler already adios; leaving unchanged"
			continue
		fi
		grep -qw adios "$sched" 2>/dev/null || continue
		echo adios >"$sched" 2>>"$LOG"
		log "$dev scheduler=$(cat "$sched" 2>/dev/null)"
	done
}

apply_tcp_sysctls() {
	changed=0
	set_one() {
		path=/proc/sys/$1
		want=$2
		cur=$(cat "$path" 2>/dev/null)
		[ "$cur" = "$want" ] && return 0
		echo "$want" >"$path" 2>>"$LOG" && changed=1
	}
	set_one net/ipv4/tcp_mtu_probing 1
	set_one net/ipv4/tcp_ecn 1
	set_one net/ipv4/tcp_slow_start_after_idle 0
	set_one net/ipv4/tcp_notsent_lowat 16384
	if [ "$changed" -eq 0 ]; then
		log "tcp sysctls already applied; leaving unchanged"
	else
		log "tcp sysctls: mtu_probing=$(cat /proc/sys/net/ipv4/tcp_mtu_probing) ecn=$(cat /proc/sys/net/ipv4/tcp_ecn) ss_after_idle=$(cat /proc/sys/net/ipv4/tcp_slow_start_after_idle) notsent_lowat=$(cat /proc/sys/net/ipv4/tcp_notsent_lowat)"
	fi
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

# Vendor init hardcodes `write /sys/block/zram0/comp_algorithm lz4` for dash
# (init.mt6991.rc:191).  lz4kd is not listed by zram's available-algorithm
# probe but the vendor zram accepts it once the device is reset, so restore
# the vendor's previous lz4kd selection at boot.  Skip when Scene manages
# zram itself (its config says zram=true), so its algorithm choice wins.
apply_zram_lz4kd() {
	dev=/sys/block/zram0
	conf=/data/swap_config.conf

	[ -e "$dev/comp_algorithm" ] || return 0
	grep -q "zram0" /proc/swaps 2>/dev/null || return 0

	if [ -f "$conf" ] && grep -q '^zram=true' "$conf" 2>/dev/null; then
		log "zram: Scene-managed, skip lz4kd"
		return 0
	fi

	case "$(cat "$dev/comp_algorithm" 2>/dev/null)" in
	*"[lz4kd]"*)
		return 0
		;;
	esac

	bd="$(cat "$dev/backing_dev" 2>/dev/null)"
	wl="$(cat "$dev/writeback_limit_enable" 2>/dev/null)"
	disk="$(cat "$dev/disksize" 2>/dev/null)"
	prio="$(awk '/zram0/{print $5}' /proc/swaps 2>/dev/null)"

	swapoff /dev/block/zram0 2>>"$LOG"
	echo 1 >"$dev/reset" 2>>"$LOG"
	echo 4 >"$dev/max_comp_streams" 2>>"$LOG"
	if ! echo lz4kd >"$dev/comp_algorithm" 2>>"$LOG"; then
		log "zram: lz4kd rejected, falling back to lz4"
		echo lz4 >"$dev/comp_algorithm" 2>>"$LOG"
	fi
	[ -n "$bd" ] && [ "$bd" != "none" ] && \
		echo "$bd" >"$dev/backing_dev" 2>>"$LOG"
	[ "$wl" = "1" ] && echo 1 >"$dev/writeback_limit_enable" 2>>"$LOG"
	echo "${disk:-17179869184}" >"$dev/disksize" 2>>"$LOG"
	mkswap /dev/block/zram0 >/dev/null 2>>"$LOG"
	# A negative priority cannot be passed through this swapon; the default
	# (-2) matches the vendor init state.
	swapon /dev/block/zram0 2>>"$LOG"
	log "zram: comp=$(cat "$dev/comp_algorithm" 2>/dev/null) swap_prio=$(awk '/zram0/{print $5}' /proc/swaps 2>/dev/null)"
}

