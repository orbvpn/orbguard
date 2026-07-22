# OrbGuard — App Store Connect version info (copy/paste)

For the **1.0** version page (English U.K.). Screenshots are in `store-assets/ios/`
(1242×2688, valid 6.5" size — the first 3 are used on the install sheet).

---

## Promotional Text (≤170) — editable anytime without review
```
Scan your phone for spyware, block scam texts and dangerous sites, firewall malicious connections, and find, lock or recover your phone if it's lost or stolen.
```
(159 chars.)

## Keywords (≤100, comma-separated, NO spaces after commas)
```
antivirus,spyware,anti-theft,find my phone,scam,phishing,privacy,firewall,malware,security,stalkerware
```
(100 chars. Don't repeat the app name or words already in the title — Apple indexes those automatically.)

## Description (≤4000)
```
OrbGuard is your all-in-one mobile security and anti-theft app. It scans your phone for spyware and risky apps, screens scam texts and dangerous websites, blocks malicious connections with an on-device firewall, and helps you find, lock, or recover your phone if it's ever lost or stolen — all from one simple, honest app.

WHY ORBGUARD
Most "security" apps do one thing. OrbGuard brings the essentials together in a clean app that tells you the truth about your phone — and never fakes a result.

SCAN FOR SPYWARE & RISKY APPS
• Check installed apps for spyware, stalkerware and dangerous permission combinations
• Inspect an app file before you install it, and spot apps that impersonate ones you already have
• Get a clear Privacy Score with the exact things to fix

STOP SCAMS & PHISHING
• Scam Text Filter screens messages for smishing, phishing and malicious links
• Website protection warns you about dangerous and fraudulent sites
• Check suspicious phone numbers and QR codes

ON-DEVICE FIREWALL
• Blocks known malicious, tracking and surveillance domains
• Runs quietly with a live "blocked today" counter — protection stays on in the background

ANTI-THEFT: FIND, LOCK, RECOVER
• Locate your phone from the app or your OrbGuard web account
• Sound an alarm, lock the screen, or mark it lost/stolen
• If it's stolen, capture a photo from the front camera to see who has it
• You control all of this — only for your own device

PRIVACY BY DESIGN
• Anonymous scanning works with no account at all
• Sign in with a passwordless email link, Apple, Google, or a passkey (Face ID / Touch ID)
• We don't sell your data

ONE ACCOUNT ACROSS ORB
OrbGuard shares your Orb (OrbVPN) account and subscription. Sign in once and your protection follows you — and an OrbGuard subscription also unlocks your OrbVPN access.

SUBSCRIPTION
OrbGuard offers optional Basic, Premium and Ultimate plans (monthly or yearly). Premium unlocks unlimited ad-free scans, full anti-theft remote control and thief-camera capture. Core scanning is free. Payment is charged to your Apple Account at confirmation of purchase. Subscriptions renew automatically unless turned off at least 24 hours before the end of the period; manage or cancel anytime in your Apple Account settings.

IMPORTANT
OrbGuard's anti-theft features (location, remote lock, camera capture) are for YOUR OWN device and are always started by you, the owner — for example after your phone is lost or stolen. Do not use them to monitor anyone else.

Terms of Service: https://orbvpn.com/terms
Privacy Policy: https://orbvpn.com/privacy
Questions? support@orbvpn.com
```

## Support URL
```
https://orbvpn.com/support
```

## Marketing URL (optional)
```
https://orbvpn.com
```

## Version
```
1.0
```

## Copyright (≤200)
```
© 2026 OrbVPN
```

## Routing App Coverage File
Leave empty (that's only for maps/routing apps).

---

## App Review Information

### Sign-In required: **Yes** — provide a demo account
Because sign-in is passwordless by default, set a **password** on a demo Orb account
and enter it here (the app has a "Use password instead" option). Give it an active
subscription so premium features show.
```
User name: [ your demo Orb account email ]
Password:  [ password you set on it ]
```

### Contact Information
```
First name: [ your first name ]
Last name:  [ your last name ]
Phone:      [ your phone ]
Email:      nima@nubatt.com
```

### Notes (≤4000)
```
OrbGuard is a personal device-security and anti-theft app. Sign-in uses your Orb (OrbVPN/OrbNet) account and is passwordless by default (email sign-in link), with Apple, Google, and passkey options. A demo account WITH A PASSWORD is provided in Sign-In Information so review can sign in without email access — use the "Use password instead" option on the sign-in screen.

Reaching premium features / the paywall:
1. Launch the app (anonymous scanning works with no account).
2. Settings tab → "Sign in / Account" → sign in with the demo account.
3. Premium features (unlimited ad-free scans; anti-theft remote control and camera capture) are gated behind the subscription; the paywall is reachable from Settings and when tapping a premium feature.

About the sensitive features:
- Anti-theft camera capture, location, and remote lock are ALWAYS initiated by the account owner for their OWN enrolled device (e.g. after loss/theft). They are not covert monitoring of third parties. The app requests the relevant permissions and the Terms require the user to have the legal right/consent to use them. Location and remote actions are optional and off until the user enables them.

Shared subscription: OrbGuard shares one subscription with OrbVPN via the common Orb account, so a purchase here also applies to the user's OrbVPN access.

Contact: support@orbvpn.com
```

---

## App Store Version Release
Choose **"Manually release this version"** for a first launch (so you control the
go-live moment after approval). Switch to automatic later if you prefer.

---

## FIRST-SUBMISSION checklist (other required sections, outside this screen)

1. **Build** — none uploaded yet. I can build + upload the iOS build via
   `flutter build ipa` → `asc-upload` (your Apple team key). NOTE: needs the
   provisioning profile to carry the new capabilities (Sign in with Apple,
   Associated Domains for passkeys, Push, Network Extension) — see below.

2. **Export compliance** — handled: I set `ITSAppUsesNonExemptEncryption = false`
   in Info.plist (app uses only standard HTTPS/TLS = exempt), so you won't be
   prompted per upload.

3. **App Privacy** (App Store Connect → App Privacy) — you must fill the data-
   collection questionnaire. Declare: Contact Info (email) for account; Identifiers;
   Diagnostics; Location (for anti-theft, linked to user, app functionality);
   User Content / Photos (thief-camera image, app functionality); and note SMS
   content is processed for security (not on iOS — SMS scanning is Android-only,
   so on iOS you can omit SMS). Do NOT mark anything as "used for tracking".

4. **Age rating** — complete the questionnaire → expect **17+** (unrestricted web
   access via URL checks / the security context). Nothing objectionable, but
   answer honestly.

5. **Category** — Primary **Utilities**, Secondary **Productivity** (matches OrbVPN).

6. **In-App Purchases** — Apple requires your **first** subscription to be submitted
   **with** the app version. Attach your OrbGuard subscriptions (the `orbguard_*`
   products) to this 1.0 submission.

7. **Capabilities on the App ID / provisioning** (Apple Developer portal) so the
   build's features work: Sign in with Apple ✅ (done earlier), Push Notifications,
   Associated Domains (`webcredentials:orbai.world` for passkeys), App Groups,
   Network Extensions. Enable any missing ones before I build the IPA.

Tell me when you're ready and I'll build + upload the iOS build.
