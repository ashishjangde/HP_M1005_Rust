# v0.3.4 — Accept scanner edge margins and simplify errors

The M1005 can finish a scan a few rows before the exact requested A4 height. Scans
that are short by less than 1% now keep the complete rows received and trim only the
unavailable bottom edge. Larger or malformed transfers still fail safely.

Scanner alerts now show a concise failure detail instead of the entire progress log.
If the first page fails, the app clears that unfinished session so resolution and
preset settings can be changed before retrying. Multi-page sessions keep pages already
added to the PDF.

Page previews draw directly into the native preview canvas with a separate crop
selection overlay. The Xcode sample-image launch mode makes preview and crop UI easy
to exercise without starting a USB scan. The progress bar resets when a scan finishes.

The Scan and Cancel buttons stay near the settings, and the preview size is bounded
so edit and save controls remain reachable.

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

- `HP_M1005_Rust-0.3.4-macos-arm64.pkg`: printer driver and scanner app installer.
- `HP_M1005_Scan-0.3.4-macos-arm64.dmg`: drag-to-Applications scanner app installer.
- `HP_M1005_Scan-0.3.4-macos-arm64.zip`: scanner app by itself.
- `HP_M1005_Rust-0.3.4-source.tar.gz`: source from the matching release tag.
- `SHA256SUMS.txt`: SHA-256 checksums for the release downloads.

This independent community driver is not HP-supported software. GPL-2.0-or-later;
keep corresponding source and license notices with any redistribution. See
[README.md](README.md) for build and removal instructions.
