#!/usr/bin/env python3
"""Exercise Apple's actual PDF/raster pipeline and restricted CUPS stdin handling."""
import pathlib
import struct
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PPD = ROOT / "ppd/HP-M1005-Rust.ppd"
DRIVER = ROOT / "target/release/m1005"


def run(command, **kwargs):
    result = subprocess.run([str(x) for x in command], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace"))
    return result.stdout


def page_count(job):
    data = job.split(b",XQX", 1)[1]
    offset, pages = 0, 0
    while True:
        kind, count = struct.unpack_from(">II", data, offset)
        offset += 8
        if kind == 7:
            assert count <= 65536
            offset += count
        else:
            for _ in range(count):
                _, size = struct.unpack_from(">II", data, offset)
                offset += 8 + size
        if kind == 3:
            pages += 1
        if kind == 2:
            assert data[offset:].startswith(b"\x1b%-12345X@PJL EOJ")
            return pages


with tempfile.TemporaryDirectory(prefix="m1005-macos-") as folder:
    folder = pathlib.Path(folder)
    source = folder / "test.txt"
    source.write_text("M1005 Rust native macOS integration test\n"
                      "ABCDEFGHIJKLMNOPQRSTUVWXYZ\n0123456789\n")
    pdf = run(["/usr/sbin/cupsfilter", "-i", "text/plain", "-m", "application/pdf",
               "-p", PPD, source])
    document = folder / "test.pdf"
    document.write_bytes(pdf)
    for paper in ["A4", "Letter", "Legal", "A5"]:
        raster = run(["/usr/sbin/cupsfilter", "-i", "application/pdf", "-m",
                      "application/vnd.cups-raster", "-p", PPD,
                      "-o", "PageSize=" + paper, document])
        # Reproduce the actual print sandbox restriction that forbids reopening stdin.
        profile = '(version 1) (allow default) (deny file-read-data (literal "/dev/stdin") (literal "/dev/fd/0"))'
        command = ["/usr/bin/sandbox-exec", "-p", profile, DRIVER,
                   "filter", "1", "test", "test", "1", "PageSize=" + paper]
        output = run(command, input=raster)
        assert page_count(output) == 1
        print(f"PASS {paper}: PDF -> Apple raster -> sandboxed Rust stdin -> XQX ({len(output):,} bytes)")
    truncated = subprocess.run([str(DRIVER), "filter", "1", "test", "test", "1", ""],
                               input=raster[:-100], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert truncated.returncode != 0, "truncated raster must fail"
    assert b"truncated raster" in truncated.stderr
    print("PASS truncated raster rejected")
