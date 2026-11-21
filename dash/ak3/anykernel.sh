### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Dash production kernel + ART/BBRv3/ADIOS tune
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot shell variables
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

kernel_version=$(cat /proc/version | awk -F '-' '{print $1}' | awk '{print $3}')
case $kernel_version in
    5.1*) ksu_supported=true ;;
    6.1*) ksu_supported=true ;;
    6.6*) ksu_supported=true ;;
    *) ksu_supported=false ;;
esac

ui_print " " "  -> ksu_supported: $ksu_supported"
$ksu_supported || abort "  -> Non-GKI device, abort."

# Only patch boot. init_boot carries the official ramdisk and must stay
# untouched; this kernel is a boot-only replacement.
dump_boot
write_boot
## end boot install

# Optional: install the companion KSU module if /data is mounted.
if [ -d /data/adb/modules ] && [ -d "$AKHOME/module" ]; then
    rm -rf /data/adb/modules/dash_art_tune
    cp -af "$AKHOME/module" /data/adb/modules/dash_art_tune
    chmod 755 /data/adb/modules/dash_art_tune/post-fs-data.sh \
              /data/adb/modules/dash_art_tune/service.sh \
              /data/adb/modules/dash_art_tune/uninstall.sh \
              /data/adb/modules/dash_art_tune/common.sh \
              /data/adb/modules/dash_art_tune/action.sh \
              /data/adb/modules/dash_art_tune/customize.sh
    ui_print "  -> dash_art_tune KSU module installed"
else
    ui_print "  -> /data not mounted; install the KSU module zip separately"
fi
