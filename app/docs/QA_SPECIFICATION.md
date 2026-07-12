# OrbGuard QA & Test Specification

**Version:** 1.0.0
**Created:** 2026-01-07
**Status:** Draft - Pending Approval

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Environment Configuration](#3-environment-configuration)
4. [API Specification](#4-api-specification)
5. [Database Schema](#5-database-schema)
6. [Feature List with Acceptance Criteria](#6-feature-list-with-acceptance-criteria)
7. [Flutter App Test Cases](#7-flutter-app-test-cases)
8. [Error Codes Reference](#8-error-codes-reference)
9. [Platform-Specific Requirements](#9-platform-specific-requirements)
10. [Test Data](#10-test-data)
11. [Edge Cases to Test](#11-edge-cases-to-test)
12. [Test Execution Protocol](#12-test-execution-protocol)
13. [Definition of "Complete"](#13-definition-of-complete)
14. [Known Issues & Limitations](#14-known-issues--limitations)

---

## 1. Project Overview

**OrbGuard** is an enterprise-grade mobile threat defense platform providing anti-spyware detection, phishing protection, network security auditing, and threat intelligence integration.

### Components

| Component | Technology | Location | Purpose |
|-----------|------------|----------|---------|
| **OrbGuard API** | Go (Chi router) | `/Users/nima/Developments/orbguard.lab` | Backend REST API + gRPC |
| **OrbGuard App** | Flutter | `/Users/nima/Developments/orbguard` | Multi-platform mobile/desktop app |
| **Database** | PostgreSQL | Local/Docker | Persistent storage |
| **Cache** | Redis | Local/Docker | Session & rate limiting |
| **Graph DB** | Neo4j | Local/Docker | Threat correlation |
| **Message Queue** | NATS JetStream | Local/Docker | Real-time events |

### Target Platforms

- iOS 15+ (iPhone, iPad)
- Android SDK 24+ (API 24 = Android 7.0)
- macOS 11+ (Apple Silicon & Intel)
- Windows 10/11

---

## 2. Architecture

### Backend Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        API Layer (Chi Router)                    │
│  ┌──────────────────┬──────────────────┬─────────────────────┐  │
│  │   REST API       │    gRPC Server   │   WebSocket Hub     │  │
│  │   (Port 8090)    │    (Port 9002)   │   (Real-time)       │  │
│  └──────────────────┴──────────────────┴─────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                      Middleware Layer                            │
│  ┌────────┬─────────┬───────────┬──────────┬─────────────────┐  │
│  │  Auth  │ Logger  │ RateLimit │  CORS    │    Recovery     │  │
│  └────────┴─────────┴───────────┴──────────┴─────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                      Service Layer                               │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Intelligence | SMS | URL | DarkWeb | Apps | Network | ML  │ │
│  │  YARA | MITRE | Correlation | Privacy | Device | QR | VPN  │ │
│  └────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                    Infrastructure Layer                          │
│  ┌──────────┬─────────┬──────────┬────────────┬──────────────┐  │
│  │ PostgreSQL│  Redis  │  Neo4j   │   NATS     │ External APIs│  │
│  └──────────┴─────────┴──────────┴────────────┴──────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Flutter App Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Presentation Layer                            │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  24 Screens (Glass UI Theme) | Widgets | Navigation        │ │
│  └────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                    State Management (Provider)                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  18 Providers (Dashboard, SMS, URL, Network, Settings...)  │ │
│  └────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                      Service Layer                               │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  38 Services (API Client, Security, ML, Notifications...)  │ │
│  └────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                    Platform Layer                                │
│  ┌──────────┬──────────┬──────────┬───────────────────────────┐ │
│  │  iOS     │ Android  │  macOS   │  Windows                  │ │
│  │  (Swift) │ (Kotlin) │  (Swift) │  (C++)                    │ │
│  └──────────┴──────────┴──────────┴───────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Environment Configuration

### Development Environment

| Service | Host | Port | Notes |
|---------|------|------|-------|
| OrbGuard API | localhost | 8090 | HTTP REST API |
| gRPC Server | localhost | 9002 | gRPC threat queries |
| PostgreSQL | localhost | 5432 | Database |
| Redis | localhost | 6379 | Cache/Rate limiting |
| Neo4j | localhost | 7687 | Graph DB (Bolt protocol) |
| NATS | localhost | 4222 | Message queue |

### Staging/Production

| Service | URL |
|---------|-----|
| API | `https://guard.orbai.world` |
| Admin Dashboard | `https://admin.orbai.world` |
| WebSocket | `wss://guard.orbai.world/ws/threats` |

### Environment Variables (Backend)

```bash
# Required
ORBGUARD_DATABASE_PASSWORD=<db_password>
ORBGUARD_JWT_SECRET=<jwt_secret_32_chars_min>
ORBGUARD_REDIS_PASSWORD=<redis_password>
ORBGUARD_NEO4J_PASSWORD=<neo4j_password>

# Optional API Keys
ORBGUARD_SOURCES_GOOGLE_SAFEBROWSING_API_KEY=<key>
ORBGUARD_SOURCES_ABUSEIPDB_API_KEY=<key>
ORBGUARD_SOURCES_GREYNOISE_API_KEY=<key>
ORBGUARD_SOURCES_VIRUSTOTAL_API_KEY=<key>
ORBGUARD_SOURCES_ALIENVAULT_OTX_API_KEY=<key>
ORBGUARD_SOURCES_KOODOUS_API_KEY=<key>
```

### Flutter App Configuration

**File:** `lib/services/api/api_config.dart`

```dart
static const String baseUrl = 'https://guard.orbai.world';
static const String apiVersion = '/api/v1';
static const Duration connectTimeout = Duration(seconds: 30);
static const Duration receiveTimeout = Duration(seconds: 30);
```

---

## 4. API Specification

### 4.1 Authentication

All `/api/v1/*` endpoints require authentication via API key header:

```
Authorization: Bearer <api_key>
```

**Public endpoints (no auth required):**
- `GET /health` - Health check
- `GET /ready` - Readiness check
- `GET /api/v1/stats` - Public statistics

### 4.2 Core Endpoints

#### 4.2.1 Intelligence (Threat Indicators)

| Method | Endpoint | Description | Request | Response |
|--------|----------|-------------|---------|----------|
| `GET` | `/api/v1/intelligence` | List all indicators | Query: `page`, `limit`, `type`, `severity` | `200`: Array of indicators |
| `GET` | `/api/v1/intelligence/pegasus` | Pegasus-specific IOCs | Query: `limit` | `200`: Array of Pegasus indicators |
| `GET` | `/api/v1/intelligence/mobile` | Mobile-specific IOCs | Query: `platform`, `limit` | `200`: Array of mobile indicators |
| `GET` | `/api/v1/intelligence/mobile/sync` | Sync for mobile apps | Query: `since`, `platform` | `200`: Delta sync response |
| `GET` | `/api/v1/intelligence/community` | Community-reported | Query: `status` | `200`: Community reports |
| `GET` | `/api/v1/intelligence/check` | Check single indicator | Query: `value`, `type` | `200`: Match result |
| `POST` | `/api/v1/intelligence/check/batch` | Check multiple | Body: `{indicators: [...]}` | `200`: Batch results |
| `POST` | `/api/v1/intelligence/report` | Report new threat | Body: indicator data | `201`: Created report |

**Expected Behaviors:**
- Valid indicator check → `200` with `{found: true/false, indicator: {...}, matches: [...]}`
- Invalid indicator type → `400` with `{error: "Invalid indicator type"}`
- Rate limit exceeded → `429` with `{error: "Rate limit exceeded", retry_after: 60}`

#### 4.2.2 SMS Protection (Smishing)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/sms/analyze` | Analyze single SMS |
| `POST` | `/api/v1/sms/analyze/batch` | Analyze multiple SMS |
| `POST` | `/api/v1/sms/check-url` | Check URL in SMS |
| `GET` | `/api/v1/sms/patterns` | Get phishing patterns |
| `GET` | `/api/v1/sms/stats` | Get SMS analysis stats |

**Request Body (analyze):**
```json
{
  "sender": "+1234567890",
  "message": "Your package is waiting...",
  "timestamp": "2026-01-07T12:00:00Z"
}
```

**Response (analyze):**
```json
{
  "risk_score": 0.85,
  "risk_level": "high",
  "threat_type": "phishing",
  "detected_urls": ["https://fake-delivery.com/track"],
  "suspicious_keywords": ["package", "click here", "urgent"],
  "phishing_patterns": ["delivery_scam"],
  "recommendation": "block"
}
```

#### 4.2.3 URL Protection (Safe Web)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/url/check` | Check single URL |
| `POST` | `/api/v1/url/check/batch` | Check multiple URLs |
| `GET` | `/api/v1/url/reputation/{domain}` | Get domain reputation |
| `GET` | `/api/v1/url/whitelist` | Get whitelist |
| `POST` | `/api/v1/url/whitelist` | Add to whitelist |
| `GET` | `/api/v1/url/blacklist` | Get blacklist |
| `POST` | `/api/v1/url/blacklist` | Add to blacklist |
| `DELETE` | `/api/v1/url/list/{id}` | Remove from list |
| `GET` | `/api/v1/url/dns-rules` | Get DNS block rules |
| `POST` | `/api/v1/url/report` | Report malicious URL |

**Request Body (check):**
```json
{
  "url": "https://suspicious-site.com/login"
}
```

**Response:**
```json
{
  "url": "https://suspicious-site.com/login",
  "safe": false,
  "threat_types": ["phishing", "malware"],
  "risk_score": 0.92,
  "domain_age_days": 3,
  "ssl_valid": false,
  "category": "phishing",
  "sources": ["urlhaus", "safebrowsing"]
}
```

#### 4.2.4 Dark Web Monitoring

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/darkweb/check/email` | Check email breach |
| `POST` | `/api/v1/darkweb/check/password` | Check password breach (k-anonymity) |
| `GET` | `/api/v1/darkweb/monitor` | Get monitored assets |
| `POST` | `/api/v1/darkweb/monitor` | Add monitored asset |
| `DELETE` | `/api/v1/darkweb/monitor/{id}` | Remove asset |
| `GET` | `/api/v1/darkweb/status` | Get monitoring status |
| `GET` | `/api/v1/darkweb/alerts` | Get exposure alerts |
| `POST` | `/api/v1/darkweb/alerts/{id}/ack` | Acknowledge alert |
| `GET` | `/api/v1/darkweb/breaches` | Get known breaches |
| `POST` | `/api/v1/darkweb/refresh` | Force refresh |

**Request (check email):**
```json
{
  "email": "user@example.com"
}
```

**Response:**
```json
{
  "email": "user@example.com",
  "breached": true,
  "breach_count": 3,
  "breaches": [
    {
      "name": "LinkedIn",
      "date": "2021-06-22",
      "data_classes": ["email", "password_hash"],
      "severity": "high"
    }
  ],
  "last_checked": "2026-01-07T12:00:00Z"
}
```

#### 4.2.5 App Security Suite

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/apps/analyze` | Analyze app |
| `POST` | `/api/v1/apps/analyze/batch` | Batch analyze |
| `GET` | `/api/v1/apps/reputation/{package}` | Get app reputation |
| `POST` | `/api/v1/apps/sideloaded` | Check sideloaded |
| `POST` | `/api/v1/apps/privacy-report` | Privacy audit |
| `GET` | `/api/v1/apps/trackers` | Get known trackers |
| `GET` | `/api/v1/apps/permissions/dangerous` | Dangerous permissions |

**Request (analyze):**
```json
{
  "package_name": "com.suspicious.app",
  "permissions": ["CAMERA", "MICROPHONE", "READ_SMS"],
  "install_source": "unknown",
  "version": "1.0.0"
}
```

**Response:**
```json
{
  "package_name": "com.suspicious.app",
  "risk_score": 0.78,
  "risk_level": "high",
  "threats": ["spyware_behavior", "excessive_permissions"],
  "dangerous_permissions": ["READ_SMS", "RECORD_AUDIO"],
  "trackers_detected": ["facebook_analytics", "google_firebase"],
  "is_sideloaded": true,
  "recommendation": "uninstall"
}
```

#### 4.2.6 Network Security

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/network/wifi/audit` | Audit WiFi network |
| `GET` | `/api/v1/network/wifi/security-types` | Security types info |
| `POST` | `/api/v1/network/dns/check` | Check DNS security |
| `GET` | `/api/v1/network/dns/providers` | Secure DNS providers |
| `POST` | `/api/v1/network/dns/configure` | Configure DNS |
| `POST` | `/api/v1/network/arp/check` | Check ARP spoofing |
| `POST` | `/api/v1/network/ssl/check` | Check SSL stripping |
| `POST` | `/api/v1/network/vpn/recommend` | VPN recommendation |
| `POST` | `/api/v1/network/audit/full` | Full network audit |

**Request (wifi audit):**
```json
{
  "ssid": "CoffeeShop_WiFi",
  "bssid": "AA:BB:CC:DD:EE:FF",
  "security_type": "WPA2",
  "signal_strength": -65,
  "nearby_networks": [
    {"ssid": "CoffeeShop_WiFi", "bssid": "AA:BB:CC:DD:EE:00"}
  ]
}
```

**Response:**
```json
{
  "network": "CoffeeShop_WiFi",
  "security_score": 45,
  "threats": [
    {
      "type": "evil_twin",
      "severity": "high",
      "description": "Potential evil twin detected with same SSID"
    }
  ],
  "recommendations": [
    "Use VPN on this network",
    "Verify with staff this is the correct network"
  ]
}
```

#### 4.2.7 QR Code Security (Quishing)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/qr/scan` | Scan QR code |
| `POST` | `/api/v1/qr/scan/batch` | Batch scan |
| `POST` | `/api/v1/qr/check-url` | Check QR URL |
| `POST` | `/api/v1/qr/preview` | Safe preview |
| `GET` | `/api/v1/qr/content-types` | Content types |
| `GET` | `/api/v1/qr/threat-types` | Threat types |
| `GET` | `/api/v1/qr/suspicious-tlds` | Suspicious TLDs |

**Request (scan):**
```json
{
  "content": "https://bit.ly/3abc123",
  "content_type": "url"
}
```

**Response:**
```json
{
  "content": "https://bit.ly/3abc123",
  "content_type": "url",
  "safe": false,
  "resolved_url": "https://phishing-site.com/steal",
  "threat_type": "phishing",
  "risk_score": 0.89,
  "is_shortener": true,
  "suspicious_tld": true,
  "recommendation": "do_not_open"
}
```

#### 4.2.8 MITRE ATT&CK

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/mitre/tactics` | List tactics |
| `GET` | `/api/v1/mitre/tactics/{id}` | Get tactic |
| `GET` | `/api/v1/mitre/techniques` | List techniques |
| `GET` | `/api/v1/mitre/techniques/search` | Search techniques |
| `GET` | `/api/v1/mitre/techniques/{id}` | Get technique |
| `GET` | `/api/v1/mitre/matrix` | Get ATT&CK matrix |
| `POST` | `/api/v1/mitre/navigator/export` | Export Navigator layer |

#### 4.2.9 YARA Rules Engine

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/yara/scan` | Scan with YARA |
| `POST` | `/api/v1/yara/scan/apk` | Scan APK |
| `POST` | `/api/v1/yara/scan/ipa` | Scan IPA |
| `POST` | `/api/v1/yara/quick-scan` | Quick scan |
| `GET` | `/api/v1/yara/rules` | List rules |
| `POST` | `/api/v1/yara/rules` | Add rule |
| `DELETE` | `/api/v1/yara/rules/{id}` | Delete rule |

#### 4.2.10 Device Security

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/device/register` | Register device |
| `GET` | `/api/v1/device/{device_id}` | Get device info |
| `POST` | `/api/v1/device/{device_id}/locate` | Locate device |
| `POST` | `/api/v1/device/{device_id}/lock` | Remote lock |
| `POST` | `/api/v1/device/{device_id}/wipe` | Remote wipe |
| `POST` | `/api/v1/device/{device_id}/ring` | Ring device |
| `POST` | `/api/v1/device/{device_id}/sim` | Report SIM |
| `POST` | `/api/v1/device/vulnerabilities/audit` | OS vulnerability audit |

#### 4.2.11 Enterprise Features

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/enterprise/overview` | Enterprise overview |
| `POST` | `/api/v1/enterprise/mdm/integrations` | Create MDM integration |
| `POST` | `/api/v1/enterprise/zerotrust/posture` | Assess device posture |
| `POST` | `/api/v1/enterprise/zerotrust/evaluate` | Evaluate access |
| `POST` | `/api/v1/enterprise/siem/events` | Send SIEM event |
| `POST` | `/api/v1/enterprise/compliance/reports` | Generate compliance report |

#### 4.2.12 OrbNet VPN Integration

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/orbnet/dns/block` | Should block domain |
| `POST` | `/api/v1/orbnet/dns/block/batch` | Batch check |
| `GET` | `/api/v1/orbnet/rules` | List block rules |
| `POST` | `/api/v1/orbnet/rules` | Add block rule |
| `POST` | `/api/v1/orbnet/emergency-block` | Emergency block |
| `POST` | `/api/v1/orbnet/sync` | Sync threat data |
| `GET` | `/api/v1/orbnet/dashboard` | Dashboard stats |

#### 4.2.13 Forensics

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/forensics/ios/shutdown-log` | Analyze iOS shutdown log |
| `POST` | `/api/v1/forensics/ios/backup` | Analyze backup |
| `POST` | `/api/v1/forensics/android/logcat` | Analyze logcat |
| `POST` | `/api/v1/forensics/full` | Full forensic analysis |
| `POST` | `/api/v1/forensics/quick-check` | Quick check |

#### 4.2.14 WebSocket Streaming

| Endpoint | Protocol | Description |
|----------|----------|-------------|
| `/ws/threats` | WebSocket | Real-time threat updates |

**Message Types:**
```json
// Subscribe
{"type": "subscribe", "filters": {"severity": ["critical", "high"], "platform": "ios"}}

// Threat Event
{"type": "threat", "data": {"id": "...", "severity": "critical", "indicator": {...}}}

// Heartbeat
{"type": "ping"}
{"type": "pong"}
```

---

## 5. Database Schema

### Core Tables

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `sources` | Threat intelligence sources | id, name, slug, category, reliability |
| `threat_actors` | Known threat actors | id, name, type, motivation, country |
| `malware_families` | Malware classification | id, name, type, platforms, capabilities |
| `campaigns` | Attack campaigns | id, name, status, threat_actor_id |
| `indicators` | IOCs (domains, IPs, hashes) | id, value, type, severity, confidence |
| `indicator_sources` | Many-to-many indicator-source | indicator_id, source_id |
| `community_reports` | User-reported threats | id, status, indicator_value |
| `update_history` | Source update logs | id, source_id, success, new_indicators |

### Enum Types

```sql
indicator_type: domain, ip, ipv6, hash, url, process, certificate, package, email, filepath, registry, yara
severity_level: critical, high, medium, low, info
platform_type: android, ios, windows, macos, linux, all
source_category: abuse_ch, phishing, ip_reputation, mobile, general, government, isac, community, premium
campaign_status: active, inactive, historic
threat_actor_type: nation-state, criminal, hacktivist, private-sector, unknown
```

---

## 6. Feature List with Acceptance Criteria

### 6.1 SMS Protection (Smishing Detection)

**Endpoints:** `POST /api/v1/sms/analyze`, `POST /api/v1/sms/analyze/batch`

**Expected Behaviors:**

| Scenario | Expected Result |
|----------|-----------------|
| Valid SMS with phishing URL | `200` with `risk_level: high`, detected URLs listed |
| Clean SMS message | `200` with `risk_level: low`, `recommendation: allow` |
| SMS with urgency keywords | `200` with increased risk score, keywords flagged |
| Empty message body | `400` with validation error |
| Invalid timestamp | `400` with `error: "Invalid timestamp format"` |
| Batch > 100 messages | `400` with `error: "Batch size exceeds limit"` |

**Flutter App Behavior:**

| State | Expected UI |
|-------|-------------|
| Analyzing | Show shimmer loading animation on SMS card |
| High risk detected | Red warning banner, "Block" button prominent |
| Low risk | Green checkmark, minimal UI interruption |
| API timeout | Retry toast with "Check Again" button |
| No permission | Show permission request dialog |

### 6.2 URL Protection (Safe Web)

**Endpoints:** `POST /api/v1/url/check`, `GET /api/v1/url/reputation/{domain}`

**Expected Behaviors:**

| Scenario | Expected Result |
|----------|-----------------|
| Known phishing URL | `200` with `safe: false`, threat types listed |
| Legitimate URL (google.com) | `200` with `safe: true`, `risk_score < 0.2` |
| Shortened URL (bit.ly) | `200` with resolved URL, `is_shortener: true` |
| Invalid URL format | `400` with `error: "Invalid URL format"` |
| URL with suspicious TLD (.tk, .ml) | `200` with elevated risk, `suspicious_tld: true` |
| Newly registered domain (<7 days) | `200` with warning, `domain_age_days` included |

**Flutter App Behavior:**

| State | Expected UI |
|-------|-------------|
| Checking URL | Loading indicator in URL preview card |
| Unsafe URL | Full-screen warning with "Go Back" and "Proceed Anyway" |
| Safe URL | Green indicator, allow proceed |
| Offline | Cache check only, show "Limited protection" banner |

### 6.3 Dark Web Monitoring

**Endpoints:** `POST /api/v1/darkweb/check/email`, `GET /api/v1/darkweb/alerts`

**Expected Behaviors:**

| Scenario | Expected Result |
|----------|-----------------|
| Breached email | `200` with `breached: true`, breach list |
| Clean email | `200` with `breached: false` |
| Invalid email format | `400` with validation error |
| Password check (k-anonymity) | `200` with `pwned: true/false`, count |
| Add monitored asset | `201` with asset ID |
| Remove non-existent asset | `404` |

**Flutter App Behavior:**

| State | Expected UI |
|-------|-------------|
| Breach found | Red alert card with breach details |
| No breaches | Green status with "All clear" message |
| Checking | Pulse animation on monitoring card |
| New alert | Push notification + badge on tab |

### 6.4 QR Code Security (Quishing)

**Endpoints:** `POST /api/v1/qr/scan`, `POST /api/v1/qr/preview`

**Expected Behaviors:**

| Scenario | Expected Result |
|----------|-----------------|
| QR with phishing URL | `200` with `safe: false`, resolved URL shown |
| QR with legitimate URL | `200` with `safe: true` |
| QR with WiFi config | `200` with parsed WiFi details |
| QR with crypto address | `200` with address validation |
| Malformed QR content | `400` with parse error |
| QR with URL shortener | `200` with `is_shortener: true`, resolved URL |

**Flutter App Behavior:**

| State | Expected UI |
|-------|-------------|
| Scanning | Camera preview with scan overlay |
| Unsafe QR detected | Haptic feedback + red warning overlay |
| Safe QR | Green checkmark, show content preview |
| Preview mode | Safe rendering of QR content |

### 6.5 App Security Suite

**Endpoints:** `POST /api/v1/apps/analyze`, `GET /api/v1/apps/trackers`

**Expected Behaviors:**

| Scenario | Expected Result |
|----------|-----------------|
| Known spyware package | `200` with `risk_level: critical`, `recommendation: uninstall` |
| Legitimate app | `200` with `risk_level: low` |
| App with dangerous permissions | `200` with permissions flagged |
| Sideloaded app detection | `200` with `is_sideloaded: true` |
| Privacy report request | `200` with tracker list, permission analysis |

**Flutter App Behavior:**

| State | Expected UI |
|-------|-------------|
| Scanning apps | Progress bar with app count |
| Threat found | Red badge on app icon, expandable details |
| All apps safe | Green summary card |
| Uninstall recommended | Deep link to app settings |

### 6.6 Network Security

**Endpoints:** `POST /api/v1/network/wifi/audit`, `POST /api/v1/network/audit/full`

**Expected Behaviors:**

| Scenario | Expected Result |
|----------|-----------------|
| Open WiFi network | `200` with `security_score < 30`, warnings |
| WPA3 secured network | `200` with `security_score > 80` |
| Evil twin detected | `200` with `threat: evil_twin` |
| ARP spoofing detected | `200` with `threat: arp_spoofing` |
| DNS hijacking attempt | `200` with `threat: dns_hijacking` |

**Flutter App Behavior:**

| State | Expected UI |
|-------|-------------|
| Auditing network | Network animation, progress indicator |
| Threat detected | Red banner with "Connect to VPN" CTA |
| Network secure | Green shield icon |
| VPN recommended | VPN toggle in bottom sheet |

### 6.7 Device Security

**Endpoints:** `POST /api/v1/device/register`, `POST /api/v1/device/{id}/locate`

**Expected Behaviors:**

| Scenario | Expected Result |
|----------|-----------------|
| Device registration | `201` with device ID and token |
| Locate device | `200` with location if available |
| Lock device | `202` command queued |
| Wipe device | `202` command queued, requires confirmation |
| SIM change detected | Event published, alert generated |
| OS vulnerability found | `200` with CVE list and patches |

**Flutter App Behavior:**

| State | Expected UI |
|-------|-------------|
| Registration | Loading during initial setup |
| Location found | Map view with device pin |
| Lock sent | Confirmation toast |
| Wipe confirmation | 2-step confirmation dialog |

---

## 7. Flutter App Test Cases

### 7.1 Unit Tests

| Test Category | Test Cases |
|---------------|------------|
| **API Client** | - Successful request handling<br>- Timeout handling<br>- Retry logic<br>- Auth header injection |
| **Providers** | - State initialization<br>- State updates on API response<br>- Error state handling<br>- Loading state management |
| **Services** | - SMS analysis service<br>- URL reputation service<br>- QR scanner service<br>- Notification service |
| **Models** | - JSON parsing<br>- Null safety<br>- Default values |

### 7.2 Widget Tests

| Screen | Test Cases |
|--------|------------|
| **Dashboard** | - Threat count display<br>- Protection status indicator<br>- Quick action buttons<br>- Pull-to-refresh |
| **SMS Protection** | - Message list rendering<br>- Risk badge colors<br>- Analyze button tap<br>- Empty state |
| **URL Protection** | - URL input validation<br>- Check button state<br>- Result display<br>- History list |
| **QR Scanner** | - Camera permission request<br>- Scan overlay<br>- Result modal<br>- Flash toggle |
| **Settings** | - Toggle states persistence<br>- Theme switching<br>- Notification preferences |

### 7.3 Integration Tests

| Flow | Steps | Expected Result |
|------|-------|-----------------|
| **First Launch** | 1. Open app<br>2. Complete onboarding<br>3. Grant permissions<br>4. Register device | Device registered, dashboard shown |
| **SMS Scan** | 1. Open SMS screen<br>2. Tap scan<br>3. Wait for analysis<br>4. View results | All messages analyzed with risk scores |
| **QR Scan** | 1. Open QR scanner<br>2. Scan QR code<br>3. View preview<br>4. Open/block URL | Safe URLs open, unsafe show warning |
| **Network Audit** | 1. Open network screen<br>2. Tap audit<br>3. View results<br>4. Connect VPN | Audit complete, VPN suggestion shown |
| **Dark Web Check** | 1. Open dark web screen<br>2. Add email<br>3. Run check<br>4. View results | Breach status shown with details |

### 7.4 Platform-Specific Tests

#### iOS

| Test | Verification |
|------|-------------|
| VPN Extension | NEPacketTunnelProvider activates |
| Background scan | BGTaskScheduler executes |
| Permissions | All permission dialogs work |
| Jailbreak detection | Correctly detects jailbroken devices |
| Keychain storage | Credentials stored securely |

#### Android

| Test | Verification |
|------|-------------|
| Background service | Foreground service runs |
| Permissions | Runtime permissions work |
| Root detection | Correctly detects rooted devices |
| Accessibility | Service activates if enabled |
| Work profile | App works in managed profile |

#### macOS

| Test | Verification |
|------|-------------|
| Window management | Resizing works correctly |
| Keyboard shortcuts | Cmd+C, Cmd+V work |
| Menu bar | App appears in menu bar |
| File access | Sandbox permissions work |
| Persistence scan | KnockKnock-style scan works |

#### Windows

| Test | Verification |
|------|-------------|
| High DPI | Scales correctly on 4K |
| Dark mode | Follows system theme |
| Startup | Auto-start option works |
| Firewall | Rules can be modified |
| Antivirus | No false positive conflicts |

---

## 8. Error Codes Reference

### HTTP Status Codes

| Code | Meaning | UI Response |
|------|---------|-------------|
| `200` | Success | Show results |
| `201` | Created | Show success toast |
| `202` | Accepted (async) | Show "Processing" state |
| `400` | Bad Request | Show field-specific errors |
| `401` | Unauthorized | Redirect to login, refresh token |
| `403` | Forbidden | Show "Access denied" message |
| `404` | Not Found | Show "Not found" state |
| `409` | Conflict | Show "Already exists" error |
| `422` | Unprocessable | Show validation errors |
| `429` | Rate Limited | Show retry timer |
| `500` | Server Error | Show "Something went wrong" with retry |
| `502` | Bad Gateway | Show "Service unavailable" |
| `503` | Service Unavailable | Show maintenance message |

### API Error Response Format

```json
{
  "error": "Error code string",
  "message": "Human-readable message",
  "details": {
    "field": "specific_field",
    "reason": "validation_reason"
  },
  "request_id": "abc123",
  "timestamp": "2026-01-07T12:00:00Z"
}
```

### Common Error Codes

| Error Code | Description | Resolution |
|------------|-------------|------------|
| `invalid_api_key` | API key invalid or expired | Re-authenticate |
| `rate_limit_exceeded` | Too many requests | Wait for `retry_after` |
| `invalid_input` | Request validation failed | Fix input and retry |
| `resource_not_found` | Requested resource doesn't exist | Check ID/slug |
| `duplicate_entry` | Resource already exists | Use existing or update |
| `service_unavailable` | Backend service down | Retry with backoff |

---

## 9. Platform-Specific Requirements

### iOS Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| iOS Version | 15.0 | 17.0+ |
| Device | iPhone SE (2nd gen) | iPhone 12+ |
| Storage | 100MB | 200MB |
| RAM | 2GB | 4GB |

**iOS-Specific Features:**
- Network Extension for VPN/DNS filtering
- Background App Refresh for scheduled scans
- Push notifications via APNs
- Keychain for secure storage
- Jailbreak detection

**Permissions Required:**
- Camera (QR scanning)
- Local Network (network audit)
- Notifications
- Background App Refresh

### Android Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Android Version | 7.0 (API 24) | 12.0+ (API 31) |
| Device | Any with 2GB RAM | 4GB+ RAM |
| Storage | 100MB | 200MB |

**Android-Specific Features:**
- Foreground service for protection
- Accessibility service (optional)
- VPN service for DNS filtering
- Work profile support

**Permissions Required:**
- SMS read (smishing detection)
- Camera (QR scanning)
- Location (network audit)
- Package query (app analysis)
- Foreground service
- Post notifications (Android 13+)

### macOS Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| macOS Version | 11.0 (Big Sur) | 13.0+ (Ventura) |
| Architecture | Intel or Apple Silicon | Apple Silicon |
| Storage | 150MB | 300MB |

**macOS-Specific Features:**
- Persistence scanner (KnockKnock-style)
- Network connection monitoring
- Browser extension scanning
- VirusTotal integration

### Windows Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Windows Version | 10 (1809) | 11 |
| Architecture | x64 | x64 |
| Storage | 150MB | 300MB |

**Windows-Specific Features:**
- Startup registration
- Firewall rule management
- Registry monitoring
- System tray integration

---

## 10. Test Data

### Test Users

| Purpose | Email | Password | Notes |
|---------|-------|----------|-------|
| Standard user | test@orbguard.test | TestPass123! | Basic permissions |
| Admin user | admin@orbguard.test | AdminPass456! | Full access |
| Breached email | pwned@breached.test | N/A | Returns breach data |
| Clean email | clean@secure.test | N/A | No breaches |

### Test Indicators

| Type | Value | Expected Result |
|------|-------|-----------------|
| Phishing URL | `https://test-phishing.orbguard.test/login` | Threat detected |
| Clean URL | `https://google.com` | Safe |
| Malicious domain | `malware-test.orbguard.test` | Blocked |
| Clean domain | `github.com` | Safe |
| Test hash (malware) | `d4c9d9f5e8c8a4e7b3f2a1c0d9e8f7a6` | Threat detected |
| Clean hash | `e3b0c44298fc1c149afbf4c8996fb924` | Safe (SHA256 empty) |

### Test SMS Messages

| Content | Expected Risk |
|---------|---------------|
| "Your package is waiting! Click here: bit.ly/abc123" | High (phishing) |
| "Your OTP is 123456. Do not share." | Low (legitimate) |
| "URGENT: Your account will be suspended! Verify: evil.com" | Critical (phishing) |
| "Meeting tomorrow at 3pm. - John" | Low (clean) |

### Test QR Codes

| Content | Expected Result |
|---------|-----------------|
| `https://phishing-site.test/login` | Unsafe - phishing |
| `https://github.com` | Safe |
| `WIFI:S:TestNetwork;T:WPA;P:password123;;` | WiFi config parsed |
| `bitcoin:1A1zP1...` | Crypto address parsed |

---

## 11. Edge Cases to Test

### Input Validation

| Case | Test Input | Expected Handling |
|------|------------|-------------------|
| Empty string | `""` | `400` validation error |
| Null value | `null` | `400` validation error |
| Very long string | 10,000 chars | `400` max length error |
| Unicode | `éмојї 🔥 العربية` | Handled correctly |
| SQL injection | `'; DROP TABLE--` | Sanitized, no effect |
| XSS attempt | `<script>alert(1)</script>` | Escaped in response |
| Path traversal | `../../etc/passwd` | Rejected |
| Emoji in URL | `https://test.com/🔥` | URL encoded correctly |

### Network Conditions

| Condition | Expected Behavior |
|-----------|-------------------|
| No internet | Show offline mode, use cached data |
| Slow connection (>5s) | Show loading state, don't timeout prematurely |
| Intermittent connection | Automatic retry with backoff |
| VPN active | All requests go through VPN |
| Proxy configured | Respect system proxy settings |
| IPv6 only | API must work on IPv6 |

### Device States

| State | Expected Behavior |
|-------|-------------------|
| Low battery (<20%) | Reduce background scan frequency |
| Low storage (<100MB) | Warn user, clear cache |
| Background app | Background tasks continue |
| App killed | Service restarts on next trigger |
| Device locked | Notifications still arrive |
| Do Not Disturb | Respect DND for non-critical alerts |

### Concurrency

| Scenario | Expected Behavior |
|----------|-------------------|
| Multiple scans | Queue requests, show combined progress |
| Rapid button taps | Debounce, single request |
| Simultaneous API calls | All complete without race conditions |
| WebSocket reconnect | Automatic reconnection with backoff |

### Time & Date

| Case | Expected Handling |
|------|-------------------|
| Different timezone | All dates in UTC, display local |
| DST transition | No time jumps in logs |
| Far future date | Handled gracefully |
| Epoch timestamp | Converted correctly |

---

## 12. Test Execution Protocol

### Phase 1: API Tests (Backend)

```bash
# 1. Start backend services
cd /Users/nima/Developments/orbguard.lab
docker-compose up -d

# 2. Run backend health check
curl http://localhost:8090/health

# 3. Run API integration tests
go test ./... -v -tags=integration

# 4. Verify all endpoints respond correctly
# (See API test script in /scripts/api_tests.sh)
```

**Pass Criteria:**
- All health checks pass
- API responds within 200ms average
- No 5xx errors
- Rate limiting works correctly

### Phase 2: Flutter Unit & Widget Tests

```bash
# 1. Navigate to Flutter project
cd /Users/nima/Developments/orbguard

# 2. Run unit tests
flutter test

# 3. Run widget tests
flutter test --tags=widget

# 4. Generate coverage report
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

**Pass Criteria:**
- All tests pass
- Coverage > 70% for core services
- No runtime exceptions

### Phase 3: Platform Integration Tests

#### iOS

```bash
# 1. Build iOS app
flutter build ios --debug

# 2. Run on simulator
flutter run -d "iPhone 15 Pro"

# 3. Run integration tests
flutter test integration_test/ -d "iPhone 15 Pro"

# 4. Test on physical device
flutter run -d <device_id>
```

#### Android

```bash
# 1. Build Android app
flutter build apk --debug

# 2. Run on emulator
flutter run -d "emulator-5554"

# 3. Run integration tests
flutter test integration_test/ -d "emulator-5554"
```

#### macOS

```bash
# 1. Build macOS app
flutter build macos --debug

# 2. Run on macOS
flutter run -d macos

# 3. Run integration tests
flutter test integration_test/ -d macos
```

#### Windows

```powershell
# 1. Build Windows app
flutter build windows --debug

# 2. Run on Windows
flutter run -d windows

# 3. Run integration tests
flutter test integration_test/ -d windows
```

### Phase 4: Manual Testing Checklist

| Feature | iOS | Android | macOS | Windows |
|---------|-----|---------|-------|---------|
| App launch | [ ] | [ ] | [ ] | [ ] |
| Login/Auth | [ ] | [ ] | [ ] | [ ] |
| Dashboard load | [ ] | [ ] | [ ] | [ ] |
| SMS scan | [ ] | [ ] | N/A | N/A |
| URL check | [ ] | [ ] | [ ] | [ ] |
| QR scan | [ ] | [ ] | [ ] | [ ] |
| Network audit | [ ] | [ ] | [ ] | [ ] |
| Dark web check | [ ] | [ ] | [ ] | [ ] |
| App security scan | [ ] | [ ] | N/A | N/A |
| Settings persist | [ ] | [ ] | [ ] | [ ] |
| Push notifications | [ ] | [ ] | [ ] | [ ] |
| Offline mode | [ ] | [ ] | [ ] | [ ] |
| Background scan | [ ] | [ ] | [ ] | [ ] |

### Failure Handling Protocol

When a test fails:

1. **Capture evidence:**
   - Screenshot/screen recording
   - Console logs (`flutter logs`)
   - Network trace (Charles/Proxyman)
   - API request/response

2. **Document:**
   ```
   Feature: [Feature name]
   Platform: [iOS/Android/macOS/Windows]
   Test: [Test name]
   Status: FAIL
   Error: [Error message]
   Steps to reproduce:
   1. ...
   2. ...
   Evidence: [Link to screenshot/logs]
   ```

3. **Prioritize:**
   - P0: App crash, data loss, security issue
   - P1: Feature broken, bad UX
   - P2: Minor issue, workaround exists
   - P3: Cosmetic, low impact

---

## 13. Definition of "Complete"

A feature is considered complete when ALL of the following are true:

### Backend (API)

- [ ] Endpoint returns correct response for all input types
- [ ] Validation errors return 400 with specific messages
- [ ] Auth errors return 401/403 appropriately
- [ ] Rate limiting works (429 returned correctly)
- [ ] Response time < 200ms (p95)
- [ ] No errors in server logs (warnings acceptable if expected)
- [ ] Database queries optimized (no N+1)
- [ ] API documentation updated

### Flutter App

- [ ] Feature works on all target platforms (iOS, Android, macOS, Windows)
- [ ] Loading states shown during API calls
- [ ] Error states handled with retry option
- [ ] Offline behavior graceful
- [ ] No console errors/warnings
- [ ] Accessibility labels present
- [ ] Dark mode works correctly
- [ ] Localization strings present (if applicable)
- [ ] Performance: UI updates < 100ms after response

### Quality Gates

| Gate | Threshold |
|------|-----------|
| Unit test coverage | > 70% |
| Integration test pass | 100% |
| Manual test pass | 100% on all platforms |
| API response time (p95) | < 200ms |
| App startup time | < 3s |
| Memory usage (idle) | < 150MB |
| Battery impact (background) | < 5%/hour |

---

## 14. Known Issues & Limitations

### Current Limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| ML models not trained | On-device ML unavailable | Use API-based analysis |
| Dark web API mock | Limited breach data | Manual testing with mock data |
| Data broker removal manual | No automated opt-out | Guided manual process |
| No admin dashboard | Backend-only management | API direct calls |

### Known Issues

| Issue | Severity | Status |
|-------|----------|--------|
| Neo4j optional | Low | Falls back to PostgreSQL |
| NATS optional | Low | Falls back to in-memory events |
| iOS VPN requires entitlement | Medium | TestFlight/App Store only |

### Dependencies on External Services

| Service | Impact if Down | Fallback |
|---------|----------------|----------|
| Google Safe Browsing | URL check degraded | Use local blocklist |
| HIBP | Breach check unavailable | Cached results only |
| VirusTotal | Hash lookup unavailable | Local YARA rules |
| AbuseIPDB | IP reputation unavailable | Cached results |

---

## Appendix A: API Test Commands

```bash
# Health check
curl -s http://localhost:8090/health | jq

# Check URL
curl -s -X POST http://localhost:8090/api/v1/url/check \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}' | jq

# Analyze SMS
curl -s -X POST http://localhost:8090/api/v1/sms/analyze \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"sender": "+1234567890", "message": "Test message"}' | jq

# Check dark web breach
curl -s -X POST http://localhost:8090/api/v1/darkweb/check/email \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com"}' | jq

# Get stats
curl -s http://localhost:8090/api/v1/stats | jq
```

---

## Appendix B: Flutter Test Commands

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/services/api_client_test.dart

# Run with coverage
flutter test --coverage

# Run integration tests on device
flutter test integration_test/app_test.dart -d <device>

# Run golden tests
flutter test --update-goldens

# Check for issues
flutter analyze
```

---

## Approval

| Role | Name | Date | Signature |
|------|------|------|-----------|
| QA Lead | | | |
| Dev Lead | | | |
| Product Owner | | | |

---

*Document Version: 1.0.0*
*Last Updated: 2026-01-07*
