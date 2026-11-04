#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
cargo build --release
APP="$ROOT/output/HP M1005 Scan.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/output/swift-cache"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/target/release/m1005" "$APP/Contents/Resources/m1005"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
cp "$ROOT/THIRD_PARTY.md" "$APP/Contents/Resources/THIRD_PARTY.md"
xcrun swiftc -O -module-cache-path "$ROOT/output/swift-cache" \
  -framework AppKit -framework UniformTypeIdentifiers \
  "$ROOT/macos/ScanApp.swift" -o "$APP/Contents/MacOS/HP M1005 Scan"
/usr/bin/codesign --force --sign - "$APP/Contents/Resources/m1005"
/usr/bin/codesign --force --sign - "$APP"
print "Built $APP"
