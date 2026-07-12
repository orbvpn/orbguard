# OrbGuard Deferred Implementation Items

This document outlines features that are architecturally designed but require external work, partnerships, or specialized infrastructure to complete.

---

## 1. Flutter UI Screens

**Status:** ✅ COMPLETE (2026-01-07)
**Dependency:** Frontend development resources

All 8 screens have been implemented with iOS 26 Liquid Glass design.

### Completed Screens

#### 1.1 Identity Theft Protection Screen ✅
```
Location: lib/screens/identity/identity_protection_screen.dart
Provider: lib/providers/identity_protection_provider.dart
```
**Implemented features:**
- ✅ Protection score overview with monitoring status
- ✅ Credit freeze toggle controls (Equifax, Experian, TransUnion)
- ✅ Dark web exposure alerts list with severity badges
- ✅ Monitored assets management (SSN, credit cards, emails, phones)
- ✅ Credit report summary view with score history

#### 1.2 Executive Protection Screen ✅
```
Location: lib/screens/enterprise/executive_protection_screen.dart
Provider: lib/providers/executive_protection_provider.dart
```
**Implemented features:**
- ✅ VIP profile management (add/remove executives)
- ✅ BEC/CEO fraud alert feed with risk levels
- ✅ Impersonation detection results
- ✅ Attack type visualization (CEO Fraud, Vendor Fraud, W2 Scam, etc.)
- ✅ Message analyzer tool for checking suspicious emails

#### 1.3 Threat Hunting Dashboard ✅
```
Location: lib/screens/security/threat_hunting_screen.dart
Provider: lib/providers/threat_hunting_provider.dart
```
**Implemented features:**
- ✅ MITRE ATT&CK technique visualization (coverage view)
- ✅ Available threat hunts with priority badges
- ✅ Hunt findings timeline with severity
- ✅ Investigation case management
- ✅ Hunt progress tracking

#### 1.4 Supply Chain Monitor Screen ✅
```
Location: lib/screens/supply_chain/supply_chain_screen.dart
Provider: lib/providers/supply_chain_provider.dart
```
**Implemented features:**
- ✅ Dependency overview with vulnerability counts
- ✅ CVE alert cards with severity badges (CVSS scores)
- ✅ Package dependency list with risk indicators
- ✅ License compliance checking
- ✅ Update recommendations

#### 1.5 Network Firewall Screen ✅
```
Location: lib/screens/network/network_firewall_screen.dart
Provider: lib/providers/network_firewall_provider.dart
```
**Implemented features:**
- ✅ Per-app network rules list
- ✅ Domain/IP blocklist management
- ✅ Connection attempt logs with process identification
- ✅ Rule creation modal
- ✅ Quick toggle for app internet access

#### 1.6 Social Media Monitor Screen ✅
```
Location: lib/screens/social_media/social_media_screen.dart
Provider: lib/providers/social_media_provider.dart
```
**Implemented features:**
- ✅ Connected accounts dashboard with sync status
- ✅ Impersonation alert cards
- ✅ Fake profile detection results
- ✅ Account takeover warnings
- ✅ Privacy settings overview

#### 1.7 Rogue AP Detection Screen ✅
```
Location: lib/screens/rogue_ap/rogue_ap_screen.dart
Provider: lib/providers/rogue_ap_provider.dart
```
**Implemented features:**
- ✅ Nearby WiFi networks list with trust scores
- ✅ Evil twin detection alerts
- ✅ Signal strength visualization
- ✅ Threat detection history
- ✅ Trusted network whitelist management

#### 1.8 Enterprise Policy Screen (Admin) ✅
```
Location: lib/screens/enterprise/enterprise_policy_screen.dart
Provider: lib/providers/enterprise_policy_provider.dart
```
**Implemented features:**
- ✅ Policy template library (BYOD, Corporate, Contractor, HIPAA, PCI-DSS)
- ✅ Active policy list with compliance status
- ✅ Policy violations feed
- ✅ BYOD settings management
- ✅ Policy creation from templates

### UI Components Used

All screens use the iOS 26 Liquid Glass design system:

| Component | Purpose |
|-----------|---------|
| `GlassScaffold` | Main scaffold with gradient background |
| `GlassAppBar` | Frosted glass app bar |
| `GlassCard` | Frosted glass card containers |
| `GlassContainer` | Generic glass container |
| `TabController` | Multi-tab navigation |
| `ModalBottomSheet` | Creation/detail dialogs |

---

## 2. ML Model Training

**Status:** Specifications defined, models pending
**Dependency:** ML infrastructure and training data

### Model Specifications

See: `assets/ml/model_specifications.json`

### Required Models

#### 2.1 Phishing URL Detector
```
File: assets/ml/models/phishing_detector.tflite
Input: URL features (length, entropy, char distribution, TLD)
Output: Probability [0-1] of phishing
Target size: <2MB
```

**Training requirements:**
- Dataset: 500K+ labeled URLs (phishing/legitimate)
- Sources: PhishTank, OpenPhish, Alexa Top 1M
- Features: URL lexical analysis, domain age, certificate info
- Framework: TensorFlow → TFLite conversion

#### 2.2 SMS Scam Classifier
```
File: assets/ml/models/sms_scam_classifier.tflite
Input: Tokenized SMS text
Output: Probability [0-1] of scam
Target size: <3MB
```

**Training requirements:**
- Dataset: 100K+ labeled SMS messages
- Sources: SMS Spam Collection, user-reported scams
- Features: Text embeddings, urgency keywords, link presence
- Framework: TensorFlow text model → TFLite

#### 2.3 Spyware Behavior Detector
```
File: assets/ml/models/spyware_behavior.tflite
Input: App behavior features (permissions, API calls, network patterns)
Output: Spyware probability [0-1]
Target size: <5MB
```

**Training requirements:**
- Dataset: APK behavioral analysis from malware zoos
- Sources: VirusTotal, AndroZoo, custom sandboxing
- Features: Permission combinations, API sequences, network fingerprints
- Framework: TensorFlow → TFLite

#### 2.4 Network Anomaly Detector
```
File: assets/ml/models/network_anomaly.tflite
Input: Network flow features
Output: Anomaly score [0-1]
Target size: <2MB
```

**Training requirements:**
- Dataset: Normal traffic + known attack patterns
- Sources: CICIDS, custom traffic captures
- Features: Packet sizes, timing, destination patterns
- Framework: TensorFlow autoencoder → TFLite

### Training Infrastructure Needed

| Component | Purpose |
|-----------|---------|
| GPU cluster | Model training (recommended: 4x V100) |
| MLflow | Experiment tracking |
| DVC | Dataset versioning |
| Label Studio | Data annotation |
| TFX pipeline | Training automation |

### Integration Guide

```dart
// After models are trained, integrate via:
import 'package:orbguard/lib/services/ml/tflite_ml_service.dart';

final mlService = TFLiteMLService();
await mlService.initialize();

// Use appropriate model
final result = await mlService.classifyURL(url);
final smsResult = await mlService.classifySMS(message);
```

---

## 3. Dark Web Monitoring API

**Status:** Service layer ready, API integration pending
**Dependency:** Commercial partnership

### Required Partner Capabilities

| Capability | Description |
|------------|-------------|
| Credential monitoring | Email/password breach detection |
| PII exposure alerts | SSN, credit card, address leaks |
| Real-time notifications | Webhook/push on new findings |
| Historical data | Past breach exposure history |
| Takedown requests | Remove exposed data (premium) |

### Recommended Partners

1. **SpyCloud** - Enterprise credential monitoring
   - API: REST + webhooks
   - Coverage: 200B+ breach records
   - Contact: enterprise@spycloud.com

2. **Have I Been Pwned (Commercial)** - Breach notification
   - API: REST
   - Coverage: 12B+ accounts
   - Contact: troy@haveibeenpwned.com

3. **DarkOwl** - Dark web intelligence
   - API: REST + streaming
   - Coverage: Tor, I2P, paste sites
   - Contact: sales@darkowl.com

4. **Recorded Future** - Threat intelligence
   - API: REST
   - Coverage: Full dark web + threat actors
   - Contact: info@recordedfuture.com

### Integration Points

```dart
// In identity_theft_protection_service.dart
// Replace mock implementation with real API:

Future<List<DarkWebExposure>> checkDarkWebExposure(String email) async {
  // TODO: Replace with actual API call
  // final response = await darkWebApi.checkEmail(email);
  // return response.exposures.map((e) => DarkWebExposure.fromJson(e)).toList();
}
```

### API Contract Expected

```json
// POST /api/v1/monitor/email
{
  "email": "user@example.com",
  "include_historical": true
}

// Response
{
  "exposures": [
    {
      "breach_name": "Example Breach",
      "breach_date": "2024-01-15",
      "data_types": ["email", "password_hash", "name"],
      "severity": "high",
      "source": "dark_web_forum"
    }
  ],
  "last_checked": "2025-01-07T12:00:00Z"
}
```

---

## 4. Data Broker Removal

**Status:** Workflow designed, automation pending
**Dependency:** Manual opt-out processes + potential partnerships

### Overview

Data brokers collect and sell personal information. Removal requires submitting opt-out requests to each broker individually.

### Major Data Brokers

| Broker | Opt-out URL | Automation Difficulty |
|--------|-------------|----------------------|
| Spokeo | spokeo.com/optout | Medium - email verification |
| WhitePages | whitepages.com/suppression | Medium - identity verification |
| BeenVerified | beenverified.com/app/optout | Hard - requires account |
| Intelius | intelius.com/opt-out | Medium - form submission |
| PeopleFinder | peoplefinder.com/optout | Easy - form only |
| Radaris | radaris.com/control/privacy | Hard - verification required |
| TruePeopleSearch | truepeoplesearch.com/removal | Easy - form only |
| FastPeopleSearch | fastpeoplesearch.com/removal | Easy - form only |
| ThatsThem | thatsthem.com/optout | Medium - email verification |
| Pipl | pipl.com/help/remove | Hard - business accounts |

### Implementation Options

#### Option A: DIY Automation (Complex)
Build automated opt-out submission:
- Pros: No ongoing costs
- Cons: High maintenance, CAPTCHAs, constant changes

```dart
// Would require:
// - Headless browser automation (Puppeteer/Selenium)
// - CAPTCHA solving service
// - Email verification handling
// - Regular maintenance for site changes
```

#### Option B: Partner Service (Recommended)
Integrate with data removal service:

1. **DeleteMe** (Abine)
   - Handles 40+ brokers
   - API available for enterprise
   - Contact: enterprise@joindeleteme.com

2. **Kanary**
   - Automated scanning + removal
   - API available
   - Contact: business@kanary.com

3. **Privacy Duck**
   - Manual removal service
   - White-label available
   - Contact: partners@privacyduck.com

### User Workflow (Current Design)

```
1. User enters personal info to monitor
   └── Name, addresses, phone numbers, emails

2. Service scans data broker sites
   └── Automated search for user's records

3. Found records displayed to user
   └── List of brokers holding their data

4. User initiates removal
   └── Either:
       a) Guided manual opt-out (free)
       b) Automated removal via partner (premium)

5. Ongoing monitoring
   └── Re-check brokers periodically
   └── Alert if data reappears
```

### Service Integration Point

```dart
// In identity_theft_protection_service.dart

Future<List<DataBrokerRecord>> scanDataBrokers(UserProfile profile) async {
  // TODO: Implement broker scanning
  // Option A: Custom scraping
  // Option B: Partner API integration
}

Future<RemovalStatus> requestDataRemoval(DataBrokerRecord record) async {
  // TODO: Implement removal request
  // Either generate opt-out instructions or trigger API
}
```

---

## Implementation Priority

| Item | Priority | Effort | Business Impact |
|------|----------|--------|-----------------|
| Flutter UI Screens | High | 4-6 weeks | Required for user interaction |
| ML Model Training | Medium | 6-8 weeks | Improves detection accuracy |
| Dark Web API | High | 1-2 weeks | Key differentiator feature |
| Data Broker Removal | Medium | 2-4 weeks | Premium feature potential |

---

## Getting Started

1. **UI Development**: Start with high-value screens (Identity Protection, Threat Dashboard)
2. **ML Training**: Begin data collection now, training can run parallel to UI work
3. **Dark Web API**: Initiate partner discussions, shortest integration time
4. **Data Broker**: Evaluate partner vs build decision based on resources

---

*Document created: 2026-01-07*
*Last updated: 2026-01-07*
*Section 1 (Flutter UI Screens) completed: 2026-01-07*
