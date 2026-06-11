# FCM Push Activation Guide (OrbGuard)

This guide turns on **push wake-ups** for the anti-theft device agent. It is
written so the app **keeps building today** (`flutter build apk`) and becomes
push-capable with a small, well-defined set of steps once the Firebase
credentials/config files are available.

## Why push (and what works without it)

The device agent (`lib/services/device_agent/device_agent.dart`) currently has
**no push channel**. Remote commands (locate / lock / wipe / ring / selfie /
message) are **HTTP-polled**:

- 60-second foreground timer
- poll on every app resume
- Android: an extra 15-minute WorkManager background cycle
- iOS: foreground + resume only (no background scheduling in this build)

That is correct but higher-latency. A **high-priority FCM data push** lets the
backend wake the agent so a queued command is fetched and executed in **seconds**.

The push seam already lives in `lib/services/device_agent/push_service.dart`
(`DevicePushService`). Two of its capabilities are **already real and used**:

- `registerToken(token)` → `OrbGuardApiClient.registerPushToken()` →
  `POST /api/v1/device/{device_id}/push-token`
- `onPushReceived()` → `DeviceAgent.instance.pollNow()` (immediate command poll)

They are simply never driven yet, because nothing produces a token until
Firebase is enabled. The Firebase-specific code is present but **unreachable**,
guarded by `const bool kFirebaseEnabled = false`. The app build does **not**
import any firebase package.

> **Do NOT add `firebase_core` / `firebase_messaging` to `pubspec.yaml` or apply
> the `com.google.gms.google-services` Gradle plugin until you have
> `android/app/google-services.json`.** Adding the plugin without that file
> breaks `flutter build apk`.

---

## Activation steps

### (a) Firebase project + Android config

1. Create a Firebase project (or reuse an existing OrbVPN/OrbGuard one) at
   <https://console.firebase.google.com>.
2. Add an **Android app** with package name **`com.orb.guard`**
   (this matches `android/app/build.gradle.kts` `applicationId`/`namespace`).
3. Download **`google-services.json`** and place it at **`android/app/google-services.json`**.

### (b) Add the Flutter dependencies + Gradle plugin

1. In `pubspec.yaml` add (pin to versions compatible with your Flutter SDK):

   ```yaml
   dependencies:
     firebase_core: ^3.6.0
     firebase_messaging: ^15.1.3
   ```

   Then `flutter pub get`.

2. In **`android/build.gradle.kts`** (project-level) add the classpath:

   ```kotlin
   buildscript {
       dependencies {
           classpath("com.google.gms:google-services:4.4.2")
       }
   }
   ```

   (If the project uses the plugins DSL / `settings.gradle.kts` plugin
   management, declare `id("com.google.gms.google-services") version "4.4.2" apply false` there instead.)

3. In **`android/app/build.gradle.kts`** apply the plugin:

   ```kotlin
   plugins {
       // ...existing plugins...
       id("com.google.gms.google-services")
   }
   ```

4. Ensure `POST_NOTIFICATIONS` permission is declared (Android 13+) in
   `android/app/src/main/AndroidManifest.xml`:

   ```xml
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
   ```

### (c) iOS config and APNs (account-owner only)

iOS push **cannot** be completed without the Apple APNs key, which only the
Apple Developer **account owner** has. Until then, **iOS uses polling** (already
implemented) — no action needed for iOS to keep working.

When you are ready:

1. Set the iOS bundle id to your real production id. The project currently uses
   the placeholder **`com.example.orbguard`** in
   `ios/Runner.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER`); change
   it to the production bundle id you register below.
2. In Firebase, add an **iOS app** with that bundle id; download
   **`GoogleService-Info.plist`** into `ios/Runner/` and add it to the Runner
   target in Xcode.
3. In the **Apple Developer** portal, create an **APNs Auth Key (.p8)** and
   upload it to **Firebase → Project Settings → Cloud Messaging → APNs Auth Key**
   (with Key ID + Team ID).
4. In Xcode, enable the **Push Notifications** capability and
   **Background Modes → Remote notifications** for the Runner target.

### (d) Flip the switch in the app

In `lib/services/device_agent/push_service.dart`:

1. Uncomment the two imports marked `--- FIREBASE BLOCK: imports ---` at the top.
2. Uncomment the body marked `--- FIREBASE BLOCK (uncomment on activation, step 3) ---`
   inside `initFirebaseMessaging()`.
3. Uncomment the top-level `orbGuardFirebaseBackgroundHandler` marked
   `--- FIREBASE BLOCK: background handler ---`.
4. Set `const bool kFirebaseEnabled = true;`.
5. In `lib/main.dart` (app entry), register the background handler **before**
   `runApp`:

   ```dart
   FirebaseMessaging.onBackgroundMessage(orbGuardFirebaseBackgroundHandler);
   ```

   No other call sites change: `DeviceSecurityProvider.init()` already calls
   `DevicePushService.instance.init()`, which now obtains and registers the
   token and wires the message handlers.

### (e) Backend

1. Set the FCM sender credentials (config-gated; absent ⇒ the sender no-ops/503s
   with a log, never fabricates a send):
   - `ORBGUARD_FCM_PROJECT_ID`
   - `ORBGUARD_FCM_SERVICE_ACCOUNT_JSON` (path to / contents of the FCM service
     account JSON)
2. Run **migration 022** (`orbguard.lab/migrations/022_*.sql`) to wire the
   `POST /api/v1/device/{device_id}/push-token` route + sender config. The
   `device_security.push_token` column already exists from the original device
   schema; 022 adds route handling and any sender bookkeeping.

---

## Verification after activation

- `flutter analyze` → 0 errors, `flutter build apk` succeeds with the deps added.
- On a real Android device, after login the logs show
  `push token registered with backend (android)`.
- Issue a remote command from another session; the target device fetches and
  executes it within seconds (log: `push received → polling device agent now`),
  not on the next 60s/15-min tick.
- iOS: until the APNs key is uploaded, expect polling behavior (documented),
  not push.

## Files involved

- `lib/services/device_agent/push_service.dart` — the push seam (this is where
  you flip `kFirebaseEnabled` and uncomment the Firebase blocks).
- `lib/services/api/orbguard_api_client.dart` — `registerPushToken()`.
- `lib/services/api/api_config.dart` — `ApiEndpoints.devicePushToken()`.
- `lib/providers/device_security_provider.dart` — calls
  `DevicePushService.instance.init()` after device registration.
- `lib/services/device_agent/device_agent.dart` — `pollNow()` /
  `runHeadlessCycle()` driven by the push hooks.
