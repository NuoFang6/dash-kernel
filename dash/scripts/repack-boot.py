#!/usr/bin/env python3
"""Repack an Android boot image while preserving its stock AVB metadata.

This is intentionally not a generic boot-image builder.  It replaces only the
kernel inside an existing stock boot image, keeps the original boot header and
KernelSU-relevant properties, and preserves the OEM-signed vbmeta block and
AVB footer.  The boot hash descriptor still describes the stock kernel, which
is accepted by the dash bootloader only in the device's current hidden-unlock
state; the signed vbmeta itself must not be modified.
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

PAGE_SIZE = 4096
AVB_FOOTER_MAGIC = b"AVBf"
AVB_FOOTER_SIZE = 64


def align_up(value: int, alignment: int) -> int:
    return (value + alignment - 1) & ~(alignment - 1)


def read_avb_footer(data: bytes):
    footer = data[-AVB_FOOTER_SIZE:]
    if footer[:4] != AVB_FOOTER_MAGIC:
        raise SystemExit("stock boot image has no AVB footer")
    version_major, version_minor = struct.unpack_from(">II", footer, 4)
    original_size, vbmeta_offset, vbmeta_size = struct.unpack_from(
        ">QQQ", footer, 12
    )
    return {
        "version": (version_major, version_minor),
        "original_size": original_size,
        "vbmeta_offset": vbmeta_offset,
        "vbmeta_size": vbmeta_size,
    }, bytearray(footer)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stock", required=True, type=Path)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    stock = args.stock.read_bytes()
    kernel = args.kernel.read_bytes()
    if stock[:8] != b"ANDROID!":
        raise SystemExit(f"{args.stock}: not an Android boot image")
    header_version = struct.unpack_from("<I", stock, 40)[0]
    if header_version != 4:
        raise SystemExit(f"{args.stock}: expected header v4, got {header_version}")
    header_size = struct.unpack_from("<I", stock, 20)[0]
    if header_size > PAGE_SIZE:
        raise SystemExit(f"unsupported boot header size {header_size}")
    if len(stock) <= AVB_FOOTER_SIZE:
        raise SystemExit("stock image is too small")

    footer, footer_bytes = read_avb_footer(stock)
    vb_off = footer["vbmeta_offset"]
    vb_size = footer["vbmeta_size"]
    if vb_off + vb_size + AVB_FOOTER_SIZE > len(stock):
        raise SystemExit("invalid stock AVB footer offsets")
    vbmeta = stock[vb_off:vb_off + vb_size]
    if len(vbmeta) != vb_size or vbmeta[:4] != b"AVB0":
        raise SystemExit("stock image does not contain a valid vbmeta block")

    new_end = PAGE_SIZE + len(kernel)
    if new_end <= footer["original_size"]:
        new_original_size = footer["original_size"]
        new_vb_off = vb_off
    else:
        # Preserve the signed vbmeta bytes, but relocate them after the larger
        # kernel and update the (unsigned) footer to the new offsets.
        new_vb_off = align_up(new_end, PAGE_SIZE)
        new_original_size = new_vb_off
    if new_vb_off + vb_size + AVB_FOOTER_SIZE > len(stock):
        raise SystemExit("new kernel plus AVB metadata exceeds the boot partition")

    out = bytearray(len(stock))
    out[:PAGE_SIZE] = stock[:PAGE_SIZE]
    struct.pack_into("<I", out, 8, len(kernel))
    struct.pack_into("<I", out, 12, 0)  # this device's boot has no ramdisk
    out[PAGE_SIZE:new_end] = kernel
    out[new_vb_off:new_vb_off + vb_size] = vbmeta

    struct.pack_into(">QQQ", footer_bytes, 12,
                     new_original_size, new_vb_off, vb_size)
    out[-AVB_FOOTER_SIZE:] = footer_bytes

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(out)
    print(f"stock: {args.stock} ({len(stock)} bytes)")
    print(f"kernel: {args.kernel} ({len(kernel)} bytes)")
    print(f"output: {args.output} ({len(out)} bytes)")
    print(f"vbmeta: {new_vb_off:#x}+{vb_size} (OEM bytes preserved)")
    print(f"avb footer: original_image_size={new_original_size:#x}")


if __name__ == "__main__":
    main()
