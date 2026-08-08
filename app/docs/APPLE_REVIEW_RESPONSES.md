# App Review responses — OrbGuard (iOS + macOS)

Two automated App Review messages, with the reply and the code change that backs
it up.

**STATUS: applied live via the App Store Connect API on 2026-08-01.** Both the
App Description and the App Review Information → Notes were updated on the iOS
(`30b84d62…`) and macOS (`9bac40ff…`) 1.0 versions, which were in REJECTED state
and therefore editable. The replies below are what now sits in the review notes;
they still need to be *sent* as replies in the Resolution Center.

---

## 1. "An automated analysis indicates the app contains VPN functionality"

### Why it fired

It was our own fault, not a false positive on behaviour: the iOS app *declared*
VPN entitlements it never implemented.

`ios/Runner/Runner.entitlements` claimed `packet-tunnel-provider`, `dns-proxy`
and `app-proxy-provider`, plus Personal VPN
(`com.apple.developer.networking.vpn.api` = `allow-vpn`), and
`ios/Runner/Info.plist` declared `NEProviderClasses` naming
`DNSProxyProvider` and `PacketTunnelProvider`.

Verified against the project before changing anything:

- `DNSProxyProvider` does not exist anywhere in the repository.
- `PacketTunnelProvider.swift` and `VPNManager.swift` are compiled into **zero**
  targets — they are dead files, never built or shipped.
- No source in the Runner target references `NEVPNManager`,
  `NETunnelProviderManager` or `NEVPNProtocol`.
- The macOS target has no NetworkExtension or VPN entitlements at all, and no
  extension targets.

The only network extension OrbGuard actually ships is `OrbGuardFilter`, an
`NEFilterDataProvider` content filter that is configured through
`NEFilterManager` on MDM-supervised devices.

### Fix applied

Entitlements now list `content-filter-provider` only; the Personal VPN
entitlement and the whole `NEProviderClasses` dictionary are removed.

### Reply to send

> OrbGuard does not have VPN functionality on iOS or macOS, and it collects no
> user information via VPN.
>
> The automated analysis was triggered by stale entitlements in our project, not
> by app behaviour. Our iOS entitlements declared packet-tunnel, dns-proxy and
> app-proxy providers plus the Personal VPN entitlement, and Info.plist declared
> NEProviderClasses — but nothing implemented any of them. No shipping code
> references NEVPNManager or NETunnelProviderManager, and the classes named in
> NEProviderClasses either do not exist or are compiled into no target. We have
> removed all of them in this build. The macOS app has never declared any
> NetworkExtension or VPN entitlement.
>
> The only network extension OrbGuard ships is a content filter
> (NEFilterDataProvider, "OrbGuardFilter"), used solely to warn the user about
> malicious and fraudulent websites on MDM-supervised devices. It inspects
> destinations locally to decide allow/deny and does not record browsing history.
>
> Answering your questions directly:
>
> - What user information is the app collecting using VPN? None. There is no VPN.
> - For what purposes? Not applicable — no VPN data is collected.
> - Will the data be shared with any third parties? No. There is no VPN data to
>   share.
>
> For completeness: OrbGuard *detects* whether a VPN or proxy is already active
> on the device and reports that to the user as a security signal, and it can
> hand off to our separate OrbVPN app if the user chooses. Neither creates,
> configures or routes traffic through a VPN in this app.

---

## 2. "Does not include a functional link to the Terms of Use (EULA)"

### Why it fired

The App Description linked `https://orbvpn.com/terms` — our own service terms.
For auto-renewable subscriptions App Review requires a link to the **Terms of
Use (EULA)**: either Apple's standard EULA linked from the description, or a
custom EULA registered in App Store Connect.

### Fix applied

`APP_STORE_LISTING.md` now carries Apple's standard EULA link alongside the
existing legal links:

```
Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Terms of Service: https://orbvpn.com/terms
Privacy Policy: https://orbvpn.com/privacy
```

**This must be applied to the live App Description in App Store Connect** — it is
metadata, so it does not ship in a binary.

Alternative if our own terms should govern instead: paste
`https://orbvpn.com/terms` into App Store Connect → App Information → License
Agreement as a custom EULA. Do one or the other, not neither.

### Reply to send

> Thank you — corrected. OrbGuard uses Apple's standard Terms of Use (EULA), and
we have added a functional link to it in the App Description: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/ 
The subscription terms in the description already state the plan names, duration, that payment is charged to the Apple Account at confirmation, and that subscriptions auto-renew unless turned off at least 24 hours before the end of the period. The Terms of Use and Privacy Policy are also reachable in-app from the subscription screen itself.

---

## Also corrected in this pass

The iOS description advertised an **ON-DEVICE FIREWALL** ("blocks known
malicious, tracking and surveillance domains", "live blocked today counter").
That is Android-only — it is implemented by `OrbFirewallVpnService.kt` /
`FirewallChannelHandler.kt`, which have no iOS counterpart; iOS has only the
MDM-scoped content filter. Advertising it on the App Store listing is a
Guideline 2.3.1 accurate-metadata risk, so the section has been removed from
`APP_STORE_LISTING.md`.

The Scam Text Filter claim is accurate on iOS and stays — it is a real
`MessageFilterExtension` in the `OrbGuardSmsFilter` target.


---

## Still outstanding: macOS has no native scanner

Found while correcting the macOS listing. `macos/Runner/MainFlutterWindow.swift`
registers only three channels — `com.orb.guard/wifi`, `com.orb.guard/supplyChain`
and `com.orb.guard/logs`. It does **not** register `com.orb.guard/system`, which
every device-scan stage runs over.

That is the same defect Windows had: all scan stages fail, `anyStageSucceeded`
stays false, and `DeviceScanUnavailableException` surfaces as an error screen. A
reviewer pressing the main action gets a failure.

Unlike Windows, this is not simply a matter of writing the native code: Mac App
Store apps are sandboxed (`com.apple.security.app-sandbox`), so they cannot
enumerate other applications' files, inspect other processes, or read
system-wide privacy records. A faithful port of the Windows scanner is not
possible under the MAS sandbox. What a sandboxed Mac app *can* honestly do —
Wi-Fi/network analysis, scam-link checks, account and device management — is
what the rewritten description now claims, and the description states the
sandbox limitation outright.

Decision still needed: either build the reduced, sandbox-legal macOS check set
so the primary action succeeds, or hold the macOS submission. Shipping it with
a scan action that errors will fail review the same way Windows did.

---

## 4. iOS 2.1(b) — "we cannot locate the In-App Purchases" (submission c745b6a9, 2026-08-03)

### Why it fired (verified against the code)

Three compounding causes, all real:

1. **Discoverability.** In build 8 the only paywall route available to a
   signed-out reviewer was Settings → 8th section ("Trust & transparency") →
   3rd tile "Plans & pricing" — a long scroll behind a label that never says
   "subscription". The self-describing "Subscription" tile only rendered when
   already signed in; premium feature gates route signed-out users to the
   login screen, never to the paywall. No paywall entry existed on Home,
   Protect, or onboarding.
2. **Silent product-load failure.** Products were queried from StoreKit exactly
   once at app startup and never re-queried when the paywall opened. If that
   single query failed or returned nothing (products not yet cleared for sale /
   still propagating / offline first launch), the paywall rendered three tiers
   with "Price unavailable" and permanently disabled "Unavailable" buttons —
   no error, no retry. The reviewer would see a screen with no working IAP.
3. **Sandbox purchases cannot verify** against the production OrbNet backend
   (see the "backend actions" list below): the environment assertion rejects
   sandbox receipts on the production server, and OrbGuard's bundle
   id / shared secret were never configured in the deployed config. Both must
   be fixed server-side or an attempted purchase fails after payment UI.

### Code changes in this build (1.0.0+9)

- `lib/screens/settings/settings_screen.dart` — the **Account** section (first
  section in Settings) now always shows a **"Subscription — View plans &
  subscribe"** tile, signed in or not.
- `lib/screens/pricing/pricing_screen.dart` + `lib/services/iap/iap_service.dart`
  — the paywall re-queries StoreKit products when opened with none loaded, and
  a failed/empty query now shows a visible "Plans couldn't be loaded / Try
  again" card instead of silently-disabled tiers.

### Reply to paste in Resolution Center (after uploading build 9)

Thank you for the review. We have uploaded a new build (1.0.0 build 9) that makes the In-App Purchases easier to locate, and here are the exact steps:

1. Launch OrbGuard. The onboarding slides and the permissions primer can both be skipped ("Skip" / "Skip for now").
2. Tap the Settings tab (right-most item in the bottom navigation).
3. The first section, "Account", contains "Subscription — View plans & subscribe". Tapping it opens the Plans screen.
4. The Plans screen lists our three auto-renewable subscription tiers — Guard, Guard+ and Guard Ultimate — each with Monthly/Yearly options. These are the six submitted In-App Purchases: orbguard_basic_monthly, orbguard_basic_yearly, orbguard_premium_monthly, orbguard_premium_yearly, orbguard_ultimate_monthly, orbguard_ultimate_yearly. (The same screen is also reachable via Settings → Trust & transparency → "Plans & pricing", and a "Restore purchases" action is on the screen.)
5. One subscription unlocks premium in OrbGuard and OrbVPN through the shared Orb account, so checkout asks for a sign-in first. Please use the demo account in App Review Information: [FILL: demo email] / [FILL: demo password] After signing in, tap "Choose Guard+" (or any tier) to start the standard StoreKit purchase sheet.

The In-App Purchases are not restricted by storefront, region, or devicem configuration — they are available in all storefronts. Receipt validation is
server-side and follows Apple's documented flow (verify against production, retry against sandbox on status 21007), so purchases work in the Apple-provided sandbox environment. The Paid Applications agreement is accepted in App Store Connect.

### Backend actions required BEFORE resubmitting (OrbNet repo — not this repo)

Without these, the reviewer's sandbox purchase fails after payment:

1. **Accept sandbox receipts for OrbGuard on the production server.**
   `internal/service/payment/apple.go` — `assertEnvironment` (and its JWS-path
   caller) currently rejects any non-Production receipt on a production server
   with status 21010, immediately after the 21007 sandbox retry succeeded.
   App Review always purchases with sandbox Apple IDs, so this guarantees a
   failed review. Safe to allow for OrbGuard: the granted entitlement expiry
   comes from the receipt itself (sandbox terms last minutes), and the
   no-downgrade guard (`iapGuardKeepsExisting`) already prevents a
   cross-transaction grant from shortening a live paid subscription.
   Suggested shape: a `payment.apple.accept_sandbox_receipts_for: orbguard`
   config list checked inside `assertEnvironment` (OrbVPN's strict behaviour
   stays the default).
2. **Configure OrbGuard's Apple identity in production.** Set
   `ORBNET_PAYMENT_APPLE_ORBGUARD_BUNDLE_ID=com.orb.guard` and
   `ORBNET_PAYMENT_APPLE_ORBGUARD_SHARED_SECRET=<App-Specific Shared Secret
   from ASC → OrbGuard → App Information>` on the deployed service. Today the
   fields are declared in `internal/config/config.go` but set nowhere, so every
   OrbGuard receipt falls back to OrbVPN's identity and is rejected with
   "bundle_id mismatch".

### App Store Connect checklist (manual)

- All six `orbguard_*` subscriptions exist with EXACTLY those product ids
  (an older doc, SETUP_ACTIONS_REQUIRED.md, said `orb_*` — the app queries
  `orbguard_*`; ORBGUARD_SUBSCRIPTIONS.md is canonical), have localized
  display names + a review screenshot, and are in "Ready to Submit".
- The six subscriptions are ATTACHED to the 1.0 version submission (first-ever
  IAPs are only reviewed with an app version).
- Business → Agreements: Paid Applications agreement is Active.
- App Review Information: demo account email + password filled in
  (ORBGUARD_SUBSCRIPTIONS.md still has `[ your demo Orb account email ]`
  placeholders), and the account actually exists on api.orbai.world.

---

## 5. macOS 2.1 — antivirus questionnaire (submission 108dd75e, 2026-08-02)

### Reply to paste in Resolution Center

Facts verified against the codebase; two [FILL] blanks (company history, demo
account) need real values before sending.

> Thank you — answers below.
>
> **What malware or antivirus engine are you using? Is the engine open-source
> based or original?**
> The engine is original, developed entirely in-house by our team. No
> open-source or licensed third-party antivirus engine (e.g. ClamAV) is used.
> On macOS the app runs fully inside the App Sandbox and performs: on-device
> heuristic checks (e.g. running applications launched from temporary or
> user-writable locations, background apps with no user-facing presence),
> Wi-Fi/network security analysis, scam-link checking, and cloud
> threat-intelligence lookups (malicious domains, IPs, URLs, file hashes,
> process names, certificates) against our own service. Platform capabilities
> differ by OS; anything the macOS sandbox does not permit is shown in the app
> as "unavailable" rather than reported as clean.
>
> **How is the definition database hosted?**
> On our own infrastructure: a threat-intelligence service we operate on
> Microsoft Azure (Azure Container Apps, PostgreSQL + Neo4j) at
> guard.orbai.world. It aggregates and curates reputable public and commercial
> threat-intelligence feeds — abuse.ch (URLhaus, ThreatFox, MalwareBazaar,
> Feodo Tracker), OpenPhish, Google Safe Browsing, AbuseIPDB, GreyNoise,
> AlienVault OTX, VirusTotal, CISA KEV, and the Citizen Lab / Amnesty
> International MVT indicator sets for mercenary spyware — plus our own
> curation. We also expose the data over a standards-based STIX 2.1 / TAXII
> 2.1 endpoint.
>
> **Is the database encrypted or transferred using a secure method?**
> All transfers use HTTPS (TLS) exclusively; App Transport Security defaults
> are in force with no exceptions on macOS, and API access is authenticated.
> The app declares ITSAppUsesNonExemptEncryption=false (standard TLS only).
>
> **How frequently will the definition database be updated?**
> The app refreshes definitions automatically every 6 hours while running,
> and on launch when the local cache is older than 24 hours. Server-side, the
> fastest upstream feeds are ingested every 15 minutes and the remainder on
> 30-minute to 24-hour cycles.
>
> **Is this app available outside of the Mac App Store?**
> No. The macOS app is distributed exclusively through the Mac App Store.
>
> **Where can your customers get support?**
> support@orbvpn.com and https://orbvpn.com/support (also linked inside the
> app under Settings → About).
>
> **Has the app been certified or validated by an independent security firm?**
> Not yet. OrbGuard has not been evaluated by an independent antivirus testing
> organization at this stage; we intend to pursue independent evaluation as
> the product matures. Our detection content builds on publicly documented,
> widely used indicator sources (including Citizen Lab and Amnesty
> International's Mobile Verification Toolkit indicators).
>
> **How long have you been in the antivirus business and what qualifications
> does your company have?**
> OrbGuard is built by Orb Global Ltd, the team behind OrbVPN.
> [FILL: e.g. "We have operated OrbVPN, a consumer network-security product,
> since 20XX, serving users on iOS, Android, macOS, Windows and smart-TV
> platforms."] OrbGuard is our device-security / anti-surveillance product,
> built on the same backend infrastructure and the threat-intelligence
> pipeline described above.
>
> **How do you plan to monetize this app?**
> Free tier plus auto-renewable subscriptions sold exclusively through Apple's
> In-App Purchase (three tiers, monthly/yearly — six products). The
> subscription unlocks unlimited scanning, the expert console, and remote
> device tools; one subscription covers OrbGuard and OrbVPN via the shared Orb
> account. We do not sell user data.

### Honesty fix included in build 9

`lib/screens/settings/settings_screen.dart` claimed "OrbGuard is notarized by
Apple" — wrong for a Mac App Store build (MAS apps are App Store-signed and
reviewed, not Developer ID-notarized). Copy now says it is signed and
distributed through the Mac App Store and runs sandboxed.

Known residue (do NOT claim otherwise to Apple): the Dart macOS persistence
scanner (`macos_persistence_scanner_service.dart`) still carries placeholder
`_knownMalwareHashes` values that can never match a real SHA-256 — macOS
answers above deliberately do not claim hash-signature scanning of local files.
