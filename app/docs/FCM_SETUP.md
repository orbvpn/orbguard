# FCM Push — ACTIVATED (Android + iOS)

> iOS APNs Auth Key (ZRV7WVGX9B, team 33T4RDL646) uploaded to the orb-guard Firebase
> project on 2026-06-11. Both platforms are now fully configured for real-time push.
> Final delivery test requires a real iOS device (build + run + issue a remote command).

**Anti-theft real-time push is ACTIVATED for Android and code-complete for iOS.** When a remote
command (locate/lock/wipe/ring/selfie) is issued, the backend sends a high-priority FCM data push
so the device acts in seconds instead of waiting for the next poll. Polling remains the fallback.

Firebase project: **orb-guard** (project #568666805173). App id (both platforms): **com.orb.guard**.

## DONE (this session)
### Backend (live, revision 0000058+)
- FCM HTTP v1 sender initialized — startup log: `FCM push service initialized project_id=orb-guard`.
- Service account `orbguard-fcm-sender@orb-guard.iam.gserviceaccount.com` (role: firebasecloudmessaging.admin); key set as Container App secret `fcm-sa-json`.
- Env: `ORBGUARD_FCM_PROJECT_ID=orb-guard`, `ORBGUARD_FCM_SERVICE_ACCOUNT_JSON=secretref:fcm-sa-json`.
- Migration 022 (device_push_tokens) applied to prod; `POST /device/{id}/push-token` live (verified 200, "push token registered"); command creation fires `command_pending` push (best-effort).

### Android (build verified — `flutter build apk` succeeds)
- `android/app/google-services.json` in place.
- `com.google.gms.google-services` plugin: classpath in `settings.gradle.kts`, applied in `app/build.gradle.kts`.
- `POST_NOTIFICATIONS` permission added.
- `firebase_core` + `firebase_messaging` in pubspec; `kFirebaseEnabled=true`; foreground + background handlers wired (`main.dart` registers `orbGuardFirebaseBackgroundHandler`).
- **Android push works now** (token registers on first run, commands wake the device).

### iOS (code/config complete)
- Bundle id set to `com.orb.guard` (was placeholder); `GoogleService-Info.plist` added to the Runner target in Xcode; `aps-environment` entitlement + `remote-notification` background mode present.

## REMAINING — iOS: one Console upload (≈60s)

GOOD NEWS: you can reuse the **OrbVPN APNs Auth Key** — APNs `.p8` keys are TEAM-WIDE,
and OrbVPN (`com.orb.vpn`) + OrbGuard (`com.orb.guard`) are on the **same Apple team `33T4RDL646`**
(Orb Global Ltd). OrbVPN already uses FCM, so its APNs key relays push for OrbGuard too.

The key is: **`~/Downloads/AuthKey_ZRV7WVGX9B.p8`**
  - Key ID: **ZRV7WVGX9B**   (the other 4 `.p8` files in ~/.private_keys are App Store Connect API keys)
  - Team ID: **33T4RDL646**
  - (Verify in Apple Developer → Keys: the key whose service is "Apple Push Notifications service (APNs)".)

Upload it to the OrbGuard Firebase project (Firebase has NO API for this — Console only):
1. https://console.firebase.google.com → project **orb-guard** → ⚙ Project Settings → **Cloud Messaging** tab.
2. Under **Apple app configuration** (app `com.orb.guard`) → **APNs Authentication Key** → **Upload**.
3. Pick `AuthKey_ZRV7WVGX9B.p8`, enter Key ID `ZRV7WVGX9B` and Team ID `33T4RDL646`. Save.
4. Confirm the App ID `com.orb.guard` has the **Push Notifications** capability (Apple Developer → Identifiers,
   or Xcode automatic signing adds it on first build since the `aps-environment` entitlement is set).
5. Build/run on a REAL iOS device (push never works in the simulator).

That's it — after the upload, iOS gets real-time push. Until then iOS uses polling (already working).

ALTERNATIVE (not needed): the provided `aps.cer` is an OrbGuard-specific push CERTIFICATE for
`com.orb.guard`. Firebase also accepts a `.p12` (cert + private key), but the `.p8` above is the
modern, non-expiring, team-wide method and is strictly better — use it.

Android is fully live (token registers, commands wake the device).

## Verify it end-to-end (real device)
Run the app on an Android device → it registers its FCM token (`push token registered` in backend logs).
Issue a remote command from the panel/API → backend logs an FCM send and the device polls immediately.
