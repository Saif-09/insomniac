#!/usr/bin/env bash
#
# screenshots.sh — regenerate the Mac App Store screenshots.
#
# Output: AppStore/screenshots/*.png at 2560×1600, ready to upload.
#
# Built from the **App Store** target on purpose. The direct-download build has
# rows the store build doesn't (Automatic updates, Silent toggling), and
# screenshots showing features the shipped app lacks are both a review risk and
# a lie to the customer. Generating from insomniac-mas keeps them honest by
# construction.
#
# Debug configuration, because the generator and the `poseForScreenshot` hooks
# are `#if DEBUG` — they cannot exist in a shipping binary.
#
# Sandbox is disabled for this run only: it would block writing the PNGs, and it
# has no bearing on how the UI draws. APP_STORE (which decides the feature set)
# is still defined, which is the part that matters.
#
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$PWD/AppStore/screenshots"
DD="$PWD/build/screenshots-dd"
APP="$DD/Build/Products/Debug-appstore/Insomniac.app"

echo "▶ Building the App Store target (Debug)…"
xcodebuild -project insomniac.xcodeproj -scheme insomniac-mas -configuration Debug \
  -derivedDataPath "$DD" -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO ENABLE_APP_SANDBOX=NO build >/dev/null

rm -rf "$OUT"; mkdir -p "$OUT"

echo "▶ Rendering…"
# `open` rather than running the binary directly: a bare exec never gets
# activation rights from the window server.
open -n "$APP" --env "INSOMNIAC_SCREENSHOTS=$OUT"

for _ in $(seq 1 40); do
  [ -f "$OUT/04-safety.png" ] && break
  sleep 1
done
sleep 1
pkill -f "Debug-appstore/Insomniac.app" 2>/dev/null || true

COUNT="$(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')"
[ "$COUNT" -gt 0 ] || { echo "✗ no screenshots produced"; exit 1; }

echo "✓ $COUNT screenshots → $OUT"
for f in "$OUT"/*.png; do
  printf '  %-22s ' "$(basename "$f")"
  sips -g pixelWidth -g pixelHeight "$f" | tail -2 | tr -d '\n' | tr -s ' '
  echo
done
