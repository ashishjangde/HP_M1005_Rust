#!/usr/bin/env python3
"""Inspect public release artifacts without installing or starting a scan."""
import hashlib
import pathlib
import plistlib
import subprocess
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION = re.search(r'^version = "([^"]+)"', (ROOT / "Cargo.toml").read_text(), re.MULTILINE).group(1)
DIST = ROOT / "output/releases" / VERSION
PACKAGE = DIST / f"HP_M1005_Rust-{VERSION}-macos-arm64.pkg"
ZIP = DIST / f"HP_M1005_Scan-{VERSION}-macos-arm64.zip"


def run(*args):
    return subprocess.check_output([str(x) for x in args], stderr=subprocess.STDOUT).decode()


def check_binary(path):
    assert "arm64" in run("/usr/bin/file", path)
    load_commands = run("/usr/bin/otool", "-l", path)
    assert "minos 13.0" in load_commands, f"wrong deployment target: {path}"
    run("/usr/bin/codesign", "--verify", path)
    for line in run("/usr/bin/otool", "-L", path).splitlines()[1:]:
        dependency = line.strip().split(" (", 1)[0]
        assert dependency.startswith(("/usr/lib/", "/System/Library/")), dependency


names = run("/usr/sbin/pkgutil", "--payload-files", PACKAGE).splitlines()
allowed = ("Library/Printers/M1005Rust", "Library/Printers/PPDs", "Applications/HP M1005 Scan.app")
parents = {"", "Library", "Library/Printers", "Applications"}
for name in names:
    path = name.removeprefix("./")
    if path == ".":
        path = ""
    # pkgutil lists AppleDouble entries for macOS provenance attributes. The
    # installer restores these as metadata, not as user-visible payload files.
    if any(part.startswith("._") for part in pathlib.PurePosixPath(path).parts):
        continue
    assert path in parents or path.startswith(allowed), f"unexpected payload: {name}"
    assert not path.endswith((".png", ".pdf", ".pbm", ".xqx", ".log")), f"runtime data leaked: {name}"
print("PASS installer contains only the intended app, driver, PPD and notices")

with tempfile.TemporaryDirectory(prefix="m1005-release-") as folder:
    folder = pathlib.Path(folder)
    unpacked = folder / "pkg"
    run("/usr/sbin/pkgutil", "--expand-full", PACKAGE, unpacked)
    payload = next(unpacked.rglob("Payload"))
    app = payload / "Applications/HP M1005 Scan.app"
    driver = payload / "Library/Printers/M1005Rust"
    for binary in [app / "Contents/MacOS/HP M1005 Scan", app / "Contents/Resources/m1005",
                   driver / "filter/rastertom1005", driver / "bin/m1005"]:
        check_binary(binary)
    run("/usr/bin/codesign", "--verify", "--deep", app)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleShortVersionString"] == VERSION
    assert info["LSMinimumSystemVersion"] == "13.0"
    assert "GPL-2.0-or-later" in (driver / "THIRD_PARTY.md").read_text()
    assert (driver / "LICENSE").read_bytes() == (ROOT / "LICENSE").read_bytes()
    assert (driver / "JBIG-COPYING").read_bytes() == (ROOT / "vendor/jbig/COPYING").read_bytes()
    component = ET.parse(next(unpacked.rglob("PackageInfo"))).getroot()
    assert component.attrib["install-location"] == "/"
    assert component.attrib["identifier"] == "local.m1005rust.printscan"
    assert component.attrib["auth"] == "root"
    assert component.attrib["relocatable"] == "false"
    assert component.find("bundle") is not None
    assert len(component.find("relocate")) == 0
    print("PASS extracted binaries are arm64, target macOS 13, and use only system libraries")
    print("PASS package metadata, local code signatures and GPL notices")
    with zipfile.ZipFile(ZIP) as archive:
        assert not any(name.startswith("__MACOSX/") for name in archive.namelist())
        archived = archive.read("HP M1005 Scan.app/Contents/Resources/m1005")
        assert hashlib.sha256(archived).digest() == hashlib.sha256((driver / "bin/m1005").read_bytes()).digest()
    print("PASS scanner ZIP matches the installer driver and excludes resource-fork metadata")

print("Release artifact inspection passed")
