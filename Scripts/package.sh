#!/usr/bin/env bash
#
# package.sh — build a Release insomniac.app and wrap it in a drag-to-install DMG.
#
# Free Apple ID (now):   produces an un-notarized DMG. It works, but recipients
#                        must right-click → Open the first time (Gatekeeper warns).
# Paid program (later):  if a "Developer ID Application" cert is in your keychain
#                        AND you export NOTARY_PROFILE=<your notarytool profile>,
#                        it re-signs with Developer ID, notarizes, and staples —
#                        a clean double-clickable download. See PUBLISHING.md.
#
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="insomniac"
CONFIG="Release"
BUILD_DIR="$PWD/build"
APP_NAME="insomniac.app"
VOL="insomniac"
DMG="$BUILD_DIR/insomniac.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

echo "▶ Building ${CONFIG}…"
xcodebuild -project insomniac.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR/dd" -destination 'generic/platform=macOS' build >/dev/null
APP="$BUILD_DIR/dd/Build/Products/$CONFIG/$APP_NAME"
[ -d "$APP" ] || { echo "✗ build produced no app"; exit 1; }

# --- Optional: switch to Developer ID signing (paid program only) ------------
DEVID="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}' || true)"
if [ -n "$DEVID" ]; then
  echo "▶ Re-signing with Developer ID ($DEVID), inside-out…"
  codesign --force --options runtime --timestamp --sign "$DEVID" \
    "$APP/Contents/MacOS/dev.saif.insomniac.helper"
  codesign --force --options runtime --timestamp --sign "$DEVID" "$APP"
  codesign --verify --deep --strict --verbose=1 "$APP"
else
  echo "⚠ No 'Developer ID Application' certificate — DMG will be un-notarized."
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
    set position of item "$APP_NAME" of container window to {205, 185}
    set position of item "Applications" of container window to {495, 185}
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

# --- Optional: notarize + staple (needs DevID + NOTARY_PROFILE) --------------
if [ -n "$DEVID" ] && [ -n "$NOTARY_PROFILE" ]; then
  echo "▶ Notarizing (profile: $NOTARY_PROFILE)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG" && echo "✓ Notarized + stapled."
else
  echo "⚠ Skipped notarization."
  echo "  Recipients must right-click → Open the app the first time (Gatekeeper)."
  echo "  See PUBLISHING.md to enable notarization."
fi

echo "✓ Done → $DMG"
