# Enabling the three iOS app extensions (post-1.0)

The 1.0 App Store build ships WITHOUT the three app extensions (excluded in
commit `1e51ee8`). This is the exact path to shipping each one. Current
App-ID registry state (verified via the App Store Connect API, 2026-07-23):

| App ID | Capabilities today | Missing for its extension |
|---|---|---|
| `com.orb.guard` (main) | IAP, Push, Sign in with Apple | App Groups (to share state with the extensions), Associated Domains (also needed for iOS passkeys) |
| `com.orb.guard.OrbGuardSmsFilter` | IAP | **Message Filter** (`com.apple.developer.identitylookup.message-filter`) — the capability that blocked the 1.0 archive |
| `com.orb.guard.OrbGuardCallDirectory` | IAP, App Groups | none — capability-complete |
| `com.orb.guard.OrbGuardFilter` | IAP, App Groups, Network Extensions | none — capability-complete |

## 1. SMS Filter (`OrbGuardSmsFilter`, ILMessageFilterExtension)

Blocker: the Message Filter capability is NOT exposed in the ASC API's
capability enum (verified — the API lists 28 types, none is message-filter),
so it must be enabled manually, once:

1. **Apple Developer portal** → Certificates, Identifiers & Profiles →
   Identifiers → `com.orb.guard.OrbGuardSmsFilter` → Edit → enable the
   **Message Filter** capability → Save.
   - If the portal list doesn't show it: open `ios/Runner.xcworkspace` in
     Xcode, select the `OrbGuardSmsFilter` target → Signing & Capabilities →
     `+ Capability` → **Message Filtering** (with automatic signing signed
     into team 33T4RDL646, Xcode registers it on the App ID for you).
2. That's the whole grant — no Apple review/request form is needed for the
   filter extension itself. (Only the *network* variant, deferring queries to
   your server via `ILMessageFilterQueryHandling`, requires the associated
   domain `messagefilter:` entry on top.)
3. Re-enable the target: `git revert 1e51ee8` (restores the pbxproj
   dependencies + Embed App Extensions entries; Podfile/pubspec parts of that
   commit stay — revert only the pbxproj hunk if the others conflict).
4. Rebuild (`flutter build ipa --release`) — the archive that failed with
   "Entitlement …identitylookup.message-filter not found" now signs.
5. QA on a real device: Settings → Messages → Unknown & Junk → enable
   OrbGuard, then verify filtering of non-contact SMS.

## 2. Call Directory (`OrbGuardCallDirectory`, CXCallDirectoryProvider)

Capability-complete (CallKit needs no special App-ID capability). The blocker
is the open install bug (FB 90349: extension fails to install/activate —
repros on the local simulator; strip-appex was the workaround).

1. Fix the 90349 repro first (attach the appex, run on device, Settings →
   Phone → Call Blocking & Identification → toggle OrbGuard, watch Console
   for `callservicesd` errors).
2. Then include the target in the build (same revert as above) and QA that
   `CXCallDirectoryManager.reloadExtension` succeeds.

## 3. Content Filter (`OrbGuardFilter`, NEFilterDataProvider)

Capability-complete (Network Extensions + App Groups already on its App ID).
The blocker is engineering, not signing: on iOS, `NEFilterDataProvider` only
runs on **supervised (MDM-managed) devices** — Apple does not allow consumer
content-filter data providers. The extension is also currently unwired from
the Flutter layer.

- For consumer devices the equivalent capability is the DNS-filter approach
  the Android side already ships. On iOS that would be an
  `NEDNSProxyProvider`/`NEDNSSettingsManager` design (DNS settings manager IS
  consumer-usable since iOS 14) — a different extension type, still under the
  Network Extensions capability the App ID already has.
- Decision needed: target MDM/enterprise (keep NEFilterDataProvider) or
  consumer DNS filtering (new NEDNSSettings extension). Until then this stays
  out of the build.

## Shared plumbing when re-enabling (any of the three)

- Add **App Groups** to the main `com.orb.guard` App ID (API-enablable; the
  extensions already have it) and put the same `group.com.orb.guard` group in
  the app + extension entitlements, so the app can hand the filter/directory
  data over.
- While in the portal, also add **Associated Domains** to `com.orb.guard`
  (`webcredentials:orbai.world`) — required for iOS passkeys to work with the
  orbai.world relying party, independent of the extensions.
- Capability changes invalidate existing provisioning profiles; the next
  automatic-signing build regenerates them — do NOT toggle capabilities while
  a build is mid-review.
- Ship as 1.1: bump `pubspec.yaml` build number, archive, upload, submit.
