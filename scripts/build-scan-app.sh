#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
export MACOSX_DEPLOYMENT_TARGET=13.0
cargo build --release
APP="$ROOT/output/HP M1005 Scan.app"
ICONSET="$ROOT/macos/Assets.xcassets/AppIcon.appiconset"
if [[ -e "$APP" ]]; then /bin/rm -rf "$APP"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/output/swift-cache" "$ICONSET"
touch "$ROOT/output/.metadata_never_index"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/target/release/m1005" "$APP/Contents/Resources/m1005"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
cp "$ROOT/THIRD_PARTY.md" "$APP/Contents/Resources/THIRD_PARTY.md"
swift -module-cache-path "$ROOT/output/swift-cache" "$ROOT/scripts/build-app-icon.swift" "$ROOT/artwork/hp-m1005-scan-icon.png" "$ICONSET"
xcrun actool --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 13.0 \
  --target-device mac --app-icon AppIcon --output-partial-info-plist "$ROOT/output/AppIcon-Info.plist" \
  "$ROOT/macos/Assets.xcassets"
xcrun swiftc -O -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$ROOT/output/swift-cache" \
  -framework AppKit -framework UniformTypeIdentifiers -framework Vision -framework CoreImage -framework CoreText -framework ImageIO \
  "$ROOT/macos/ScanApp.swift" "$ROOT/macos/CropPreviewView.swift" "$ROOT/macos/ScanDocument.swift" "$ROOT/macos/main.swift" \
  -o "$APP/Contents/MacOS/m1005-scan"
/usr/bin/codesign --force --sign - "$APP/Contents/Resources/m1005"
/usr/bin/codesign --force --sign - "$APP"
print "Built $APP"
