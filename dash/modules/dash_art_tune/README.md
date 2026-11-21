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

## Install

Flash `dash_art_tune-v1.2.zip` as a KernelSU/Magisk module, then reboot.

Manual apply without reboot: `su -c '/data/adb/modules/dash_art_tune/action.sh'`

Logs: `/data/local/tmp/dash_art_tune.log`

## Revert

Disable/remove the module and reboot. All property changes are non-persistent;
TCP and scheduler settings are also reset by the next boot.
