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

# --- Stage (use ditto, NOT cp -R, to preserve the signature) -----------------
STAGE="$BUILD_DIR/stage"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"

echo "▶ Creating DMG…"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

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
