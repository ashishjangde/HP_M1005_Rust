#!/bin/zsh
set -euo pipefail
(( EUID == 0 )) || { print -u2 "Run this script with sudo."; exit 1; }
/usr/sbin/lpadmin -x HP_M1005_Rust
# Explicit files only; leave every other printer and driver untouched.
/bin/rm -f /Library/Printers/M1005Rust/filter/rastertom1005 \
  /Library/Printers/M1005Rust/ppd/HP-M1005-Rust.ppd /Library/Printers/M1005Rust/LICENSE
/bin/rmdir /Library/Printers/M1005Rust/filter /Library/Printers/M1005Rust/ppd /Library/Printers/M1005Rust
