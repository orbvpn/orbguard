# OrbGuard — Subscription products to create (copy/paste)

Prices/durations mirror OrbVPN's **live** products (pulled 2026-07-19).

> **Apple IAP product IDs are globally unique across your whole developer account**
> (not per-app), so OrbGuard uses its own `orbguard_*` IDs. I map those to the same
> shared OrbNet plans in the backend, so an OrbGuard purchase unlocks the same account
> (and OrbVPN). Use the **same `orbguard_*` IDs on Google** too.

**6 products** = 3 tiers (Basic / Premium / Ultimate) × 2 durations (Monthly / Yearly).

| Product ID | Duration | Price (USD) | Tier | Maps to plan |
|---|---|---|---|---|
| `orbguard_basic_monthly`   | 1 month | 3.99  | Basic    | basic-monthly |
| `orbguard_premium_monthly` | 1 month | 6.99  | Premium  | premium-monthly |
| `orbguard_ultimate_monthly`| 1 month | 11.99 | Ultimate | ultimate-monthly |
| `orbguard_basic_yearly`    | 1 year  | 20.99 | Basic    | basic-yearly |
| `orbguard_premium_yearly`  | 1 year  | 49.99 | Premium  | premium-yearly |
| `orbguard_ultimate_yearly` | 1 year  | 79.99 | Ultimate | ultimate-yearly |

**Field limits (App Store):** Display Name ≤ 30 chars · Description ≤ 45 chars. All
values below fit.

---

# A) APP STORE CONNECT  (App → Monetization → Subscriptions)

Subscription **Group → Reference Name:** `OrbGuard`

Per subscription set Reference Name, Product ID, Duration, Price, and one
**Localization (English (U.S.))** = Display Name + Description.

| # | Reference Name | Product ID | Duration | Price | Display Name | Description (≤45) |
|---|---|---|---|---|---|---|
| 1 | `OrbGuard Basic Monthly`     | `orbguard_basic_monthly`   | 1 Month | 3.99  | `OrbGuard Basic`    | `Essential security scans & alerts` |
| 2 | `OrbGuard Premium Monthly`   | `orbguard_premium_monthly` | 1 Month | 6.99  | `OrbGuard Premium`  | `Full protection + anti-theft control` |
| 3 | `OrbGuard Ultimate Monthly`  | `orbguard_ultimate_monthly`| 1 Month | 11.99 | `OrbGuard Ultimate` | `All features across all your devices` |
| 4 | `OrbGuard Basic Yearly`      | `orbguard_basic_yearly`    | 1 Year  | 20.99 | `OrbGuard Basic`    | `Essential security scans & alerts` |
| 5 | `OrbGuard Premium Yearly`    | `orbguard_premium_yearly`  | 1 Year  | 49.99 | `OrbGuard Premium`  | `Full protection + anti-theft control` |
| 6 | `OrbGuard Ultimate Yearly`   | `orbguard_ultimate_yearly` | 1 Year  | 79.99 | `OrbGuard Ultimate` | `All features across all your devices` |

Copy-paste values (each ≤ limits):

- Display Names: `OrbGuard Basic` (14) · `OrbGuard Premium` (16) · `OrbGuard Ultimate` (17)
- Descriptions:
  - Basic:    `Essential security scans & alerts`      (33)
  - Premium:  `Full protection + anti-theft control`   (36)
  - Ultimate: `All features across all your devices`   (36)

---

# B) GOOGLE PLAY CONSOLE  (Monetize → Products → Subscriptions)

6 subscriptions (one per product ID). Each: create with the Product ID, add **one
base plan** (auto-renewing, matching period + price), fill Name + benefit. The
receipt's product id = the **subscription** id (`orbguard_*`) — keep exact.

| Product / Subscription ID | Name | Base plan ID | Period | Price | Benefit (short) |
|---|---|---|---|---|---|
| `orbguard_basic_monthly`   | `OrbGuard Basic (Monthly)`    | `monthly-auto` | 1 month | 3.99  | Essential security scans & alerts |
| `orbguard_premium_monthly` | `OrbGuard Premium (Monthly)`  | `monthly-auto` | 1 month | 6.99  | Full protection + anti-theft control |
| `orbguard_ultimate_monthly`| `OrbGuard Ultimate (Monthly)` | `monthly-auto` | 1 month | 11.99 | All features across your devices |
| `orbguard_basic_yearly`    | `OrbGuard Basic (Yearly)`     | `yearly-auto`  | 1 year  | 20.99 | Essential security scans & alerts |
| `orbguard_premium_yearly`  | `OrbGuard Premium (Yearly)`   | `yearly-auto`  | 1 year  | 49.99 | Full protection + anti-theft control |
| `orbguard_ultimate_yearly` | `OrbGuard Ultimate (Yearly)`  | `yearly-auto`  | 1 year  | 79.99 | All features across your devices |

---

# C) REVIEW NOTES

## C1. Per-subscription "Review Notes" (paste into each subscription's review field)
Same note works for all 6 (adjust the tier word):

```
This auto-renewable subscription unlocks OrbGuard's premium protection for the
signed-in account: unlimited ad-free security/privacy scans plus the anti-theft
suite (remote locate, alarm, lock, and owner-triggered camera capture) for a
lost or stolen device. Tiers differ by device limit. The account is shared with
the user's Orb (OrbVPN) account, so the same subscription also applies there.
To test: open the app, tap Settings → Sign in, sign in with the demo account in
App Review Information, then open Settings → subscription / the paywall to
purchase in the sandbox. Anti-theft actions are always initiated by the account
owner on their own enrolled device and require the permissions the app requests.
```

## C2. App-level "App Review Information → Notes" (App Store → App Review Information)

```
OrbGuard is a personal device-security and anti-theft app. Sign-in uses your Orb
(OrbVPN/OrbNet) account and is passwordless by default (email sign-in link), with
Google, Apple, and passkey options. A demo account with a PASSWORD is provided
below so review can sign in without email access.

Reaching premium features / the paywall:
1. Launch the app (anonymous scanning works with no account).
2. Settings tab → "Sign in / Account" → sign in with the demo account.
3. Premium features (unlimited ad-free scans; anti-theft remote control and
   camera capture) are gated behind the subscription; the paywall is reachable
   from Settings and when tapping a premium feature.

About the sensitive features:
- Anti-theft camera capture, location, remote lock and remote wipe are ALWAYS
  initiated by the account owner for their OWN enrolled device (e.g. after loss/
  theft). They are not covert monitoring of third parties. The app requests the
  relevant permissions and the Terms of Service require the user to have the legal
  right/consent to use them.
- Remote wipe and location are optional and off until the user enables them.

Shared subscription: OrbGuard shares one subscription with OrbVPN via the common
Orb account, so a purchase here also applies to the user's OrbVPN access.

Contact: support@orbvpn.com
```

## C3. Demo account (you must fill this in — App Review Information → Sign-In)
Provide a real test account the reviewer can use. Because default sign-in is
passwordless, EITHER:
- (a) Set a **password** on a demo Orb account and put the email + password in the
  Sign-In fields (recommended — the app has a "Use password instead" option), OR
- (b) Provide an email whose inbox the reviewer can reach for the sign-in link.

```
Demo email:    [ your demo Orb account email ]
Demo password: [ password you set on it ]  (use the app's "Use password instead")
```
Give this demo account an active OrbGuard/OrbVPN subscription (or note that review
can complete a sandbox purchase) so the premium features are visible.

---

## Notes
- **Do NOT change the Product IDs** — the backend maps `orbguard_*` → the shared plans.
- Prices are OrbVPN's current USD; change only if you deliberately want OrbGuard to differ.
- Apple: create now (app exists). Google: create the app + upload the AAB first.
- After live: send me the Apple **App-Specific Shared Secret** and confirm the Play
  **service-account access**, and I'll wire receipt validation + the `orbguard_*`→plan map.
