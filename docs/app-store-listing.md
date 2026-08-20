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
Auto-off and thermal safety
```

> Was "Keep your Mac awake, safely". App Review rejected that under
> **5.2.5** for trademark use of "Mac" in the subtitle. Apple allows
> referential use inside a description, but not in the short naming
> fields — so no Apple mark appears in the name or subtitle at all now.

## Promotional text (170 char max)

```
Most keep-awake apps are one switch. Insomniac watches heat, battery and load, tells you how long is safe, and ends the session itself before anything cooks.
```

## Description

```
Every keep-awake utility can block sleep. Insomniac is built around the part
they skip: knowing when to stop.

WHAT MAKES IT DIFFERENT

• Thermal cutoff. Insomniac watches the live thermal state and ends the session
  by itself when the machine reaches a serious or critical level, so a long job
  behind a closed lid can't quietly cook the hardware.

• Low-battery cutoff. On battery power, the session ends at a percentage you
  choose, so the machine can sleep normally instead of running flat.

• A safety advisor. Before you start, Insomniac reads the current thermal state,
  power source, system load and — if you want it — the outdoor temperature where
  you are, then rates the risk and suggests a session length to match. Nothing
  else in this category reasons about whether staying awake is a good idea right
  now.

• A power-assertion inspector. A System tab lists every process currently
  holding the machine awake, with the kind of assertion each one holds, read
  straight from the operating system. It is usually the fastest way to answer
  "why won't this thing sleep?" — and it works whether or not Insomniac is the
  one responsible.

HOW IT WORKS

Flip one switch in the menu bar. Pick how long: 15 minutes, an hour, two hours,
or any custom length from ten minutes to eight hours. When the timer ends,
normal sleep comes back automatically. There is no indefinite mode — sessions
always end, by design.

Close the lid during a session and Insomniac can turn the screen off for you.

HONEST ABOUT THE LID

Many apps in this category imply they keep a laptop running with the lid shut.
On Apple silicon that is not true: the lid sensor forces sleep, and no software
overrides it outside clamshell mode with an external display on power. Insomniac
says so in its own interface rather than failing silently, and points you at
what does work.

QUIET BY DESIGN

It lives in the menu bar, not the Dock. No account, no sign-in, no analytics, no
tracking, no data collection of any kind. Open source.
```

## Keywords (100 char max, comma-separated)

```
awake,caffeine,nosleep,insomnia,thermal,overheat,battery,timer,menubar,assertion,display,idle
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

| Order | File | Shows |
|---|---|---|
| 1 | `01-safety.png` | The thermal and low-battery cutoffs |
| 2 | `02-advisory.png` | The risk read and suggested session length |
| 3 | `03-system.png` | The power-assertion inspector |
| 4 | `04-timer.png` | The auto-off timer and the switch |

They render the app's real SwiftUI views, and are built from the **App Store**
target so they can only ever show features that build actually has.

**The order is the point.** The rejected set opened on "One switch. Your Mac
stays awake." — which is what every keep-awake app on the store says, and is
exactly the impression that earned the 4.3(a) duplicate finding. The
differentiators now lead and the generic switch comes last. No headline
contains an Apple trademark either, since screenshot text is metadata under
5.2.5 as much as the subtitle is.

## Review notes

```
HOW TO REACH THE INTERFACE
The app has no Dock icon by design (LSUIElement). After launch, look for a moon
icon in the menu bar at the top-right of the screen and click it to open the
panel. A welcome window on first launch points at it. There is no sign-in and no
account; every feature is available immediately.

WHAT DISTINGUISHES THIS APP (re: guideline 4.3)
Blocking sleep is one IOKit call and is common to this category. Insomniac's
functionality is the safety layer around it, none of which is template or
boilerplate:

1. Thermal cutoff — the app subscribes to thermal state changes and terminates
   its own session at a user-selected level (serious or critical).
2. Low-battery cutoff — on battery, the session self-terminates at a
   user-selected percentage, driven by IOKit power-source notifications.
3. Session-length advisor — combines thermal state, power source, system load
   and optional local temperature into a risk rating and a recommended
   duration, and refuses to start a session that would immediately trip the
   battery cutoff.
4. Power-assertion inspector — the System tab enumerates every process holding
   a sleep-preventing assertion via IOPMCopyAssertionsByProcess, showing the
   assertion type per process. This works regardless of whether Insomniac is
   running a session.
5. Honest clamshell reporting — the app detects whether lid-closed operation is
   actually achievable on the current hardware and configuration, and says so,
   rather than implying capability it does not have.

The source is original and written by one developer; it is public at
https://github.com/Saif-09/insomniac for verification. It is not built from a
purchased or repackaged template, and this is the only app of its kind on this
account.

WEATHER / NETWORK
The optional "Use local weather" setting performs an IP-based geolocation
lookup and a public weather API request to fetch an ambient temperature used by
the advisor. It requires no Location Services permission and can be turned off
in Settings. No other network requests are made.
```

---

## Reply to App Store Review — submission 88a6430a-7b19-4361-ac7e-03b3197f1580

Paste into the Resolution Center thread when resubmitting. A 4.3(a) finding is
rarely resolved by a silent resubmit; the reviewer needs to be told what to look
at and where.

```
Thank you for the detailed review. We have addressed both items.

GUIDELINE 5.2.5 — TRADEMARK

The subtitle was "Keep your Mac awake, safely". It has been changed to:

    Auto-off and thermal safety

No Apple trademark now appears in the app name, subtitle, keywords, or in any
screenshot text. Where the description refers to Apple silicon, it does so
descriptively and only to explain a hardware limitation the app reports to the
user, not to suggest any association with or endorsement by Apple.

GUIDELINE 4.3(a) — DUPLICATE FUNCTIONALITY

We understand the concern: preventing idle sleep is a single IOKit call, many
apps do it, and our previous metadata led with exactly that generic capability
("One switch. Your Mac stays awake."). That framing misrepresented the app, and
we have replaced it.

The functionality that distinguishes Insomniac is the safety and diagnostic
layer around the assertion, not the assertion itself:

1. Thermal cutoff. The app observes thermal state changes and terminates its
   own session automatically at a user-selected level (serious or critical). A
   long unattended job cannot leave the machine held awake while it overheats.

2. Low-battery cutoff. On battery power the session self-terminates at a
   user-chosen percentage, driven by IOKit power-source notifications, so the
   machine sleeps normally rather than running flat.

3. Session-length advisor. Before a session starts, the app combines live
   thermal state, power source, system load and optionally the local outdoor
   temperature into a risk rating and a recommended duration. It also refuses
   to start a session that would immediately trip the battery cutoff, rather
   than starting and stopping.

4. Power-assertion inspector. The System tab enumerates every process currently
   holding a sleep-preventing assertion, with the assertion type for each,
   using IOPMCopyAssertionsByProcess. This is a diagnostic for "why will this
   machine not sleep?" and functions whether or not our own session is running.

5. Honest hardware reporting. The app determines whether lid-closed operation
   is actually possible on the current hardware and configuration and states
   this plainly in its interface, instead of implying a capability the hardware
   does not provide.

There is also no indefinite mode: every session has a bounded duration, by
design.

The screenshots have been reordered so these capabilities are what a customer
sees first, with the generic on/off control last.

On the specific factors listed in the rejection: the app is not built from a
purchased or repackaged template, shares no source or assets with any other
submission, and is the only app of this kind on our account. The complete
source is public at https://github.com/Saif-09/insomniac and can be inspected
to verify all of the above.

We would be glad to answer any further questions.
```
