# insomniac

Keep your Mac awake with the **lid closed** — safely. A menu-bar utility that
prevents clamshell sleep (no external display required) and actively advises how
long that's safe based on the machine's live thermal state, auto-stopping before
things get too hot.

### 🌙 [**Download &amp; install → saif-09.github.io/insomniac**](https://saif-09.github.io/insomniac/)

The landing page has the download and a one-minute setup guide. Direct link to
the latest build:
[**insomniac.dmg**](https://github.com/Saif-09/insomniac/releases/latest/download/insomniac.dmg)
(unsigned test build — see the setup steps on the page).

> macOS clamshell sleep is **not** prevented by `caffeinate` or IOKit power
> assertions unless you have an external display, power, and keyboard attached.
> insomniac uses `pmset -a disablesleep 1`, which works with nothing attached —
> and pairs it with a thermal safety layer because a closed lid restricts
> airflow.

---

## Status

All four PRD milestones are implemented:

| Milestone | What | Status |
|-----------|------|--------|
| **M1** | Core keep-awake: toggle, auto-off timer + countdown, safe restore, crash recovery, menu-bar-only UI | ✅ |
| **M2** | Thermal advisory + live safety cutoff (built on `ProcessInfo.thermalState`) | ✅ |
| **M3** | Weather ambient modifier (Open-Meteo + automatic IP geolocation, graceful degradation) | ✅ |
| **M4** | `SMAppService` privileged helper + XPC for silent toggling (no password prompt) | ✅ (see [Privilege model](#privilege-model)) |

### Decisions (from the PRD's open questions)

1. **Minimum macOS:** 14.0 Sonoma.
2. **Default thermal cutoff:** `serious` (conservative).
3. **"Indefinite":** not offered — the longest auto-off is a hard **8-hour cap**.
4. **Temperature in UI:** risk level + advisory text only, no degree readout
   (honest given Apple Silicon has no supported CPU-temp API).
5. **Distribution:** Developer-ID-signed, notarized direct download (the core
   feature is sandbox-incompatible, so this is not a Mac App Store build).

---

## Architecture

Menu-bar-only SwiftUI app (`MenuBarExtra`, `LSUIElement = true`, no Dock icon).
The sandbox is **disabled** — `pmset disablesleep` requires root.

```
insomniac/
  insomniacApp.swift        @main scene; menu-bar label reflects state/risk
  Core/
    AppController.swift      single source of truth: session, timer, cutoff, wiring
    AppDelegate.swift        applicationShouldTerminate → restore sleep before exit
    Preferences.swift        UserDefaults-backed settings
    Models.swift             AutoOffDuration, RiskLevel, StopReason, Session
  Power/
    PowerControlling.swift   protocol + error type (privilege model abstraction)
    AppleScriptPowerController.swift   Phase 1: admin password prompt
    PowerControlService.swift          picks helper-if-installed, else AppleScript
    SystemSleepState.swift             read-only `pmset -g` probe (crash recovery)
  Monitors/
    ThermalMonitor.swift     ProcessInfo.thermalState + change notification
    PowerSourceMonitor.swift IOKit AC/battery
    LoadMonitor.swift        coarse sustained-load read (getloadavg / core count)
  Advisory/
    ThermalAdvisor.swift     combines signals → risk + suggested duration + message
  Weather/
    IPGeolocationService.swift  permission-free approx. location (GeoJS → freeipapi)
    WeatherService.swift     Open-Meteo current temperature
  Notifications/
    NotificationManager.swift  auto-off notifications
  UI/
    MenuContent.swift        the dropdown panel
    SettingsSection.swift    cutoff level, weather, helper install
    RiskLevel+UI.swift       colors/symbols for the advisory
  Privileged/                APP-side helper client
    HelperClient.swift       XPC client (conforms to PowerControlling)
    HelperInstaller.swift    SMAppService register/approve/unregister

Shared/
    HelperProtocol.swift     XPC contract — compiled into BOTH targets

Helper/                       PRIVILEGED HELPER TARGET (com.apple.product-type.tool)
    main.swift               NSXPCListener bootstrap
    HelperTool.swift         validates client signature, runs pmset as root
    dev.saif.insomniac.helper.plist   launchd plist (embedded in app bundle)
```

The whole app talks to one `PowerControlling` abstraction. The Phase-1
AppleScript path and the Phase-4 XPC helper are interchangeable behind it.

### Safety invariants

- **Never leave sleep disabled.** Restored on toggle-off, auto-off, thermal
  cutoff, and quit/logout (`applicationShouldTerminate` defers exit until the
  async restore completes). A hard crash can't be intercepted → **crash
  recovery** on next launch detects `disablesleep == 1` with no active session
  and offers to reset it.
- **Live thermal cutoff** (the most reliable safety mechanism): if `thermalState`
  escalates to the configured level (`serious` by default) during a session,
  the app auto-stops and notifies. This beats any up-front prediction because we
  can't read live die temperature on Apple Silicon.
- **Live battery cutoff:** on battery power, if the charge drops to/below the
  configured threshold (default 20%) during a session, the app auto-stops and
  notifies — so the Mac can sleep normally before the battery runs out. Driven by
  IOKit power-source changes and backstopped by the 1 s countdown tick.
- **Hard auto-off cap.** No "indefinite" — sessions always end.

---

## Build & run

Requires Xcode 26.x and macOS 14+.

```bash
# Build (Debug)
xcodebuild -project insomniac.xcodeproj -scheme insomniac \
  -configuration Debug -destination 'platform=macOS' build

# Or just open it
open insomniac.xcodeproj
```

Run from Xcode (▶). The icon appears in the menu bar; there is no window and no
Dock icon. Click it for the toggle, countdown, and advisory.

> **First run will request** Notifications and (if weather is enabled) Location.
> Both are optional — the app works without them. Toggling **On** prompts for
> your admin password unless the privileged helper is installed.

---

## Privilege model

**Phase 1 (default, works immediately):** toggling runs
`pmset -a disablesleep <0|1>` via AppleScript's *"with administrator
privileges"*, so macOS shows its standard password dialog.

**Phase 4 (silent, optional):** install the `SMAppService` privileged helper
from **Settings → Silent toggling → Install helper**. After a one-time approval
in **System Settings → General → Login Items & Extensions**, toggling is silent
(no password). The app auto-prefers the helper once it's enabled.

The helper is a root daemon, so it only accepts XPC connections that satisfy a
code-signing requirement pinned to this app's identifier **and** Team ID
(`dev.saif.insomniac` / `DTQF9KJP6S`). See `Helper/HelperTool.swift`.

### What requires a real signing identity / device (not verifiable headlessly)

The project **builds and signs** both targets and embeds the helper correctly
(`Contents/MacOS/dev.saif.insomniac.helper` + `Contents/Library/LaunchDaemons/…`).
The following only exercise on a real machine with your Developer ID:

- Actual helper **registration/approval** and silent XPC toggling.
- The real **lid-closed-stays-awake** behavior.
- Live **thermal cutoff** firing under sustained load.

### Helper status: `.notFound` is normal before installing

For an `SMAppService` **daemon**, `SMAppService.daemon(...).status` returns
`.notFound` until the daemon has been `register()`-ed — the system simply has no
Background Task Management record for it yet. This is **not** a packaging error
(it does not mean the plist or executable is missing). The app treats `.notFound`
and `.notRegistered` identically and shows the **Install helper** affordance.

To actually register and reach `.enabled`, the app should be run from
**`/Applications`** (not Xcode's DerivedData), as a properly signed bundle —
ideally Developer-ID-signed + notarized. A debug build run from DerivedData is
Gatekeeper-rejected and is an unreliable place to register a privileged root
daemon. Recommended flow:

```bash
# 1. Build a PROPERLY SIGNED bundle. Build in Xcode (Product → Build), or via CLI
#    WITHOUT CODE_SIGNING_ALLOWED=NO (that flag produces an ad-hoc binary that
#    SMAppService refuses, failing register() with errSecCSBadResource / -67056):
xcodebuild -project insomniac.xcodeproj -scheme insomniac -configuration Debug \
  -destination 'platform=macOS' build

# 2. Copy to /Applications with `ditto`, NOT `cp -R`. cp -R does not preserve a
#    signed .app bundle's sealed resources and corrupts the signature.
killall insomniac 2>/dev/null
rm -rf /Applications/insomniac.app
ditto ~/Library/Developer/Xcode/DerivedData/insomniac-*/Build/Products/Debug/insomniac.app /Applications/insomniac.app

# 3. Launch the installed copy (not the Xcode Run button):
open /Applications/insomniac.app
# In the app: Settings → Silent toggling → Install helper.
# If it asks for approval: System Settings → General → Login Items & Extensions
# → enable insomniac under "Allow in the Background".

# Sanity check the copy is real-signed (not adhoc) before installing the helper:
codesign -dv /Applications/insomniac.app 2>&1 | grep -E 'TeamIdentifier|Signature'
# Want: TeamIdentifier=DTQF9KJP6S  and  a real Signature (NOT "Signature=adhoc").
```

Verify registration state:

```bash
launchctl print system/dev.saif.insomniac.helper   # "Could not find service" until registered
sudo sfltool dumpbtm | grep -i insomniac           # lists a record once registered
```

---

## Distribution (Developer ID + notarization)

```bash
# Archive
xcodebuild -project insomniac.xcodeproj -scheme insomniac \
  -configuration Release archive -archivePath build/insomniac.xcarchive

# Export Developer-ID-signed app (needs an ExportOptions.plist with
# method = developer-id), then notarize + staple:
xcrun notarytool submit insomniac.zip --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple insomniac.app
```

Hardened Runtime is enabled on both targets (required for notarization). The
embedded helper is re-signed on copy (`CodeSignOnCopy`).

---

## Privacy

No telemetry, no data collection. When the local-weather nudge is on, insomniac
sends your device's public IP to a third-party geolocation provider (GeoJS, with
freeipapi.com as a fallback) to estimate your city — no GPS, no account, no
permission prompt — then sends only those approximate coordinates to Open-Meteo
for the temperature. Turn off the weather toggle to send nothing at all; the
advisory still runs on thermal state, charger, and load. (IP geolocation is
city-level and can be wrong on a VPN — fine for a soft ambient nudge.)
```
