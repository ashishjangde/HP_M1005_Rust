#!/bin/zsh
# Install only this project's filter, PPD and dedicated queue. GPL-2.0-or-later.
set -euo pipefail
ROOT="${0:A:h:h}"
QUEUE="HP_M1005_Rust"
DEST="/Library/Printers/M1005Rust"

if (( EUID != 0 )); then
  print -u2 "Run with sudo: sudo /bin/zsh '$ROOT/scripts/install.sh'"
  exit 1
fi
[[ -x "$ROOT/target/release/m1005" ]] || { print -u2 "Build first with cargo build --release"; exit 1; }
/usr/bin/cupstestppd -I filters "$ROOT/ppd/HP-M1005-Rust.ppd" >/dev/null

# Discover just this model. The URI may contain a serial number; do not log it.
USB_URI="$(/usr/sbin/lpinfo -v | /usr/bin/awk '$1 == "direct" && ($2 ~ /^usb:\/\/Hewlett-Packard\/HP%20LaserJet%20M1005([?]|$)/ || $2 ~ /^usb:\/\/HP\/HP%20LaserJet%20M1005([?]|$)/) { print $2; exit }')"
[[ -n "$USB_URI" ]] || { print -u2 "HP LaserJet M1005 not detected. Connect and power it on."; exit 1; }

/usr/bin/install -d -o root -g wheel -m 755 "$DEST/filter" "$DEST/ppd"
/usr/bin/install -o root -g wheel -m 755 "$ROOT/target/release/m1005" "$DEST/filter/rastertom1005"
/usr/bin/install -o root -g wheel -m 644 "$ROOT/ppd/HP-M1005-Rust.ppd" "$DEST/ppd/HP-M1005-Rust.ppd"
/usr/bin/install -o root -g wheel -m 644 "$ROOT/LICENSE" "$DEST/LICENSE"
/usr/bin/codesign --verify "$DEST/filter/rastertom1005"
/usr/bin/cupstestppd "$DEST/ppd/HP-M1005-Rust.ppd"
/usr/sbin/lpadmin -p "$QUEUE" -E -v "$USB_URI" -P "$DEST/ppd/HP-M1005-Rust.ppd" \
  -D "HP LaserJet M1005 (Rust)" -o printer-is-shared=false -o PageSize=A4
/usr/sbin/cupsenable "$QUEUE"
/usr/sbin/cupsaccept "$QUEUE"

print "Installed HP LaserJet M1005 (Rust). Select it in the macOS print dialog."
