#!/system/bin/sh
# Undo the vendor WLAN privacy switches so stock logging can resume after the
# module is removed, then drop the overlay and log file.
RP=/data/adb/ksu/bin/resetprop
for k in persist.vendor.performance.disable.wlan_logs \
	 persist.vendor.cnss_diag.enable \
	 persist.vendor.tcpdump.enable; do
	[ -x "$RP" ] && "$RP" -p -d "$k" 2>/dev/null
	[ -x "$RP" ] && "$RP" -d "$k" 2>/dev/null
done
umount /data/vendor/wifi/cnss_diag.conf 2>/dev/null
rmdir /data/vendor/wlan_logs/tcpdump.pcap0 2>/dev/null
rm -f /data/local/tmp/dash_art_tune.log
exit 0
