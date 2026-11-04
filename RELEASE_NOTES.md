# v0.2.0 — HP M1005 printing and scanning for Apple Silicon

Download **HP_M1005_Rust-0.2.0-macos-arm64.pkg** for the complete setup. It installs
the printer driver and the HP M1005 Scan app. Rust, Xcode, Homebrew, Ghostscript
and Rosetta are not required to use the downloads.

## Install and use

1. Connect the HP LaserJet M1005 MFP by USB and turn it on.
2. Open the `.pkg` installer and finish the installation using your Mac administrator password.
3. Print from any app with **Command-P → HP LaserJet M1005 (Rust)**.
4. Open **HP M1005 Scan** from Applications or Spotlight to save scans as PNG or PDF.

If the printer was disconnected during installation, add it through System Settings
→ Printers & Scanners → Add Printer. Select the M1005, then select **HP LaserJet M1005
- Native Rust** under **Use → Select Software**.

## macOS security prompt

This community release is **unsigned and not notarized by Apple**. The app binaries
have local ad-hoc signatures, which do not establish a verified developer identity.
If macOS blocks the downloaded installer or app, first try opening it, then use
**System Settings → Privacy & Security → Open Anyway** for that specific download
if you choose to trust it. See [Apple's instructions](https://support.apple.com/en-gb/102445).
Keep normal macOS security settings enabled.

## Included downloads

- `HP_M1005_Rust-0.2.0-macos-arm64.pkg`: combined printer and scanner installer.
- `HP_M1005_Scan-0.2.0-macos-arm64.zip`: scanner app only; unzip and move the app to Applications.
- `HP_M1005_Rust-0.2.0-source.tar.gz`: corresponding GPL source for these binaries.
- `SHA256SUMS.txt`: SHA-256 checksums for the downloadable files.

## Compatibility and verified behavior

- **Apple Silicon only** (M-series Macs). The binaries target **macOS 13 or later**;
  hardware verification was on **macOS 27.0.1**. Earlier versions have not been hardware-tested.
- HP LaserJet M1005 MFP over USB; other HP models are not supported by this release.
- Printing: monochrome 600 dpi, A4 physically verified. Letter, Legal and A5 have pipeline tests.
- Scanning: A4 flatbed, color or grayscale, PNG or single-page PDF, optional 180° rotation.
- 150 dpi color/PNG and 300 dpi grayscale/PDF were physically verified. The app offers 75–600 dpi.
- Scanning uses the included app; it does not add an Image Capture/ICA driver or a system Scan tab.
- No network/AirPrint serving, OCR, multi-page PDF assembly or automatic document feeder support.

The source is **GPL-2.0-or-later**. Original third-party notices are included in the
source archive and installed driver. This is an independent project, not an official HP driver.
