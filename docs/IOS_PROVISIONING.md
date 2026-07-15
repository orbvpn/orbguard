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
iOS delivery needs APNs:

1. Apple Developer portal → Keys → create an **APNs Auth Key** (`.p8`), note the Key ID.
2. Firebase console → project **orb-guard** → Project Settings → Cloud Messaging → iOS app
   `com.orb.guard` → upload the APNs key (Key ID + Team ID `33T4RDL646`).
3. Enable the **Push Notifications** capability on App ID `com.orb.guard`.
4. For release builds, set `aps-environment` = `production` in `ios/Runner/Runner.entitlements`
   (currently `development`).

## 2. Content filter — `OrbGuardFilter` (enterprise/MDM only)

Wired into the Xcode build (`ios/scripts/add_filter_target.rb`), builds green. Apple only
**runs** an `NEFilterDataProvider` on **MDM-supervised** devices — not consumer iPhones.

1. App ID `com.orb.guard.OrbGuardFilter` → enable **Network Extensions** capability
   (`content-filter-provider`).
2. Sign both Runner and the extension with a profile carrying that capability.
3. Activation requires an **MDM profile** that turns on the content filter (managed devices).
   There is no consumer toggle — this is by Apple's design.

## 3. SMS filter — `OrbGuardSmsFilter` (real consumer anti-smishing)

`ILMessageFilterExtension`: iOS routes messages **from unknown senders** to the extension,
which classifies them (on-device heuristic + defer to `guard.orbai.world/api/v1/sms/analyze`).

1. App ID `com.orb.guard.OrbGuardSmsFilter` → enable **SMS and Call Reporting** /
   `com.apple.developer.identitylookup.message-filter` capability.
2. Sign with a profile carrying that entitlement.
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
