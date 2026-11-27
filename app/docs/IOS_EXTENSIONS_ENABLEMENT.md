# iOS app extensions: what ships and why

Updated 2026-11-28. The iPhone app embeds three extensions: the widget
(`OrbGuardWidget`), the Call Directory (`OrbGuardCallDirectory`) and the
Message Filter (`OrbGuardSmsFilter`). The Content Filter (`OrbGuardFilter`)
stays out (section 3).

## App IDs (team 33T4RDL646, read back through the App Store Connect API)

| App ID | Resource id | Capabilities |
|---|---|---|
| `com.orb.guard` | RA23J8DSFL | IAP, Push, Sign in with Apple, App Groups, Access Wi-Fi Information, Associated Domains |
| `com.orb.guard.OrbGuardWidget` | P93S4963Y9 | IAP, App Groups (App ID created 2026-11-28) |
| `com.orb.guard.OrbGuardCallDirectory` | FHDD53AKLM | IAP, App Groups |
| `com.orb.guard.OrbGuardSmsFilter` | QZM36D6BNZ | IAP, App Groups (App Groups added 2026-11-28) |
| `com.orb.guard.OrbGuardFilter` | B6N8S64CCS | IAP, App Groups, Network Extensions (not shipped) |

All four shipped bundles carry `group.com.orb.guard.shared` in their
entitlements. The App Groups **capability** is on all four App IDs, but the
**group itself** is assigned only to `com.orb.guard` and
`com.orb.guard.OrbGuardCallDirectory` (their Xcode-managed profiles list it).
For `OrbGuardWidget` and `OrbGuardSmsFilter` it still has to be assigned,
once, by a person:

- The public API can enable the capability but has no App Group resource
  (`settings` reads back `null`).
- Xcode's automatic provisioning with the API key creates App IDs and
  profiles, but its group-assignment call answers "Authentication failed"
  (seen 2026-11-28 on both App IDs, three times; the same build signs once
  the group is not requested).
- So: either sign in again in Xcode, Settings, Accounts (the saved session
  for the team's Apple ID was rejected), after which any
  `xcodebuild -allowProvisioningUpdates` build assigns it; or in the
  developer portal open Identifiers, the App ID, App Groups, Configure, tick
  `group.com.orb.guard.shared`, Continue, Save. Until then a signed archive
  fails on those two targets with "doesn't support the
  group.com.orb.guard.shared App Group".

## 1. Message Filter (`OrbGuardSmsFilter`, ILMessageFilterExtension)

- **No capability or entitlement is needed.** Xcode's own Message Filter
  Extension template has none, and Apple's capability list (Xcode's cached
  portal capabilities) has no message-filter entry. The entitlements file
  used to claim `com.apple.developer.identitylookup.message-filter`, which
  does not exist; that invented entitlement is what stopped automatic
  provisioning ("Entitlement ... not found"), not a missing portal switch.
- **On the device only.** The classifier (links, shorteners, punycode and
  raw-IP hosts, scam wording, one-time-code shape) decides; when unsure it
  delivers the text normally. The old network deferral to
  `/api/v1/sms/analyze` could never work: iOS sends its own JSON with no
  Authorization header (the API answers 401), guard.orbai.world serves no
  apple-app-site-association (404), and the extension had no
  `messagefilter:` associated domain. Message text never leaves the iPhone.
- **Turning it on (iOS 26):** in Messages, the Filter button at the top
  right, Manage Filtering, Text Message Filter, then turn on Text Message
  Filter and OrbGuard. iOS 26 has no Settings path for this. iOS gives the
  app no way to read whether it is on.

## 2. Call Directory (`OrbGuardCallDirectory`, CXCallDirectoryProvider)

- **ITMS-90349 root cause:** the Info.plist named the extension point
  `com.apple.callkitcalldirectory.extension`, which does not exist. The real
  identifier, as in Xcode's Call Directory Extension template, is
  `com.apple.callkit.call-directory`. The same wrong value is why the
  simulator refused to install the app with the appex inside.
- **Data:** the extension reads `call_directory.json` from the App Group
  container. The app writes it through the `com.orb.guard/call_directory`
  channel (`list`, `block`, `unblock`, `status`, `openSettings`). The only
  numbers in it are ones the person adds in the Scam shield on iPhone; nothing
  writes caller-ID labels yet.
- **Turning it on (iOS 26):** Settings, Apps, Phone, Call Blocking &
  Identification, then OrbGuard. The Scam shield reads the real on/off state
  (`CXCallDirectoryManager`) and opens that page.

## Versions

Every extension takes the app's version and build from
`Flutter/Generated.xcconfig` through its own base xcconfig
(`OrbGuardWidget.xcconfig`, `OrbGuardCallDirectory.xcconfig`,
`OrbGuardSmsFilter.xcconfig`): `CFBundleShortVersionString` is
`$(FLUTTER_BUILD_NAME)` and `CFBundleVersion` is `$(FLUTTER_BUILD_NUMBER)`.
Hard-coded values (the Call Directory and Message Filter said 1.0.0 / 1.0.0
while the app was 1.0.0 (11)) fail validation.

## Verified 2026-11-28

- **Simulator (iOS 27.1, arm64 Debug build):** the app installs with all
  three appexes in `PlugIns` (the Call Directory used to make the install
  fail), PlugInKit lists `com.orb.guard.OrbGuardCallDirectory` under
  `com.apple.callkit.call-directory`, `com.orb.guard.OrbGuardSmsFilter` under
  `com.apple.identitylookup.message-filter` and the widget under
  `com.apple.widgetkit-extension`, and the app launches to onboarding.
- **App Store validation:** a signed Release archive as 1.1.0 (12), exported
  for App Store Connect with the API key, passed
  `xcrun altool --validate-app` with "VERIFY SUCCEEDED with no errors"; no
  ITMS-90349. Not uploaded. Because the group is not yet assigned to the
  Widget and Message Filter App IDs, that archive was made with the group
  removed from those two entitlements files for the run only; Runner and the
  Call Directory kept theirs. Every bundle was signed by the existing Apple
  Distribution certificate, with Xcode-managed App Store profiles.
- **Not verified:** anything on a real iPhone (iOS actually loading the
  extensions, a blocked call, a filtered text).

## 3. Content Filter (`OrbGuardFilter`, NEFilterDataProvider)

Not shipped. On iOS, `NEFilterDataProvider` only runs on supervised
(MDM-managed) devices; Apple does not allow consumer content-filter data
providers. The target stays in the project, outside Runner's dependencies and
Embed App Extensions phase.

- For consumer devices the equivalent is the DNS-filter approach the Android
  side already ships. On iOS that would be an `NEDNSSettingsManager` design
  (consumer-usable since iOS 14), a different extension type under the
  Network Extensions capability the App ID already has.
- Decision needed: target MDM/enterprise (keep NEFilterDataProvider) or
  consumer DNS filtering. Until then this stays out of the build.

## Notes

- Capability changes invalidate existing provisioning profiles; the next
  automatic-signing build regenerates them. Do not toggle capabilities while
  a build is in review.
