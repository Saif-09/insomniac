# App Store Connect listing — Insomniac

Everything needed to fill in the App Store Connect record.

**The record already exists** — "Insomniac - Sleep Blocker", app ID `6801908392`,
bundle ID `app.ziyarex.insomniac.mas`. It was created by Xcode's *Distribute App*
flow. What follows is the metadata still to be filled in, plus a record of how it
was made.

> Xcode **can** create app records, via a privileged endpoint the public API
> doesn't expose — `POST /v1/apps` on the App Store Connect API is refused
> outright (*"the resource 'apps' does not allow 'CREATE'"*), so a script can't
> do it, but Product → Archive → Distribute App can.
>
> Note that Xcode's creation step is not idempotent: run it twice and the second
> attempt fails with *"The SKU/Bundle ID/name you entered has already been
> used"*, which looks like a failure but actually means the first one worked.
> Cancel and re-run Distribute App; it will find the record and go straight to
> upload.

## Creating the record (if it ever needs recreating)

<https://appstoreconnect.apple.com> → **Apps → + → New App**

| Field | Value |
|---|---|
| Platform | macOS |
| Name | `Insomniac - Sleep Blocker` |
| Primary language | English (U.S.) |
| Bundle ID | `app.ziyarex.insomniac.mas` |
| SKU | `app.ziyarex.insomniac.mas` |
| User access | Full Access |

The bundle ID is deliberately **not** `dev.saif.insomniac` — that one belongs to
the direct-download build. Two installed apps sharing an identifier confuses
LaunchServices, and this matches the convention already used for OreoNotch
(`app.ziyarex.notch` / `app.ziyarex.notch.mas`).

## Category

- Primary: **Utilities**
- Secondary: *(leave empty)*

## Subtitle (30 char max)

```
Keep your Mac awake, safely
```

## Promotional text (170 char max)

```
One switch keeps your Mac awake for as long as you choose — and stops on its own if it gets hot, the battery runs low, or your timer ends.
```

## Description

```
Insomniac keeps your Mac awake while it works — downloads, renders, builds,
backups, long uploads — and then gets out of the way.

Flip one switch in the menu bar and your Mac stops falling asleep. Pick how
long: 15 minutes, an hour, two hours, or any custom length up to eight hours.
When the timer ends, normal sleep comes back automatically. You never have to
remember to turn it off.

SAFE BY DEFAULT

Keeping a laptop awake is easy. Doing it without cooking the machine or
draining the battery is the part most apps skip. Insomniac watches the things
that matter and stops the session on its own:

• Thermal cutoff — if your Mac reaches a serious or critical thermal state,
  the session ends so the machine can cool down.
• Low-battery cutoff — on battery power, the session ends at the percentage
  you choose, so your Mac can sleep normally before it dies.
• A live advisory that reads your current thermal state, power source, system
  load and (optionally) local temperature, then suggests a session length that
  suits the conditions.

HONEST ABOUT WHAT IT CAN'T DO

Most keep-awake apps quietly promise to keep working with the lid closed.
On modern Macs that isn't true — closing the lid puts the machine to sleep, and
no app can override it unless you're in clamshell mode with an external
display on power. Insomniac tells you that up front instead of failing
silently, and offers to turn the screen off for you when the lid closes.

SEE WHAT'S REALLY GOING ON

A System tab shows the truth straight from macOS: every app and process
currently holding your Mac awake, its power source, and its thermal state. It's
often the fastest way to find out why your Mac isn't sleeping when you want it
to.

QUIET BY DESIGN

Insomniac lives in the menu bar, not the Dock. No account, no sign-in, no
analytics, no tracking. It collects nothing about you.
```

## Keywords (100 char max, comma-separated)

```
awake,caffeine,sleep,insomnia,nosleep,display,screen,timer,menubar,battery,thermal,download,render
```

## URLs

- Privacy Policy URL (**required**): `https://insomniac.ziyarex.com/privacy.html`
- Support URL (**required**): `https://insomniac.ziyarex.com/`
- Marketing URL: `https://insomniac.ziyarex.com/`

## App Privacy

Answer **"No, we do not collect data from this app."**

That is accurate: no analytics SDK, no account, nothing persisted off-device.
One caveat to be aware of when answering — the optional weather advisory sends
the user's approximate location to a third-party service:

- Approximate location comes from the user's IP via an IP-geolocation lookup
  (no Location Services permission prompt, city-level at best).
- It is used only to fetch an ambient temperature for the advisory.
- It is off if the user turns "Use local weather" off in Settings.
- Nothing is stored, and it isn't linked to any identity.

Apple's questionnaire treats "data not collected by you and not linked to the
user" as not-collected, so "No" is the correct answer — but if you'd rather not
argue the point during review, turning `weatherEnabled` off by default (in
`Preferences.swift`) removes the question entirely.

## Export compliance

**Does your app use encryption?** → No.

The app makes HTTPS requests, which is exempt under the standard
"uses only encryption provided by the operating system" exemption. Answering
this in App Store Connect once sets `ITSAppUsesNonExemptEncryption` for you.

## Age rating

4+ — no objectionable content of any kind.

## Screenshots

Four, already generated, in `AppStore/screenshots/` at 2560×1600 (an accepted
size). Regenerate with `./Scripts/screenshots.sh`.

| File | Shows |
|---|---|
| `01-stay-awake.png` | A running session — the switch, countdown ring and advisory |
| `02-auto-off.png` | The auto-off picker — the timer that always turns it back |
| `03-system.png` | The System tab — what's keeping the Mac awake |
| `04-safety.png` | Settings — the thermal and low-battery cutoffs |

They render the app's real SwiftUI views, and are built from the **App Store**
target so they can only ever show features that build actually has.

## Review notes

```
Insomniac is a menu-bar utility that prevents idle sleep using a standard IOKit
power assertion (IOPMAssertionCreateWithName / PreventUserIdleSystemSleep),
released automatically when the session ends or the app quits.

There is no sign-in and no account — every feature is available immediately on
launch.

The app has no Dock icon by design (LSUIElement); it appears as a moon icon in
the menu bar at the right side of the screen. Click it to open the panel with
the "Stay Awake" switch.

The optional "Use local weather" setting performs an IP-based geolocation
lookup and a public weather API request to fetch an ambient temperature used in
the session-length advisory. It requires no Location Services permission and
can be turned off in Settings.
```
