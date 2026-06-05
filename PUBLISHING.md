# Publishing insomniac

insomniac **cannot** ship on the Mac App Store: its core feature (`pmset
disablesleep` via a privileged helper) is incompatible with the App Sandbox the
store requires. So distribution is a **Developer-ID-signed, notarized direct
download** (a `.dmg`). This is the standard path for utilities like this.

## TL;DR

```bash
./Scripts/package.sh                       # build + DMG (un-notarized on a free account)
NOTARY_PROFILE=insomniac-notary ./Scripts/package.sh   # full notarized DMG (paid program)
```

Output: `build/insomniac.dmg`.

---

## Where things stand on this machine

- ✅ App builds, signs (Apple Development), and runs.
- ✅ App icon set.
- ❌ **No "Developer ID Application" certificate** installed.
- ❌ **No notarization credentials** configured.
- ❌ Account is a **free Apple ID** — so the two items above aren't obtainable yet.

### What a free Apple ID can do *today*
`./Scripts/package.sh` produces a working `build/insomniac.dmg`, but it is **not
notarized**. Anyone you send it to will get Gatekeeper's "can't be opened"
warning and must **right-click the app → Open → Open** the first time (or you can
tell them to run `xattr -dr com.apple.quarantine /Applications/insomniac.app`).
Fine for yourself and a few testers; not acceptable for public distribution.

---

## To publish properly (one-time setup, needs the paid program)

### 1. Join the Apple Developer Program
$99/yr at <https://developer.apple.com/programs/>. A free Apple ID cannot create
a Developer ID certificate or notarize.

### 2. Create a "Developer ID Application" certificate
Xcode → **Settings → Accounts** → select your team → **Manage Certificates…** →
**＋ → Developer ID Application**. Confirm it's installed:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 3. Store notarization credentials once
Create an app-specific password at <https://account.apple.com> (Sign-In &
Security → App-Specific Passwords), then:

```bash
xcrun notarytool store-credentials insomniac-notary \
  --apple-id "you@example.com" \
  --team-id "DTQF9KJP6S" \
  --password "abcd-efgh-ijkl-mnop"   # the app-specific password
```

### 4. Build the notarized DMG

```bash
NOTARY_PROFILE=insomniac-notary ./Scripts/package.sh
```

The script will: re-sign the app + helper with Developer ID and the Hardened
Runtime, build the DMG, submit to Apple's notary service, wait, and staple the
ticket. The result is a clean double-clickable download.

### 5. Verify before shipping

```bash
spctl -a -t open --context context:primary-signature -v build/insomniac.dmg   # → accepted
codesign --verify --deep --strict --verbose=2 "/Volumes/insomniac/insomniac.app"
```

---

## Notes

- **Hardened Runtime** is already enabled on both targets (required for
  notarization).
- The **privileged helper** is signed inside-out (helper first, then app) so the
  app's signature seals it correctly.
- The app is **not sandboxed** by design — keep it that way; sandboxing breaks
  `pmset` and the SMAppService helper.
- Hosting: any static host works (your site, GitHub Releases, etc.). Serve the
  stapled `.dmg`; no special server config needed.
