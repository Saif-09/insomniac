#!/usr/bin/env bash
#
# appstore.sh — build, sign, validate and upload the Mac App Store build.
#
# Produces build/appstore/Insomniac.pkg, signed with Apple Distribution and the
# "3rd Party Mac Developer Installer" certificate, and uploads it to App Store
# Connect as a new build of the app record.
#
# Usage:
#   ./Scripts/appstore.sh              # build + validate + upload
#   ./Scripts/appstore.sh --no-upload  # stop after validation
#
# ── Two things this script cannot do for you ─────────────────────────────────
#
# 1. Create the App Store Connect app record. Apple's API refuses it outright:
#    `POST /v1/apps` returns "The resource 'apps' does not allow 'CREATE'", so no
#    script can do it. Xcode can (Product > Archive > Distribute App), as can the
#    web UI. Until it exists, upload fails with "Cannot determine the Apple ID
#    from Bundle ID", which sounds like a signing problem and isn't.
#    Already done: "Insomniac - Sleep Blocker" / app.ziyarex.insomniac.mas.
#
# 2. Sign with the App Store Connect API key. The key in
#    ~/.appstoreconnect/private_keys can notarize and can upload, but it lacks
#    permission to create bundle IDs or distribution provisioning profiles
#    ("Cloud signing permission error"). So signing runs off the Apple ID that
#    Xcode is logged in with — hence no -authenticationKey* flags on the
#    archive/export steps. Give the key Admin access in App Store Connect →
#    Users and Access → Integrations if you'd rather it be self-contained.
#
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="insomniac-mas"
CONFIG="Release"
OUT="$PWD/build/appstore"
ARCHIVE="$OUT/Insomniac.xcarchive"
PKG="$OUT/export/Insomniac.pkg"
TEAM_ID="DTQF9KJP6S"
# Deliberately not hardcoded: this repo is public, and while the key ID and
# issuer ID aren't secrets on their own, they're two thirds of what an attacker
# needs if the .p8 ever leaks. Keep them in your shell profile:
#   export ASC_KEY_ID=…  ASC_ISSUER_ID=…
# The matching AuthKey_$ASC_KEY_ID.p8 must be in ~/.appstoreconnect/private_keys.
KEY_ID="${ASC_KEY_ID:-}"
ISSUER_ID="${ASC_ISSUER_ID:-}"
UPLOAD=1
[ "${1:-}" = "--no-upload" ] && UPLOAD=0

if [ -z "$KEY_ID" ] || [ -z "$ISSUER_ID" ]; then
  echo "✗ Set ASC_KEY_ID and ASC_ISSUER_ID first (App Store Connect →"
  echo "  Users and Access → Integrations → Keys; the issuer UUID is above the table)."
  exit 1
fi

rm -rf "$OUT"; mkdir -p "$OUT"

echo "▶ Archiving $SCHEME…"
xcodebuild -project insomniac.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates archive >/dev/null

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
PLIST

echo "▶ Exporting App Store package…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" \
  -allowProvisioningUpdates >/dev/null

[ -f "$PKG" ] || { echo "✗ export produced no .pkg"; exit 1; }

echo "▶ Package signature:"
pkgutil --check-signature "$PKG" | sed -n '2,4p'

# Sanity: the sandbox must actually be on, or App Review rejects it.
APP="$ARCHIVE/Products/Applications/Insomniac.app"
if ! codesign -d --entitlements - "$APP" 2>&1 | grep -q "app-sandbox"; then
  echo "✗ the exported app is not sandboxed — App Store will reject it"; exit 1
fi
echo "✓ Sandbox entitlement present"

echo "▶ Validating with App Store Connect…"
xcrun altool --validate-app -f "$PKG" -t macos \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"

if [ "$UPLOAD" = "1" ]; then
  echo "▶ Uploading…"
  xcrun altool --upload-app -f "$PKG" -t macos \
    --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"
  echo "✓ Uploaded. It appears in App Store Connect → TestFlight/Builds after"
  echo "  Apple finishes processing (usually 5–30 minutes)."
else
  echo "✓ Validated only → $PKG"
fi
