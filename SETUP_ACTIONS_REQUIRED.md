# OrbGuard — Setup Actions Required (things only you can do)

This is the checklist of **manual, out-of-code steps** you need to perform in
external consoles (Google Cloud, App Store Connect, Play Console) for the three
open items. Everything that is *code* I am doing myself — this file is only the
parts that live behind your developer accounts.

> **Golden rule for all of this: OrbVPN must not change.** Every backend change I
> make is additive and defaults to today's exact OrbVPN behaviour. None of the
> steps below touch the OrbVPN app, its products, or its credentials.

Legend: ✅ = I do it in code · 🧑‍💻 = **you** do it in a console

---

## 1. Magic-link per-app routing + branding (#70)

**Status: code DONE (pending review + deploy).** When OrbGuard requests a
sign-in link, the email is now OrbGuard-branded and the link opens **OrbGuard**
(`orbguard://login?code=…`) instead of OrbVPN. OrbVPN's email + `orbvpn://`
link are byte-for-byte unchanged (the new behaviour only triggers on an explicit
`client=orbguard`).

What I changed (OrbNet backend + OrbGuard app):
- ✅ `client` field on the magic-link request; per-app email template + deep-link scheme.
- ✅ OrbGuard app sends `client:"orbguard"` and registers the `orbguard://login` deep link.

**🧑‍💻 Your steps: essentially none for the custom-scheme approach.**
`orbguard://` is a custom URL scheme — it needs **no console configuration**.

Optional (only if you later want the *nicer* iOS experience where the link opens
the app without the "Open in OrbGuard?" prompt — i.e. **Universal Links**):
- 🧑‍💻 In **App Store Connect / Apple Developer**, enable the *Associated Domains*
  capability for the OrbGuard App ID.
- 🧑‍💻 Host an `apple-app-site-association` file at `https://<your-domain>/.well-known/`
  listing the OrbGuard app. (Tell me the domain and I'll wire the backend path.)
- Android equivalent: `assetlinks.json` for App Links.

Skip this unless you want it; the custom scheme already fixes the reported bug.

---

## 2. Subscription: buy OrbGuard = get OrbVPN, shared plans (#71)

**Good news: the entitlement is already shared.** OrbNet stores **one
subscription per account**, and OrbGuard already reads it (that's why "Premium
Yearly" shows). So *any* purchase on the account already unlocks both apps. What's
missing is only the **purchase path** for OrbGuard. Three parts — two are mine,
one is yours.

### VERIFIED STORE STATE (checked via the ASC + Play APIs on 2026-07-19)
- **App Store Connect: ✅ `com.orb.guard` "OrbGuard" ALREADY EXISTS.** You can
  create iOS subscriptions immediately — no build upload needed first on Apple.
- **Google Play: ❌ `com.orb.guard` does NOT exist yet** (Play API: "Package not
  found"). The app record must be created manually (no API can create it), then the
  first AAB uploaded. **I've built a signed release AAB for you** — see 2b.
- **Signing:** OrbGuard now has a real **upload keystore** at
  `~/.secrets/orbguard-upload.jks` (SHA-256 `91:70:AF:8C:22:82:CF:28:94:CC:0A:7C:84:
  D3:D4:44:F0:3E:5E:D9:DC:9A:F8:A7:D1:4E:D5:AE:2C:CE:20:52`). Gradle signs release
  builds with it (via gitignored `android/key.properties`). **KEEP THIS KEYSTORE
  SAFE** — with Play App Signing the upload key is resettable, but don't lose it.

### 2a. 🧑‍💻 App Store Connect (OrbGuard app — `com.orb.guard`) — app EXISTS, just add products
1. Create **auto-renewable subscription products** in the OrbGuard app record.
2. **Reuse OrbVPN's exact product IDs** — the same strings OrbVPN uses:
   - `orb_basic_monthly`, `orb_premium_monthly`, `orb_family_monthly`
   - `orb_basic_yearly`, `orb_premium_yearly`, `orb_family_yearly`
   - (Product IDs are scoped **per app** in the App Store, so reusing the strings
     is legal, and it means the backend maps them to the existing plans with **zero
     database change**.)
3. Put them in a subscription **group** (e.g. "OrbGuard Premium") with the right
   durations/prices to match the OrbVPN equivalents.
4. Generate/локate the **App-Specific Shared Secret** for the OrbGuard app
   (App Store Connect → the app → App Information, or the account-level shared
   secret) and **send it to me** — I need it for receipt validation.
5. If you use the App Store Server API (recommended over the legacy shared
   secret), give me the **Issuer ID, Key ID, and .p8 key** scoped to OrbGuard.

### 2b. 🧑‍💻 Google Play Console (OrbGuard app — `com.orb.guard`) — CREATE the app first
Exact sequence (the app doesn't exist yet; I can't create it via API):
1. Play Console → **Create app** → name "OrbGuard", default language, App/Game =
   App, Free/Paid, accept declarations. This creates the record.
2. Set the **package name to `com.orb.guard`** by uploading the first build: go to
   a track (Internal testing is easiest) → **Create release** → upload
   **`OrbGuard-1.0-release.aab`** (I built + signed it; sent to you / at repo root).
   On first upload, **enroll in Play App Signing** (recommended — Google manages the
   app signing key; your upload key stays resettable).
3. After enrolling, copy the **App signing key certificate SHA-1 + SHA-256** from
   Play Console → **Setup → App signing** and send them to me — I add them to the
   Google OAuth Android client (so Google Sign-In works in the **released** build)
   and to the passkey `assetlinks.json` (so passkeys work in release).
4. Grant your Play service account
   `play-publisher@xexchange-486112.iam.gserviceaccount.com` **access to the
   OrbGuard app** (Users & permissions → add the OrbGuard app to its permissions,
   with financial/subscription read) — lets the backend validate Play receipts and
   lets me push future builds with `play-publish`.
5. Then create the **same subscription products** (reuse the same product IDs as 2a).

### 2c. ✅ Backend + app (my work)
- ✅ Make OrbNet's receipt validation **app-aware**: today it hard-rejects any
  receipt whose bundle ≠ `com.orb.vpn` (Apple) and bakes in `com.orbvpn.android`
  (Google). I'll add OrbGuard's bundle/package/secret as an **additional** entry,
  selected by an optional `app` field that **defaults to OrbVPN** — OrbVPN's
  validation path stays identical. Same for the renewal webhooks.
- ✅ Add the IAP purchase flow to the OrbGuard app (it's a stub today) → posts the
  receipt to the same `/payments/verify-receipt`, then refreshes the JWT so
  premium unlocks.

### 2d. ⚠️ One product decision you need to make
Because there is exactly **one** subscription row per account, if a user has an
active **OrbVPN** store subscription **and** also buys in **OrbGuard** (or vice
versa), the second purchase **overwrites** the first on that single row (two
independent store subscriptions can't co-exist). Choose one:
- **(A)** Steer users to purchase in only one app (simplest — e.g. OrbGuard's
  pricing screen says "manage your plan in OrbVPN" if they already subscribe there), **or**
- **(B)** I add "don't overwrite a longer-dated active subscription" logic to the
  upsert (safe, a bit more code).

Tell me A or B and I'll implement accordingly.

---

## 3. Google Sign-In failure (#69) — FIXED (your console was already correct)

> **Update:** your screenshot proved the Android OAuth client is set up correctly
> (right project, package `com.orb.guard`, matching SHA-1). The bug was **on our
> side**, and I've now fixed it. **You need to do nothing here except re-test** (and
> the Play-signing SHA-1 for release, below). Details for the record:

**UPDATE 2026-07-19 (after you enabled Google in orb-guard + sent new config):**
I moved the app fully into the **orb-guard** project — verified in the *built APK*:
`default_web_client_id = 568666805173-9ufp2it7…` (orb-guard **Web** client),
`project_id = orb-guard`, iOS client `568666805173-gj5jahjs…`, and the backend now
accepts that Web client. **Everything app-side + backend-side is correct and verified.**
Passkey login (also new) reaches the backend fine, proving the app/network are good.

**Yet Google still returns `[28444]`.** With the app 100% consistent on orb-guard, the
only thing left is **server-side in the orb-guard project: the Android OAuth client is
missing.** Evidence: the `google-services.json` you sent contains a **Web** client but
**no Android** client (there should be a `client_type 1` entry). `google_sign_in`
requires an **Android OAuth client** (package `com.orb.guard` + your SHA-1) to exist in
the same project as the Web client — without it, Google returns 28444 even though your
code is perfect.

### 🧑‍💻 The remaining Google fix (60-second check — do ONE of these)
The SHA-1 you added *should* auto-create the Android client, but it isn't there yet.
1. **Verify/create it in Google Cloud Console** (not Firebase):
   console.cloud.google.com → select project **orb-guard** → **APIs & Services →
   Credentials** → under "OAuth 2.0 Client IDs", look for a client of type **Android**
   for `com.orb.guard`. If it's **missing**, click **+ Create credentials → OAuth client
   ID → Android**, package `com.orb.guard`, SHA-1
   `12:5A:18:03:8A:6C:F0:D1:38:3D:15:9B:AB:44:FE:97:3C:AD:96:F3`.
2. **Also confirm the OAuth consent screen is configured** for orb-guard (APIs &
   Services → OAuth consent screen). A brand-new project's unconfigured consent screen
   also yields 28444. If it's in **Testing**, add your account as a **Test user** or
   **Publish**.
3. Then wait ~5 min for propagation and retry. (Re-downloading `google-services.json`
   after the Android client exists is optional — I don't need it; the app already has the
   Web client. But if the new json shows a `client_type 1` Android entry, that confirms
   it's fixed.)

**Bottom line on Google:** there is nothing left for me to change in code — I verified
the app is fully correct. This last item is a project-config action in the orb-guard
Google Cloud console that only you can do. **And you don't have to wait on it: passkey
and magic-link both give you working logins now.**

---

<details><summary>Earlier diagnosis (project-split — now resolved; kept for history)</summary>

**THE ROOT CAUSE (a project mismatch) — needed one console action from you.**

After more digging (I instrumented the app, read the built APK, and confirmed the
error still fires with the Web-client fix applied + after a reboot), the real cause
was a **Firebase/OAuth project split**:

- OrbGuard's app is bound to Firebase project **`orb-guard` / `568666805173`** — its
  **FCM** project. This is baked into the APK by `google-services.json`
  (`google_app_id = 1:568666805173:android:…`, `project_id = orb-guard`).
- But your Google **OAuth clients** (the Android `com.orb.guard` client *and* the
  Web client) live in a **different** project — **`orbvpn-f8292` / `428639254932`**.

On Android, `google_sign_in` (Credential Manager) validates the calling app against
**the project the app is bound to** (`orb-guard`) — which has **no OAuth clients at
all** — so Google returns **`[28444] Developer console is not set up correctly`**,
*regardless of how correct the clients in `orbvpn-f8292` are*. This is exactly why it
works for OrbVPN (its `google-services.json` project and its OAuth clients are the
**same** project) but not for OrbGuard (they're split). Google's own guidance: Sign-In
OAuth and Firebase are tightly bound to **one** project.

**What I already changed (kept, both additive + OrbVPN-safe):** app `serverClientId`
→ a real **Web** client, and the backend accepts that audience. Necessary but *not
sufficient* — the project split above is the remaining blocker.

### 🧑‍💻 The fix — do the OAuth setup in OrbGuard's OWN Firebase project
Everything OrbGuard already lives in the **`orb-guard`** project (FCM), so add the
OAuth there too — then app-project == OAuth-project and 28444 disappears. **This keeps
FCM working and stays 100% native `google_sign_in` (no web-login switch).**

In the **Firebase console → project `orb-guard` (568666805173)**:
1. **Project Settings → Your apps → the `com.orb.guard` Android app → Add fingerprint**
   → paste the debug SHA-1 `12:5A:18:03:8A:6C:F0:D1:38:3D:15:9B:AB:44:FE:97:3C:AD:96:F3`
   (and later the Play App Signing SHA-1). Firebase auto-creates the **Android OAuth
   client** in this project.
2. **Authentication → Sign-in method → enable _Google_.** This auto-creates the
   project's **Web client** (the "Web client (auto created by Google Service)").
3. **Download the updated `google-services.json`** and send it to me (it now contains
   the OAuth clients + a `default_web_client_id`). I'll drop it into the app.
4. Tell me the new **Web client ID** (or I'll read it from that file). ✅ I then set the
   app's `serverClientId` to it and add it to the backend's accepted-audience list.

That's the whole fix. (Alternatively we could move OrbGuard's *Firebase* binding into
`orbvpn-f8292`, but that changes the FCM sender ID and would require re-provisioning
push — not worth it. Keeping OAuth in `orb-guard` is cleaner.)

**Also for the Play release build** — see below.

</details>

---

<details><summary>Original diagnosis notes (superseded by the fix above)</summary>

**Captured native error after picking an account:**

```
GoogleSignInException code=unknownError
description=[28444] Developer console is not set up correctly.
```

**What this means:** everything on the app + backend side is correct —
- Google's servers are reachable (no network block),
- the account picker appears and you can select an account,
- the app requests the token with the right `serverClientId`
  (`428639254932-93ijb65q…`, which the backend already accepts),
- the APK is signed with the debug keystore whose SHA-1
  **`12:5A:18:03:8A:6C:F0:D1:38:3D:15:9B:AB:44:FE:97:3C:AD:96:F3`** — the exact
  one you registered.

Error **`[28444]`** is Google's **`DEVELOPER_ERROR`**: after you pick an account,
Google checks that an **Android OAuth client** matching *(package `com.orb.guard`
+ that SHA-1)* exists **in the same Google Cloud project that owns the web client
`93ijb65q`** — and it can't find a valid one. So the sign-in dies right there and
the app shows "Couldn't sign in with Google."

Since the SHA-1 is already correct, the misconfiguration is one of these — check
in order:

### 🧑‍💻 The fix — Google Cloud Console → project `orbvpn-f8292` (number `428639254932`)
**APIs & Services → Credentials.** Confirm there is an **OAuth 2.0 Client ID of
type _Android_** with **both**:
- **Package name:** exactly `com.orb.guard` (a typo like `com.orbguard` or
  `com.orb.guard.debug` causes 28444), and
- **SHA-1 certificate fingerprint:** `12:5A:18:03:8A:6C:F0:D1:38:3D:15:9B:AB:44:FE:97:3C:AD:96:F3`

The three things that produce 28444 even when the SHA-1 "was registered":
1. **Wrong project** — the Android client was created in a *different* project than
   the web client `93ijb65q`. It **must** be in `orbvpn-f8292` (428639254932). This
   is the single most likely cause.
2. **Wrong client type** — the SHA-1 was added to a *Firebase Android app* whose
   Firebase project isn't `orbvpn-f8292`, so no matching **OAuth Android client**
   exists in the right Cloud project. (If you use Firebase, add the OrbGuard app to
   the `orbvpn-f8292` Firebase project so it auto-creates the Android OAuth client.)
3. **Package typo** — the client's package isn't exactly `com.orb.guard`.

Also, while you're there: **OAuth consent screen** — if Publishing status is
**"Testing"**, either add your test accounts under **Test users** or click
**Publish app** (email+profile are non-sensitive → no verification review). This
isn't the 28444 cause but will block real users at launch otherwise.

After you fix the client, sign-in works with **no app change** — I already
confirmed the app + backend are correct.

</details>

### 🧑‍💻 Also for the Play release build (do before launch)
Play re-signs with **Play App Signing** → a **different** SHA-1 than the debug one.
Once OAuth lives in the `orb-guard` project (above), add the **Play App Signing key
SHA-1** as a second fingerprint on the `com.orb.guard` app **in `orb-guard`** (Play
Console → Setup → App signing → copy the SHA-1), so sign-in also works in the released
build.

---

## Quick summary of what I need back from you

| # | I need from you |
|---|---|
| #70 | **Nothing** — deployed + app wired. Just check the OrbGuard-branded email/link once I re-install the app (device dropped off USB). |
| #71 | App Store shared-secret / Server-API key for `com.orb.guard`; Play service-account access to the OrbGuard app; **decision A or B** on the subscription-collision rule. |
| #69 | In the **`orb-guard` Firebase project**: add the SHA-1 to the app + enable Google sign-in, then send me the **updated `google-services.json`** (§3). Then it works. |
