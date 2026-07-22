# OrbGuard desktop platforms — store submission state & guide

_Last updated: 2026-07-23_

## macOS → Mac App Store (READY — automated from this machine)

What was wrong and is now fixed (commit history has details):
- Bundle id was the `com.example.orbguard` placeholder → now `com.orb.guard`
  (must match — the ASC app 6779076286 already has a macOS 1.0 listing with
  desktop screenshots under that bundle id).
- No `DEVELOPMENT_TEAM` → set to 33T4RDL646 with automatic signing.
- `Info.plist` lacked `LSApplicationCategoryType` (required) and
  `ITSAppUsesNonExemptEncryption` → added (utilities / false).
- Entitlements already had the two hard MAS requirements (app-sandbox +
  network.client); added `com.apple.developer.applesignin` since the login
  screen offers Sign in with Apple on Apple platforms.
- The mobile ad SDKs (Unity/Adivery/Yandex) do NOT register on macOS — no
  build risk; ads simply report "unavailable" and the paywall carries the
  purchase path (StoreKit works via in_app_purchase_storekit).

Build + upload recipe (what the session automation runs):
```sh
cd app
flutter build macos --config-only
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Release archive -archivePath build/macos/Runner.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyID Z38WAKQU8Z \
  -authenticationKeyIssuerID 69a6de79-f3ec-47e3-e053-5b8c7c11a4d1 \
  -authenticationKeyPath ~/.private_keys/AuthKey_Z38WAKQU8Z.p8
xcodebuild -exportArchive -archivePath build/macos/Runner.xcarchive \
  -exportPath build/macos/pkg -exportOptionsPlist <plist: method=app-store, automatic> \
  (same -authenticationKey… flags)
xcrun altool --upload-app -f build/macos/pkg/*.pkg -t macos \
  --apiKey Z38WAKQU8Z --apiIssuer 69a6de79-f3ec-47e3-e053-5b8c7c11a4d1
```
Then in ASC: the macOS 1.0 version → attach the processed build → add the 6
subscriptions → Submit (can ride the same review cycle as iOS or follow it).

Caveats for macOS 1.0 (honest scope):
- Passkey sign-in needs Associated Domains (`webcredentials:orbai.world`) —
  not enabled yet (do together with the iOS 1.1 extension work; magic-link /
  password / Google / Apple sign-in all work meanwhile).
- Push (FCM) has no macOS `aps-environment` entitlement — anti-theft push is
  a mobile feature; macOS uses none of it.

## Windows → Microsoft Partner Center (SCAFFOLDED — needs your Partner Center values)

Reality check: a Flutter Windows build REQUIRES a Windows host — it cannot be
built from this Mac. The repo now has everything so the build runs in CI:
- `app/pubspec.yaml` → `msix` dev-dependency + `msix_config` (placeholders).
- `.github/workflows/windows-msix.yml` → manual-dispatch workflow on a
  `windows-latest` runner: `flutter build windows --release` +
  `dart run msix:create --store` → uploads the `.msix` as an artifact.
- The Windows runner target is real and healthy (11 plugins incl. passkeys,
  secure storage, local auth; ad SDKs & Firebase messaging correctly absent).

Your steps:
1. Partner Center (https://partner.microsoft.com) → Apps and games → New
   product → reserve the name **OrbGuard**.
2. Product management → Product identity: copy the three values —
   `Package/Identity/Name`, `Package/Identity/Publisher` (CN=GUID), and
   `Publisher display name`.
3. Put them in `app/pubspec.yaml` → `msix_config:` (replace the three
   REPLACE placeholders), commit, push.
4. GitHub → Actions → "Windows MSIX" → Run workflow → download the
   `orbguard-windows-msix` artifact.
5. Partner Center → your app → Start submission → Packages → upload the
   .msix; fill listing (store-assets/ has icons/screenshots), pricing
   (note: our in-app subscriptions do NOT exist on Windows — the app's
   paywall uses Apple/Google IAP only, so on Windows users can sign in to an
   account subscribed elsewhere; consider hiding purchase buttons on Windows
   before wide release), age ratings, and submit.
6. First-run QA on a real Windows machine (or the CI artifact in a VM) is
   strongly recommended before submitting — the Windows build has never been
   smoke-tested.

## Linux (NOT STARTED — decision needed)

No store target exists (no Snap/Flathub/deb pipeline), the Linux build has
never been exercised, and per the platform-reality assessment Linux was
trimmed from the ship list. Options when wanted:
- Direct download (.deb/AppImage) from Azure Blob, exactly like OrbVPN's
  `orb.blob.core.windows.net` links on the website download page — lowest
  effort, matches existing infra.
- Flathub/Snapcraft for discoverability — more packaging work.
The website's OrbGuard download page currently lists iOS/Android (live) and
macOS (coming soon); add Linux there once a build exists.
