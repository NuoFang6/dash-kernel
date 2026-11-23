#!/usr/bin/env python3
"""Compare a built vmlinux against the factory ABI baseline.

The factory numbers in configs/abi-baseline.json were parsed from the BTF blob
inside the stock boot image, so they describe what the prebuilt vendor .ko
modules on this device were compiled against.

Hard entries must match exactly: a change in task_struct size or in the
android_vendor_data1 offset silently makes MTK vendor modules read and write
the wrong task_struct bytes (observed on 2026-11-24 as a garbled screen and a
reboot with no boot animation, caused by CONFIG_RSEQ adding rseq/mm_cid).

Soft entries are reported as deviations only; they are documented, reviewed
layout changes.

Usage: check-abi.py <vmlinux> [baseline.json]
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_BASELINE = Path(__file__).resolve().parent.parent / "configs" / "abi-baseline.json"


def pahole_struct(vmlinux: Path, name: str) -> tuple[int, dict[str, int]]:
    out = subprocess.run(
        ["pahole", "-C", name, str(vmlinux)],
        capture_output=True, text=True, check=False,
    )
    if out.returncode != 0 or not out.stdout:
        raise RuntimeError(f"pahole could not read {name} from {vmlinux}: {out.stderr.strip()}")
    size = None
    members: dict[str, int] = {}
    for line in out.stdout.splitlines():
        m = re.search(r"/\* size: (\d+)", line)
        if m and size is None:
            size = int(m.group(1))
            continue
        m = re.match(r"\s+\S.*?\b(\w+)(?:\[\d+\])?;\s*/\*\s*(\d+)\s+", line)
        if m:
            members[m.group(1)] = int(m.group(2))
    if size is None:
        raise RuntimeError(f"no size found for {name} in {vmlinux}")
    return size, members


def read_actual(vmlinux: Path, key: str) -> int:
    if "." in key:
        struct, member = key.split(".", 1)
        _, members = pahole_struct(vmlinux, struct)
        if member not in members:
            raise RuntimeError(f"{struct} has no member {member}")
        return members[member]
    size, _ = pahole_struct(vmlinux, key)
    return size


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    vmlinux = Path(sys.argv[1])
    baseline = json.loads(Path(sys.argv[2] if len(sys.argv) > 2 else DEFAULT_BASELINE).read_text())
    if not vmlinux.is_file():
        print(f"missing {vmlinux}", file=sys.stderr)
        return 2

    failed = 0
    print(f"factory ABI check: {vmlinux}")
    for label, entries, fatal in (
        ("hard", baseline.get("hard", {}), True),
        ("soft", baseline.get("soft", {}), False),
    ):
        for key, spec in entries.items():
            expected = spec.get("size", spec.get("offset"))
            try:
                actual = read_actual(vmlinux, key)
            except Exception as exc:  # noqa: BLE001 - report and continue
                print(f"  {label:4s} {key:36s} ERROR {exc}")
                failed += 1
                continue
            if actual == expected:
                print(f"  {label:4s} {key:36s} {actual} ok")
            elif fatal:
                print(f"  {label:4s} {key:36s} {actual} != {expected}  <-- BROKEN")
                failed += 1
            else:
                print(f"  {label:4s} {key:36s} {actual} != {expected}  (reviewed deviation)")
    if failed:
        print("hard ABI mismatch: prebuilt vendor modules will misbehave", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
