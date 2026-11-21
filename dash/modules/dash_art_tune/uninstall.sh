#!/system/bin/sh
# All tuned properties are non-persistent and expire on reboot. Only the log
# needs cleanup.
rm -f /data/local/tmp/dash_art_tune.log
exit 0
