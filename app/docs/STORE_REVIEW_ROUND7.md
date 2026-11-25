# Store review — round 7 (Google Play rejection + Apple iOS 3.1.2(c) + macOS VPN questionnaire)

_Written 2026-08-22 for build **1.0.0+11** (Android versionCode 11, iOS/macOS build 11)._

## What was rejected and what changed in the app

| Store | Issue | What we changed (code) |
|---|---|---|
| Google Play | **Anti-SMS-phishing use case not allowed** (needs Google pre-qualification with a public track record we do not have) | Removed `READ_SMS` / `RECEIVE_SMS` and the SMS broadcast receiver. OrbGuard **never reads the inbox**. The Scam Text Check now works on text the user **pastes** or **shares to OrbGuard** from Messages/WhatsApp (new `ACTION_SEND text/plain` intent filter → Check tab, analysed immediately). |
| Google Play | **AccessibilityService**: missing in listing + insufficient prominent disclosure (Name / Email / identifiers) | Removed **all three** accessibility services (`AccessibilityMonitorService` did nothing, `BrowserAccessibilityService` was never reachable from the UI, `MessagingAccessibilityService` had no channel at all) and `BIND_ACCESSIBILITY_SERVICE`. Stalkerware detection still lists accessibility-enabled apps via `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES` (no permission needed). Accessibility priming step / setup cards / rationale sheets removed. With no AccessibilityService the Accessibility-API policy no longer applies. |
| Google Play | **VpnService not documented in the description** | Long description rewritten (pushed via the Play API, see below): a dedicated "ON-DEVICE FIREWALL (uses Android VpnService)" section explains the local DNS filter, that it is not a VPN service, no server, consent dialog, off by default. Manifest comment documents the same. |
| Apple iOS | **3.1.2(c)** per-month calculated price more prominent than the billed amount | `_PriceRow` in `lib/screens/pricing/pricing_screen.dart`: headline is now always the **billed** store price (`$4.99 / month`, `$49.90 / year`); "Billed … once a year. Renews automatically." underneath; the per-month equivalent is a smaller, lighter note ("Works out to about $4.16 a month."). Test updated (`test/screens/pricing_test.dart`). |
| Apple macOS | automated "VPN functionality" questionnaire | No code change needed — answers below (the app has no VPN; it *detects* VPN/proxy configs and deep-links to the separate OrbVPN app). |

Also: priming copy/test, permission manager, legal privacy text (SMS bullet), home guard probe
("Scam text check"), `docs/` updated. `flutter analyze` clean; full test suite green.

---

## A. Google Play — what YOU must do in Play Console (step by step)

Everything below is in **Play Console → OrbGuard (com.orb.guard)**: https://play.google.com/console

1. **The new build is already uploaded** (versionCode 11, Production track, status *Draft*)
   and the **store description is already updated** — both via the API. Because the app
   has a rejected review pending, Google would not let the API "send for review", so you
   must do that step by hand:
   - Left menu → **Release → Production**. You should see release **11 (1.0.0)** as a draft.
   - Click **Review release** (bottom right) → read the summary → **Start rollout to Production**.
   - If the page says "changes not sent for review", go to **Publishing overview** (left menu,
     near the top) → **Send for review**.

2. **Remove the SMS permission declaration** (this is what triggered "does not meet the
   anti-SMS phishing criteria"):
   - Left menu → **Policy → App content** (scroll; sometimes under "Monitor and improve").
   - Open **Sensitive app permissions** (may be labelled "Permissions declaration").
   - In the **SMS and Call Log** section choose **"My app does not use SMS or Call Log
     permissions"** (or delete the existing SMS declaration). Save.
   - If Google's form still insists on a core-functionality answer, that means the new build
     (without `READ_SMS`) has not been picked up yet — do step 1 first, then come back.

3. **Accessibility declaration** — if App content shows an "Accessibility" / "Accessibility
   Service" declaration, answer **"My app does not use the AccessibilityService API"**. If there
   is no such form, there is nothing to do (Google decides from the manifest, and build 11 has
   no accessibility service).

4. **VpnService declaration** — in the same App content area look for **"VPN"** /
   **"VpnService"**. Choose the option for a **device-level security use (firewall)** — *not*
   "VPN / network proxy". Use this text where a description is asked:

   > OrbGuard uses VpnService only to run a local, on-device DNS firewall that blocks known
   > malicious, tracking and surveillance domains. The interface routes only the virtual DNS
   > resolver address (10.111.222.1); all other traffic uses the normal network. No VPN server
   > is involved, no traffic leaves the device for this feature, nothing is logged off-device.
   > The user must accept Android's VPN consent dialog and the feature is off by default.
   > The use is documented in the Play listing ("ON-DEVICE FIREWALL (uses Android
   > VpnService)") and in the app before enabling.

5. **Data safety** (Policy → App content → **Data safety** → Manage):
   - **Messages → SMS or MMS**: set to **not collected** (we no longer read any SMS).
   - Keep **Personal info → Name / Email address / User IDs** (account sign-in) as already
     declared — they are collected only when the user signs in; purpose "App functionality,
     Account management"; not shared for advertising.
   - Text the user pastes/shares into the checker is sent to our server for analysis only.
     Declare it as **App activity → Other user-generated content** → Collected, Not shared,
     Optional, purpose "App functionality" (it is processed and not stored with the account).
   - Save → **Submit** the Data safety form.

6. **Also fix the "Not adhering to policies" generic line**: it is the umbrella for the items
   above; no separate action.

7. Done. Google re-reviews automatically after **Send for review** (usually 1–7 days).

What the API already did for you today:
- `PATCH listings/en-US` — new long description (VpnService section, no SMS-inbox / no
  accessibility claims, "Scam Text Check: paste or share") — committed with
  `changesNotSentForReview=true`.
- Uploaded `app-release.aab` (versionCode 11) to the **Production** track as **Draft** with
  release notes.

---

## B. Apple — iOS reply (Guideline 3.1.2(c)), submission a20d2258, build 1.0 (11)

Paste in App Store Connect → the app → iOS version 1.0 → **App Review** message thread
(after attaching build 11 to the version and re-submitting):

> Thank you for the review. Guideline 3.1.2(c) is addressed in build 1.0 (11).
>
> The subscription purchase screen has been revised so that the **billed amount** is the
> single most prominent price element for every plan, on both billing cycles:
>
> - The large headline price is now always the amount charged: e.g. "$4.99 / month" for a
>   monthly plan and "$49.90 / year" for a yearly plan (both read live from StoreKit).
> - Directly under it, in normal text: "Billed $49.90 once a year. Renews automatically."
> - The per-month equivalent of a yearly plan ("Works out to about $4.16 a month.") is now a
>   small, lighter, subordinate note below the billed amount — smaller than both the headline
>   and the billing line — and is never shown as the headline.
>
> No introductory offers or free trials are presented. We also re-checked the Settings
> "Subscription" tile and the plan-comparison cards: no other screen shows a calculated price.

ASC checklist before you press Submit (same as last round):
1. Wait for build 11 to finish processing (TestFlight tab shows it).
2. App Store tab → iOS **1.0** → **Build** → pick 1.0 (11) → Save.
3. **In-App Purchases and Subscriptions** section → the 6 `orbguard_*` subscriptions attached.
4. App Review Information: demo account filled; Notes box gets the macOS VPN text below too
   (harmless on iOS).
5. Reply in the message thread with the text above → **Submit for Review**.

---

## C. Apple — macOS reply ("app contains VPN functionality")

Reply in the macOS version's App Review thread **and** paste the same text into
**App Review Information → Notes** for the macOS 1.0 version (they asked for both):

> OrbGuard for macOS does **not** provide VPN functionality. The automated analysis most
> likely picked up these three things, none of which is a VPN:
>
> 1. **"Hidden VPN & proxy" security check** — a detection feature. It reads the Mac's own
>    network configuration (active network interfaces and system/environment proxy settings)
>    to warn the user if an unexpected VPN or proxy is routing their traffic, which is a
>    common spyware technique. It reads only; it never creates, configures or connects a VPN.
> 2. **Hand-off to OrbVPN** — a button that opens our separate OrbVPN app (or its App Store
>    page) if the user wants a VPN. OrbGuard itself contains no tunnel, no
>    NetworkExtension, and requests no VPN entitlement (the sandbox entitlements are: app
>    sandbox, network client, location, camera, keychain, user-selected files).
> 3. The word "VPN" in copy and the shared OrbVPN/Orb account branding.
>
> Answers to the questions:
> - **What user information is the app collecting using VPN?** None. There is no VPN, so no
>   traffic passes through OrbGuard and nothing is collected by one. The VPN/proxy check
>   reads local configuration and displays the result on the device; it is not uploaded.
> - **For what purposes?** Not applicable — no VPN data is collected. (The only network
>   traffic OrbGuard sends is to our own threat-intelligence API for the checks the user runs,
>   and to the shared Orb account service for sign-in and subscriptions, as described in the
>   Privacy Policy.)
> - **Will the data be shared with any third parties?** No. Nothing is collected via VPN and
>   nothing is shared or sold.
>
> We have added this clarification to App Review Information as requested.

(Reference for reviewers if they ask: the Android build *does* use Android's VpnService for a
local DNS firewall; that feature does not exist in the macOS or iOS builds.)

---

## D. Resubmission log

- 2026-08-22: Play listing updated via API (edit committed, not sent for review — UI step).
- 2026-08-22: AAB versionCode 11 (98.9 MB) → Production (Draft) via `play-publish` (edit 07841521887041019371, committed with changesNotSentForReview — press **Send for review** in the Console).
- Build note: Gradle failed 8× with TLS "Tag mismatch" downloading artifacts on this Mac; fixed by `./gradlew --stop` + `JAVA_TOOL_OPTIONS="-Djdk.tls.client.protocols=TLSv1.2"` before `flutter build appbundle`.
- 2026-08-22: IPA 1.0 (11) → App Store Connect via `asc-upload` — UPLOAD SUCCEEDED, delivery 2b0dcc0a-5b0d-4b78-ab31-a3cc9c1de63e.
- 2026-08-22: macOS pkg 1.0 (11) via altool — UPLOAD SUCCEEDED, delivery 3c8bf365-22d9-4f59-bdaf-f8ae58383dd7.

---

## E. Round 7b — 2026-08-25 rejection of submission 10 (build 11) — ROOT CAUSE

Google rejected submission **10** (Production 1.0.0 = versionCode **11**, new listing, Data
safety) on 2026-08-25 with the *same* three Accessibility-API items. Build 11 provably has no
AccessibilityService (`bundletool dump manifest` on `app-release.aab`: zero
`BIND_ACCESSIBILITY_SERVICE`, zero SMS permissions) and the listing already says "no
accessibility service". The cause is **not** the code or the listing:

**Play Console → App content → Accessibility services → "View app bundles and APKs"** lists the
bundles that still declare `BIND_ACCESSIBILITY_SERVICE`:

| versionCode | track | since |
|---|---|---|
| 4 (1.0) | Closed testing – OrbGuard | Jul 20, 2026 |
| 4 (1.0) | Closed testing – Alpha | Jul 20, 2026 |
| 5 (1.0) | Internal testing | Jul 20, 2026 |

Google's policy review is app-wide across **every active track**, so as long as builds 4/5 stay
live on the testing tracks the Accessibility rejection repeats no matter how clean Production is.
(API track ids: `internal`=5, `alpha`=4, `beta`=4, `OrbGuard`=4.)

### Fix (Console actions, ~2 minutes)

1. Put build 11 on all four testing tracks — one command (new helper `~/.local/bin/play-promote`,
   reuses the already-uploaded bundle, commits with `changesNotSentForReview`):

   ```
   play-promote --package com.orb.guard --version-code 11 \
                --tracks internal alpha beta OrbGuard --not-sent-for-review
   ```
   (`play-promote --package com.orb.guard --show` prints the current track → versionCode map.)

2. Play Console → **Publishing overview** → confirm the list now also shows the four testing-track
   releases → **Submit changes for review**.
3. App content → the **Accessibility services** row should disappear / show "not used" once no
   active bundle declares the permission; nothing to fill in. Same for **SMS and Call log**.

Nothing else changed: code, AAB (versionCode 11), listing and Data safety are the ones from §A.

### Resubmission log (round 7b)
- 2026-08-30: `play-promote --version-code 11 --tracks internal alpha beta OrbGuard --not-sent-for-review`
  → edit 16691470251647744412 committed; every track now = 11 (internal went live at once).
- 2026-08-30: App content → Accessibility services → "View app bundles and APKs" now says
  "You don't have any app bundles or APKs in your app that access sensitive permissions".
- 2026-08-30: Publishing overview → **Send 7 changes for review** confirmed (Production, Open
  testing, Closed testing Alpha + OrbGuard → 1.0.0/11, short + full description, Data safety).
  Google's pre-submission quick checks were running; changes are forwarded to review when they pass.
- 2026-08-30 18:48: quick checks passed → **Submission 11 — In review** (Production, Open testing, Closed testing Alpha + OrbGuard, Store Listing, App Content). Code committed as 6e0a971.
