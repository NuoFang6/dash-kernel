#!/system/bin/sh
# dash_art_tune: dex2oat CPU/thread tuning + early BBRv3.
# Runs before zygote, so dalvik.vm.* props are inherited by the runtime.

MODDIR=${0%/*}
. "$MODDIR/common.sh"

if command -v resetprop >/dev/null 2>&1; then
	RESETPROP=resetprop
elif [ -x /data/adb/ksu/bin/resetprop ]; then
	RESETPROP=/data/adb/ksu/bin/resetprop
else
	RESETPROP=
fi

setp() {
	key="$1"
	val="$2"
	old="$(getprop "$key")"
	if [ -n "$RESETPROP" ]; then
		"$RESETPROP" -n "$key" "$val" >>"$LOG" 2>&1
	else
		setprop "$key" "$val" >>"$LOG" 2>&1
	fi
	log "prop $key: ${old:-<unset>} -> $(getprop "$key")"
}

# Only CPU/thread scheduling for dex2oat. Heap/GC properties are left at the
# platform values.
#
# ART's variant table ends at cortex-a76. cortex-a55 and cortex-a76 have the
# same crc/lse/fp16/dotprod bits and neither needs the a53 errata fixes, so
# with features=runtime the two are equivalent; the actual ISA extensions
# (including SVE/SVE2 on this SoC) come from hwcap detection.
setp dalvik.vm.isa.arm64.features runtime
setp dalvik.vm.isa.arm64.variant cortex-a55
setp dalvik.vm.dex2oat-threads 8
setp dalvik.vm.dex2oat-cpu-set 0,1,2,3,4,5,6,7
setp dalvik.vm.boot-dex2oat-threads 8
setp dalvik.vm.background-dex2oat-threads 4
setp dalvik.vm.boot-dex2oat-cpu-set 0,1,2,3,4,5,6,7
setp dalvik.vm.default-dex2oat-cpu-set 0,1,2,3,4,5,6,7
setp dalvik.vm.background-dex2oat-cpu-set 0,1,2,3

apply_bbr

exit 0
