#!/bin/zsh
# Used by the release installer. No printer data or USB serial numbers are logged.
set -euo pipefail
QUEUE="HP_M1005_Rust"
PPD="/Library/Printers/M1005Rust/ppd/HP-M1005-Rust.ppd"
(( EUID == 0 )) || { print -u2 "Run printer setup with administrator privileges."; exit 1; }
[[ -f "$PPD" ]] || { print -u2 "The M1005 printer driver is not installed."; exit 1; }
USB_URI="$(/usr/sbin/lpinfo -v | /usr/bin/awk '$1 == "direct" && ($2 ~ /^usb:\/\/Hewlett-Packard\/HP%20LaserJet%20M1005([?]|$)/ || $2 ~ /^usb:\/\/HP\/HP%20LaserJet%20M1005([?]|$)/) { print $2; exit }')"
if [[ -z "$USB_URI" ]]; then
  print "Driver installed. Connect and power on the M1005, then add it in System Settings > Printers & Scanners. Select HP LaserJet M1005 - Native Rust under Use > Select Software."
  exit 0
fi
/usr/sbin/lpadmin -p "$QUEUE" -E -v "$USB_URI" -P "$PPD" \
  -D "HP LaserJet M1005 (Rust)" -o printer-is-shared=false -o PageSize=A4
/usr/sbin/cupsenable "$QUEUE"
/usr/sbin/cupsaccept "$QUEUE"
print "HP LaserJet M1005 (Rust) is ready. Select it in the print dialog."
