#!/usr/bin/env bash
#
# update_appcast.sh — sign the built DMG for Sparkle and write docs/appcast.xml.
#
# Run after ./Scripts/package.sh. Sparkle's `generate_appcast` reads the DMG,
# signs it with the EdDSA private key in your login keychain, and emits the
# appcast entry (version, length, signature, release notes) that existing users'
# copies of Insomniac poll for.
#
# The download URL points at the *versioned* GitHub release tag, not
# releases/latest — an appcast entry has to keep resolving to the exact build it
# was signed for, and a "latest" URL silently starts pointing somewhere else the
# next time you ship.
#
# Publishing order matters:
#   1. ./Scripts/package.sh
#   2. create the GitHub release (tag vX.Y.Z) and attach build/insomniac.dmg
#   3. ./Scripts/update_appcast.sh
#   4. commit + push docs/appcast.xml (GitHub Pages serves it)
#
# Shipping the appcast before the release asset exists points every running copy
# of the app at a 404.
#
set -euo pipefail
cd "$(dirname "$0")/.."

DMG="build/insomniac.dmg"
SPARKLE_VERSION="2.9.5"
TOOLS="build/sparkle-tools"
STAGING="build/appcast-staging"
REPO="Saif-09/insomniac"

[ -f "$DMG" ] || { echo "✗ $DMG not found — run ./Scripts/package.sh first"; exit 1; }

VERSION="$(defaults read "$PWD/build/export/insomniac.app/Contents/Info" CFBundleShortVersionString)"
echo "▶ Version $VERSION"

# --- Fetch Sparkle's tools (cached in build/, not committed) -----------------
if [ ! -x "$TOOLS/bin/generate_appcast" ]; then
  echo "▶ Fetching Sparkle $SPARKLE_VERSION tools…"
  mkdir -p "$TOOLS"
  curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
    | tar -xJ -C "$TOOLS"
fi

# --- Stage the DMG + its release notes --------------------------------------
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp "$DMG" "$STAGING/insomniac-${VERSION}.dmg"

# generate_appcast picks up <archive-basename>.html as that version's release
# notes and inlines them into the appcast, which is what Sparkle shows in its
# "a new version is available" sheet.
if [ -f "docs/release-notes/${VERSION}.html" ]; then
  cp "docs/release-notes/${VERSION}.html" "$STAGING/insomniac-${VERSION}.html"
else
  echo "⚠ No docs/release-notes/${VERSION}.html — the update sheet will have no notes."
fi

# --- Generate + sign ---------------------------------------------------------
echo "▶ Generating appcast…"
"$TOOLS/bin/generate_appcast" \
  --download-url-prefix "https://github.com/${REPO}/releases/download/v${VERSION}/" \
  --link "https://saif-09.github.io/insomniac/" \
  --maximum-versions 5 \
  "$STAGING"

cp "$STAGING/appcast.xml" docs/appcast.xml
echo "✓ Wrote docs/appcast.xml"
echo
echo "Check the enclosure URL resolves before pushing:"
grep -o 'url="[^"]*"' docs/appcast.xml | head -3
echo
echo "Then: git add docs/appcast.xml && git commit && git push"
