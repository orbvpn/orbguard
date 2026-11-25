# OrbGuard — Microsoft Store listing copy

Version-controlled source for the Partner Center listing (app `9P7B42QW180D`).
Applied to the submission via the Store submission API.

## Why this differs from the iOS/Play copy

Two claims in the shared description are wrong or not allowed on Windows:

1. **QR code scanning** — `mobile_scanner` has no Windows implementation, so the
   Windows build does not offer a QR scanner at all. Advertising it is a 10.2.x
   metadata mismatch.
2. **"One subscription (purchased on iOS/Android)"** — naming another store as
   the place to buy is prohibited steering under Microsoft Store Policy 10.8.2.
   The Windows build sells nothing; premium simply travels with the Orb account.

Everything else is accurate for Windows as of the native scanner landing
(`app/windows/runner/orbguard/`), which implements the same
`com.orb.guard/system` checks Android and iOS run.

## Title

OrbGuard

## Description

```
OrbGuard tells you if you're being watched. It checks this PC for spyware and
risky software, shows which apps have really been using your camera, microphone
and location, screens scam links and dangerous websites, and adds anti-theft
protection for the devices on your account - all in one clean, honest app that
never fakes a result.

KNOW IF YOU'RE BEING WATCHED
- Security checkups for spyware, stalkerware and risky software
- See which apps have actually used your camera, microphone and location
- Spots programs that start with Windows, hide inside your browser, or borrow a
  Windows system name to blend in
- Checks for certificates that could let someone read your encrypted traffic
- Clear, plain-English results with the exact things to fix

STOP SCAMS & PHISHING
- Check suspicious links before you open them
- Website protection warns about dangerous and fraudulent sites

ONE ACCOUNT, EVERY PLATFORM
- Sign in with your Orb account - passkeys supported
- Premium features travel with your Orb account across OrbGuard, OrbVPN and
  OrbBrowser
- Manage anti-theft for your phones from the web or desktop

HONEST BY DESIGN
- A check that cannot run on this PC says so - it is never counted as "clean"
- We analyse only what's needed to warn you about threats
- Never sold, never used for advertising profiles
- Delete your account and all data any time, right in the app

Privacy policy: https://orbvpn.com/privacy
Terms: https://orbvpn.com/terms
```

## Features

- Spyware & risky-software checkups
- Camera, microphone & location usage transparency
- Scam link & website protection
- Passkey sign-in
- One account across OrbGuard, OrbVPN & OrbBrowser

## Notes for certification

Maintained at `app/docs/WINDOWS_CERT_NOTES.md` — it walks the reviewer through
the sign-in flow that failed 10.1.2.10 in 1.0.6.0.

## Screenshots

The listing currently reuses the macOS captures (`store-assets/macos/`) as
`desktop1-3.png`. Genuine Windows captures are still owed: taking them needs an
interactive desktop session on a Windows machine, which the automated pipeline
cannot produce. Replace them with a listing-only update when available.
