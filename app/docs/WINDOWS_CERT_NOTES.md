WHAT CHANGED SINCE THE FAILED 1.0.6.0 SUBMISSION (10.1.2.10, "Unusable Feature: Sign in")

Thank you for the detailed repro - it identified the defect exactly. In 1.0.6.0 the
emailed sign-in link used the "orbguard://" URI scheme, which was never registered
with Windows. Activating the link reached our web endpoint (so the page reported
success) but the final hand-off to the app had no handler, so sign-in never
completed. 1.0.7.0 fixes this in three independent places:

1. "orbguard://" is now registered by the package (windows.protocol extension in the
   app manifest), so activating the emailed link opens OrbGuard directly.
2. If OrbGuard is already running, the link is handed to the running window instead
   of starting a second copy the user cannot see.
3. A "Sign-in link" field is shown on screen as soon as the link is sent, so sign-in
   can be completed by pasting the link instead of activating it. In 1.0.6.0 that
   field was hidden behind a secondary "Can't open the link?" control.

HOW TO TEST SIGN-IN

1. Launch OrbGuard.
2. Open Settings (gear icon) -> Sign in.
3. Enter any email address you control and press "Email me a sign-in link".
4. The screen immediately shows a "Sign-in link" field plus a "Verify & sign in"
   button. Either path below completes sign-in:

   PATH A (the link - this is what failed before and is now fixed)
   Open the message we send and activate the sign-in link. Windows hands it to
   OrbGuard, the app signs you in, and the sign-in screen closes by itself.

   PATH B (fallback, needs no working link)
   Copy the sign-in link out of the email (right-click the "Sign In" button ->
   Copy link), paste it into the "Sign-in link" field, and press "Verify & sign in".
   The app accepts the whole URL and completes sign-in.

5. Settings then shows the signed-in account.

HOW TO TEST THE MAIN FEATURE (security checkup)

Press "Run check" on the home screen. No sign-in is required. The scan inspects
this PC natively and reports what it finds:
 - running processes and their signatures
 - programs set to start with Windows
 - which apps have used the camera, microphone and location
 - components loaded inside browsers
 - certificates in the trusted root store
 - text-input processors

If a particular check cannot run it is listed as unavailable - it is deliberately
never counted as a passed or "clean" check. On a clean test machine, finding zero
threats with a few checks listed unavailable is the expected, correct result.

ADDITIONAL NOTES FOR TESTING

- No pre-existing account is needed. An account is created automatically the first
  time you sign in, and there is no payment step.
- Sign-in is OPTIONAL. Close the sign-in screen and the scanning and protection
  features are fully usable without an account.
- There is no in-app purchase surface in the Windows build. Nothing is sold or
  upgraded inside this app on Windows; the Plans screen only states that premium
  travels with an existing account and offers nothing for sale.
- The app needs an internet connection to reach the OrbGuard service.
- Declared capabilities are limited to internetClient and location. Location is used
  only to read the Wi-Fi network name for network-safety checks. The previous
  submission also declared webcam and microphone; this build no longer requests
  them, because the Windows build does not use them.

Privacy policy: https://orbvpn.com/privacy
Support: https://orbvpn.com/en/legal
