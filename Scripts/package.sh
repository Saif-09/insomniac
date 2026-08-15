#!/usr/bin/env bash
#
# package.sh — build, sign, notarize and package the direct-download Insomniac.
#
# Produces build/insomniac.dmg: a Developer-ID-signed, hardened-runtime,
# notarized, stapled disk image, plus the Sparkle appcast entry that tells
# existing users the new version exists.
#
# Why archive/exportArchive rather than `codesign --force` over the built app:
# the bundle now contains a privileged helper AND Sparkle.framework, and Sparkle
# nests an XPC service that carries its own entitlements. Re-signing that from
# the outside strips them (`--force` without `--entitlements` drops what was
# there) and produces an app that passes `codesign --verify` but fails to
# update. Letting Xcode export the archive signs every nested component
# inside-out with the right identity and the right entitlements.
#
# Usage:
#   ./Scripts/package.sh                    # build + sign + notarize + DMG
#   SKIP_NOTARIZE=1 ./Scripts/package.sh    # skip the notary round-trip
#
# Notarization credentials come from a notarytool keychain profile; set
# NOTARY_PROFILE to override the default name. See PUBLISHING.md.
#
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="insomniac"
CONFIG="Release"
BUILD_DIR="$PWD/build"
APP_NAME="insomniac.app"
VOL="insomniac"
DMG="$BUILD_DIR/insomniac.dmg"
ARCHIVE="$BUILD_DIR/insomniac.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
NOTARY_PROFILE="${NOTARY_PROFILE:-insomniac-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-}"
TEAM_ID="DTQF9KJP6S"

rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

# --- Archive ----------------------------------------------------------------
echo "▶ Archiving ${CONFIG}…"
xcodebuild -project insomniac.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  archive >/dev/null

# --- Export with Developer ID ------------------------------------------------
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
PLIST

echo "▶ Exporting with Developer ID…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR" >/dev/null

APP="$EXPORT_DIR/$APP_NAME"
[ -d "$APP" ] || { echo "✗ export produced no app"; exit 1; }

echo "▶ Verifying signature…"
codesign --verify --deep --strict --verbose=1 "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority=Developer ID|Runtime" || {
  echo "✗ not signed with Developer ID + hardened runtime"; exit 1; }

# --- Notarize the app before packaging --------------------------------------
# Notarizing the app itself (not just the DMG) means the ticket is stapled into
# the bundle, so it stays valid however the user ends up copying it out.
if [ -z "$SKIP_NOTARIZE" ]; then
  echo "▶ Notarizing the app (profile: $NOTARY_PROFILE)…"
  ZIP="$BUILD_DIR/insomniac-notarize.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
else
  echo "⚠ SKIP_NOTARIZE set — the app is signed but not notarized."
fi

# --- Stage (ditto preserves the signature; cp -R would not) ------------------
STAGE="$BUILD_DIR/stage"; rm -rf "$STAGE"; mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"

echo "▶ Rendering install-window background…"
swift "$PWD/Scripts/make_dmg_background.swift" "$STAGE/.background/bg.png" >/dev/null

# --- Build a read-write DMG, lay out the install window, then compress -------
echo "▶ Building styled DMG…"
# Detach any stale mounts from earlier runs, or Finder targets the wrong disk.
for v in /Volumes/"$VOL"*; do [ -d "$v" ] && hdiutil detach "$v" -force >/dev/null 2>&1 || true; done
RW="$BUILD_DIR/rw.dmg"; rm -f "$RW"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
hdiutil attach "$RW" -nobrowse -noautoopen >/dev/null
sleep 1
osascript <<OSA || echo "⚠ Finder layout skipped (allow “control Finder” if prompted). DMG still builds."
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {220, 160, 920, 658}
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to 100
    set text size of vo to 12
    set background picture of vo to file ".background:bg.png"
    set position of item "$APP_NAME" of container window to {245, 155}
    set position of item "Applications" of container window to {455, 155}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
sync; sleep 1
hdiutil detach "/Volumes/$VOL" >/dev/null 2>&1 || hdiutil detach "/Volumes/$VOL" -force >/dev/null 2>&1
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
rm -f "$RW"

# --- Sign + notarize the DMG itself -----------------------------------------
if [ -z "$SKIP_NOTARIZE" ]; then
  DEVID="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}')"
  echo "▶ Signing and notarizing the DMG…"
  codesign --force --sign "$DEVID" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  echo "✓ Notarized + stapled."
  spctl -a -t open --context context:primary-signature -v "$DMG" || true
fi

# --- Also emit a version-stamped copy ----------------------------------------
# The GitHub release needs BOTH names attached:
#   insomniac.dmg           — what the landing page's releases/latest/download
#                             link points at, and must keep pointing at
#   insomniac-<version>.dmg — what the appcast enclosure references, because an
#                             appcast holds several versions at once and each
#                             entry has to resolve to its own build
# They are byte-identical copies; attach both to the release.
VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
cp "$DMG" "$BUILD_DIR/insomniac-${VERSION}.dmg"

echo "✓ Done → $DMG"
echo "        → $BUILD_DIR/insomniac-${VERSION}.dmg  (same file, for the appcast enclosure)"
echo
echo "Next:"
echo "  1. Create the GitHub release, tag v${VERSION}, attach BOTH .dmg files above"
echo "  2. ./Scripts/update_appcast.sh   (signs the DMG for Sparkle, writes docs/appcast.xml)"
echo "  3. Commit and push docs/"
