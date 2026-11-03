#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Install the standard mihomo_alpha KSU module. The module ships the mihomo
# binary; the user config stays outside the module at /data/adb/mihomo/config.yaml.
MODULE_DIR="$DASH_ROOT/modules/mihomo_alpha"
BIN="$MODULE_DIR/bin/mihomo"
CONFIG="${MIHOMO_CONFIG:-$DASH_ROOT/../handoff/mihomo-test/config-tun.yaml}"
ZIP="${MIHOMO_MODULE_ZIP:-$DASH_ROOT/../handoff/mihomo_alpha.zip}"

require_cmd adb
require_cmd zip
require_file "$MODULE_DIR/module.prop"
require_file "$BIN"
require_file "$CONFIG"
adb get-state >/dev/null 2>&1 || die "no adb device"

rm -f "$ZIP"
(
	cd "$MODULE_DIR"
	zip -q -9 -r "$ZIP" module.prop post-fs-data.sh service.sh action.sh \
		uninstall.sh bin/mihomo
)
adb push "$ZIP" /data/local/tmp/mihomo_alpha.zip >/dev/null
adb shell 'su -c "/data/adb/ksu/bin/ksud module install /data/local/tmp/mihomo_alpha.zip"'
adb shell 'su -c "mkdir -p /data/adb/mihomo"'
adb push "$CONFIG" /data/local/tmp/mihomo-config.yaml >/dev/null
adb shell 'su -c "cp /data/local/tmp/mihomo-config.yaml /data/adb/mihomo/config.yaml; \
	chown root:root /data/adb/mihomo/config.yaml; chmod 600 /data/adb/mihomo/config.yaml"'
echo "installed mihomo_alpha; config: /data/adb/mihomo/config.yaml"
echo "reboot to activate the module"
