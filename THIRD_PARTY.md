# Source and license notices

This project is distributed under GPL-2.0-or-later.
The original repository bootstrap's Apache 2.0 license text is preserved separately
in `licenses/Apache-2.0.txt`. The driver and bundled codec use the GPL terms described here.

- JBIG-KIT 2.1 sources (`vendor/jbig/jbig.c`, `jbig.h`, `jbig_ar.c`, `jbig_ar.h`)
  are copyright Markus Kuhn, with original notices preserved in each file.
  They were obtained from the OpenPrinting `foo2zjs` repository on 2026-11-04.
  The license is GPL-2.0-or-later; `vendor/jbig/COPYING` contains the upstream license.
- XQX record layout and encoder settings follow Rick Richardson's `foo2xqx.c`
  and `xqx.h`, distributed under GPL-2.0-or-later. The Rust driver uses its own
  framing implementation, validated against a separately built upstream encoder.
- Upstream: https://github.com/OpenPrinting/foo2zjs
- Source revision checked: `80499ed5bf6caa2963ad337e37cfda78a80aab1e` (`main-fixes`).
- CUPS APIs and raster structure definitions are supplied by the macOS system SDK.
- Scanner command sequences and packet layout follow SANE's `backend/hpljm1005.c`,
  copyright (C) 2007-2008 Philippe Rétornaz. The upstream file is GPL-2.0-or-later
  with the SANE linking exception. This project's Rust implementation remains
  GPL-2.0-or-later. Reference retrieved on 2026-11-04:
  https://gitlab.com/sane-project/backends/-/blob/master/backend/hpljm1005.c
- Native scanner transport and export use Apple's system IOKit, CoreGraphics and
  ImageIO APIs. The graphical app uses the system AppKit framework.

The driver does not redistribute HP or Apple proprietary printer drivers or firmware.
