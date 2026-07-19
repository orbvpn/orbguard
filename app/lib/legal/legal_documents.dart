// lib/legal/legal_documents.dart
//
// OrbGuard in-app legal text: Terms of Service + Privacy Policy.
//
// IMPORTANT: This is a protective, industry-standard draft modeled on the
// structure used by consumer security / anti-theft apps (Norton, Prey, Life360)
// and OrbGuard's parent, OrbVPN. It is NOT legal advice and does not guarantee
// immunity from litigation — no document can. OrbGuard's anti-theft features
// (front-camera capture of whoever holds a lost device, remote lock/wipe, and
// location tracking) carry specific legal exposure under biometric-privacy laws
// (e.g. Illinois BIPA, GDPR), anti-wiretap/eavesdropping statutes, and computer
// -misuse laws (e.g. CFAA). A qualified attorney MUST review and localize these
// terms before public launch. Keep the shared account/subscription master terms
// authoritative at the OrbVPN URLs below.

class LegalDocs {
  LegalDocs._();

  static const String company = 'OrbVPN';
  static const String app = 'OrbGuard';
  static const String supportEmail = 'support@orbvpn.com';

  // Master (shared-account) legal docs — OrbGuard shares the OrbVPN/OrbNet
  // account, so the account, subscription, billing and data-controller terms are
  // governed by these. The in-app text below adds OrbGuard-specific terms.
  static const String masterTermsUrl = 'https://orbvpn.com/terms';
  static const String masterPrivacyUrl = 'https://orbvpn.com/privacy';

  static const String lastUpdated = 'July 2026';

  static const String termsTitle = 'Terms of Service';
  static const String privacyTitle = 'Privacy Policy';

  // A one-line acceptance summary shown on the login screen.
  static const String acceptanceLine =
      'By continuing you agree to the OrbGuard Terms of Service and Privacy Policy.';

  static const String terms = '''
OrbGuard — Terms of Service
Last updated: $lastUpdated

These Terms of Service ("Terms") are a binding agreement between you and $company
("$company", "we", "us") governing your use of the $app application and related
services (the "Service"). $app is part of the $company / OrbNet account family;
your account, subscription and billing are additionally governed by the $company
Terms of Service at $masterTermsUrl, which are incorporated by reference. If these
Terms conflict with the master Terms on account/billing matters, the master Terms
control for those matters.

READ THESE TERMS CAREFULLY. THEY INCLUDE AN "AS IS" DISCLAIMER OF WARRANTIES, A
LIMITATION OF LIABILITY, AN INDEMNIFICATION OBLIGATION, AND (WHERE ENFORCEABLE) A
BINDING ARBITRATION AND CLASS-ACTION WAIVER. BY CREATING AN ACCOUNT, TAPPING
"AGREE", OR USING THE SERVICE, YOU ACCEPT THESE TERMS. IF YOU DO NOT AGREE, DO NOT
USE THE SERVICE.

1. Eligibility. You must be at least 16 years old (or the age of digital consent
in your jurisdiction) and able to form a binding contract. You represent that you
are not barred from using the Service under any applicable law.

2. The Service. $app provides security and anti-theft tools, which may include
device and network scanning, threat and privacy checks, alerts, and — when you
enable them — remote device features such as locate, alarm/ring, lock, data wipe,
and front-camera capture of whoever is using a device you have registered. Features
vary by platform, device, permissions, and subscription tier, and may change,
be limited, or be discontinued at any time.

3. YOUR AUTHORIZATION AND LAWFUL USE (IMPORTANT). You may enable and use $app only
on devices you OWN or are otherwise legally authorized to monitor and control, and
only in a manner permitted by law. By enabling any remote or monitoring feature you
represent and warrant that: (a) you have all rights and authority necessary to do
so; (b) you have obtained every consent required by law from any person who uses,
carries, or may be captured, located, or recorded by the device (including camera
images and location); and (c) your use complies with all applicable laws, including
privacy, biometric, data-protection, surveillance, wiretap/eavesdropping, and
computer-misuse laws. You are solely responsible for determining whether, and how,
you may lawfully use these features in your jurisdiction. $app is a tool; you — not
$company — control how it is used. DO NOT use $app to stalk, harass, surveil, or
track any person without their knowledge and legally valid consent, or on any device
you do not own or control. Misuse may be a crime.

4. No guarantee of results. Security and anti-theft tools are inherently imperfect.
$company does NOT warrant that the Service will detect every threat, prevent loss or
theft, recover any device, capture any image, determine any location, lock or wipe
any device successfully or in time, or otherwise achieve any particular result.
Remote actions depend on the device's power, connectivity, operating system, and
third-party services outside our control and may be delayed, incomplete, or fail.

5. Data wipe and data loss. A remote wipe or factory reset is IRREVERSIBLE and will
delete data. You are solely responsible for maintaining backups and for the decision
to issue any lock, wipe, or other destructive command. To the maximum extent
permitted by law, $company is not liable for any loss of data, device, access, or
functionality resulting from your use of these features.

6. Accounts and security. You are responsible for your account credentials and for
all activity under your account. Notify us promptly of any unauthorized use.

7. Subscriptions and payments. Paid features are governed by the $company subscription
terms at $masterTermsUrl and by the applicable app-store rules. Purchases made through
an app store are billed and refunded according to that store's policies.

8. Acceptable use. You will not: reverse engineer, resell, or misuse the Service;
interfere with its operation; use it unlawfully or to infringe others' rights; or use
it on devices or persons you are not authorized to monitor.

9. Intellectual property. The Service, including its software, content, and marks, is
owned by $company and its licensors and is protected by law. We grant you a limited,
revocable, non-exclusive, non-transferable license to use the Service for its intended
personal, lawful purpose.

10. DISCLAIMER OF WARRANTIES. THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE",
WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS, IMPLIED, OR STATUTORY, INCLUDING ANY
IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND
NON-INFRINGEMENT, AND ANY WARRANTY THAT THE SERVICE WILL BE UNINTERRUPTED, SECURE,
ERROR-FREE, OR EFFECTIVE. SOME JURISDICTIONS DO NOT ALLOW CERTAIN DISCLAIMERS, SO
PARTS OF THIS SECTION MAY NOT APPLY TO YOU.

11. LIMITATION OF LIABILITY. TO THE MAXIMUM EXTENT PERMITTED BY LAW, $company AND ITS
AFFILIATES, OFFICERS, EMPLOYEES, AND SUPPLIERS WILL NOT BE LIABLE FOR ANY INDIRECT,
INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, OR FOR ANY LOSS OF
DATA, DEVICES, PROFITS, GOODWILL, OR THE FAILURE TO PREVENT OR RECOVER FROM ANY THEFT,
LOSS, OR INTRUSION, ARISING OUT OF OR RELATING TO THE SERVICE, EVEN IF ADVISED OF THE
POSSIBILITY. TO THE MAXIMUM EXTENT PERMITTED BY LAW, $company'S TOTAL AGGREGATE
LIABILITY FOR ALL CLAIMS RELATING TO THE SERVICE WILL NOT EXCEED THE GREATER OF (a)
THE AMOUNT YOU PAID $company FOR THE SERVICE IN THE 12 MONTHS BEFORE THE EVENT GIVING
RISE TO THE CLAIM, OR (b) USD 50.

12. INDEMNIFICATION. You will defend, indemnify, and hold harmless $company and its
affiliates from and against any claims, damages, liabilities, and expenses (including
reasonable legal fees) arising out of or related to your use or misuse of the Service,
your violation of these Terms, or your violation of any law or of any third party's
rights — including any claim that your use of a monitoring, camera, location, lock, or
wipe feature was unauthorized or unlawful.

13. Third-party services. The Service may rely on or link to third-party services and
app stores. We are not responsible for third-party services, and their terms govern
your use of them.

14. Termination. We may suspend or terminate the Service or your access at any time,
including for violation of these Terms. Sections that by their nature should survive
termination (including 3–5 and 10–16) will survive.

15. Governing law; dispute resolution. Except where prohibited, these Terms are
governed by the laws specified in the $company master Terms at $masterTermsUrl, and any
dispute will be resolved as set out there, which may include BINDING INDIVIDUAL
ARBITRATION AND A WAIVER OF CLASS OR REPRESENTATIVE ACTIONS to the extent enforceable
in your jurisdiction. Nothing limits rights that cannot be waived under applicable law.

16. Changes; miscellaneous. We may update these Terms; material changes will be
notified in-app or by email, and continued use after changes means acceptance. If any
provision is unenforceable, the rest remains in effect. These Terms, together with the
master $company Terms and Privacy Policy, are the entire agreement between us.

Contact: $supportEmail
''';

  static const String privacy = '''
OrbGuard — Privacy Policy
Last updated: $lastUpdated

This Privacy Policy explains how $company ("we") handles information in the $app app.
$app shares the $company / OrbNet account; the full, controlling privacy notice —
including data controller, retention, international transfers, and your rights — is at
$masterPrivacyUrl and is incorporated by reference. This in-app notice summarizes what
$app specifically collects and why.

1. Information we process.
• Account data: your email and authentication identifiers, via your $company/OrbNet
  account. Sign-in options include email link, password, passkey, and Google/Apple.
• Device & security data: device model, OS version, security posture, app/network
  signals, and scan results used to detect threats and show your privacy score.
• Location data: when you enable Locate or periodic reporting, we process the device's
  location to show it to you (the account owner) and support anti-theft.
• Camera images ("thief capture"): when you (or you via the web panel) trigger a photo,
  the device's front camera captures an image that is uploaded to your account so you
  can identify who has the device. These images may contain a person's likeness.
• Diagnostics: limited logs to operate and secure the Service.

2. How we use it. To provide and secure the Service; to run scans, alerts, and
anti-theft features you enable; to manage your account and subscription; to prevent
abuse; and to comply with law.

3. Your consent and responsibility. You enable location and camera features yourself,
and you are responsible for having any consent the law requires from people who use or
may be captured by the device. Do not enable these features on devices or people you
are not authorized to monitor.

4. Sharing. We do not sell your personal data. We share it only with service providers
that operate the Service under contract, with your account (the device owner), and as
required by law or to protect rights and safety. See $masterPrivacyUrl for details.

5. Retention. We keep data only as long as needed for the purposes above or as required
by law. Camera images and location history are retained per the settings and the master
policy and can be deleted from your account.

6. Security. We use technical and organizational measures to protect data, but no system
is perfectly secure.

7. Your rights. Depending on your jurisdiction (e.g. GDPR, CCPA/CPRA) you may have rights
to access, correct, delete, or port your data, and to object to or restrict certain
processing. Exercise them as described at $masterPrivacyUrl or by contacting us.

8. Children. The Service is not directed to children under 16, and we do not knowingly
collect their data.

9. Changes. We may update this Policy; material changes will be notified in-app or by
email.

Contact: $supportEmail
''';
}
