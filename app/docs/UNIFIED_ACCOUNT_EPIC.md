# Unified Account Epic — shared OrbVPN identity, web remote-control, remote camera

**Kicked off 2026-07-17.** Make OrbGuard part of the OrbVPN account universe: one login +
one subscription across OrbX/OrbVPN and OrbGuard, ad-watch → scan credits, and let a user
control their phone's anti-theft (lock / alarm / mark-stolen / locate / **take a photo of the
thief**) from the `orbnet.admin` web panel.

## Locked decisions (user, 2026-07-17)
1. **Build all three phases in order A→B→C** (full epic; check in per phase).
2. **All 5 repos are mine** to map + modify.
3. **Identity bridge = OrbGuard verifies OrbNet's JWT** (app + web send their OrbNet token
   directly to `guard.orbai.world`, which validates the signature, reads `user_id`, enforces
   device ownership).

## The system (from 4 investigations — the key finding)
Two backends. **OrbNet is the account system; OrbGuard is the security system.** The whole epic
is unlocked by OrbGuard adopting OrbNet identity.

| | **OrbNet** `api.orbai.world` (Go REST, `/Developments/orbnet`) | **OrbGuard** `guard.orbai.world` (Go chi, `orbguard/backend`) |
|---|---|---|
| Used by | OrbX/OrbVPN app + `orbnet.admin` web | OrbGuard app only |
| Identity | Real user accounts (email primary, JWT: user_id/email/role/subscription_*) | **Anonymous device-only** (`/auth/login` returns 501; UserID always "") |
| Subscription | **Account-based** — in JWT claims + `GET /subscriptions/current`; IAP receipts server-reconciled | none (PricingScreen is a UI stub, no IAP) |
| Ad credits | Server-granted: `POST /ad/session`→ show →`POST /ad/verify`→ `GET /tokens/balance.service_only_balance` (1 credit = 1 VPN min) | none, no ad SDK |
| Anti-theft | — | **Built**: locate/ring/selfie/mark-stolen real; **lock/wipe = unimplemented native stubs**; FCM push **now live** (provisioned 2026-07-17); command relay = FCM + 60s/15min poll |

**Cross-app sharing is confirmed account-based** — a sibling app "OrbGo" already shares accounts
by pointing at `api.orbai.world` (comment in OrbX `api_client.dart:73-77`). So same login → same
JWT → same subscription + same credit balance, automatically.

## Reuse map (what to copy from OrbX `orbx.flutter`)
Backend-agnostic REST clients — copy into OrbGuard, point at `api.orbai.world/api/v1`:
`data/api/rest/api_client.dart` (Dio + bearer + 401 auto-refresh), `auth_api.dart`,
`repositories/auth_repository.dart`, `core/services/token_service.dart`, `subscription_api.dart`,
`payment_api.dart`, `ad_api.dart`, `credits_api.dart`, `wallet_api.dart`, `ad_smart_service.dart`;
models `user/auth_response/subscription/subscription_status/ad`. Adapt (strip VPN coupling):
`ad_provider.dart` (keep session→show→verify, drop VPN reconnect); `iap_service.dart` (OrbGuard
needs its OWN store product IDs, but receipts still reconcile onto the shared account).
Token storage = `flutter_secure_storage` keys `auth_token`/`refresh_token`/`user_data` (identical
to OrbX so the session is literally shared on-device where possible).
Deps to add: dio, flutter_secure_storage, get_it, logger; unity_ads_plugin, adivery,
yandex_mobileads, app_tracking_transparency (ads); in_app_purchase(+_storekit/_android);
sign_in_with_apple, google_sign_in, passkeys, local_auth, app_links (auth). **No graphql.**

## Phases

### Phase A — Shared account (login + subscription + ad-scan-credits)  [mostly OrbGuard app + one OrbNet decision]
- A1 Auth: copy OrbX REST/auth/token clients into OrbGuard → `api.orbai.world`; build a login
  screen (email/password + magic-link + OAuth + passkey, all converge on the same flow). Keep the
  existing anonymous device-registration but LINK it to the logged-in user (so the backend can
  scope devices to a user — feeds Phase B).
- A2 Subscription: read entitlement from the JWT/`/subscriptions/current`; replace the free
  `AppMode.pro` local toggle + stub PricingScreen with real entitlement gating; wire IAP with
  OrbGuard's own product IDs (receipts reconcile to the shared account).
- A3 Ads→scan credits: copy the OrbX ad flow (session→show→verify→balance); add scan metering
  (new concept — scans aren't metered today) spent from the credit balance. **OrbNet-side
  decision:** grant scan-credits via the existing `service_only_balance` pool (shared currency)
  vs a new scan-credit ledger (pending OrbNet map — agent ad873ea1).

### Phase B — Device ownership + web remote control  [OrbGuard backend + orbnet.admin web + Android native]
- B1 Identity bridge (OrbGuard backend): verify OrbNet JWT (mechanism pending OrbNet map — shared
  secret vs public key/JWKS), populate `TokenClaims.UserID` from it (the columns/context plumbing
  already exist but are inert), bind `device_security_devices.user_id` to the authed user on
  register, enforce ownership on EVERY `/device/{id}/*` handler (today: horizontal-authz hole —
  any token can command any device), add `GET /device` "my devices" scoped to the user.
- B2 Web UI (orbnet.admin): ✅ BUILT + DEPLOYING (orbnet.admin `61df695`→main→Azure orbnet-admin).
  New `/dashboard/anti-theft` page (device cards + locate/ring/lock/wipe/mark-stolen; wipe type-to-
  confirm; honest "queued" toasts; 402→premium, 404→not-linked). `guard-api-client.ts` reuses the
  OrbNet JWT with `autoRefresh:false` (guard has no /auth/refresh → avoids logout-on-401);
  `api/anti-theft.ts` typed 402/404 mapping. Guard CORS for `orbvpn.xyz` LIVE (`63a0181`, preflight
  verified). tsc/eslint/build clean. **✅ LIVE-VERIFIED (Playwright, real session on orbvpn.xyz):**
  the `/dashboard/anti-theft` page renders (nav entry + honest "commands are queued" alert + stat
  cards + "sign in on the OrbGuard app to link your phone" empty state); the cross-origin
  `GET /device/mine` to guard **succeeded** (clean 0-devices state, not CORS/error) with ZERO console
  errors — CORS + JWT + ownership all working end-to-end. Deployed to orbnet-admin.

**PHASE B COMPLETE (2026-07-18)** — every component built, deployed, verified: B1 backend (prod e2e,
16 assertions), B1-app claim, B2 web panel (live browser), B3 native lock/wipe (APK builds). The only
unproven-live step is a physical device reacting to a web command — needs the new app build on a
phone + logged into OrbNet + device-admin granted (a user-run real-device demo); every piece up to
that is individually verified.
- B3 Android lock/wipe: ✅ DONE (`3df4ba4`). Native `com.orb.guard/device_admin` handler
  (isAdminActive/lockNow/wipeData/requestAdmin) + OrbDeviceAdminReceiver + res/xml (force-lock +
  wipe-data) + manifest BIND_DEVICE_ADMIN + ACTION_ADD_DEVICE_ADMIN enable flow. Honest: inactive
  admin → lock/wipe return false (backend acks FAILED), never faked. Device Security→Anti-Theft tab
  gained an "Enable device administrator" card (Android). APK builds; 267/267 tests. iOS lock/wipe =
  MDM-only (honest-unavailable). Store release is a separate user-controlled step.
- B1-app: ✅ DONE (`ca9a07d`). App claims its device for the signed-in OrbNet account (POST
  /device/{id}/claim with the OrbNet JWT) after login + at agent start — best-effort, idempotent.

#### B backend investigation (2026-07-18, mapped in `orbguard/backend`)
Backend is MORE ready than the memory note implied. Confirmed facts (file:line):
- **Router:** whole `/api/v1` group is behind `apimiddleware.APIKeyAuth(cfg.JWT.Secret)`
  (`internal/api/router.go:84`). Device anti-theft endpoints under `/device/{device_id}/…`
  (`router.go:471-504`): register/get/update, locate/lock/wipe/ring/command,
  commands/pending+ack, mark-lost/stolen/recovered, location(+history), sim(+history/trusted).
- **Auth today:** `APIKeyAuth` (`internal/api/middleware/auth.go:118`) accepts the S2S shared secret
  OR an opaque **Redis-stored session token** (`auth:token:<t>`) whose `TokenClaims` MAY carry
  `UserID`/`DeviceID` → already put in context (`ContextKeyUserID/DeviceID`, :185-190). **No JWT is
  parsed anywhere** — no `golang-jwt` in go.mod. OrbGuard's own `Login` returns **501** ("no user
  store… directing client to device registration", `handlers/auth.go`). ⇒ OrbNet JWT will be the
  PRIMARY user identity.
- **Ownership hole CONFIRMED:** no `/device` handler reads `ContextKeyUserID` or checks the device's
  owner — any authed caller can command any `device_id`. `RegisterDevice` (`handlers/device_security.go:31`)
  decodes the body and stores it with **no** identity from context.
- **Schema (good news):** `device_security_devices` already has `user_id UUID` (nullable) +
  `idx_devsec_devices_user`; `device_commands` also has `user_id UUID` (`migrations/011`, `022`).
  ⚠️ **Type mismatch:** OrbGuard's owner is a **UUID**, but OrbNet's JWT `user_id` is an **INTEGER**
  (saw 22203/22204 in A3 e2e). Plan: add `orbnet_user_id BIGINT` (+ index) to devices (and commands),
  enforce ownership on THAT. Next migration = **023**.
- **Command relay:** `IssueCommand` (`device_security.go:147`) writes to `device_commands`; FCM push
  registry live (`migrations/022`), device also polls `commands/pending` + acks. locate/ring/selfie/
  mark-stolen real; lock/wipe = native stubs (Phase B3).
- **Deploy:** root `.github/workflows/deploy.yml` → Azure Container App `orbguard-lab` rg `ORB` on
  `backend/**` push to main.

**Refined B1 plan:** (1) add `golang-jwt/jwt/v5`; (2) new middleware `OrbNetJWTAuth` — verify HS256
with a new `ORBNET_JWT_ACCESS_SECRET` config, check `iss=="orbnet"` + exp, put int `user_id` in a new
`ContextKeyOrbNetUserID`; mount on `/device` (and a subscriber-gate reading the JWT's subscription_*
claims per the premium decision); (3) migration 023 adds `orbnet_user_id BIGINT` to
`device_security_devices` + `device_commands` (+ indexes); (4) `RegisterDevice`/`UpdateDevice` stamp
`orbnet_user_id` from the verified token (the ownership BOOTSTRAP = the logged-in app claims its
device); (5) an ownership guard helper on every `/device/{device_id}/*` handler (404/403 if the
device's `orbnet_user_id` ≠ caller); (6) `GET /device` my-devices scoped to the caller. App side: send
the OrbNet JWT (Authorization: Bearer) on device register/update/commands once logged in.

#### B1 — DONE + DEPLOYED + e2e-VERIFIED on prod (2026-07-18)
OrbGuard `a4f1e8c` on main (also `ec0b17c` on production-hardening), migration 023 applied to prod DB,
`ORBNET_JWT_ACCESS_SECRET` copied from `orbnet-go`→`orbguard-lab` container (rg ORB). **Prod e2e (real
JWTs + device key) — all green:** unclaimed→404; claim→200 (idempotent), other acct→409; owner read/
mark→200; free owner lock/locate→**402** (premium gate); non-owner get/lock→**404** (isolation);
device-self settings/commands→200 (**app path preserved**); device key→another device→**403** (hole
closed). Verifier + guard + gate unit-tested. **NEXT: B2 (web panel controls) + B3 (native lock/wipe).**

### Phase C — Remote camera ("photograph the thief" from web)  [mostly web UI; loop already exists]
- The full loop already works: web `POST /device/{id}/command {type:take_selfie}` → device polls →
  captures (front camera, real) → `POST /device/{id}/selfie` → web `GET /device/{id}/selfies`.
- C1 Web UI: a "Take photo" button + a photos gallery on the device page.
- C2 (optional/at-scale) real blob storage (Azure Blob) — today the image is base64 in the
  `image_url` text column; fine for MVP, blob is the upgrade. Add camera-selection (front/back).
- C3 Latency + background: FCM now live → near-instant on Android; capture is foreground-only
  (background isolate can't open the camera) — deferred to next foreground; document honestly.

#### C build (2026-07-18) — ✅ DONE + DEPLOYED + verified (orbnet.admin `6c94d11`→prod)
"Take photo" button + Dialog photo gallery on the anti-theft page (`api/anti-theft.ts` `takePhoto`/
`getSelfies`; image_url data URIs render directly; trigger/captured_at/map link; honest queued toast).
tsc/eslint/build clean; deployed to orbnet-admin; live page renders with **0 console errors** (per-device
Photos/Take-photo buttons show once an account has a linked device). **PHASE C COMPLETE — EPIC CODE DONE.**

#### C build (2026-07-18) — was web UI in progress (agent a7f6623b)
Backend loop **verified on prod** (B2 test account): `take_selfie` command → **402** for a free account
(premium-gated exactly like lock/ring); `GET /device/{id}/selfies` → **200** `{count, device_id,
selfies:[]}` for the owner. `ThiefSelfie.image_url` is a **`data:image/jpeg;base64,…`** URI (renders
directly in `<img>`). So C is pure web UI in orbnet.admin, extending the Phase B anti-theft page:
`anti-theft.ts` gets `takePhoto()` (`POST /command {type:take_selfie}`) + `getSelfies()`; the page
gets a per-device "Take photo" button (honest "queued, captured on next check-in" toast) + a photo
gallery (grid of data-URI images with trigger_type + captured_at + optional map link, a Dialog
lightbox, refresh, honest empty state). No backend/app changes — the device+backend side already works.

## External config needed (ads + OAuth) — findings 2026-07-18
Both features are CODE-COMPLETE and fail honestly until these external registrations exist. The
shared *backends* are reusable; the per-app *identity registrations* are not (OrbGuard = `com.orb.guard`
Android / `com.orb.guard` iOS; OrbVPN = `com.orbvpn.android` / `com.orb.vpn`).

**Ads (A3)** — ✅ WIRED + FUNCTIONAL (`a8aa44c`). OrbVPN production IDs are now the platform-aware
DEFAULTS in `rewarded_ad_service.dart` (Unity Android `6025377`/iOS `6025376` + `Rewarded_Android`/`iOS`;
Adivery `c3e6649e-…`/`819b9205-…`; Yandex `R-M-18438192-1`/`R-M-18436157-1`), still `--dart-define`-
overridable. APK builds with the plugins. The watch-ad→scan-credit loop is live out of the box.
⚠️ These IDs are bound to OrbVPN's store listing → mixes revenue + slight no-fill/policy risk under
`com.orb.guard`; clean follow-up = add OrbGuard entries under the SAME ad accounts → own IDs (plug into
--dart-define). Fine for launch/testing as-is.

**Google OAuth** — ✅ iOS + serverClientId WIRED (`a8aa44c`), NO backend change needed. Backend accepts
a LIST (`ORBNET_OAUTH_GOOGLE_VALID_CLIENT_IDS`); OrbX's real serverClientId `428639254932-93ijb65q…`
(a **web** client) is IN that list, so OrbGuard uses it as its default serverClientId → the idToken
audience is already accepted. Default iOS clientId = OrbGuard's OWN iOS client `428639254932-69dmmhiju98…`
(bundle `com.orb.guard`, user-created); its reversed-client-id URL scheme added to `ios/Runner/Info.plist`.
project = `orbvpn-f8292`. **ONE STEP LEFT (Android):** create an Android OAuth client (pkg `com.orb.guard`
+ SHA-1 `12:5A:18:03:8A:6C:F0:D1:38:3D:15:9B:AB:44:FE:97:3C:AD:96:F3`) in that project → drop OrbGuard's
`google-services.json` into `android/app/`. With the shared serverClientId, its audience is already
accepted → no further backend work. (The user-provided `07plgm1s8…` "installed" client is unused — an
installed-type client isn't valid as a serverClientId; the web `93ijb65q…` is used instead.)

**Apple OAuth** — native idToken `aud` = the app bundle (`com.orb.guard`). Backend Apple config is a
SINGLE `ORBNET_OAUTH_APPLE_CLIENT_ID` (currently OrbVPN's `com.orb.vpn`) — needs a small backend change
to also accept `com.orb.guard`. App: enable "Sign in with Apple" on the `com.orb.guard` App ID +
regen profile (entitlement already in code from A1.5).

**Not a blocker:** magic-link + password login work with ZERO config; OAuth is optional polish.

## Honesty guardrails (carry over)
Never claim lock/wipe works where it doesn't (iOS MDM-only; Android needs the native handler).
Web control only after real per-user ownership enforcement (close the horizontal-authz hole first).
Camera capture is foreground-deferred — don't promise instant on a locked/backgrounded phone.

## OrbNet backend contract (resolved 2026-07-17 — the foundation)
OrbNet = **chi v5**, migrations `internal/database/migrations/001..074`, deploys via GH Actions →
Azure Container App **`orbnet-go` (rg ORB)**. No OrbGuard/device concept there yet (clean slate).

- **JWT = HS256 symmetric shared secret.** No JWKS/asymmetric. OrbGuard verifies by: parse →
  require HS256 → key = `ORBNET_JWT_ACCESS_SECRET` (min 32 ch; live value in OrbNet `.env` +
  the `orbnet-go` Azure app env — NOT printed by the agent) → assert `iss=="orbnet"` + `exp`
  future. **No `aud`** (accepts as-is). Access TTL = **1h**; OrbGuard can't refresh (refresh secret
  is OrbNet-internal) → clients re-present a fresh OrbNet access token; OrbGuard treats it as a
  short-lived bearer. Mint/verify ref: `pkg/jwt/jwt.go:203,245-270`.
- ⚠️ **SECURITY TRADEOFF (raise at Phase B):** HS256 shared secret = anyone holding it can *mint*
  OrbNet tokens. Sharing it with OrbGuard grants OrbGuard token-minting power over the whole
  account system. Clean fix = OrbNet moves access tokens to RS256/ES256 + a public key / JWKS
  (none today) so OrbGuard verifies with a PUBLIC key only. Decision for the user at Phase B:
  ship on HS256 now vs invest in RS256/JWKS first.
- **User id = `users.id SERIAL` (int).** JWT `user_id`/`sub` = that int. OrbGuard keys devices on it.
- **Entitlement is IN the token** (`subscription_valid/tier/status/expires_at/...`) — OrbGuard reads
  it from the verified JWT, no extra call. Also `GET /subscriptions/current`.
- **Ad→credit path** (`/ad/session`→`/ad/verify`→`AddServiceCredits`→`token_balances.service_only_balance`;
  `reward_type` ∈ vpn_seconds/seconds/credits already branches). **Scan-credit approach (chosen: a):**
  add `reward_type='scan_credits'`, use the neutral `user_credits` ledger (migration 072) via
  `AddScanCredits`/`DeductScanCredits`, expose `GET /scan-credits/balance` + `POST /scan-credits/spend`.
  Credit ledger lives in OrbNet's DB → OrbGuard grants/spends **server-to-server** using the
  internal API key (`X-API-Key: ORBNET_SERVER_INTERNAL_API_KEY`, `middleware/auth.go:172-205`) or by
  forwarding the user JWT.
- **CORS:** OrbGuard backend must add `https://admin.orbai.world` to its allow-list so the web panel
  can POST anti-theft commands (OrbNet's CORS is irrelevant to a guard.orbai.world call).

## Phase A1 status — DONE + e2e-verified (2026-07-17)
Committed `d433207`. OrbNet auth stack ported (`lib/services/orbnet/*`), `AccountProvider`,
`LoginScreen` ("Sign in with your OrbVPN account"), Settings "Account" section, `flutter_secure_storage`.
analyze 0/0; 236/236 tests (3 new). **e2e proven:** (1) live `api.orbai.world` register+login loop
returns real USER JWT; (2) a REAL-account sign-in on the device (`nima@golsharifi.com`) authenticated
against prod OrbNet and returned a genuine RFC-7807 policy response — the full request→auth→parse→
display stack works. Login screen + Settings Account section render correctly (verified on device,
light+dark). (Build infra note: needed `flutter clean` + clearing a corrupt `~/.gradle/caches/8.14`
transform — disk-full collateral, not code.)

⚠️ **DEVICE-LIMIT FINDING (epic decision needed).** OrbNet login counts the caller as a *device*
against the plan's device limit (the real account hit **"logged in on 8 devices but your plan allows
only 7"**). So OrbGuard sharing the account **consumes a VPN device slot** — friction, and the user's
account is already over. Decision: should an OrbGuard sign-in count against the VPN device limit?
Likely NOT (OrbGuard is a security companion, not a tunnel) → an OrbNet-side change to exclude the
OrbGuard platform from the device-limit count (or give OrbGuard its own limit). Raise before A2 ships.

## Phase A progress
The **account layer (A1 + A1.5 + A2) is DONE and comprehensively verified.** A3 (ads→credits) is
the remaining Phase A work and needs shared-backend (OrbNet) changes — see the decision point below.

- **A1 (login)** ✅ e2e-verified. `d433207`. Real-backend proof: register+login of a throwaway
  account returned a real USER JWT for BOTH password and magic-link paths (the network/session
  layer genuinely works). A real-account login correctly hit OrbNet's device-limit policy (7/plan)
  — proving the full stack end to end, and motivating OrbGuard's own device limit (A3/backend).
- **A2 (subscription gating)** ✅ `ec671c2`. `hasPremium` + `PremiumGate` upsell; Pro console now
  subscriber-gated; PricingScreen reflects real state. Gate behavior directly tested
  (`premium_gate_test.dart`): premium→passes through; logged-out→"Sign in" upsell; logged-in-free→
  "See plans" upsell; + the real Settings Pro-toggle integration (toggle stays off, upsell shows).
- **A1.5 (login UX + OAuth)** ✅ `be0d08b` + `e05c8a9`. Magic-link primary, password secondary,
  Google/Apple buttons (real flows, honest errors). **On-device verified (Android Galaxy Fold):**
  login screen renders per spec (Google button, Apple correctly hidden on Android, lime magic-link
  primary, "Use password instead" reveal swaps to password form + "Sign in"), and the honesty
  guardrail fires — an unconfigured Google tap shows "Couldn't sign in with Google — try email
  instead" with NO fake session. Credential handoff proven in CI (`login_screen_test.dart`): typed
  email+password reach `login()` verbatim → "Signed in"; typed email reaches `loginWithMagicLink()`
  → advances to code entry. Full suite **252/252**, analyze 0/0.
  - *Note on manual on-device login demo:* a live typed-login screenshot was blocked by environment,
    not by OrbGuard — the Android device's default voice-assistant (Midas/OrbX) repeatedly stole
    foreground, and the iOS sim lacks `idb` for scripted taps. The successful-login path is instead
    proven by the combination above (real-backend JWT + on-device UI + in-CI credential handoff),
    which is reproducible rather than a one-off screenshot.
  - **Config still needed for Google/Apple e2e:** Google OAuth clients + serverClientId
    (google-services.json is FCM-only, 0 oauth_client entries), Apple capability on the App
    ID/profile (iOS entitlement added), and OrbNet `/auth/oauth/login` must accept OrbGuard's OAuth
    audience. Magic-link + password work with no extra config.
- **A3 (ads → scan credits)** 🚧 IN PROGRESS.
  - **Backend ✅ BUILT + DEPLOYED** (2026-07-18). OrbNet commit `abb8517` on `main` (rebased onto
    origin, gated, no OrbX overlap) → Azure deploy triggered. Adds `token_balances.scan_credit_balance`
    (migration 104, embedded/idempotent, auto-applies on startup), `reward_type='scan_credits'`
    opt-in on `POST /ad/session`, a scan-credit branch in `grantSessionReward` (OrbX/VPN paths
    untouched), `token.Add/Deduct/GetScanCredits`, and `GET /scan-credits/balance` + `POST
    /scan/consume` (402 when empty). Rate `ORBNET_SCAN_CREDITS_PER_AD` (default 1). Build+vet+tests
    green. **✅ POST-DEPLOY E2E VERIFIED ON PROD** (real fresh-account JWTs, api.orbai.world):
    (1) full loop — balance 0 → `/ad/session {reward_type:scan_credits}` → `/ad/verify` grants
    `scan_credits_earned:1` → balance 1 → `/scan/consume` → balance 0 → `/scan/consume` → **402
    "Insufficient scan credits"**. (2) Isolation — after a scan_credits ad, scan_credits=1 but VPN
    `service_only_balance=0`. (3) OrbX unchanged — a NORMAL ad (no reward_type) → `reward_type:
    vpn_seconds`, VPN `service_only_balance=+3`, scan_credits=0. Gating confirmed bulletproof.
  - **App side ✅ BUILT + WIRED** (`95e46d3` foundation, `c1d9e96` gate). OrbNet ad + scan-credit
    client (`ad_api`/`scan_credit_api`, 402→`InsufficientScanCreditsException`), `ScanCreditProvider`
    (earn/spend, honest — credit only after a real ad + `/ad/verify`), config-gated Unity→Adivery→
    Yandex waterfall (`rewarded_ad_service`, `--dart-define` IDs, `AdsNotConfigured` never faked),
    `watch_ad_sheet`. **Gate model (user chose "every scan costs a credit"):** `scan_gate.ensureScanCredit`
    — premium=unlimited/no ads; free=1 credit/scan (out→watch-ad sheet; signed-out→sign-in; error→
    blocked+surfaced). Wired into `main.dart _startScan(userInitiated)` (first-run check + auto-scan
    exempt) + `dashboard_screen`. Suite **267/267**.
  - **⛔ NEEDS USER: ad config** — Unity/Adivery/Yandex IDs via `--dart-define` (`UNITY_GAME_ID`,
    `UNITY_REWARDED_PLACEMENT`, `ADIVERY_APP_ID`, `ADIVERY_PLACEMENT`, `YANDEX_REWARDED_UNIT_ID`) +
    native (iOS `SKAdNetworkItems`/`NSUserTrackingUsageDescription` + `pod install`; Android
    Yandex/Adivery maven + minSdk + AD_ID perm). Until supplied, ads are honestly UNAVAILABLE, so a
    free user who is out of credits genuinely can't scan (premium + the free onboarding check work).
  - Device e2e of the UI blocked by (a) ad config above and (b) the device-limit login blocker (#64).
  - **Device limit** (decision #4) — ✅ BUILT + DEPLOYED (2026-07-18). OrbNet `b1235cd` on main +
    app `1c18710`. Opt-in `client="orbguard"` on login → routes through the EXISTING no-device path
    (`issueWebSession`/`LoginByUserIDWeb`, same as web checkout): OrbGuard logins don't consume a VPN
    device slot (own limit, enforced by guard.orbai.world), so capped users (free=1) can log in.
    Strictly gated (`IsOrbGuardClient`, `oneof=orbguard`) → OrbVPN path byte-for-byte unchanged; app
    sends `client:'orbguard'` on password/magic/OAuth. Passkey/QR/security paths untouched, no
    migration. build+vet+tests green (+TestIsOrbGuardClient). **✅ POST-DEPLOY E2E VERIFIED ON PROD:**
    3 `client=orbguard` logins with different device_ids all HTTP200 (489c no-device token), while a
    NORMAL client got HTTP200 on device 1 then HTTP403 DEVICE_LIMIT_EXCEEDED on devices 2–3 (free
    tier=1). OrbGuard bypasses the VPN limit; OrbVPN enforcement intact.

### A3 technical plan (from investigation, agent a356a83d, 2026-07-18)
**Key simplifier:** OrbGuard's ported OrbNet auth stack (`lib/services/orbnet/`, base `api.orbai.world`)
already yields a user JWT, so **the app calls OrbNet `/ad/session` + `/ad/verify` DIRECTLY** — no new
S2S backend route needed. OrbNet's HMAC-per-session + idempotent `GrantReward` already guard double-credit.

**OrbX ad stack to mirror** (`/Developments/orbx.flutter`): plugins `unity_ads_plugin ^0.4.0` (global),
`adivery ^4.9.0` (Iran), `yandex_mobileads ^7.18.0` (Russia). Flow = `AdProvider.watchAdForVPNTime()`
(`ad_provider.dart:1625`) → `startAdSession`→`POST /ad/session` (`ad_api.dart:13`) → show → reward cb →
`_verifyAndCreditReward()` (`:2224`) → `smartVerify`→`POST /ad/verify` (`ad_api.dart:32`) → refresh balance.

**OrbNet side** (`/Developments/orbnet`, next migration = **104**):
- `grantSessionReward` (`internal/handler/adverification.go:230-262`) currently: `reward_type` ∈
  `vpn_seconds`(legacy)/`credits`(→`AddServiceCredits`→`token_balances.service_only_balance`)/`bonus`.
- ADD `reward_type='scan_credits'` + a **separate** balance (new `token_balances.scan_credit_balance`
  col or a `scan_credits` table — keep OUT of `service_only_balance` so VPN minutes don't mingle) +
  `AddScanCredits` mirroring `AddServiceCredits` (`token/service.go:1395`), ledger `type='SCAN_CREDIT'`.
- Reward amount via `ad_provider_config.reward_credits` (`GetCreditsPerAd`, `vpnauth/service.go:921`),
  gated so OrbGuard sessions grant scan_credits not VPN minutes.
- Spend endpoint `POST /scan/consume` (JWT) → `DeductScanCredits` (pattern `DeductServiceCredits`
  `token/service.go:1443`). `ORBNET_SERVER_INTERNAL_API_KEY` middleware exists (`auth.go:171`) but no
  credit-grant internal route today — not needed for the direct-JWT approach.
- ⚠️ OrbNet is the LIVE shared VPN backend — changes to `grantSessionReward`/token service touch OrbX.
  Gate strictly on `reward_type`/app; check in with user before deploying to prod (GH Actions → Azure rg ORB).

**OrbGuard app side** (no ad/credit code exists yet; scan chokepoints found):
- Add ad SDK(s) to pubspec; port slim ad client (reuse `orbnet_api_client.dart`) + trimmed `AdProvider`
  (drop VPN-pause) + `ScanCreditProvider{balance, canScan, refresh()}`.
- "Watch ad → earn scan credits" button by the dashboard scan CTA (`dashboard_screen.dart:161`).
- **Gate the scan** at `scanning_screen.dart:136 _startScan` / `_navigateToScan` before
  `app_malware_scanner.dart:86 scan()`; zero credits → watch-ad sheet. Decide auto-scan
  (`auto_scan_scheduler.dart`) exempt vs metered.
- **Device limit:** the A1 e2e hit OrbNet's device-limit policy (7/plan). OrbGuard needs its OWN limit —
  likely an OrbNet-side device-kind/app tag so OrbGuard registrations don't consume VPN device slots.

## Premium model — DECIDED (user, 2026-07-17)
- **Device limit:** OrbGuard gets its OWN separate device limit, independent of the VPN's 7 →
  OrbNet-side change (a distinct limit/counter for OrbGuard installs; exclude from VPN device count).
- **Subscription unlocks EVERYTHING** (free tier = basic scanning + watch-ads-for-scan-credits;
  subscriber = full product): (1) ad-free + more/unlimited scan credits; (2) the Pro/expert console
  (today a free toggle → becomes premium); (3) unlimited + deeper scans (dark-web/forensics/full
  app-malware); (4) the Phase B/C remote control + thief-camera are subscriber-only.
- Gating key = `AccountProvider.hasPremium` (isLoggedIn && subscriptionValid). Logged-out or
  no-valid-subscription = free tier. Build a reusable `PremiumGate` for A2 + reused in B/C.

## Phase split clarified
- **Phase A stays app↔OrbNet only** (login/subscription/ads hit `api.orbai.world` directly; no
  shared secret needed yet; guard.orbai.world stays on the device api_key). Ship login + real
  subscription gating + ad→scan-credits.
- **Phase B** is where guard.orbai.world verifies the OrbNet JWT (the HS256-secret decision lands
  here), links device→user_id, and enforces ownership.
