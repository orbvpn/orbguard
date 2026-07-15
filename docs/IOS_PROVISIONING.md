# OrbGuard iOS — Apple provisioning & on-device activation runbook

Several iOS features are **built in code** but need Apple Developer–portal setup + a
signed build to actually run — the same class of step as an APNs key. This is the
single checklist of everything that's yours to do in the Apple Developer portal and on
the device. Nothing here is a code gap; it's Apple's capability/signing model.

App ID / bundle: **`com.orb.guard`** (Apple team `33T4RDL646`).
Shared App Group (already in `ios/Runner/Runner.entitlements`): **`group.com.orb.guard.shared`**.

---

## 1. Push notifications (APNs) — for FCM push on iOS

The FCM pipeline is live end-to-end on the backend + Android (verified: 4 real tokens).
iOS delivery needs APNs. **APNs key already created: `AuthKey_CNVSQQAPM9.p8` (Key ID `CNVSQQAPM9`).**

1. ✅ `aps-environment` = `production` set in `ios/Runner/Runner.entitlements` (done in code).
2. **YOU (Firebase Console — no CLI/API exists for this):** Firebase console → project **orb-guard**
   → Project Settings → **Cloud Messaging** → Apple app config → **APNs Authentication Key** →
   Upload → the `.p8` file, **Key ID `CNVSQQAPM9`**, **Team ID `33T4RDL646`**.
3. **Push Notifications** capability on App ID `com.orb.guard` — with automatic signing (now
   configured on all targets, team `33T4RDL646`) Xcode registers this on archive; or enable it
   manually in the portal.

## 2. Content filter — `OrbGuardFilter` (enterprise/MDM only)

Wired into the Xcode build (`ios/scripts/add_filter_target.rb`), builds green. Apple only
**runs** an `NEFilterDataProvider` on **MDM-supervised** devices — not consumer iPhones.

1. App ID `com.orb.guard.OrbGuardFilter` → enable **Network Extensions** capability
   (`content-filter-provider`). Automatic signing registers this on Archive.
2. Signing: handled by automatic signing (all targets carry team `33T4RDL646`).
3. Activation requires an **MDM profile** that turns on the content filter (managed devices).
   There is no consumer toggle — this is Apple's design; nothing in code changes it.

> **Honest product note:** because the content filter only activates under MDM, it does
> **nothing for consumer users**. If OrbGuard ships to consumers, consider dropping the
> `OrbGuardFilter` target (and the `content-filter-provider` / unused
> `packet-tunnel-provider` / `dns-proxy` / `app-proxy-provider` entitlements on Runner) from
> the consumer build to simplify review — keep it only in an enterprise/MDM variant. The
> **SMS filter and Call Directory extensions are the real consumer iOS wins.**

## 3. SMS filter — `OrbGuardSmsFilter` (real consumer anti-smishing)

`ILMessageFilterExtension`: iOS routes messages **from unknown senders** to the extension,
which classifies them (on-device heuristic + defer to `guard.orbai.world/api/v1/sms/analyze`).

1. Capability = `com.apple.developer.identitylookup.message-filter` (portal name: **"SMS and
   Call Reporting"**). **IMPORTANT — this goes on the EXTENSION's App ID
   `com.orb.guard.OrbGuardSmsFilter`, NOT the main `com.orb.guard`.** If you couldn't find the
   capability, it's almost certainly because that extension App ID doesn't exist in the portal
   yet (it's brand-new). Easiest path: with **automatic signing** (now set on every target,
   team `33T4RDL646`), open `ios/Runner.xcworkspace` in Xcode signed into the team and **Archive**
   — Xcode auto-creates the 3 extension App IDs and registers their capabilities. If you prefer
   manual: create App ID `com.orb.guard.OrbGuardSmsFilter` first, then "SMS and Call Reporting"
   appears in its capability list. (Note: some Apple accounts must *request* the message-filter
   entitlement — if the toggle is greyed with a "request" link, submit that form.)
2. Sign with a profile carrying that entitlement (automatic signing handles this on Archive).
3. On the device: **Settings → Messages → Unknown & Spam → Filter Unknown Senders** and select
   **OrbGuard** as the SMS filtering app. (The user must opt in — Apple requirement.)
4. QA: text the device from an unknown number with a smishing-style link; confirm it lands in
   the filtered/junk tab.

## 4. Call Directory — `OrbGuardCallDirectory` (spam-call block/ID)

`CXCallDirectoryProvider`: loads blocked/identified numbers from the shared App Group container
(the app fills it from threat intel / user blocks).

1. App ID `com.orb.guard.OrbGuardCallDirectory` → app group `group.com.orb.guard.shared`
   (no special capability beyond the app group + being an app-extension).
2. On the device: **Settings → Phone → Call Blocking & Identification** → enable **OrbGuard**.
3. QA: add a number to the block list in-app, reload the extension, call from that number,
   confirm it's blocked/labeled.

---

## Notes
- Items 3 & 4 are the real consumer iOS security wins (2 & content-filter are enterprise-only).
- All four extensions build in the Xcode project without signing (simulator, `CODE_SIGNING_ALLOWED=NO`);
  device install + the Settings toggles are the only remaining steps and they are inherently the
  operator's / user's, not codeable.
- `asc-upload <ipa>` (see global setup) handles the TestFlight upload once signed.
