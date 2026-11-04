#!/bin/zsh
# Build distributable artifacts from reviewed source; never copy the output directory wholesale.
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
[[ "$(uname -m)" == "arm64" ]] || { print -u2 "Build this release on Apple Silicon."; exit 1; }
export MACOSX_DEPLOYMENT_TARGET=13.0
export COPYFILE_DISABLE=1
VERSION="$(/usr/bin/awk -F '"' '/^version = / {print $2; exit}' Cargo.toml)"
[[ "$VERSION" == <->.<->.<-> ]] || { print -u2 "Invalid release version."; exit 1; }
BUILD="$(/usr/bin/mktemp -d "$ROOT/output/release-build.XXXXXX")"
trap '/bin/rm -rf "$BUILD"' EXIT
DIST="$ROOT/output/releases/$VERSION"
mkdir -p "$DIST"
/bin/zsh scripts/build-scan-app.sh
/usr/bin/codesign --force --sign - target/release/m1005
PAYLOAD="$BUILD/root"
DRIVER="$PAYLOAD/Library/Printers/M1005Rust"
mkdir -p "$PAYLOAD/Applications" "$DRIVER/filter" "$DRIVER/bin" "$DRIVER/ppd" \
  "$PAYLOAD/Library/Printers/PPDs/Contents/Resources" "$BUILD/scripts" "$BUILD/resources"
/usr/bin/ditto --norsrc --noextattr --noacl "$ROOT/output/HP M1005 Scan.app" "$PAYLOAD/Applications/HP M1005 Scan.app"
/usr/bin/install -m 755 target/release/m1005 "$DRIVER/filter/rastertom1005"
/usr/bin/install -m 755 target/release/m1005 "$DRIVER/bin/m1005"
/usr/bin/install -m 755 packaging/configure-printer.sh "$DRIVER/configure-printer.sh"
/usr/bin/install -m 755 scripts/uninstall.sh "$DRIVER/uninstall-printing.sh"
/usr/bin/install -m 644 ppd/HP-M1005-Rust.ppd "$DRIVER/ppd/HP-M1005-Rust.ppd"
/usr/bin/install -m 644 ppd/HP-M1005-Rust.ppd "$PAYLOAD/Library/Printers/PPDs/Contents/Resources/HP-M1005-Rust.ppd"
for NOTICE in LICENSE THIRD_PARTY.md README.md; do
  /usr/bin/install -m 644 "$NOTICE" "$DRIVER/$NOTICE"
done
/usr/bin/install -m 644 vendor/jbig/COPYING "$DRIVER/JBIG-COPYING"
print "Corresponding source: https://github.com/ashishjangde/HP_M1005_Rust/tree/v$VERSION" > "$DRIVER/SOURCE.txt"
/usr/bin/install -m 755 packaging/preinstall packaging/postinstall "$BUILD/scripts/"
/usr/bin/install -m 644 packaging/welcome.html packaging/conclusion.html "$BUILD/resources/"
/usr/bin/xattr -cr "$PAYLOAD"
/usr/bin/codesign --verify --deep "$PAYLOAD/Applications/HP M1005 Scan.app"
/usr/bin/codesign --verify "$DRIVER/filter/rastertom1005"
/usr/bin/pkgbuild --analyze --root "$PAYLOAD" "$BUILD/components.plist"
/usr/bin/plutil -replace 0.BundleIsRelocatable -bool NO "$BUILD/components.plist"
/usr/bin/plutil -replace 0.BundleHasStrictIdentifier -bool YES "$BUILD/components.plist"
/usr/bin/pkgbuild --root "$PAYLOAD" --component-plist "$BUILD/components.plist" \
  --identifier local.m1005rust.printscan --version "$VERSION" --install-location / \
  --ownership recommended --scripts "$BUILD/scripts" "$BUILD/driver.pkg"
/bin/cat > "$BUILD/Distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>HP LaserJet M1005 Print &amp; Scan</title>
  <welcome file="welcome.html" mime-type="text/html"/>
  <conclusion file="conclusion.html" mime-type="text/html"/>
  <options customize="never" require-scripts="false" rootVolumeOnly="true" hostArchitectures="arm64"/>
  <allowed-os-versions><os-version min="13.0"/></allowed-os-versions>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <choices-outline><line choice="default"/></choices-outline>
  <choice id="default" title="HP M1005 Print and Scan"><pkg-ref id="local.m1005rust.printscan"/></choice>
  <pkg-ref id="local.m1005rust.printscan" version="$VERSION" onConclusion="none">driver.pkg</pkg-ref>
</installer-gui-script>
EOF
PACKAGE="HP_M1005_Rust-$VERSION-macos-arm64.pkg"
/usr/bin/productbuild --distribution "$BUILD/Distribution.xml" --resources "$BUILD/resources" \
  --package-path "$BUILD" "$DIST/$PACKAGE"
/usr/bin/ditto -c -k --norsrc --noextattr --noacl --keepParent "$PAYLOAD/Applications/HP M1005 Scan.app" \
  "$DIST/HP_M1005_Scan-$VERSION-macos-arm64.zip"
mkdir -p "$BUILD/dmg/Applications"
/usr/bin/ditto --norsrc --noextattr --noacl "$PAYLOAD/Applications/HP M1005 Scan.app" \
  "$BUILD/dmg/HP M1005 Scan.app"
/bin/ln -s /Applications "$BUILD/dmg/Applications/Applications"
/usr/bin/hdiutil create -quiet -volname "HP M1005 Scan" -srcfolder "$BUILD/dmg" \
  -ov -format UDZO "$DIST/HP_M1005_Scan-$VERSION-macos-arm64.dmg"
/bin/rm -rf "$ROOT/output/HP M1005 Scan.app"
print "Release binaries built in $DIST"
