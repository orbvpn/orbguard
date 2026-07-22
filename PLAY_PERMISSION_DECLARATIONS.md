# OrbGuard — Google Play permission declarations (answer sheet)

Audited against the real code on 2026-07-20. Copy/paste the blocks. Char counts fit
the 500-char fields.

> ⚠️ **Read §4 and §5 first** — `MANAGE_EXTERNAL_STORAGE` and (optionally)
> `ACCESS_BACKGROUND_LOCATION` are the two most-rejected permissions on Play.
> Removing what you don't strictly need is far safer than declaring it.

---

## 1. FOREGROUND_SERVICE_SPECIAL_USE  ✅ genuinely used

**What it is:** `OrbFirewallVpnService` — an on-device DNS firewall (VpnService)
already declaring `foregroundServiceType="specialUse"` with the subtype
*"On-device DNS firewall that blocks malicious domains"*. It shows a persistent
notification (*"OrbGuard is protecting… Firewall active · N blocked today"*), so the
task is user-noticeable — which is exactly what Play requires.

**Answer — "What tasks require FOREGROUND_SERVICE_SPECIAL_USE?"**
```
OrbGuard runs an on-device DNS firewall as a VpnService that continuously screens the device's DNS queries and blocks known malicious, phishing and surveillance domains. Protection must stay active while the user is not in the app - that is the entire point of a firewall - so it runs as a foreground service. It is user-noticeable: a persistent notification shows the firewall is active and how many domains were blocked today, and the user can disable it at any time from that notification or in the app.
```

---

## 2. QUERY_ALL_PACKAGES  ✅ permitted use (antivirus)

OrbGuard's App Malware Scan enumerates installed packages to inspect permissions,
signing cert, install source and malware signatures. "Antivirus apps" is an
explicitly permitted use.

**Core purpose (≤500):**
```
OrbGuard is a mobile security/antivirus app. Its App Malware Scan enumerates installed packages so it can inspect each app's risk signals - requested dangerous permissions, signing certificate, install source and known malware/stalkerware signatures - and warn the user about malicious or spyware apps. Broad visibility is required because a threat can be any installed package; a scoped <queries> list cannot detect unknown or newly-installed malware. Findings are shown in the app's Scan and Protect screens.
```

**Usage — tick:**
- ✅ **App functionality**
- ✅ **Fraud prevention, security, and compliance**
- ❌ Everything else (no analytics/ads/personalization use of the app list)

**Video:** required. Record: open OrbGuard → Scan → run the app/malware scan →
show the per-app results list. ~60s, narrate that it's scanning installed apps.

---

## 3. BIND_ACCESSIBILITY_SERVICE  ⚠️ needs a prominent-disclosure video

Three services: `AccessibilityMonitorService` (detects malicious/abusive
accessibility services — a classic spyware vector), `BrowserAccessibilityService`
(reads the URL bar to warn on phishing sites), `MessagingAccessibilityService`.

**Usage — tick:**
- ✅ **App functionality**
- ✅ **Fraud prevention, security, and compliance**

**Sensitive data — answer `Yes`** if the browser-protection service sends visited
URLs off-device for reputation lookup (OrbGuard has a URL-reputation backend, so
this is almost certainly **Yes**). Answering "No" while URLs leave the device would
be a false declaration. → Then you must disclose it in-app and in the privacy policy.

**Prominent-disclosure video must show**, before the user enables the service, a
screen that says *why* (detect spyware abusing accessibility; warn about phishing
pages) and *what data* (page URLs checked for reputation). Your current in-app sheet
says accessibility is used to detect malicious services and explicitly states
"OrbGuard will NOT read your screen content" — good, but it must also mention the
URL check if URLs are sent.

---

## 4. MANAGE_EXTERNAL_STORAGE  🔴 RECOMMEND REMOVING

**Finding:** in the code this is only a *permission check*
(`Environment.isExternalStorageManager()` in `MainActivity.checkStoragePermission()`).
There is no shipped feature that requires reading every file on the device.

All-files access is one of Play's most-rejected permissions, and "we scan files" is
only accepted for genuine file-manager/antivirus file scanning that provably cannot
use MediaStore/SAF. **Unless you ship a real full-disk file scanner, remove it** —
that deletes this whole declaration and its rejection risk.

*If you do keep it*, you must answer:
- **Feature (≤500):** describe the actual on-device file malware scan.
- **Usage:** ✅ Core functionality (only)
- **Technical reason (≤500):** must argue MediaStore/SAF can't work — e.g. malware
  hides in non-media files in app-specific and download directories that MediaStore
  does not index and SAF requires per-folder user picking, which cannot cover a
  full-device threat scan.

👉 Tell me and I'll remove `MANAGE_EXTERNAL_STORAGE` (and its dead permission-setup
entry) the same way I removed `READ_CALL_LOG`.

---

## 5. Location — FINE / COARSE / BACKGROUND  ⚠️ background is the sensitive one

Legitimate: anti-theft "find my device". Foreground FINE/COARSE are fine.
**BACKGROUND** is heavily scrutinised — it's needed because a lost/stolen phone
isn't being actively used, so the locate must work with the app backgrounded.

**App purpose (≤500):**
```
OrbGuard is a personal device-security and anti-theft app. It scans the device for spyware, malware, scam texts and privacy risks, runs an on-device DNS firewall against malicious domains, and gives the owner anti-theft tools for their own device: locate it, sound an alarm, lock it, and - if it is stolen - capture a photo from the front camera. The owner controls all of this from the app or from their OrbGuard web account.
```

**Location feature needing background access (≤500):**
```
Find My Device (anti-theft locate). When the owner loses their phone or marks it lost/stolen, they request its location from the OrbGuard app on another device or from the OrbGuard web panel; the app then reports the phone's current location so the owner can recover it. This must work while OrbGuard is in the background, because a lost or stolen phone is not being actively used - if location only worked in the foreground the feature could never locate a missing device. Location is visible only to the device owner's own account.
```

**Video:** must show the prominent disclosure **before** the runtime prompt,
explaining the anti-theft locate feature and background use. ~30s.

---

## Videos you must record (I can't do these)
| Declaration | Video |
|---|---|
| QUERY_ALL_PACKAGES | Open app → Scan → app/malware scan → results (~60s) |
| Accessibility | The disclosure screen explaining why + what data, then enabling (~1-3min) |
| Background location | Disclosure screen → runtime prompt → locate feature (~30s) |
| All-files (if kept) | The file scan actually running (~30s) |

Upload to YouTube (unlisted is fine) or Drive and paste the links.

---

## Summary of my recommendation
| Permission | Verdict |
|---|---|
| FOREGROUND_SERVICE_SPECIAL_USE | Declare (firewall) — solid |
| QUERY_ALL_PACKAGES | Declare (antivirus) — solid |
| BIND_ACCESSIBILITY_SERVICE | Declare + honest "Yes" on sensitive data + disclosure video |
| MANAGE_EXTERNAL_STORAGE | **Remove** unless you ship a real file scanner |
| ACCESS_BACKGROUND_LOCATION | Declare (find-my-device) — justified, needs video |
