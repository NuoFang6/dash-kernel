# dash_art_tune

KernelSU/Magisk module for dash (REDMI Turbo 5 Max, MT6991, 16GB).

## What it changes

- TCP: `bbr3` + `fq_codel`; re-applied after boot.
- ADIOS: switch `sdc` (primary UFS) when the scheduler offers `adios`;
  otherwise log and leave the current scheduler.
- CPU/ISA and dex2oat (values chosen from AOSP `AndroidRuntime.cpp` and
  `art/runtime/arch/arm64/instruction_set_features_arm64.cc`):
  - `dalvik.vm.isa.arm64.features=runtime` (hwcap auto-detect:
    crc/lse/fp16/dotprod/sve)
  - `dalvik.vm.isa.arm64.variant=cortex-a55` (platform value; both a55 and
    a76 are recognized and produce identical ART feature bits, while
    a720/a725/x925 are not in ART's list; `runtime` is only valid for
    `.features`, not `.variant`)
  - `dalvik.vm.dex2oat-threads=8`, `dex2oat-cpu-set=0-7`
  - boot: 8 threads on cpu0-7; background: 4 threads on cpu0-3
- Heap/GC properties are intentionally untouched.
- zram: vendor init writes `lz4` to `zram0/comp_algorithm`; when Scene is
  not managing zram (`/data/swap_config.conf` absent or `zram=false`),
  restore the previous `lz4kd` selection after boot (reset the device,
  preserve `backing_dev`/writeback limit and disksize, re-create swap).
- Vendor WLAN diagnostics/logging off:
  - persistent props `persist.vendor.performance.disable.wlan_logs=true`,
    `persist.vendor.cnss_diag.enable=false`,
    `persist.vendor.tcpdump.enable=false`
  - `/data/vendor/wifi/cnss_diag.conf` with `LOG_PATH_FLAG=0`, exposed
    through a bind mount of the module copy (created if the file is absent)
  - `/data/vendor/wlan_logs`: regular files removed and `tcpdump.pcap0`
    replaced by a directory; `vendor_tcpdump` is stopped explicitly because
    the vendor binary does not read the persistent switch

## Install

Flash `dash_art_tune-v1.4.zip` as a KernelSU/Magisk module, then reboot.

Manual apply without reboot: `su -c '/data/adb/modules/dash_art_tune/action.sh'`

Logs: `/data/local/tmp/dash_art_tune.log`

## Revert

Disable/remove the module and reboot. The WLAN persist props are deleted by
`uninstall.sh`, the bind mount disappears with the reboot, and the empty
`tcpdump.pcap0` directory is removed. TCP/scheduler settings and the
`dalvik.vm.*` props are non-persistent and expire on reboot by themselves.
