// lib/legal/legal_documents.dart
//
// OrbGuard in-app legal text: Terms of Service + Privacy Policy.
//
// IMPORTANT: This is a protective, industry-standard draft modeled on the
// structure used by consumer security / anti-theft apps (Norton, Prey,
// Life360). It is NOT legal advice and does not guarantee immunity from
// litigation — no document can. OrbGuard's anti-theft features (front-camera
// capture of whoever holds a lost device, remote lock/wipe, and location
// tracking) carry specific legal exposure under biometric-privacy laws
// (e.g. Illinois BIPA, GDPR), anti-wiretap/eavesdropping statutes, and
// computer-misuse laws (e.g. CFAA). A qualified attorney MUST review and
// localize these terms before public launch.
//
// The same text is published at https://guard.orbai.world/terms and /privacy
// (backend/internal/api/site/) — keep the two in sync when editing.

class LegalDocs {
  LegalDocs._();

  // The contracting legal entity. Required in the Terms by payment providers
  // and consumer law; mirrors backend companyinfo (orbnet).
  static const String legalEntity = 'ORB GLOBAL LTD';
  static const String companyNumber = '08274220';
  static const String registeredOffice =
      '7 Bell Yard, London, WC2A 2JR, United Kingdom';

  // Short brand name used through the text after the entity is introduced.
  static const String company = 'Orb';
  static const String app = 'OrbGuard';
  static const String supportEmail = 'support@orbvpn.com';

  // Public, always-current copies of these documents.
  static const String termsUrl = 'https://guard.orbai.world/terms';
  static const String privacyUrl = 'https://guard.orbai.world/privacy';

  static const String lastUpdated = 'September 2026';

  static const String termsTitle = 'Terms of Service';
  static const String privacyTitle = 'Privacy Policy';

  // A one-line acceptance summary shown on the login screen.
  static const String acceptanceLine =
      'By continuing you agree to the OrbGuard Terms of Service and Privacy Policy.';

  static const String terms = '''
OrbGuard — Terms of Service
Last updated: $lastUpdated

These Terms of Service ("Terms") are a binding agreement between you and
$legalEntity, a company registered in England and Wales under company number
$companyNumber with its registered office at $registeredOffice ("$company",
"we", "us"), governing your use of the $app application and related services
(the "Service"). $app uses one shared $company account across $company
applications. The current version of these Terms is always available at
$termsUrl.

READ THESE TERMS CAREFULLY. THEY INCLUDE AN "AS IS" DISCLAIMER OF WARRANTIES, A
LIMITATION OF LIABILITY, AND AN INDEMNIFICATION OBLIGATION. BY CREATING AN
ACCOUNT, TAPPING "AGREE", SUBSCRIBING, OR USING THE SERVICE, YOU ACCEPT THESE
TERMS. IF YOU DO NOT AGREE, DO NOT USE THE SERVICE.

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

7. Subscriptions, billing and automatic renewal.
(a) Plans and prices. $app offers optional paid subscription plans (currently
Guard, Guard+ and Guard Ultimate) with monthly or yearly billing. The price,
billing period, and what each plan includes are shown before you pay, and the
current plans are listed at https://guard.orbai.world/pricing. The price shown
at purchase is the price that renews. Core scanning features remain available
for free; a subscription is never required to keep using the free features.
(b) Automatic renewal. Every subscription renews automatically at the end of
each billing period (one month or one year from purchase) for the same period
and the same price, and your payment method is charged at each renewal, until
you cancel. If we change the price of your plan, we will notify you in advance
and the new price will apply only from a later renewal, so you can cancel first
if you do not agree.
(c) How to cancel. You can turn off automatic renewal at any time. Purchases
made through an app store (Google Play or the Apple App Store) are managed and
cancelled in that store's Subscriptions settings on your device. Purchases made
directly from us (for example on our website) are cancelled from your account
page or by writing to $supportEmail. Cancellation takes effect at the end of
the billing period already paid for: you keep the paid features until that date,
and no further payments are taken afterwards.
(d) Refunds. Purchases made through an app store are billed and refunded under
that store's payment policies, and refund requests for them go to the store.
For purchases made directly from us, you may cancel within 14 days of the
purchase for a full refund, provided you have not made significant use of the
paid service in that time; nothing in these Terms limits any non-waivable
refund or withdrawal right you have under the consumer law of your country.
(e) Failed payments. If a renewal charge fails, we may retry it for a limited
time and suspend paid features until a payment succeeds. Prices may be shown
and charged in your local currency; taxes may apply depending on your country.

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
RISE TO THE CLAIM, OR (b) USD 50. NOTHING IN THESE TERMS EXCLUDES LIABILITY THAT
CANNOT BE EXCLUDED BY LAW, INCLUDING FOR DEATH OR PERSONAL INJURY CAUSED BY
NEGLIGENCE, OR FOR FRAUD.

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

15. Governing law; disputes. These Terms are governed by the laws of England and
Wales, and disputes will be brought in the courts of England and Wales — except
that if you are a consumer, you keep the protection of any mandatory rules of the
country where you live and may bring proceedings in your local courts where the
law so provides. Nothing limits rights that cannot be waived under applicable law.

16. Changes; miscellaneous. We may update these Terms; material changes will be
notified in-app or by email, and continued use after changes means acceptance. If any
provision is unenforceable, the rest remains in effect. These Terms, together with the
Privacy Policy, are the entire agreement between us.

Contact: $legalEntity, $registeredOffice — $supportEmail
''';

  static const String privacy = '''
OrbGuard — Privacy Policy
Last updated: $lastUpdated

This Privacy Policy explains how $legalEntity, registered in England and Wales
under company number $companyNumber, registered office $registeredOffice
("$company", "we"), handles information in the $app app. $company is the data
controller for this processing. The current version of this Policy is always
available at $privacyUrl.

1. Information we process.
• Account data: your email and authentication identifiers, via your shared
  $company account. Sign-in options include email link, password, passkey, and
  Google/Apple.
• Device & security data: device model, OS version, security posture, app/network
  signals, and scan results used to detect threats and show your privacy score.
• Message text you choose to check: $app never reads your SMS inbox and holds
  no SMS permission. When you paste a message into the scam-text checker or
  share one to $app from another app, that text (and the sender, if you enter
  it) is transmitted over TLS to $company servers to analyse it for scams,
  phishing and malicious links. This may include processing by our AI service
  providers acting as processors under contract. We use this ONLY to detect
  and warn you about threats — never to sell, advertise or profile you.
• Links and QR codes you scan or check are sent to $company servers to evaluate
  their reputation and warn you about phishing or malicious destinations.
• Location data: when you enable Locate or periodic reporting, we process the device's
  location to show it to you (the account owner) and support anti-theft.
• Camera images ("thief capture"): when you (or you via the web panel) trigger a photo,
  the device's front camera captures an image that is uploaded to your account so you
  can identify who has the device. These images may contain a person's likeness.
• Payment data: purchases are processed by the app store or payment provider you
  buy through; we receive confirmation of the purchase and subscription status,
  never your full card details.
• Diagnostics: limited logs to operate and secure the Service.

2. How we use it. To provide and secure the Service; to run scans, alerts, and
anti-theft features you enable; to manage your account and subscription; to prevent
abuse; and to comply with law.

3. Your consent and responsibility. You enable location and camera features yourself,
and you are responsible for having any consent the law requires from people who use or
may be captured by the device. Do not enable these features on devices or people you
are not authorized to monitor.

4. Sharing. We do not sell your personal data. We share it only with service providers
that operate the Service under contract (including payment providers for billing),
with your account (the device owner), and as required by law or to protect rights
and safety.

5. Retention. We keep data only as long as needed for the purposes above or as required
by law. Camera images and location history are retained per your settings and can be
deleted from your account.

6. Security. We use technical and organizational measures to protect data, but no system
is perfectly secure.

7. Your rights. Depending on your jurisdiction (e.g. GDPR, UK GDPR, CCPA/CPRA) you may
have rights to access, correct, delete, or port your data, and to object to or restrict
certain processing. Exercise them by contacting us at $supportEmail. You may also
complain to your data-protection authority (in the UK, the ICO).

8. Children. The Service is not directed to children under 16, and we do not knowingly
collect their data.

9. Changes. We may update this Policy; material changes will be notified in-app or by
email.

Contact: $legalEntity, $registeredOffice — $supportEmail
''';
}
