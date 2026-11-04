# v0.3.0 — HP M1005 Print & Scan for Apple Silicon

Download **HP_M1005_Rust-0.3.0-macos-arm64.pkg** for the printer driver and scanner
app. It installs the CUPS print filter and **HP M1005 Scan.app**. Rust, Xcode and
Homebrew are not required to use the release.

## Scanner improvements

- Scan a sequence of pages and save them together as a multi-page PDF.
- Preview each page before saving; drag over the page to crop.
- Rotate pages left or right, reset edits, or automatically deskew using detected text lines.
- Optionally add a local macOS Vision OCR text layer so PDF text can be selected and searched.
- Document, Photo and Grayscale presets for common scan settings.
- Scan percentage, page/PDF progress, cancellation and clearer USB/scanner error guidance.
- PNG and searchable or image-only PDF output.

Place pages individually on the scanner glass. The scanner app does not depend on an
automatic document feeder. OCR runs locally on the Mac; images are not uploaded.

## Install

1. Connect and power on the M1005 over USB.
2. Open the `.pkg` and finish the macOS installer.
3. Print with **HP LaserJet M1005 (Rust)**.
4. Open **HP M1005 Scan** from Applications or Spotlight.

These Apple Silicon binaries target macOS 13 and later. They are unsigned and
notarization is not included. If Gatekeeper blocks an app you trust, use the
per-app approval flow in **System Settings → Privacy & Security → Open Anyway**.

## Downloads

- `HP_M1005_Rust-0.3.0-macos-arm64.pkg`: printer driver and scanner app installer.
- `HP_M1005_Scan-0.3.0-macos-arm64.zip`: scanner app by itself.
- `HP_M1005_Rust-0.3.0-source.tar.gz`: source from the matching release tag.
- `SHA256SUMS.txt`: SHA-256 checksums for the release downloads.

This release was built and the app compiled on Apple Silicon. The scanner transport
was physically verified in v0.2.0; the new crop, deskew, OCR and multi-page PDF
workflow in v0.3.0 has not yet been physically exercised on the M1005. Existing
single-page printing and scanning behavior is unchanged. This is an independent
community driver, not HP-supported software.

GPL-2.0-or-later. Keep the corresponding source and license notices with any
redistribution. See [README.md](README.md) for architecture, build and removal
instructions.
