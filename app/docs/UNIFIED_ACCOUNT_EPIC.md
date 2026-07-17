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
- B2 Web UI (orbnet.admin): the USER role + `/dashboard/devices` "My Devices" page already exist;
  add anti-theft controls (lock/alarm/mark-stolen/locate) + a second api-client targeting
  `guard.orbai.world` sending the OrbNet JWT. shadcn/ui; `src/api/anti-theft.ts` + page extension.
- B3 Android lock/wipe: write the `com.orb.guard/device_admin` native handler + DeviceAdminReceiver
  (the Dart bridge `device_admin.dart` exists; no native side). iOS lock/wipe = MDM-only (leave
  honest-unavailable).

### Phase C — Remote camera ("photograph the thief" from web)  [mostly web UI; loop already exists]
- The full loop already works: web `POST /device/{id}/command {type:take_selfie}` → device polls →
  captures (front camera, real) → `POST /device/{id}/selfie` → web `GET /device/{id}/selfies`.
- C1 Web UI: a "Take photo" button + a photos gallery on the device page.
- C2 (optional/at-scale) real blob storage (Azure Blob) — today the image is base64 in the
  `image_url` text column; fine for MVP, blob is the upgrade. Add camera-selection (front/back).
- C3 Latency + background: FCM now live → near-instant on Android; capture is foreground-only
  (background isolate can't open the camera) — deferred to next foreground; document honestly.

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

## Phase split clarified
- **Phase A stays app↔OrbNet only** (login/subscription/ads hit `api.orbai.world` directly; no
  shared secret needed yet; guard.orbai.world stays on the device api_key). Ship login + real
  subscription gating + ad→scan-credits.
- **Phase B** is where guard.orbai.world verifies the OrbNet JWT (the HS256-secret decision lands
  here), links device→user_id, and enforces ownership.
