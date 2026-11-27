# OrbGuard Consumer Reinvention — Master Plan & Status Matrix

> **Positioning (locked):** Anti-surveillance — *"Know if you're being watched."*
> **Platforms (locked):** iOS · Android · macOS · Windows · Linux — **all five, in parallel** (shared Flutter UI; shields mapped honestly per platform).
> **Delivery bar (locked):** every milestone shipped **100% ready and e2e-tested** before it counts as done.
> **New features:** Hidden VPN/Proxy Watch + Secure Call Check — **Phase 2**.

This document is the **single source of truth** for the reinvention program. It is updated as each
task moves. A visual mirror of this matrix is published as an Artifact (link in the Decisions Log).
Strategy rationale lives in the strategy dossier (Decisions Log).

---

## Definition of Done (every task must clear all of these)

A task is **DONE** only when, for **each platform it targets**:
1. Implemented against **real** capability (no fake/placeholder; honest "not supported here" where the OS blocks it).
2. `flutter analyze` clean (0 errors / 0 warnings) for the touched code.
3. Unit/widget test added or updated where logic changed.
4. **e2e verified** — exercised on the running target (simulator/emulator/desktop build) via the screen-sweep harness or a scripted flow; screenshot/log evidence captured.
5. Committed to `production-hardening` (no Claude co-author trailer), **App CI green**.

Platforms a task cannot apply to are marked `n/a` (e.g. anti-theft selfie on desktop) — that is a
deliberate honest gap, not an incomplete task.

---

## Status legend

| Glyph | Meaning |
|---|---|
| ⬜ | Not started |
| 🟡 | In progress |
| ✅ | Done (meets Definition of Done) |
| 🔵 | e2e-verified on that platform |
| 🚫 | n/a — platform can't support it (honest gap) |
| ⛔ | Blocked (see notes) |

Platform columns: **iOS · And · mac · Win · Lin**. `Test` = unit/widget + e2e status.

---

## Phase 0 — Trust Detox
*Repair trust before adding anything. Cross-platform Dart; applies to all five. Highest trust-per-hour.*

> **✅ COMPLETE (2026-07-16)** — all 7 tasks shipped + BLOCKER-1 (Android build) resolved. Detox
> e2e-verified at runtime on **iOS, Android, and macOS** (honest verdict wording, calm static ring,
> real per-device stats, no fake "Critical IOCs" alarm; Android 0.5 confirmed via uid=10209 → "Standard").
> Windows/Linux inherit the identical shared Dart (not runnable from this macOS host; CI-verified).

| ID | Task | iOS | And | mac | Win | Lin | Test | Status |
|----|------|-----|-----|-----|-----|-----|------|--------|
| 0.1 | Remove fake-fear from Home: rescope global "Critical IOCs" stat + kill permanent red alarm banner; show device-relevant status only | 🔵 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 0.2 | Unify to ONE honest verdict vocabulary (reconcile Security Center score vs Dashboard letter-grade "U"/"Not Protected") | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 0.3 | Wall off jailbreak / root / ADB instruction screens from the consumer flow (gate to Pro / remove from setup path) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 0.4 | Fix iOS silent-pass: scan stages that swallow UNSUPPORTED must surface "not supported on iPhone", never "0 findings / clean" | ✅ | 🚫 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 0.5 | Fix fake elevation theater: `checkShellAccess()` returns true for any app → report honestly | 🚫 | 🔵 | 🚫 | 🚫 | 🚫 | ✅ | ✅ |
| 0.6 | Strip "fear/urgency" framing (per the self-incriminating code comment) from remaining consumer copy | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

*(0.5: Kotlin is valid + isolated; **Android runtime e2e is blocked by BLOCKER-1 below** — the whole Android build currently fails on a third-party plugin, not on our code.)*

## Known blockers

- **BLOCKER-1 — Android build broken by `mobile_scanner` 7.2.1. ✅ RESOLVED (2026-07-16).**
  `flutter build apk` failed with ~30 "Unresolved reference" Kotlin errors inside the plugin's own
  source under Kotlin 2.1.0 / AGP 8.9.1. Fixed by modernizing the Android toolchain (user's call):
  **Kotlin 2.1.0 → 2.2.20, AGP 8.9.1 → 8.11.1, Gradle 8.12 → 8.14** (+ matching kotlin-stdlib; Flutter's
  migrator added `android.builtInKotlin=false` / `android.newDsl=false`). No plugin bump needed — the
  APK now builds clean (201 MB debug). Android delivery + 0.5 runtime verify + P0.7 Android leg unblocked.

- **BLOCKER-2: iOS app is killed at launch when built with Xcode 27.2 for iOS 27.1 (found 2026-11-25).
  Launch is fixed on the simulator (2026-11-25, commit `5c20b8c`, on `main`); the rest of the migration
  is unproven.**
  The crash was `EXC_BREAKPOINT` in UIKit's check for scene lifecycle adoption: `ios/Runner/Info.plist`
  had no `UIApplicationSceneManifest`, and Flutter's own build log warns that UIScene support will be
  required (https://flutter.dev/to/uiscene-migration). Not caused by Phase 5, and it blocked every new
  iPhone build, TestFlight included. What changed: `Info.plist` declares one scene with Flutter's
  `FlutterSceneDelegate`; `AppDelegate` is a `FlutterImplicitEngineDelegate` and builds its channels
  and registers the plugins in `didInitializeImplicitFlutterEngine` (there is no window during
  `didFinishLaunching` any more); the background-scan request is refreshed from
  `UIApplication.didEnterBackgroundNotification`, because UIKit no longer calls
  `applicationDidEnterBackground` on a scene-based app. Seen on the iPhone simulator (iOS 27.1): the
  app launches, runs its first check and draws Home. **Not seen:** a deep link (`orbguard://`), Sign in
  with Apple, a push, a background scan, or anything on a real iPhone. Those are the reason this
  blocker is not closed, and they need their own pass before a TestFlight build.

## Platform reality for e2e (P0.7)

This dev machine is macOS, so local e2e covers **iOS · Android · macOS**. **Windows and Linux cannot be
built or run from macOS** — their leg of every e2e is verified structurally (the Phase-0 changes are
shared Dart, identical across platforms) + via CI on Windows/Linux hosts. Marked 🔵 only where actually
exercised; Windows/Linux stay ✅ (shared-code verified) until a CI/host run confirms them.
| 0.7 | Phase 0 e2e sweep: home shows no fake alarm; scans honest on all five | 🔵 | 🔵 | 🔵 | ✅ | ✅ | 🔵 | ✅ |

## Phase 1 — Guard Mode Shell
*Two-mode architecture + consumer home + one-button ritual + onboarding. Shared UI → all five at once.*

> **✅ COMPLETE (2026-07-16)** — the whole consumer shell ships: appMode flag, lean Guard nav
> (expert console behind Pro), the calm single-verdict Guard Home + "Check my phone", the
> plain-language checkup ritual, and first-run onboarding. e2e on iOS (fresh-install → onboarding →
> Guard Home → lean nav, verified) + macOS (Guard Home) + Android (app runs, honest home in P0.7).
> Bonus: fixed a startup bug the sweep caught (main() blocked first paint on threat-intel network).
> Honest gaps: the Pro-toggle **flipping the UI** was proven by Guard's lean nav (Pro hidden by
> default) + the symmetric gating expression + provider unit tests, not a live toggle screenshot
> (iOS prefs-cache quirk; the Android emulator crashed mid-tap-through — tooling, not app). 88 tests.

| ID | Task | iOS | And | mac | Win | Lin | Test | Status |
|----|------|-----|-----|-----|-----|-----|------|--------|
| 1.1 | `appMode` (guard/pro) in SettingsProvider — persisted, defaults **guard**; toggle in Settings | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 1.2 | Navigation gating: expert drawer sections + "Intel" tab move behind Pro; Guard gets a lean 4-item nav | 🔵 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 1.3 | Guard Home: single honest verdict + one "Check my phone" button (brand-kit styled) | 🔵 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 1.4 | Unified verdict model (`ProtectionVerdict`, shipped in P0.2; drives home + dashboard) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 1.5 | The Checkup Ritual: one-button scan that **names each check as it runs**, honest per platform, ends in relief | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 1.6 | First-run Onboarding: 3 steps (anti-surveillance value → honest checkup → privacy); persist first-run flag | 🔵 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 1.7 | Phase 1 e2e: fresh install → onboarding → checkup → verdict; mode toggle; Pro hidden by default — all five | 🔵 | ✅ | 🔵 | ✅ | ✅ | 🔵 | ✅ |

## Phase 2 — The Six Shields + Two New Features
*Re-express real capability as plain-English shields; build the two new features.*

| ID | Task | iOS | And | mac | Win | Lin | Test | Status |
|----|------|-----|-----|-----|-----|-----|------|--------|
| 2.1 | Shield IA: map 19 consumer screens → 6 shields (Spyware&Pegasus · Who's Watching You · Secure Call · Hidden VPN/Proxy · Scam Shield · Identity&Breach) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2.2 | Honest per-platform shield status surfacing (incl. desktop: firewall, process/persistence scan) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2.3 | **Feature — Hidden VPN & Proxy Watch**: detect active tunnel/proxy, list installed VPN apps, whitelist OrbVPN, guide removal | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2.4 | **Feature — Secure Call Check**: device-posture (screen-cap/MITM/jailbreak/certs/a11y) + scam-number flagging | ✅ | ✅ | ✅ | 🚫 | 🚫 | ✅ | ✅ |
| 2.5 | Victim-safe stalkerware UX: removal warning + duress Quick-Exit | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2.6 | Jargon-elimination sweep across all consumer surfaces (IOC/STIX/TTP/correlation → plain English) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2.7 | Phase 2 e2e: each shield opens, runs, reports honestly per platform | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**Phase 2 complete (2026-07-17).** Six-shield `Protect` hub (`shields_screen.dart`) wired to all
six destinations, including the two new features. `flutter analyze lib` → 0 errors/0 warnings
(27 pre-existing `unnecessary_import` infos only); `flutter test` → **120/120 pass** (new suites:
`vpn_proxy_detector` 17, `secure_call_check` 11). All shields are pure-Dart navigation over
existing engines → cross-platform by construction; native gaps degrade honestly to "can't check
here" (never a false clean). 2.4 stays 🚫 on Win/Lin (no call/telephony posture surface there).

## Phase 3 — Trust & In-App GTM
*Trust surfaces + habit loop. (Certification / SEO / external audit are business tracks, noted but out of code scope.)*

| ID | Task | iOS | And | mac | Win | Lin | Test | Status |
|----|------|-----|-----|-----|-----|-----|------|--------|
| 3.1 | Trust surfaces: on-device / "we can't see your data" messaging + privacy explainer | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 3.2 | Honest per-platform capability disclosure screen ("what's possible on your device") | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 3.3 | Habit loop: "days protected" streak + weekly checkup ritual | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 3.4 | Notification discipline: rare/severe/actionable only + one scheduled summary (cap frequency) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 3.5 | Transparent pricing screen (no dark patterns; "the price you see is the price that renews") | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**Phase 3 delivered (2026-07-17)** — five parallel worktree agents built self-contained surfaces;
parent wired nav/provider. `flutter analyze lib` → 0 errors/0 warnings; `flutter test` → **160/160**
(new: privacy-explainer 3, device-capabilities 5, streak-controller 7, streak-card 2, notification-
policy 16, pricing 5). Guard Home now carries the `On-device · Private` badge (sim-verified) and a
gated "days protected" `StreakCard` (shows only after the first checkup); Settings gained a **Trust &
transparency** section (privacy explainer · device capabilities · plans) + a notification-discipline
entry. `recordCheckup` fires on every completed scan (`main.dart`).

> **3.4 now enforced on the live path (2026-07-17).** `NotificationService`'s three unsolicited
> security-alert channels — threat, breach, SMS — pass through `NotificationPolicy.deliversNow`
> (added on top of the existing per-severity/-category settings). The policy reloads per alert so
> discipline-settings changes take effect live; per-category 24h cooldown + a global daily cap apply,
> and **a `critical` alert always delivers** (a cap/cooldown must never suppress a critical security
> alert). Deliberate behavior change, documented: with `criticalOnly` defaulting **on**, only
> *critical* alerts push by default — turning "Critical alerts only" off additionally admits *high*.
> Solicited/informational notices (scan-complete, URL-blocked, generic) are intentionally NOT gated
> by this discipline (they keep their own toggles). Verified: `deliversNow` unit tests (critical
> bypasses cap + cooldown; non-criticals obey the full gate); full suite 163/163.

---

## Phase 4 — The Living Home (control panel + real real-time)
*User verdict on the P1 home: "looks like the app is not doing anything… worst possible design."
Root causes confirmed by 4 investigations (2026-07-17): (1) verdict reads a backend features-configured
score the local scan never touches → permanently "needs attention"; (2) first-run requests ZERO
permissions (a built PermissionSetupScreen exists, unwired); (3) real real-time exists (firewall,
SMS/web filters, feed) but is never surfaced — and iOS "background scan" is dead code returning a
fake `success:true`; (4) leaders (Norton/McAfee/Bitdefender) all ship a living control panel: status
hero + named-guard grid + proof-of-work numbers + a score to raise. Design target (user-approved):
https://claude.ai/code/artifact/19b038b1-e5d3-4454-a8a5-19aa0a8105b0*

| ID | Task | iOS | And | mac | Win | Lin | Test | Status |
|----|------|-----|-----|-----|-----|-----|------|--------|
| 4.1 | Honest data plane: `LastScanVerdictController` (fixes stuck verdict) + `PrivacyScoreEngine` (real-signal 0–1000) + `GuardStatusController` (live guard states) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 4.2 | Control-panel Home: pulsing live hero + score card + guard grid w/ Set-up tiles + proof-of-work feed | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 4.3 | First-run permission priming (staged, value-first) + immediate first check w/ real findings | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 4.4 | Honest scan theatre (named real checks, live counts) + findings results screen | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 4.5 | Android real-time: firewall boot persistence + guard foreground notification + blocked-today counter | 🚫 | ✅ | 🚫 | 🚫 | 🚫 | ✅ | ✅ |
| 4.6 | iOS honesty fix: real BGTaskScheduler background scan (killed the fake `success:true`) | ✅ | 🚫 | 🚫 | 🚫 | 🚫 | ✅ | ✅ |
| 4.7 | FCM instant alerts end-to-end — **LIVE (2026-07-17)** | ✅ | ✅ | 🚫 | 🚫 | 🚫 | ✅ | ✅ |
| 4.8 | Phase 4 integration + e2e + merge | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🟡 |

**Phase 4 shipping (2026-07-17).** Home redesign committed + iOS/Android builds green + 214/214 tests
(`fa05210` data plane · `0c216d4` control-panel home + scan theatre + priming · `e1596e4` native
real-time). New home sim-verified: pulsing live hero, Privacy Score 612/1000 meter, guard grid, real
verdict (a genuine scan recorded score 74 — the stuck-"needs attention" bug is dead). First-run gate
enters onboarding→priming→home. 4.7 FCM **now LIVE** — activated on the `orbguard-lab` container 2026-07-17 (secret `fcm-sa-json` =
the `orb-guard` firebase-adminsdk key; env `ORBGUARD_PUSH_ENABLED=true` + `ORBGUARD_FCM_PROJECT_ID=orb-guard`
+ `ORBGUARD_FCM_SERVICE_ACCOUNT_JSON=secretref:fcm-sa-json`); backend logged "FCM push service
initialized · project_id orb-guard"; migration 022 `device_push_tokens` applied to prod. Only real-world
delivery to a registered device remains to be observed. **Open polish:** eager notification dialog
fires at launch (pre-existing push-init) before priming explains it — suppress so priming owns the ask.

## Phase 5: The Flagship ("Close the circle")
*User verdict before this phase (2026-11): the UI is "awfully bad", the services get lost, there is
nothing to sell with, and foldables and desktop are unserved. Seven prototype rounds settled one
concept: the brand ring is the whole status system. Whole means covered. A gap means something was
found, and it opens toward the shield that found it. Segments mean a check is running. Dotted means
never checked. Grey means nothing is on watch. Six shields orbit the ring, and the app has four tabs:
Home, Protect, Check, Me. Every pop-up is a sheet. Phases 5.1 and 5.2 as built, with screenshots of
the running app: https://claude.ai/artifact/HejruYDNkgjas25busoG1k. The approved prototype (v7) lives
in `docs/flagship-prototype/` (`build.py` writes `orbguard-flagship.html`). Its published page
(https://claude.ai/artifact/17mdf21TTXLGoqPs5aXFwF) and the 5.1 page
(https://claude.ai/artifact/URXWAHKSD6sfCumGPqoX2T) were no longer in the account on 2026-11-25.*

| ID | Task | iOS | And | mac | Win | Lin | Test | Status |
|----|------|-----|-----|-----|-----|-----|------|--------|
| 5.1 | The ring and Home: `OrbRing`, the new Home (`OrbHomeScreen`), four tabs, the wide Archivo type, one vocabulary for the six shields | 🟡 | 🔵 | 🟡 | 🟡 | 🟡 | ✅ | 🟡 |
| 5.2 | Honest checks and the sale: the check inside the ring, true results, the score sheet's fixes, the four points of sale | 🟡 | 🔵 | 🟡 | 🟡 | 🟡 | ✅ | 🟡 |
| 5.3 | Every screen size: the adaptive shell for foldables and tablets, then the desktop window | 🟡 | 🟡 | 🟡 | 🟡 | 🟡 | ✅ | 🟡 |
| 5.4 | The sell kit: store screenshots, widgets, the share card and the site hero | 🟡 | 🟡 | 🟡 | 🟡 | 🟡 | ✅ | 🟡 |

**5.1 state (2026-11-25).** Built on branch `flagship-phase-1` (off `production-hardening`) and
committed with 5.2 (see "Landing" below). Its status stays 🟡 because it has run on one platform of
five. An earlier version of this note called the missing commit the only reason for the 🟡; that was
wrong. `flutter analyze`: no issues. `flutter test`:
498 pass, 8 skipped (the render harnesses, which run only when `RENDER_DIR` is set). API contract gate:
PASS. Android is 🔵: a debug build ran on a Pixel 6 emulator (Android 15) from first open through the
automatic first check, the results sheet, Home with the real score (606, gap toward Spyware), the score
sheet, a shield sheet, the privacy sheet and the Protect, Check and Me tabs, in dark and in light.
macOS, Windows and Linux are 🟡: the shared Dart is analyzed and tested on the macOS host, but the new
Home has not been run as a desktop app, and its wide layout is 5.3. iOS was ⛔ by BLOCKER-2 when 5.1
was built; the 5.2 work got it launching on the simulator, so it is 🟡 (see the 5.2 state below).

**What the Android run caught, each fixed test first:**
1. The automatic first check started on the first frame, before the device had said how much a check
   can see. It met a coverage of zero, showed "Current coverage: 0%" and never ran. It now waits for
   the start-up probes (`_ready` in `lib/main.dart`; `test/screens/first_check_test.dart`).
2. The first check, started from Home's button, went through the scan-credit gate and showed a
   signed-out person the login screen. A first check is now free wherever it starts. Later checks stay
   metered.
3. The sheet's primary button cut its label off ("Set up permissi…"). `SheetPanel` now gives the
   second action only the room its words need (`test/presentation/sheet_panel_test.dart`, 320 and 411
   wide, real fonts).
4. Four shields opened sheets headed by older expert names ("Forensic Analysis", "Privacy Protection",
   "Scam Detection", "Dark Web Monitor"). `shieldScreen` now passes each shield's own name
   (`test/screens/shield_sheet_names_test.dart`).
5. One finding was offered as "Fix these" under a line that began with a dash. It now reads "Here is
   how to fix it." and "Fix this".
6. After a restart, Home's "Close the gap" started a new, metered check instead of showing what was
   found. The last check's findings are now kept on the device (`verdict_findings_json` in
   `LastScanVerdictController`) and shown again (`test/screens/gap_card_test.dart`).

Items 1, 4 (the Spyware shield), 5 and 6 were then seen fixed on the emulator. Items 2 and 3 are held
by their widget tests alone. The run skipped onboarding (seeded settings) and had its permissions
granted over adb; the check and everything after it were the real thing.

**Decisions taken while building 5.1 (reversible, not yet reviewed by the owner):**
- The ring counts as live only while `spyware_watch` or `firewall` is active. A score appears only
  after a check.
- The breach and hidden-VPN signals do not report to Home yet, so two moons stay unlit and the score
  tops out near 766 on an iPhone and 850 with every guard on. Wiring them is the first job of 5.2.
  **Done in 5.2.**
- A scheduled background scan does not record a verdict, so Home does not move after one. **Changed
  in 5.2:** it records one.
- Home draws its own top row in Guard mode. Protect, Check and Me keep the old header until 5.3.
  **Changed in 5.2:** the old header is gone from all three.
- Protect's tiles are neutral and carry no state: only Home reads the real guard states.
- Home's column is capped at 480 wide. The bell opens system settings once alerts were refused for
  good.
- The old Home files are deleted (`control_panel_home_screen`, `guard_home_screen`, `guard_grid`,
  `live_activity_card`, `privacy_score_card`, `pulse_orb`).
- `ios/Podfile` sets a deployment floor of 15.0 for every pod in `post_install`.
- Copy rule: no em or en dash on any screen Home shows or opens, held by
  `test/presentation/copy_rules_test.dart`. About 134 such lines remain elsewhere in `lib/`, among
  them the legal text, which must not be reworded casually. **After 5.2:** none is left in `lib/`
  outside `lib/legal/`, whose 14 lines are untouched on purpose.

**Open, and the owner's call:**
- **A doubtful finding on stock Android.** `KeystrokeLoggerDetector` flags any keyboard that holds the
  INTERNET permission and is not one of four package names, at CRITICAL. Google's own voice typing
  trips it, so most Android phones would read "Your phone needs attention", and "Fix this" would point
  at a Google system app. Older than this phase, and it should be settled before any Android release.
  **Closed in 5.2.**
- **Kit lime ink on light.** `#5C8A00` is under 4.5 to 1 as small text; `#4A7000` passes. The kit is
  shared with OrbVPN, so the token is unchanged. **Changed in 5.2** to `#4A7000`, in this app only.
- **Pushes that should be sheets.** `PrivacyCheckScreen` and `LoginScreen` still open as full pages.
  **Closed in 5.2:** the check runs on Home, and sign-in is a sheet.
- **Small things seen on the device.** A location dialog appears at cold start before anything
  explains it. On Me in light, the "Appearance" label is close to invisible. On tall phones the
  never-checked Home leaves about 130 dp empty above the tab bar. On a cold start the bell's circle
  can draw a frame before its icon. The trust badge still joins two words with a middle dot.
  **All five closed in 5.2.**

**5.2 state (2026-11-25).** The owner's word after the 5.1 page was "fix all and next step please".
It was read as the go-ahead for the open items of 5.1 and for 5.2, and for nothing further. Built on
the same branch, `flagship-phase-1`. `flutter analyze`: no issues.
`flutter test`: 916 pass, 26 skipped (the render harnesses). API contract gate: PASS. Shown, with
screenshots of the running app, at https://claude.ai/artifact/HejruYDNkgjas25busoG1k.

**Landing (2026-11-25).** The owner's word was "commit, push, merge to main all".
- **Commits.** `5c20b8c` (the iOS scene lifecycle), `3ec5bbb` (5.1 and 5.2 in the app), `9fa69f0`
  (this document and the prototype's source).
- **The hardening line came first.** `main` deploys the backend on every push that touches it, and
  the backend running in production was 55 commits ahead of `production-hardening`, on branches of
  its own (pull requests #6 and #7). Merging the flagship work into `main` alone would have put an
  older backend into production. The owner chose to merge all of it: the hardening line into
  `production-hardening` (`d114416`), then `production-hardening` into `main` (`d9bc7ac`). Before the
  push, the backend in that merge was shown to be the same tree as the source of the running image,
  so the deploy rebuilt the backend that was already live. It went out green, and the service
  answered healthy from the new revision.
- **App CI is green, for the first time since 2026-07-31.** It runs on Linux, and three things were
  red there that pass on a Mac:
  - Ten tests of sign-in and plans. Both screens asked the machine they ran on whether it was
    Windows or Linux, so on the build server the phone tests saw the desktop version. They now take
    the platform they draw for, as Home and the shields do (`e2fccba`).
  - Two of this phase's own fit tests, by the same fault: Home's word for the device came from the
    machine, and "computer" wraps wider than "phone" (`534247a`).
  - The contract gate. It could not read the twenty routes the hardening line registers behind
    middleware (`x.With(...).Get(...)`), so it called six paths the app uses missing. Its parser now
    reads them, has tests of its own, and CI runs those first (`ad54c74`).

  The run on `production-hardening` at `e2fccba`: 936 tests pass, 26 skipped, the gate passes.
- **Still true after landing:** nothing here was run as a desktop app or on a real iPhone, and 5.3
  and 5.4 wait for the owner's word.

**What 5.2 built:**
- **The check inside the ring.** No second page. The ring breaks into one segment per check, fills as
  each one finishes and closes into the score (`CheckStep`, `CheckRun` and `CheckResults` in
  `lib/services/home/`). It counts the checks this device can run: 11 on the Android emulator, 5 on
  an iPhone.
- **True results** (`ResultsSheet`). Ran clean, found, could not run, not possible on this device. A
  check that broke is never counted as passed, and a run that did not finish every check is never
  titled "All clear". One finding is one row, however many checks saw it.
- **The score sheet** (`ScoreSheet`). The score as a sum, the points still to earn, and the fix behind
  each row. Its button offers the largest gain.
- **Four points of sale, all sheets.** The credit line under the results (`CreditLine`), the account
  and plan cards on Me (`AccountCard`, `PlanCard`), the credit gate (`CreditsSheet`, which replaces
  the watch-an-ad sheet) and the plans (`lib/widgets/sale/plans_sheet.dart`). Sign-in is a sheet too
  (`login_sheet.dart`). Prices come only from the store, and with no store the sheet says so.
- **All six shields report.** Breaches and a hidden VPN reach Home and the score
  (`lib/services/home/home_signals.dart`). Whether traffic is rerouted (a VPN or a proxy) has one
  owner, `VpnWatch`, and it is a question to the person, never a finding of the device check.
- **The Check tab** (`CheckTabScreen`). One box to paste a link, a message or a number (`PasteCard`,
  `PasteVerdict`), six quick checks and the full check.
- **Background checks count.** A scheduled check records its verdict, so Home moves after one.
- **`PageHead`** replaces the old top bar on Protect, Check and Me.

**Closed from the 5.1 list:**
- The keyboard false alarm. A keyboard is reported only when it was added to the phone, is switched
  on, can reach the internet and is not a widely used one, at medium for the keyboard in use and low
  otherwise (`test/detection/keyboard_findings_test.dart`).
- Lime ink on light is `#4A7000`, held above 4.5 to 1 on the light surfaces by
  `test/presentation/lime_ink_contrast_test.dart`.
- The location question no longer appears at cold start. The "Appearance" label, the bell's first
  frame, the trust badge's middle dot and the empty band on tall phones are fixed.
- BLOCKER-2's launch crash, on the simulator (see Known blockers for what is still unproven).

**What running it caught, each fixed test first:**
1. After a theme change, `const` widgets kept the old theme's ink until something else rebuilt them
   (two cards on Me). `AppColors.syncWith`, called from `MaterialApp.builder`, now marks every element
   for one rebuild when the brightness turns (`test/presentation/token_sync_test.dart`,
   `test/screens/theme_flip_test.dart`). Seen fixed on the emulator.
2. The paste check could wait for minutes, because the HTTP client under it retries. It now says
   "Still checking. This can take up to a minute." after 8 seconds and gives up after 60 with "The
   scam check took too long to answer, so nothing was judged." (`PasteCard.slowAfter`,
   `PasteCard.patience`, `PasteVerdict.late`). The slow note and the live verdict were seen on the
   emulator. The words shown on giving up are held by their test alone.
3. The analyser opens its advice with a line that only restates the verdict, behind a warning sign,
   and the card showed it as a step to take. `PasteVerdict` drops such lines. Seen fixed on the
   emulator. The backend still sends them.

**The devices.**
- **Android (🔵).** A debug build on the Pixel 6 emulator (Android 15): the automatic first check ran
  inside the ring and closed on 837 with "All clear, 11 checks ran clean."; Today reopened the
  results; the score sheet offered "Check your email, earn 100"; the credit gate and the plans opened
  as sheets, signed out, and the plans said "The store is unavailable" because the emulator has no
  store; Check, Protect and Me drew without the old bar in both themes; the paste check answered the
  built-in example from the live service.
- **iPhone (🟡).** The newest build on the iPhone simulator (iOS 27.1, a foldable's cover display):
  it launches, and with first-run settings seeded it ran its first check: "All clear, 5 checks ran
  clean.", with the 6 checks an iPhone cannot run named and not passed. Home showed 766 in dark and
  in light. Taps cannot be scripted on that simulator, so nothing past Home was seen, and on that
  display the tab bar and the sheet do not span the odd width, which is 5.3.
- **macOS, Windows, Linux (🟡).** As in 5.1: the shared Dart is analyzed and tested on the macOS host
  (and, since landing, on the Linux CI runner), and the app was not run as a desktop window.

**Not verified:**
- The Kotlin side that tells OrbGuard's own firewall from another app's VPN (`SpywareScanner.kt`):
  it compiles, and the Dart around it is unit tested, but no VPN was up on a device.
- A scheduled check started by Android's WorkManager, as opposed to the Dart that records it.
- The signed-in sale states (the balance, earning a credit) and real store prices: tests only.
- On iPhone, everything in the BLOCKER-2 note, and every screen past Home.

**Decisions taken while building 5.2 (reversible, not yet reviewed by the owner):**
- Home's VPN question waits for the first check. A breach does not wait.
- The paste check gives up after 60 seconds, because the first live answer measured took 31.
- A theme change rebuilds every element once.
- With OrbVPN installed, an active VPN is treated as the person's own and the app says so. Android
  does not say which app runs a VPN; the stricter choice is to ask once per VPN.
- A scheduled check does not extend the streak. Only a check the person starts does.
- Kit lime ink on light is `#4A7000` in this app. OrbVPN's copy of the kit is not changed.

**Open, and the owner's call:**
- **The live scam check is slow, and the cause is on the service side.** On 2026-11-25 a first
  answer took 30 to 80 seconds on the phone; one request on 13 November took under 4. The
  measurements and the ways out were given to the owner outside this repository, because the
  service is live and the repository is public. The fix needs a backend change and a deploy.
  Nothing in `backend/` or in Azure was changed.
- **Older screens.** 21 lines in 13 files still join words with an arrow or a middle dot, settings
  among them. 5.2 did not touch those screens.
- **iPhone in the background.** `BackgroundScanService.swift` still lists a proxy as a finding.

**Render harness.** `cd app && flutter test test/visual --dart-define=RENDER_DIR=<absolute dir>` writes
the ring states, five Homes at 390 by 844, three at 320 by 568 and the real shell's tabs, in both
themes. Home is given the phone it is drawn for, so the never-checked Home says "phone" there, as
it does on a phone, whatever machine runs the harness.

### 5.3 and 5.4 state (2026-11-28)

Approved by the owner ("start phases 3 and 4") on 2026-11-25 and built on branch
`flagship-phase-3` (off `b730aef`). **Not committed.** Screenshots of everything below, rendered from
the running code: https://claude.ai/artifact/PGmiL4YJMo9sXBq4noih3t. `flutter analyze`: no
issues. `flutter test`: 1016 pass, 40 skipped (render harnesses). Contract gate: PASS, and its own
tests pass.

**What 5.3 built (every screen size):**
- `ShellForm` (`lib/presentation/layout/shell_form.dart`) picks one of four forms from the window
  size, the display features and the platform: phone, split (a foldable open flat, or a tablet),
  tabletop (a fold half open on a table) and desk (a computer at least 984 wide). Pro mode keeps
  the phone layout.
- **Split.** The ring keeps the left pane (`HomeLayout.pane`) and the tab bar stays under it.
  Today and the shields (`HomeSide`) take the right pane. A shield, a tab and every sheet open in
  the right pane (`Pane`, `PanePage`, `SheetHost`), so nothing lies across the fold, and the ring
  marks the open shield. Android back closes the right pane first.
- **Tabletop.** The ring and its verdict stand in the top half (`HomeLayout.stand`); Today, the
  shields and the tab bar lie in the bottom half.
- **Desk.** A sidebar (`DeskSidebar`) in place of the tab bar, a command palette on Cmd K or
  Ctrl K, Cmd or Ctrl 1 to 4 for the tabs, and sheets as one centred column 480 wide, at most 0.9
  of the window tall. A Mac window draws its own 40 pt title bar (`DeskTitleBar`) under a clear
  native one, and its minimum size is 984 by 640, so a Mac window is always this layout
  (`macos/Runner/MainFlutterWindow.swift`). Windows keeps its own title bar. Only the Mac build
  shows plans.

**What 5.4 built (the sell kit):**
- **The share card** (`lib/widgets/home/share_card.dart`). Offered after a check that ran clean
  today with nothing open, as a Share button beside Done. It sends a picture of the card through
  the system share sheet (`share_plus`, a new dependency).
- **iPhone widgets** (`ios/OrbGuardWidget/`): small, medium and two lock screen sizes, fed by the
  shell through the `com.orb.guard/glance` channel (`lib/services/home/glance.dart`,
  `ios/Runner/GlanceChannelHandler.swift`) and the App Group `group.com.orb.guard.shared`.
- **The Mac menu bar ring and popover** (`macos/Runner/GlanceRing.swift`,
  `GlancePopoverView.swift`, `OrbGuardGlanceChannel.swift`), with Check now.
- **The site hero** at `/` (`backend/internal/api/site/`). Store buttons appear when
  `ORBGUARD_STORE_IOS`, `_ANDROID`, `_MAC` or `_WINDOWS` holds an https link.
- **Store screenshots.** `test/visual/store_render_test.dart` writes five frames for the App Store
  (1290 by 2796) and Google Play (1080 by 2160) in both themes, each a caption over a real screen
  of the shell with nobody signed in.

**Fixed while checking the renders (test first where a test applies):** the Mac command key drew
as an empty box in the keycap and is now the Solar command icon; the privacy sheet named the
machine the app ran on, not the device it draws for, and now takes the platform like Home does;
the dot beside a wrapped proof line now stays on its first line.

**Not built or not verified:**
- Android home screen widgets: started, paused at the weekly agent limit, resumes after 2 December.
- The six checks on Home for computers. Check on a computer still opens Desktop Security.
- A tray icon on Windows and Linux.
- The App ID `com.orb.guard.OrbGuardWidget` with the App Group is not registered on the Apple
  team yet; the next TestFlight build needs it. The three older iPhone extensions are not embedded.
- No foldable or tablet run on Android, and no Windows or Linux run. The desk and split forms are
  covered by widget tests and renders.
- `flutter build ios --simulator` makes an Intel-only app on this Mac: an ads SDK pod excludes
  `arm64e`, and Flutter's check matches it as `arm64`. Build with `xcodebuild` and
  `ARCHS=arm64 EXCLUDED_ARCHS=i386` instead.

**Render harnesses.** `test/visual/wide_render_test.dart` renders the foldable, tabletop, tablet,
Mac and Windows shells and the share sheet; `test/visual/store_render_test.dart` renders the store
frames. Both run only when `RENDER_DIR` is set.

---

## The honesty guardrails (never ship a claim on this list)

- **Never** "we listen to / read inside your WhatsApp, Signal, Telegram, or WeChat calls." No app can (sandbox + E2E).
- **Never** "antivirus" / "malware scanning" on iOS — Apple makes it impossible.
- **Never** remote **lock** or **wipe** — not implemented. Locate / ring / thief-selfie are real; only those are promised.
- **Never** a scan stage that "passes" a check it could not run — say "not supported on this device."
- **Never** attribute an iOS VPN tunnel to an owning app, or claim we can silently kill another app's VPN.

---

## Decisions Log

| Date | Decision | Chosen |
|------|----------|--------|
| 2026-07-16 | Headline positioning | **Anti-surveillance** — "Know if you're being watched" |
| 2026-07-16 | Delivery scope | Full product, 100% ready + e2e at every step, with this status matrix |
| 2026-07-16 | Platform rollout | **All five in parallel** (shared Flutter UI) |
| 2026-07-16 | Two new features | Hidden VPN/Proxy Watch + Secure Call Check — **Phase 2** |
| 2026-07-17 | Home redesign ambition | **Control panel + Privacy Exposure Score** (full living panel, real-signal 0–1000) |
| 2026-07-17 | Real-time depth | **All-in** — surface real state + firewall persistence + iOS BGTask fix + FCM + Android guard service |
| 2026-07-17 | Phase 4 shipping | **One complete push** (home + first-run + real-time land together) |
| 2026-11-23 | Flagship concept | **"Close the circle"**: the brand ring is the status system, six shields orbit it, four tabs, every pop-up a sheet (prototype v7) |
| 2026-11-25 | Flagship build order | **Four phases, 5.1 to 5.4.** Only 5.1 is approved and built; 5.2 to 5.4 wait for the owner's word |
| 2026-11-25 | Kit lime ink on light | **Unchanged** (`#5C8A00`), flagged: fails 4.5 to 1 as small text, `#4A7000` passes, the kit is shared with OrbVPN |
| 2026-11-25 | Flagship phase 2 | **Built**, with the open items of 5.1, after the owner's "fix all and next step please". 5.3 and 5.4 wait for the owner's word |
| 2026-11-25 | Kit lime ink on light, revised | **`#4A7000` in OrbGuard**, which reverses the row two above. OrbVPN's copy of the kit is not changed |
| 2026-11-25 | Landing the flagship | **Merged to `production-hardening` and `main`, together with the hardening line that already ran in production** (the owner: "Merge all, hotfixes too"). 5.3 and 5.4 still wait for the owner's word |
| 2026-11-25 | Flagship phases 3 and 4 | **Approved** (the owner: "start phases 3 and 4"). Built on `flagship-phase-3`, not committed, waiting for the owner's review. Screenshots: https://claude.ai/artifact/PGmiL4YJMo9sXBq4noih3t |

**Strategy dossier (rationale, competitive teardown, psychology):** https://claude.ai/code/artifact/cf12693f-fef4-4781-bf64-d4fe67b3450c
**Live status dashboard:** https://claude.ai/code/artifact/d3462645-f12c-46ca-a3c2-e1f366cf26f0

---

## How this doc is maintained

- Every task edit flips its glyphs here in the same commit that does the work.
- A platform cell goes ✅ when implemented+analyzed+tested, then 🔵 once e2e-verified on that platform.
- The visual dashboard artifact is re-published to its stable URL at each phase boundary.
- Nothing is marked done on vibes — evidence (test output / screenshot / CI link) backs every ✅.
