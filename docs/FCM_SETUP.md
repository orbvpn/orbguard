# FCM Push — Activation Status

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

## REMAINING — iOS only (needs your Apple Developer account; no one else can do this)
iOS push delivery needs an APNs key Apple only issues to the account owner:
1. Apple Developer → Certificates, IDs & Profiles → Keys → **create an APNs Auth Key (.p8)**, note the Key ID + Team ID.
2. Firebase console → Project **orb-guard** → Project Settings → Cloud Messaging → **Apple app config** → upload the `.p8` (with Key ID + Team ID).
3. Ensure the App ID `com.orb.guard` has **Push Notifications** capability enabled (Xcode automatic signing does this on first build with the entitlement present).
4. Build/run on a real iOS device (push doesn't work in the simulator).

Until step 1–4, **iOS falls back to polling** (already implemented and working). Android is fully live.

## Verify it end-to-end (real device)
Run the app on an Android device → it registers its FCM token (`push token registered` in backend logs).
Issue a remote command from the panel/API → backend logs an FCM send and the device polls immediately.
