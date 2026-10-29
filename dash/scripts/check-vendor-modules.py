#!/usr/bin/env python3
"""Check all stock dash modules against this kernel's exported symbols.

The stock .ko set is checked as one link unit: a symbol defined by any stock
module can satisfy an import from another stock module.  Undefined symbols are
then resolved against vmlinux's Module.symvers, which is the exact set of
symbols the module loader will accept.  Weak undefined references are reported
but are not fatal.

This is an offline proxy for loading the modules.  It cannot prove CFI/KCFI,
signature, CRC or runtime probe success.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def read_manifest(path: Path):
    rows = []
    with path.open() as f:
        header = f.readline().rstrip("\n").split("\t")
        if header[:2] != ["name", "dir"]:
            raise SystemExit(f"{path}: unexpected manifest header")
        for line in f:
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 8:
                continue
            rows.append(dict(zip(header, fields)))
    return rows


def read_symvers(path: Path):
    exports = {}
    with path.open(errors="replace") as f:
        for line in f:
            fields = line.rstrip("\n").split("\t")
            if len(fields) >= 2 and fields[1]:
                exports[fields[1]] = fields[0]
    return exports


def nm_symbols(nm: str, path: Path):
    proc = subprocess.run(
        [nm, "--format=posix", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    defined = set()
    undefined = {}
    for line in proc.stdout.splitlines():
        fields = line.split()
        if len(fields) < 2:
            continue
        name, kind = fields[0], fields[1]
        upper = kind.upper()
        if upper == "U":
            undefined[name] = False
        elif upper == "W":
            defined.add(name)
        elif upper not in ("N", "V"):
            defined.add(name)
        elif kind == "w":  # lowercase w is an undefined weak reference
            undefined.setdefault(name, True)
        if kind == "w":
            undefined[name] = True
        elif kind == "U":
            undefined.setdefault(name, False)
    return defined, undefined


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--symvers", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--modules", required=True, type=Path)
    parser.add_argument("--nm", default="llvm-nm")
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--allow", action="append", default=[],
                        help="symbol to report but not fail on (repeatable)")
    args = parser.parse_args()

    rows = read_manifest(args.manifest)
    exports = read_symvers(args.symvers)
    module_defined = set()
    module_undef = {}

    for row in rows:
        path = args.modules / row["dir"] / row["file"]
        if not path.is_file():
            raise SystemExit(f"missing module: {path}")
        defined, undefined = nm_symbols(args.nm, path)
        module_defined |= defined
        for name, weak in undefined.items():
            prev = module_undef.get(name)
            module_undef[name] = weak if prev is None else (prev and weak)

    allowed = set(args.allow)
    unresolved = {}
    for name, weak in module_undef.items():
        if name in exports or name in module_defined:
            continue
        unresolved[name] = {
            "weak": weak,
            "allowed": name in allowed,
        }

    hard = sorted(n for n, v in unresolved.items() if not v["weak"] and not v["allowed"])
    weak = sorted(n for n, v in unresolved.items() if v["weak"] and not v["allowed"])
    result = {
        "modules": len(rows),
        "kernel_exports": len(exports),
        "module_defined_symbols": len(module_defined),
        "unresolved_hard": hard,
        "unresolved_weak": weak,
        "allowed": sorted(allowed & set(unresolved)),
    }
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(result, indent=2) + "\n")

    print(f"modules={len(rows)} kernel_exports={len(exports)} "
          f"hard_missing={len(hard)} weak_missing={len(weak)}")
    for name in hard:
        print(f"  HARD {name}")
    for name in weak:
        print(f"  WEAK {name}")
    return 1 if hard else 0


if __name__ == "__main__":
    sys.exit(main())
