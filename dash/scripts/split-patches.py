#!/usr/bin/env python3
"""Split and validate the dash patch series by feature.

Long-term kernel changes are stored as one patch per feature under
``dash/patches/<feature-dir>/``; ``dash/patches/series`` lists the feature
dirs in application order.  The split is file-level: every file is owned by
exactly one patch, so patches never overlap and any consistent series order
applies cleanly.

The mapping below is the single source of truth for that ownership.  It is
consumed by two commands:

  write   split a full-tree squash diff (one ``git diff`` over all changes)
          into the feature patches
  check   validate ``patches/`` against the mapping; with ``--squash``, also
          verify every file's diff block matches the squash byte-for-byte

Usage:
  split-patches.py write  --squash FILE --patches-dir DIR
  split-patches.py check  [--squash FILE] --patches-dir DIR

``scripts/gen-patches.sh`` drives both from the live ``src/aosp/common`` tree.
"""

import argparse
import re
import sys
from collections import OrderedDict
from pathlib import Path

# Series order: feature dir -> ordered patch names -> owned files.
# Keep file lists as sets conceptually; order inside a written patch follows
# the squash diff, not this table.
SERIES = [
    ("010-bakasu-susfs", "BakaSU 内建 + SUSFS inline hook（VFS/security/core 交错文件不可再拆）", [
        ("0001-bakasu-integration.patch", [
            "drivers/Kconfig",
            "drivers/Makefile",
        ]),
        ("0002-susfs-bakasu-core-hooks.patch", [
            "block/ioprio.c",
            "drivers/input/input.c",
            "fs/Makefile",
            "fs/namei.c",
            "fs/namespace.c",
            "fs/notify/fdinfo.c",
            "fs/open.c",
            "fs/proc/base.c",
            "fs/proc/bootconfig.c",
            "fs/proc/fd.c",
            "fs/proc/task_mmu.c",
            "fs/proc_namespace.c",
            "fs/read_write.c",
            "fs/readdir.c",
            "fs/exec.c",
            "fs/stat.c",
            "fs/statfs.c",
            "fs/super.c",
            "kernel/kallsyms.c",
            "kernel/reboot.c",
            "kernel/sys.c",
            "mm/memory.c",
            "security/selinux/avc.c",
        ]),
    ]),
    ("020-vendor-ko-compat", "厂商 .ko 加载兼容（签名/vermagic/CRC/namespace/GKI 保护导出）", [
        ("0001-vendor-ko-compat.patch", [
            "kernel/module/Kconfig",
            "kernel/module/main.c",
            "kernel/module/signing.c",
            "kernel/module/version.c",
        ]),
    ]),
    ("030-vendor-hooks-os4", "dash OS4 android_vh_* vendor hooks（含 f2fs VIP hook 声明与文件映射空白行）", [
        ("0001-dash-os4-vendor-hooks.patch", [
            "drivers/android/Makefile",
            "drivers/android/dash_os4_decl_exports.c",
            "include/trace/hooks/dash_os4_stub.h",
            "include/trace/hooks/fs.h",
            "kernel/locking/percpu-rwsem.c",
            "kernel/rcu/tree_plugin.h",
            "kernel/sched/vendor_hooks.c",
            "mm/filemap.c",
            "mm/vmscan.c",
        ]),
    ]),
    ("040-memfd-ashmem-shim", "MEMFD_ASHMEM shim（AOSP 6.6 已自带实现，仅启用配置）", [
        ("0001-memfd-ashmem-shim.patch", [
            "mm/Kconfig",
            "mm/Makefile",
            "mm/memfd-ashmem-shim.c",
            "mm/memfd-ashmem-shim.h",
            "mm/memfd-ashmem-shim-internal.h",
            "mm/shmem.c",
        ]),
    ]),
    ("050-lz4kd-zram", "lz4kd crypto 模块、LZ4 trace 事件与 zram lz4kd 后端", [
        ("0001-lz4kd-crypto-module.patch", [
            "crypto/Kconfig",
            "crypto/Makefile",
            "crypto/lz4kd/Kconfig",
            "crypto/lz4kd/Makefile",
            "crypto/lz4kd/include/linux/lz4kd.h",
            "crypto/lz4kd/lz4kd.h",
            "crypto/lz4kd/lz4kd_private.h",
            "crypto/lz4kd/lz4kd_encode_private.h",
            "crypto/lz4kd/lz4kd_crypto.c",
            "crypto/lz4kd/lz4kd_decode.c",
            "crypto/lz4kd/lz4kd_decode_delta.c",
            "crypto/lz4kd/lz4kd_encode.c",
            "crypto/lz4kd/lz4kd_encode_delta.c",
            "include/linux/lz4kd.h",
        ]),
        ("0002-lz4-trace-events.patch", [
            "include/trace/events/lz4.h",
            "fs/erofs/decompressor.c",
        ]),
        ("0003-zram-lz4kd-backend.patch", [
            "drivers/block/zram/Kconfig",
            "drivers/block/zram/zcomp.c",
        ]),
    ]),
    ("060-f2fs-xiaomi", "Xiaomi F2FS 增强（iostat / VIP / hybrid / lock priority / fault_report）", [
        ("0001-f2fs-xiaomi-features.patch", [
            "block/Kconfig",
            "fs/f2fs/Kconfig",
            "fs/f2fs/Makefile",
            "fs/f2fs/f2fs.h",
            "fs/f2fs/file.c",
            "fs/f2fs/inode.c",
            "fs/f2fs/iostat.c",
            "fs/f2fs/super.c",
            "fs/f2fs/sysfs.c",
            "fs/f2fs/xiaomi.c",
            "fs/f2fs/xiaomi.h",
        ]),
    ]),
    ("070-erofs-xiaomi", "Xiaomi EROFS iostat sysfs", [
        ("0001-erofs-xiaomi-iostat.patch", [
            "fs/erofs/Kconfig",
            "fs/erofs/Makefile",
            "fs/erofs/data.c",
            "fs/erofs/internal.h",
            "fs/erofs/iostat.c",
            "fs/erofs/iostat.h",
            "fs/erofs/sysfs.c",
        ]),
    ]),
    ("080-dash-misc", "dash 维护性独立修复（PID 上限钳制；OpenSSL 4 extract-cert 兼容；nVHE AutoFDO 关闭）", [
        ("0001-pid-max-limit-clamp.patch", [
            "certs/extract-cert.c",
            "include/linux/threads.h",
            "kernel/pid.c",
        ]),
        ("0002-autofdo-nvhe-opt-out.patch", [
            "arch/arm64/kvm/hyp/nvhe/Makefile.nvhe",
        ]),
    ]),
    ("090-droidspaces", "DroidSpaces 容器支持：SYSVIPC 字段移入 ANDROID_KABI 填充槽（task_struct 偏移不变）", [
        ("0001-sysvipc-kabi-padding.patch", [
            "include/linux/sched.h",
        ]),
    ]),
    ("100-sched-eevdf", "调度落地（2026-11-21 FEATURES_SURVEY）：CPU 扫描顺序/CACHE_HOT_BUDDY/PREEMPT_SHORT/misfit×2/RT_PUSH_IPI/uclamp DVFS 通知/timer slack RT 继承", [
        ("0001-sched-fair-features.patch", [
            "kernel/sched/fair.c",
            "kernel/sched/features.h",
        ]),
        ("0002-sched-core-timer-slack.patch", [
            "init/init_task.c",
            "kernel/fork.c",
            "kernel/sched/core.c",
        ]),
    ]),
    ("110-net-bbrv3", "BBRv3（WK android15-6.6 KABI 版，含 tcp_output.c 内 TCP retransmit_skb_hint UAF 修复 fe99bbeee5c5）", [
        ("0001-tcp-bbrv3-kabi.patch", [
            "include/linux/tcp.h",
            "include/net/tcp.h",
            "include/uapi/linux/inet_diag.h",
            "include/uapi/linux/rtnetlink.h",
            "net/ipv4/Kconfig",
            "net/ipv4/Makefile",
            "net/ipv4/tcp.c",
            "net/ipv4/tcp_bbr3.c",
            "net/ipv4/tcp_cong.c",
            "net/ipv4/tcp_input.c",
            "net/ipv4/tcp_minisocks.c",
            "net/ipv4/tcp_output.c",
            "net/ipv4/tcp_rate.c",
        ]),
    ]),
    ("115-hide-appsockets", "hide_adb_jdwp：app-UID 隐藏 adbd socket（readdir/fdinfo 半在 010-bakasu-susfs 的 fs 文件里；此处为 af_unix bind/connect/proc-net-unix）", [
        ("0001-unix-hide-adbd-sockets.patch", [
            "net/unix/af_unix.c",
        ]),
    ]),
    ("120-arm64-perf", "arm64/库性能：copy_template prfm、ARM optimized-routines memcmp、clear_page 16B 对齐、int_sqrt、this_cpu_write/and 修复、idmap KCFI typeid、DASH_ARM64_TUNE、实验性 perf 开关", [
        ("0001-arm64-lib-perf.patch", [
            "arch/arm64/lib/clear_page.S",
            "arch/arm64/lib/copy_template.S",
            "arch/arm64/lib/memcmp.S",
            "lib/math/int_sqrt.c",
        ]),
        ("0002-arm64-percpu-fixes.patch", [
            "arch/arm64/include/asm/mmu_context.h",
            "arch/arm64/mm/Makefile",
            "arch/arm64/mm/idmap_cfi.c",
            "arch/arm64/include/asm/percpu.h",
        ]),
        ("0003-arm64-dash-tune.patch", [
            "arch/arm64/Kconfig",
            "arch/arm64/Makefile",
        ]),
        ("0004-dash-perf-experiment.patch", [
            "include/linux/list.h",
            "mm/kasan/hw_tags.c",
        ]),
    ]),
    ("130-f2fs-perf", "F2FS 三件套：GC urgent sleep 50ms / congestion wait 6ms / min_fsync_blocks 20（f2fs.h 的 6ms 落在 060-f2fs-xiaomi；file.c move-range 修复同样在 060）", [
        ("0001-f2fs-gc-segment-tuning.patch", [
            "fs/f2fs/gc.h",
            "fs/f2fs/segment.h",
        ]),
    ]),
    ("131-unicode-bypass", "casefold 零宽字符空分解边界修复（社区 unicode bypass fix，上游未采纳）", [
        ("0001-utf8-empty-decomposition.patch", [
            "fs/unicode/utf8-norm.c",
        ]),
    ]),
    ("140-power-mm", "电源/内存：alarmtimer 唤醒窗口、s2idle 单次唤醒、swap readahead ceiling、MGLRU suspend 可中断（mm/vmscan.c 半在 030）、cpufreq policy init、OPP supply-parsing 泄漏与频率溢出", [
        ("0001-power-mm-fixes.patch", [
            "drivers/base/power/wakeup.c",
            "kernel/time/alarmtimer.c",
        ]),
        ("0002-mm-swap-readahead.patch", [
            "mm/swap_state.c",
        ]),
        ("0003-mglru-suspend-memcontrol.patch", [
            "mm/memcontrol.c",
        ]),
        ("0004-cpufreq-opp-init-fixes.patch", [
            "drivers/cpufreq/cpufreq.c",
            "drivers/opp/of.c",
        ]),
    ]),
    ("150-drivers-ntsync", "NTSync 主线驱动（Wine /dev/ntsync）6.6 backport", [
        ("0001-ntsync-driver.patch", [
            "drivers/misc/Kconfig",
            "drivers/misc/Makefile",
            "drivers/misc/ntsync.c",
            "include/uapi/linux/ntsync.h",
        ]),
    ]),
    ("160-block-adios", "ADIOS blk-mq I/O 调度器（EVONIX 6.6 适配；非默认，MQ_IOSCHED_DEFAULT_ADIOS 保持 n）", [
        ("0001-adios-scheduler.patch", [
            "block/adios.c",
            "block/Kconfig.iosched",
            "block/Makefile",
        ]),
    ]),
    ("170-security-bbg", "Baseband Guard LSM（vc-teahouse，EVONIX MTK 同款集成；boot/recovery 不保护）", [
        ("0001-baseband-guard-lsm.patch", [
            "security/Kconfig",
            "security/Makefile",
            "security/baseband-guard/Kconfig",
            "security/baseband-guard/Makefile",
            "security/baseband-guard/baseband_guard.c",
            "security/baseband-guard/baseband_guard.h",
            "security/baseband-guard/blkdev_helper.c",
            "security/baseband-guard/blkdev_helper.h",
            "security/baseband-guard/kernel_compat.h",
            "security/baseband-guard/tracing/tracing.c",
            "security/baseband-guard/tracing/tracing.h",
        ]),
    ]),
    ("180-stable-backports", "EVONIX 已收录的 stable 6.6.145–158 回移（UDP tunnel 分段 UAF、IPv6 解析加固、DAMON、writeback/ext4）", [
        ("0001-net-udp-tunnel-seg-uaf.patch", [
            "net/ipv4/udp_offload.c",
        ]),
        ("0002-net-ipv6-parse-hardening.patch", [
            "net/core/skbuff.c",
            "net/ipv6/exthdrs_core.c",
            "net/ipv6/seg6.c",
        ]),
        ("0003-damon-fixes.patch", [
            "mm/damon/core.c",
            "mm/damon/core-test.h",
            "mm/damon/sysfs-schemes.c",
            "mm/damon/vaddr.c",
        ]),
        ("0004-writeback-fixes.patch", [
            "fs/fs-writeback.c",
            "include/linux/backing-dev-defs.h",
            "include/linux/writeback.h",
            "mm/backing-dev.c",
        ]),
        ("0005-ext4-writeback-xarray.patch", [
            "fs/ext4/inode.c",
        ]),
    ]),
]

# Files that show up in a src-tree diff but are script-side wiring, not patch
# material.  write/check fail on any tree diff file that is neither mapped nor
# listed here.
IGNORED_FILES = {
    # NoMount wiring (fs/Makefile + fs/Kconfig hook, fs/nomount symlink) is
    # applied by scripts/apply-patches.sh; the symlink itself is untracked.
    "fs/Kconfig",
}


def series_dirs():
    """Feature dir names in series order."""
    return [name for name, _, _ in SERIES]


def expected_mapping():
    """patch relpath (dir/name) -> set of owned files, plus sanity checks."""
    mapping = OrderedDict()
    seen_files = {}
    for dir_name, _desc, patches in SERIES:
        for patch_name, files in patches:
            key = f"{dir_name}/{patch_name}"
            if key in mapping:
                fail(f"duplicate patch in mapping: {key}")
            for f in files:
                if f in seen_files:
                    fail(f"file owned twice: {f} ({seen_files[f]} and {key})")
                seen_files[f] = key
            mapping[key] = set(files)
    return mapping


def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def parse_squash(text):
    """Split a git diff into OrderedDict(file -> block) preserving order."""
    blocks = OrderedDict()
    matches = list(re.finditer(r"(?m)^diff --git a/(.*) b/(.*)$", text))
    for i, m in enumerate(matches):
        a, b = m.group(1), m.group(2)
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        block = text[m.start():end]
        path = b if a == b else None
        if path is None:
            fail(f"rename or divergent paths not supported: a/{a} b/{b}")
        if path in blocks:
            fail(f"file appears twice in squash: {path}")
        blocks[path] = block
    preamble = text[:matches[0].start()] if matches else text
    if preamble.strip():
        fail(f"unexpected preamble before first diff header: {preamble[:80]!r}")
    return blocks


def parse_patch_file(text):
    """Files touched by one split patch (preamble tolerated and ignored)."""
    files = []
    for m in re.finditer(r"(?m)^diff --git a/(.*) b/(.*)$", text):
        files.append(m.group(2) if m.group(1) == m.group(2) else None)
    return files


def cmd_write(args):
    squash = Path(args.squash).read_text(encoding="utf-8")
    blocks = parse_squash(squash)
    mapping = expected_mapping()

    mapped = set()
    for files in mapping.values():
        mapped |= files
    unmapped = sorted(set(blocks) - mapped - IGNORED_FILES)
    missing = sorted(mapped - set(blocks))
    if unmapped:
        fail("files in squash with no mapping entry (add them to SERIES or "
             f"IGNORED_FILES in scripts/split-patches.py): {unmapped}")
    if missing:
        fail(f"mapping entries absent from squash: {missing}")

    patches_dir = Path(args.patches_dir)
    written = []
    for dir_name, desc, patches in SERIES:
        dir_path = patches_dir / dir_name
        dir_path.mkdir(parents=True, exist_ok=True)
        for patch_name, files in patches:
            body = "".join(blocks[f] for f in sorted(files))
            if not body:
                fail(f"no diff blocks for {dir_name}/{patch_name}")
            target = dir_path / patch_name
            target.write_text(body, encoding="utf-8")
            written.append((f"{dir_name}/{patch_name}", len(files)))

    # Drop patch files that the mapping no longer mentions (stale splits).
    valid = {patches_dir / d / p for d, _, ps in SERIES for p, _ in ps}
    for p in patches_dir.glob("*.patch"):
        if p not in valid:
            print(f"removing stale patch: {p.name}")
            p.unlink()

    for rel, n in written:
        print(f"wrote {rel} ({n} files)")
    print(f"ok: {len(written)} patches, {len(mapped)} files, "
          f"{len(IGNORED_FILES)} ignored")


def cmd_check(args):
    patches_dir = Path(args.patches_dir)
    mapping = expected_mapping()

    # series must list the mapping dirs in order and nothing else
    series = patches_dir / "series"
    entries = []
    for line in series.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        entries.append(line)
    if entries != series_dirs():
        fail(f"series entries {entries} != mapping dirs {series_dirs()}")

    # every listed dir/patch exists and touches exactly its mapped files
    actual = {}
    for dir_name, _desc, patches in SERIES:
        for patch_name, files in patches:
            rel = f"{dir_name}/{patch_name}"
            path = patches_dir / dir_name / patch_name
            if not path.is_file():
                fail(f"missing patch file: {rel}")
            got = parse_patch_file(path.read_text(encoding="utf-8"))
            if any(f is None for f in got):
                fail(f"rename/divergent diff inside {rel}")
            if len(set(got)) != len(got):
                fail(f"file repeated inside {rel}")
            if set(got) != set(files):
                fail(f"{rel} touches {sorted(set(got))}, mapping says {sorted(set(files))}")
            actual[rel] = set(got)
    stale = [p for p in patches_dir.glob("*/*.patch")
             if p.parent.name != "susfs-overrides"
             and f"{p.parent.name}/{p.name}" not in mapping]
    if stale:
        fail(f"patch files not covered by mapping: {[str(p) for p in stale]}")

    if actual.keys() != mapping.keys():
        fail(f"patch set mismatch: {sorted(actual)} vs {sorted(mapping)}")

    if args.squash:
        squash = Path(args.squash).read_text(encoding="utf-8")
        blocks = parse_squash(squash)
        mapped = set()
        for files in mapping.values():
            mapped |= files
        unmapped = sorted(set(blocks) - mapped - IGNORED_FILES)
        if unmapped:
            fail(f"files in squash with no mapping entry: {unmapped}")
        for rel, files in actual.items():
            path = patches_dir / rel
            text = path.read_text(encoding="utf-8")
            body = "".join(blocks[f] for f in sorted(files))
            if text != body:
                fail(f"{rel} differs from squash reassembly "
                     "(regenerate: make gen-patches)")
        print(f"ok: {len(actual)} patches match mapping and squash "
              f"({len(blocks)} files)")

    print(f"ok: patches/ matches mapping ({len(actual)} patches, "
          f"{sum(len(v) for v in actual.values())} files)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    for name in ("write", "check"):
        p = sub.add_parser(name)
        p.add_argument("--squash", help="full-tree squash diff file "
                       "(required for write; optional for check)")
        p.add_argument("--patches-dir", default=str(
            Path(__file__).resolve().parent.parent / "patches"))
        p.set_defaults(func=cmd_write if name == "write" else cmd_check)

    args = ap.parse_args()
    if args.cmd == "write" and not args.squash:
        ap.error("write requires --squash")
    args.func(args)


if __name__ == "__main__":
    main()
