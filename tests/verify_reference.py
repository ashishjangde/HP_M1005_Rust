#!/usr/bin/env python3
"""Compare the Rust XQX payload byte-for-byte with upstream foo2xqx.

Usage: python3 tests/verify_reference.py /path/to/compiled/foo2xqx
The reference is a development-only oracle; it is not part of the installed driver.
"""
import pathlib
import random
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUST = ROOT / "target/release/m1005"
REFERENCE = pathlib.Path(sys.argv[1]).resolve()


def pbm(width, height, pixels):
    return f"P4\n{width} {height}\n".encode() + pixels


rng = random.Random(1005)
cases = {
    "white": pbm(128, 128, bytes(16 * 128)),
    "black": pbm(256, 257, b"\xff" * (32 * 257)),
    "nonbyte-width": pbm(193, 257, bytes(rng.randrange(256) for _ in range(25 * 257))),
    "multi-chunk": pbm(2048, 2048, bytes(rng.randrange(256) for _ in range(256 * 2048))),
}
# Upstream preserves unused bits in the last byte. Clear them for a canonical PBM.
data = bytearray(cases["nonbyte-width"])
start = data.index(b"\n", data.index(b"\n") + 1) + 1
for offset in range(start + 24, len(data), 25):
    data[offset] &= 0x80
cases["nonbyte-width"] = bytes(data)
cases["multipage"] = cases["white"] + cases["black"] + cases["nonbyte-width"]

with tempfile.TemporaryDirectory(prefix="m1005-reference-") as folder:
    folder = pathlib.Path(folder)
    for name, data in cases.items():
        source, output = folder / "input.pbm", folder / "rust.xqx"
        source.write_bytes(data)
        subprocess.run([str(RUST), "encode", str(source), str(output)], check=True)
        expected = subprocess.run([str(REFERENCE), "-r600x600", "-p9"],
                                  input=data, stdout=subprocess.PIPE, check=True).stdout
        # Ignore the upstream PJL timestamp; compare all binary protocol records and image data.
        actual = output.read_bytes().split(b",XQX", 1)[1]
        expected = expected.split(b",XQX", 1)[1]
        assert actual == expected, f"XQX differs from foo2xqx for {name}"
        print(f"PASS {name}: {len(actual):,} protocol bytes match upstream")
