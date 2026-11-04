# v0.3.3 — Keep scanner actions visible

The scan action was below the oversized preview area in some window layouts. Scan and
Cancel now appear near the settings, and the preview has a fixed height so the editing,
page, and save controls remain reachable in the window.

The Scan button opens the destination picker first, then starts the USB scan. Status,
progress, cancellation, and scanner error guidance remain visible while a scan runs.

## Scanner features

- Multi-page PDF assembly, page preview, crop, rotate, reset edits, and auto deskew.
- Optional local macOS Vision OCR for searchable PDFs.
- Document, Photo, and Grayscale presets; PNG or PDF output.
- Scan and PDF progress, cancellation, and actionable USB/scanner errors.
- One **HP M1005 Scan** application with a custom high-resolution icon.

## Install

1. Connect and power on the M1005 over USB.
2. Open the `.pkg` and finish the macOS installer.
3. Open **HP M1005 Scan** from Applications or Spotlight.
4. Choose an output filename in the dialog opened by **Scan…**; scanning starts after you choose it.

Apple Silicon only; macOS 13 or later. The package and app are unsigned and not
notarized. If Gatekeeper blocks an app you trust, approve it under
**System Settings → Privacy & Security → Open Anyway**.

## Downloads

- `HP_M1005_Rust-0.3.3-macos-arm64.pkg`: printer driver and scanner app installer.
- `HP_M1005_Scan-0.3.3-macos-arm64.zip`: scanner app by itself.
- `HP_M1005_Rust-0.3.3-source.tar.gz`: source from the matching release tag.
- `SHA256SUMS.txt`: SHA-256 checksums for the release downloads.

The app and installer build on Apple Silicon. Multi-page PDF, crop, deskew, and OCR
features are available; physical hardware verification remains documented in the
project README. This independent community driver is not HP-supported software.

GPL-2.0-or-later. Keep corresponding source and license notices with any
redistribution. See [README.md](README.md) for build and removal instructions.
