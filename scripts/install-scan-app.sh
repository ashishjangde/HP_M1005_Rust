#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
SOURCE="$ROOT/output/HP M1005 Scan.app"
DEST="/Applications/HP M1005 Scan.app"
(( EUID == 0 )) || { print -u2 "Run with sudo."; exit 1; }
[[ -d "$SOURCE" ]] || { print -u2 "Build the Scan app first."; exit 1; }
if [[ -e "$DEST" ]]; then
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist")"
  [[ "$BUNDLE_ID" == "local.m1005rust.scan" ]] || { print -u2 "An unrelated app already uses this name."; exit 1; }
fi
/usr/bin/ditto "$SOURCE" "$DEST"
/usr/sbin/chown -R root:wheel "$DEST"
/bin/chmod -R go-w "$DEST"
/usr/bin/codesign --verify --deep "$DEST"
print "Installed /Applications/HP M1005 Scan.app"
