# HP LaserJet M1005 native Rust printing and scanning for macOS

## Download and use

**Apple Silicon Mac (M-series), macOS 13 or later.** Download the ready-made
[Print & Scan installer](https://github.com/ashishjangde/HP_M1005_Rust/releases/download/v0.3.1/HP_M1005_Rust-0.3.1-macos-arm64.pkg)
or visit the [latest release](https://github.com/ashishjangde/HP_M1005_Rust/releases/latest).
You do not need Rust, Xcode or Homebrew to use the download.

1. Connect and power on the USB printer.
2. Open the `.pkg` file and finish the installer with your Mac administrator password.
3. Print with **Command-P → HP LaserJet M1005 (Rust)**.
4. Open **HP M1005 Scan** from Applications or Spotlight to scan to PDF or PNG.

This community release is **unsigned and not Apple-notarized**. If macOS blocks the
download, use **System Settings → Privacy & Security → Open Anyway** for that
specific installer or app if you choose to trust it. See [Apple's instructions](https://support.apple.com/en-gb/102445).
The downloads include checksums and corresponding GPL source. Hardware testing
was on macOS 27.0.1; the binaries target macOS 13+, with earlier versions unverified.

For the scanner app alone, download the ZIP from the release and move the extracted
**HP M1005 Scan.app** to Applications. Intel Macs are not supported by these release binaries.

## Project

A custom CUPS raster filter for the USB HP LaserJet M1005 MFP. The driver and XQX
framing are Rust; the bundled JBIG compression library and a small CUPS ABI bridge
are C. Everything compiles natively for Apple Silicon, with no Rosetta, Ghostscript,
Homebrew runtime, HP archived driver package, background service or kernel extension.
This is an independent project, not an HP-supported driver.

The scanner protocol, USB session and planar image assembly are Rust. A small native bridge supplies macOS USB access and image export. The included
**HP M1005 Scan** app uses standard macOS controls and the same native scanner binary.

**Hardware verified on 2026-11-04:** a PDF printed correctly on an HP LaserJet M1005
over USB from an Apple Silicon Mac running macOS 27.0.1, using this installed filter
at 600 dpi on A4. The test completed through the normal macOS CUPS queue, and the
paper output was physically confirmed. Other paper sizes have pipeline tests but
have not been physically verified.

**Scanning verified on 2026-11-04:** A4 color scanning at 150 dpi to PNG and grayscale
scanning at 300 dpi to PDF both completed on the connected M1005. The output images
were visually checked, including a rendered PDF. A scan saved successfully through
the Mac app as well. Other offered resolutions have not been physically verified.

## Scan from the Mac app

Open **HP M1005 Scan** from Applications or Spotlight. Choose a preset, place the
page face-down on the glass and click **Scan…**. Preview each page, drag to select a
crop, rotate or auto-deskew it, then save as PNG or PDF. For multi-page PDFs, click
**Add Page & Scan Next** for each page and **Finish & Save PDF** when done.

- A4 flatbed; grayscale or color; PNG or multi-page PDF.
- Resolution choices: 75, 100, 150, 200, 300 and 600 dpi. Document and Grayscale
  presets use 300 dpi grayscale PDF; Photo uses 600 dpi color PNG.
- Optional local macOS Vision OCR adds a searchable text layer to PDFs.
- Preview, drag-to-crop, left/right rotation, reset-edits and text-line auto-deskew.
- Scan and PDF progress, cancellation, and actionable USB/scanner error messages.
- Cancel drains the active USB scan so the scanner can return home before releasing it.
- Existing files are preserved; choose a new filename for each output.
- The app has one installed bundle and a custom high-resolution M1005 Scan icon.
- The app is a separate scanner frontend. It does not register an Image Capture/ICA
  driver or add a Scan tab to macOS Printers & Scanners.

Build and install the scan app:

```sh
/bin/zsh scripts/build-scan-app.sh
sudo /bin/zsh scripts/install-scan-app.sh
```

Installation copies only this app bundle into `/Applications/HP M1005 Scan.app`.
Normal scanning requires no administrator password. Remove the Scan app through
Finder if you no longer need it; printing has a separate installer/uninstaller.

Command-line single-page scanning is also available:

```sh
target/release/m1005 scan-probe
target/release/m1005 scan scan.png 150 color
target/release/m1005 scan scan.pdf 300 gray
target/release/m1005 scan upright.pdf 300 gray 180
```

The final optional argument is rotation (`0` or `180`). Scans stay local; there is
no network service or upload step. Scan test files are runtime output and are not
source-code fixtures.

## Build and install

Requires macOS, Rust/Cargo, and Xcode command-line build tools.

Clone the source before following either the printer or scanner installation steps:

```sh
git clone https://github.com/ashishjangde/HP_M1005_Rust.git
cd HP_M1005_Rust
```

Build and install the printer driver:

```sh
cargo test
cargo build --release
codesign --force --sign - target/release/m1005
sudo /bin/zsh scripts/install.sh
```

Connect and power on the printer before installation. Enter your administrator
password only at the macOS/Terminal prompt. The installer adds a separate
`HP_M1005_Rust` queue named **HP LaserJet M1005 (Rust)**. Select it in any app's normal
print dialog. It installs files only under `/Library/Printers/M1005Rust` and leaves
other queues and drivers alone. Re-running the installer updates this project's queue.

To send a PDF after installation:

```sh
lp -d HP_M1005_Rust -o PageSize=A4 document.pdf
```

To remove the queue and its files:

```sh
sudo /bin/zsh scripts/uninstall.sh
```

For the downloaded installer, the same printer uninstaller is available at
`/Library/Printers/M1005Rust/uninstall-printing.sh`. Run it with `sudo /bin/zsh`.
The Scan app is separate and can be moved to Trash through Finder.

## Scope

- 600 × 600 dpi, monochrome, plain paper, simplex.
- A4, Letter, Legal and A5 options; one to 99 copies.
- CUPS raster input: 1-bit or 8-bit black/gray; ordered dithering for 8-bit input.
- PDF and other formats use macOS's existing renderers before reaching this filter.
- USB transport uses the macOS CUPS USB backend.
- Manual duplex, other media types, 1200 dpi and network/AirPrint serving
  are outside this version. Only physically verified configurations should be
  described as hardware-tested.

## Architecture

```text
App / PDF → macOS cgpdftoraster → Rust raster reader → native JBIG compression
          → Rust XQX framing → macOS USB backend → LaserJet M1005
```

`src/bitmap.rs` validates PBM images and aligns rows to 128 pixels.
`src/raster.rs` reads raster pages through the macOS CUPS API, converts grayscale,
and validates formats, dimensions and row lengths. `src/xqx.rs` writes PJL and XQX
records, including the required 65,536-byte maximum JBIG blocks. `native/bridge.c`
keeps platform C struct layouts out of Rust. The installed executable dynamically
links only macOS system libraries; JBIG is statically linked.

`src/scanner.rs` implements the ASP scanner commands from SANE's `hpljm1005` protocol,
bounded packet parsing, RGB-plane reconstruction, padded-row removal, clean
cancellation, rotation and atomic output publication without replacing existing files.
`native/scanner.c` opens only scanner interface 0 using IOKit; printing remains on its
separate macOS USB backend. The AppKit frontend uses Vision for local OCR and text-line
deskew, Core Image for image transforms, and CoreGraphics/ImageIO for PNG and searchable
multi-page PDF export.

## Verification

```sh
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
cupstestppd -I filters ppd/HP-M1005-Rust.ppd
python3 tests/verify_macos.py
```

`tests/verify_reference.py /path/to/foo2xqx` compares the Rust encoder against a
separately compiled upstream `foo2xqx` oracle. It checks white and black pages,
non-byte-aligned widths, multiple pages, and data exceeding the printer's block
limit. The binary XQX output must match exactly. The upstream executable is used
only for development validation, never by the installed driver.

The verified build passed eleven Rust unit tests, five upstream byte-for-byte
comparison cases, and five macOS pipeline/sandbox cases. `verify_macos.py` exercises
Apple's actual PDF renderer with A4, Letter, Legal and A5, checks a filter running
with restricted access to `/dev/stdin`, and verifies rejection of truncated raster
data. The filter uses inherited fd 0 directly, as required by the CUPS sandbox.

Scanner tests cover packet byte order and A4 bounds, rejecting invalid/incomplete
data, synchronizing planar RGB with row padding, keeping channels together when
rotating, and preserving both existing output files and conflicting temporary files.

Generate a calibration bitmap and encoded job without printing:

```sh
mkdir -p output
target/release/m1005 test-page output/calibration.pbm
target/release/m1005 encode output/calibration.pbm output/calibration.xqx
```

Troubleshoot with `lpstat -p HP_M1005_Rust`, `lpstat -W not-completed -o HP_M1005_Rust`,
and `/var/log/cups/error_log`. Physical print quality needs confirmation at the
printer; a completed queue alone does not prove the paper output is correct.

## License and provenance

GPL-2.0-or-later; see [LICENSE](LICENSE) and [THIRD_PARTY.md](THIRD_PARTY.md).
Keep the corresponding source and license notices with any distribution.
The original repository bootstrap's Apache 2.0 license text is retained in
[licenses/Apache-2.0.txt](licenses/Apache-2.0.txt) for provenance.

## Build a release

On Apple Silicon, run `/bin/zsh scripts/build-release.sh`. This builds the combined
`.pkg` and scanner-only ZIP in `output/releases/<version>/`, targeting macOS 13.
Run `python3 tests/verify_release.py` to inspect the installer payload, signatures,
deployment targets and scanner ZIP before publishing. The release must also include
a corresponding source archive from the exact tagged commit and SHA-256 checksums.
Read [RELEASE_NOTES.md](RELEASE_NOTES.md) for user installation instructions and limitations.
