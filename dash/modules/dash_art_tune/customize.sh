#!/system/bin/sh
# KernelSU/Magisk runs this after extraction; make the stage scripts executable
# even if the installer drops the zip permission bits.
if [ -n "$MODPATH" ] && [ -d "$MODPATH" ]; then
	chmod 755 "$MODPATH"/*.sh 2>/dev/null
fi
