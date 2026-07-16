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

| ID | Task | iOS | And | mac | Win | Lin | Test | Status |
|----|------|-----|-----|-----|-----|-----|------|--------|
| 0.1 | Remove fake-fear from Home: rescope global "Critical IOCs" stat + kill permanent red alarm banner; show device-relevant status only | 🔵 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 0.2 | Unify to ONE honest verdict vocabulary (reconcile Security Center score vs Dashboard letter-grade "U"/"Not Protected") | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 0.3 | Wall off jailbreak / root / ADB instruction screens from the consumer flow (gate to Pro / remove from setup path) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 0.4 | Fix iOS silent-pass: scan stages that swallow UNSUPPORTED must surface "not supported on iPhone", never "0 findings / clean" | ✅ | 🚫 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 0.5 | Fix fake elevation theater: `checkShellAccess()` returns true for any app → report honestly | 🚫 | ✅ | 🚫 | 🚫 | 🚫 | 🟡 | ✅ |
| 0.6 | Strip "fear/urgency" framing (per the self-incriminating code comment) from remaining consumer copy | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

*(0.5: Kotlin is valid + isolated; **Android runtime e2e is blocked by BLOCKER-1 below** — the whole Android build currently fails on a third-party plugin, not on our code.)*

## Known blockers

- **BLOCKER-1 — Android build broken by `mobile_scanner` 7.2.1.** `flutter build apk` fails with
  ~30 "Unresolved reference" Kotlin errors *inside the plugin's own source* (`MobileScannerCallback`,
  `invertBitmapColors`, `rotateBitmap`, …) under Kotlin 2.1.0 / AGP 8.9.1. Pre-existing, unrelated to
  the reinvention work; iOS/macOS/Windows/Linux unaffected. **Must be resolved for any Android
  delivery + e2e** (P0.7 Android leg, and 0.5 runtime verification depend on it). Likely fix: bump/pin
  `mobile_scanner` to a Kotlin-2.1-compatible version (or bump Kotlin/AGP per Flutter's warnings).
| 0.7 | Phase 0 e2e sweep: home shows no fake alarm; scans honest on all five | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |

## Phase 1 — Guard Mode Shell
*Two-mode architecture + consumer home + one-button ritual + onboarding. Shared UI → all five at once.*

| ID | Task | iOS | And | mac | Win | Lin | Test | Status |
|----|------|-----|-----|-----|-----|-----|------|--------|
| 1.1 | `appMode` (guard/pro) in SettingsProvider — persisted, defaults **guard**; toggle in Settings | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 1.2 | Navigation gating: expert drawer sections + "Intel" tab move behind Pro; Guard gets a lean 4-item nav | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 1.3 | Guard Home: single honest verdict + one "Check my phone" button (brand-kit styled) | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 1.4 | Unified verdict model: "Protected / Needs attention / Threat found", device-specific, improvable by action | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 1.5 | The Checkup Ritual: one-button scan that **names each check as it runs**, honest per platform, ends in relief | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 1.6 | First-run Onboarding: 3–4 steps (value → permissions-with-reasons → first checkup); persist first-run flag | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 1.7 | Phase 1 e2e: fresh install → onboarding → checkup → verdict; mode toggle; Pro hidden by default — all five | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |

## Phase 2 — The Six Shields + Two New Features
*Re-express real capability as plain-English shields; build the two new features.*

| ID | Task | iOS | And | mac | Win | Lin | Test | Status |
|----|------|-----|-----|-----|-----|-----|------|--------|
| 2.1 | Shield IA: map 19 consumer screens → 6 shields (Spyware&Pegasus · Who's Watching You · Secure Call · Hidden VPN/Proxy · Scam Shield · Identity&Breach) | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 2.2 | Honest per-platform shield status surfacing (incl. desktop: firewall, process/persistence scan) | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 2.3 | **Feature — Hidden VPN & Proxy Watch**: detect active tunnel/proxy, list installed VPN apps, whitelist OrbVPN, guide removal | 🟡 | 🟡 | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 2.4 | **Feature — Secure Call Check**: device-posture (screen-cap/MITM/jailbreak/certs/a11y) + scam-number flagging | 🟡 | 🟡 | ⬜ | 🚫 | 🚫 | ⬜ | ⬜ |
| 2.5 | Victim-safe stalkerware UX: removal warning + duress Quick-Exit | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 2.6 | Jargon-elimination sweep across all consumer surfaces (IOC/STIX/TTP/correlation → plain English) | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 2.7 | Phase 2 e2e: each shield opens, runs, reports honestly per platform | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |

*(2.3/2.4 marked 🟡 = primitives already exist in the tree per the feasibility study; not yet surfaced as the feature.)*

## Phase 3 — Trust & In-App GTM
*Trust surfaces + habit loop. (Certification / SEO / external audit are business tracks, noted but out of code scope.)*

| ID | Task | iOS | And | mac | Win | Lin | Test | Status |
|----|------|-----|-----|-----|-----|-----|------|--------|
| 3.1 | Trust surfaces: on-device / "we can't see your data" messaging + privacy explainer | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 3.2 | Honest per-platform capability disclosure screen ("what's possible on your device") | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 3.3 | Habit loop: "days protected" streak + weekly checkup ritual | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 3.4 | Notification discipline: rare/severe/actionable only + one scheduled summary (cap frequency) | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| 3.5 | Transparent pricing screen (no dark patterns; "the price you see is the price that renews") | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |

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

**Strategy dossier (rationale, competitive teardown, psychology):** https://claude.ai/code/artifact/cf12693f-fef4-4781-bf64-d4fe67b3450c
**Live status dashboard:** https://claude.ai/code/artifact/bb8e03ed-613b-4f99-9aae-e4814bb1ea20

---

## How this doc is maintained

- Every task edit flips its glyphs here in the same commit that does the work.
- A platform cell goes ✅ when implemented+analyzed+tested, then 🔵 once e2e-verified on that platform.
- The visual dashboard artifact is re-published to its stable URL at each phase boundary.
- Nothing is marked done on vibes — evidence (test output / screenshot / CI link) backs every ✅.
