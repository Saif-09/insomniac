# Publishing insomniac

Insomniac ships two ways:

| | Direct download | Mac App Store |
|---|---|---|
| Target | `insomniac` | `insomniac-mas` |
| Bundle ID | `dev.saif.insomniac` | `dev.saif.insomniac.mas` |
| Signing | Developer ID Application, notarized | Apple Distribution + 3rd Party Mac Developer Installer |
| Sandbox | No | Yes |
| Keep-awake | IOKit assertion **+** `pmset disablesleep` via privileged helper | IOKit assertion only |
| Updates | Sparkle (appcast on GitHub Pages) | The App Store |
| Script | `./Scripts/package.sh` | `./Scripts/appstore.sh` |

Both build from the same sources; `APP_STORE` is defined only for the App Store
target, and everything the sandbox forbids is fenced behind `#if !APP_STORE`.

---

## Direct download (.dmg)

```bash
./Scripts/package.sh                    # archive → Developer ID → notarize → DMG
SKIP_NOTARIZE=1 ./Scripts/package.sh    # same, minus the notary round-trip
```

Output: `build/insomniac.dmg` — signed, hardened-runtime, notarized, stapled.
Verify with:

```bash
spctl -a -t open --context context:primary-signature -v build/insomniac.dmg
# → accepted / source=Notarized Developer ID
```

### Releasing

Order matters — publishing the appcast before the release asset exists points
every running copy of the app at a 404.

1. `./Scripts/package.sh`
2. Write `docs/release-notes/<version>.html` (shown inside Sparkle's update sheet).
3. Create the GitHub release, tag `v<version>`, attach `build/insomniac.dmg`.
4. `./Scripts/update_appcast.sh` → writes `docs/appcast.xml`.
5. Commit and push `docs/` (GitHub Pages serves the appcast).

### Why `archive`/`exportArchive` and not `codesign --force`

The bundle contains a privileged helper *and* `Sparkle.framework`, and Sparkle
nests XPC services that carry their own entitlements. Re-signing that from the
outside with `codesign --force` (no `--entitlements`) silently strips them: the
result passes `codesign --verify` and then fails to update. Exporting the
archive signs every nested component inside-out with the right identity and
entitlements.

### Notarization credentials

Stored once in the keychain as the `insomniac-notary` profile:

```bash
xcrun notarytool store-credentials insomniac-notary \
  --key ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8 \
  --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER_ID"
```

`ASC_KEY_ID` / `ASC_ISSUER_ID` come from App Store Connect → Users and Access →
Integrations → Keys (the issuer UUID sits above the key table). They're kept out
of this repo because it's public — neither is a secret on its own, but together
with a leaked `.p8` they're everything an attacker needs. Put them in your shell
profile; `Scripts/appstore.sh` reads them from the environment.

Confirm it works with `xcrun notarytool history --keychain-profile insomniac-notary`.

### Sparkle signing key

Updates are signed with an EdDSA key pair. The **public** half is in
`Config/Info-insomniac.plist` as `SUPublicEDKey`; the **private** half lives in
the login keychain and is never committed. Sparkle refuses any update whose
signature doesn't verify against the public key — which matters here
specifically because this app installs a privileged helper, so an appcast-host
compromise must not be enough to ship code.

**Back the private key up now** (`generate_keys -x`, from the Sparkle tools that
`update_appcast.sh` downloads into `build/sparkle-tools/`). If it is lost, no
existing installation can ever be updated again — they would all have to
reinstall by hand.

---

## Mac App Store (.pkg)

```bash
./Scripts/appstore.sh --no-upload   # build + validate
./Scripts/appstore.sh               # build + validate + upload
```

### Two one-time manual steps

Both are Apple-side limitations, not bugs in the scripts:

1. **The app record must be created in the web UI.** The App Store Connect API
   refuses it: `POST /v1/apps` → *"The resource 'apps' does not allow 'CREATE'"*.
   Create it once (see `docs/app-store-listing.md` for every field). Until it
   exists, upload fails with *"Cannot determine the Apple ID from Bundle ID"*,
   which reads like a signing problem and isn't.

2. **Signing runs off the Xcode-logged-in Apple ID, not the API key.** The API
   key notarizes and uploads fine, but lacks permission to create bundle IDs or
   distribution profiles — passing `-authenticationKey*` to `exportArchive`
   fails with *"Cloud signing permission error"*. Grant that key Admin access
   in App Store Connect → Users and Access → Integrations if you want the
   script to be self-contained on a machine where Xcode isn't signed in.

### What the sandboxed build gives up

- The system-wide `SleepDisabled` flag and the sleep-timer readouts — no public
  API exists (`IOPMCopySystemPowerSettings` / `IOPMCopyPMPreferences` are
  private), so the System tab omits those rows.
- The privileged helper, and therefore the "silent toggling" setup row.
- Crash recovery, which is meaningless without a persistent flag: an IOKit
  assertion dies with the process.
- Sparkle, and the quarantine self-heal.

It keeps the timer, both safety cutoffs, the advisory, weather, notifications,
open-at-login, and the "keeping your Mac awake" list (`IOPMCopyAssertionsByProcess`
is public and sandbox-safe).

In practice that costs modern laptop users very little: `disablesleep` is the
only thing that can hold a Mac through a lid close, and on Apple Silicon it
can't do that either without clamshell mode.

---

## Notes

- **Never sandbox the direct-download target.** It breaks `pmset` and the
  SMAppService helper.
- `CONFIGURATION_BUILD_DIR` pins the App Store target to its own
  `Release-appstore` products directory. Without it, `Insomniac.app` and
  `insomniac.app` collide on a case-insensitive filesystem and the second build
  silently overwrites the first.
- Hosting: any static host works. Serve the stapled `.dmg`; no special server
  config needed.
