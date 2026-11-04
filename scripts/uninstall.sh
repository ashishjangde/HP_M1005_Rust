#!/bin/zsh
set -euo pipefail
(( EUID == 0 )) || { print -u2 "Run this script with sudo."; exit 1; }
if /usr/bin/lpstat -p HP_M1005_Rust >/dev/null 2>&1; then
  /usr/sbin/lpadmin -x HP_M1005_Rust
fi
# Explicit files only; leave every other printer and driver untouched.
/bin/rm -f /Library/Printers/M1005Rust/filter/rastertom1005 \
  /Library/Printers/M1005Rust/ppd/HP-M1005-Rust.ppd /Library/Printers/M1005Rust/LICENSE \
  /Library/Printers/M1005Rust/bin/m1005 /Library/Printers/M1005Rust/configure-printer.sh \
  /Library/Printers/M1005Rust/THIRD_PARTY.md /Library/Printers/M1005Rust/README.md \
  /Library/Printers/M1005Rust/JBIG-COPYING /Library/Printers/M1005Rust/SOURCE.txt \
  /Library/Printers/M1005Rust/uninstall-printing.sh \
  /Library/Printers/PPDs/Contents/Resources/HP-M1005-Rust.ppd
for DIRECTORY in /Library/Printers/M1005Rust/filter /Library/Printers/M1005Rust/ppd \
  /Library/Printers/M1005Rust/bin /Library/Printers/M1005Rust; do
  if [[ -d "$DIRECTORY" ]]; then /bin/rmdir "$DIRECTORY"; fi
done
print "Printing removed. The separate HP M1005 Scan app remains in Applications."
