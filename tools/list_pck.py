#!/usr/bin/env python3
"""Lists the files inside a Godot 4 .pck (pack format 2–4) without Godot.
Usage: python3 tools/list_pck.py build/client.pck
Prints one res:// path per line. Encrypted directories are not supported."""
import struct
import sys

PACK_DIR_ENCRYPTED = 1


def list_pck(path):
    with open(path, "rb") as f:
        if f.read(4) != b"GDPC":
            raise SystemExit(f"{path}: not a Godot pack")
        version, _major, _minor, _patch = struct.unpack("<IIII", f.read(16))
        if version < 2 or version > 4:
            raise SystemExit(f"{path}: unsupported pack format {version}")
        flags, _file_base = struct.unpack("<IQ", f.read(12))
        if flags & PACK_DIR_ENCRYPTED:
            raise SystemExit(f"{path}: encrypted directory")
        if version >= 3:
            (dir_offset,) = struct.unpack("<Q", f.read(8))
            f.seek(dir_offset)
        else:
            f.read(16 * 4)  # reserved
        (count,) = struct.unpack("<I", f.read(4))
        paths = []
        for _ in range(count):
            (length,) = struct.unpack("<I", f.read(4))
            name = f.read(length).rstrip(b"\0").decode("utf-8")
            f.read(8 + 8 + 16 + 4)  # offset, size, md5, flags
            paths.append(name if name.startswith("res://") else "res://" + name)
        return paths


if __name__ == "__main__":
    for p in list_pck(sys.argv[1]):
        print(p)
