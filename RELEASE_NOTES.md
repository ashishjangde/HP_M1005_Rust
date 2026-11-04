# v0.3.1 — HP M1005 Scan app polish

This update fixes the app bundle's launch entry point, removes stale prior scanner
executables during updates, hides the developer build copy from Spotlight indexing,
and adds a custom high-resolution scanner icon. It includes all v0.3.0 scan features.

## Scanner features

- Multi-page PDF assembly by scanning one page at a time.
- Page preview, drag-to-crop, left/right rotation, reset edits and automatic text-line deskew.
- Optional local macOS Vision OCR text layer for searchable PDFs.
- Document, Photo and Grayscale presets.
- Scan percentage, PDF progress, cancel and clearer USB/scanner error guidance.
- PNG or searchable/image-only PDF output.

The scanner app installs as a single **HP M1005 Scan** application. The build copy
is kept out of Spotlight indexing to avoid showing duplicate app entries. Place each
page individually on the glass; an automatic document feeder is not required.

## Install

1. Connect and power on the M1005 over USB.
2. Open the `.pkg` and finish the macOS installer.
3. Print with **HP LaserJet M1005 (Rust)**.
4. Open **HP M1005 Scan** from Applications or Spotlight.

Apple Silicon only; macOS 13 or later. The package and app are unsigned and not
notarized. If Gatekeeper blocks an app you trust, approve that app under
**System Settings → Privacy & Security → Open Anyway**.

## Downloads

- `HP_M1005_Rust-0.3.1-macos-arm64.pkg`: printer driver and scanner app installer.
- `HP_M1005_Scan-0.3.1-macos-arm64.zip`: scanner app by itself.
- `HP_M1005_Rust-0.3.1-source.tar.gz`: source from the matching release tag.
- `SHA256SUMS.txt`: SHA-256 checksums for the release downloads.

The app and installer build successfully on Apple Silicon. The original scanner
transport was physically verified in v0.2.0; crop, deskew, OCR and multi-page PDF
features have not yet been physically exercised on the M1005. This independent
community driver is not HP-supported software.

GPL-2.0-or-later. Keep corresponding source and license notices with any
redistribution. See [README.md](README.md) for build and removal instructions.
