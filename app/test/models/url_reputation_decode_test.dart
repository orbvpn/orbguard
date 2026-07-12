/// Golden decode tests for the URL protection endpoints.
///
/// Fixtures mirror the exact JSON emitted by the live backend:
/// - POST /api/v1/url/check -> models.URLCheckResponse
///   (orbguard.lab/internal/domain/models/url.go): {url, domain, is_safe,
///   should_block, category, threat_level, confidence, description?,
///   warnings?, block_reason?, allow_override, campaign_name?,
///   threat_actor_name?, cache_hit, checked_at}. Safe URLs carry
///   threat_level "info" (services/url_reputation.go).
/// - GET /api/v1/url/reputation/{domain} -> models.URLReputation, the
///   Wave-2 enriched shape with live DNS/TLS/RDAP data. Go encodes unset
///   time.Time as 0001-01-01T00:00:00Z; the model must treat that as
///   absent. 404 means NXDOMAIN/invalid domain (handled by the API client).
/// - POST /api/v1/url/report -> 201 {id, status, created_at, message?}
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/models/api/threat_indicator.dart';
import 'package:orbguard/models/api/url_reputation.dart';

/// A phishing hit from the threat-intel database.
const _phishingCheckJson = '''
{
  "url": "https://secure-bank-login.xyz/verify",
  "domain": "secure-bank-login.xyz",
  "is_safe": false,
  "should_block": true,
  "category": "phishing",
  "threat_level": "high",
  "confidence": 0.95,
  "description": "Known phishing domain impersonating banking services",
  "warnings": ["This site impersonates a bank"],
  "block_reason": "Listed in threat intelligence as active phishing",
  "allow_override": false,
  "campaign_name": "BankHarvest 2026",
  "threat_actor_name": "FIN-X",
  "cache_hit": true,
  "checked_at": "2026-06-10T12:00:00Z"
}
''';

/// A safe URL: omitempty fields (description/warnings/block_reason/
/// campaign_name/threat_actor_name) are absent from the wire.
const _safeCheckJson = '''
{
  "url": "https://example.com",
  "domain": "example.com",
  "is_safe": true,
  "should_block": false,
  "category": "safe",
  "threat_level": "info",
  "confidence": 0.99,
  "allow_override": false,
  "cache_hit": false,
  "checked_at": "2026-06-10T12:00:00Z"
}
''';

/// Enriched domain reputation with live DNS/TLS data but no RDAP
/// registration date (Go zero time on first_seen).
const _reputationNoRdapJson = '''
{
  "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "domain": "example.com",
  "category": "uncategorized",
  "threat_level": "info",
  "confidence": 0.6,
  "is_malicious": false,
  "is_blocked": false,
  "sources": ["dns", "tls"],
  "first_seen": "0001-01-01T00:00:00Z",
  "last_seen": "0001-01-01T00:00:00Z",
  "last_checked": "2026-06-10T12:00:00Z",
  "cert_valid": true,
  "cert_issuer": "DigiCert Inc",
  "ip_address": "93.184.216.34",
  "asn": "AS15133 Edgecast",
  "country": "US",
  "is_shortened": false,
  "is_new_domain": false,
  "has_suspicious_tld": false,
  "risk_score": 0.1
}
''';

/// A blocked threat-intel hit with full RDAP enrichment.
const _reputationBlockedJson = '''
{
  "id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
  "domain": "secure-bank-login.xyz",
  "category": "phishing",
  "threat_level": "high",
  "confidence": 0.95,
  "is_malicious": true,
  "is_blocked": true,
  "sources": ["threat_intel"],
  "first_seen": "2026-05-20T00:00:00Z",
  "last_seen": "2026-06-09T00:00:00Z",
  "last_checked": "2026-06-10T12:00:00Z",
  "registrar": "NameCheap, Inc.",
  "is_shortened": false,
  "is_new_domain": true,
  "has_suspicious_tld": true,
  "risk_score": 0.92
}
''';

const _reportResultJson = '''
{
  "id": "1c0a5c4e-88f1-4a3e-9c5e-2f0d7b3dcb6e",
  "status": "pending_review",
  "created_at": "2026-06-10T12:00:00Z",
  "message": "Report received and queued for review"
}
''';

Map<String, dynamic> _decode(String fixture) =>
    jsonDecode(fixture) as Map<String, dynamic>;

void main() {
  group('UrlReputationResult.fromJson — phishing hit', () {
    late UrlReputationResult result;

    setUp(() {
      result = UrlReputationResult.fromJson(_decode(_phishingCheckJson));
    });

    test('parses classification fields', () {
      expect(result.url, 'https://secure-bank-login.xyz/verify');
      expect(result.domain, 'secure-bank-login.xyz');
      expect(result.isSafe, isFalse);
      expect(result.shouldBlock, isTrue);
      expect(result.category, UrlCategory.phishing);
      expect(result.confidence, 0.95);
      expect(result.cacheHit, isTrue);
      expect(result.checkedAt, DateTime.utc(2026, 6, 10, 12));
    });

    test("threat_level 'high' maps to SeverityLevel.high — never to a safe "
        'or unknown level', () {
      expect(result.threatLevel, SeverityLevel.high);
      expect(result.threatLevel, isNot(SeverityLevel.unknown));
      expect(result.threatLevel, isNot(SeverityLevel.info));
      expect(result.riskScore, greaterThan(0.5));
    });

    test('derives a threat entry from the real block fields', () {
      expect(result.threats, hasLength(1));
      expect(result.threats.single.severity, SeverityLevel.high);
      expect(result.threats.single.description,
          'Listed in threat intelligence as active phishing');
      expect(result.threats.single.source, 'campaign: BankHarvest 2026');
      expect(result.recommendation,
          'Listed in threat intelligence as active phishing');
      expect(result.hasDangerousCategories, isTrue);
    });
  });

  group('UrlReputationResult.fromJson — safe URL (omitempty fields absent)',
      () {
    test('parses without optional keys and reports no threats', () {
      final result = UrlReputationResult.fromJson(_decode(_safeCheckJson));
      expect(result.isSafe, isTrue);
      expect(result.shouldBlock, isFalse);
      expect(result.category, UrlCategory.safe);
      expect(result.threatLevel, SeverityLevel.info);
      expect(result.threats, isEmpty);
      expect(result.warnings, isEmpty);
      expect(result.description, isNull);
      expect(result.blockReason, isNull);
      expect(result.recommendation, isNull);
      expect(result.riskScore, 0.0);
    });
  });

  group('UrlReputationResult.fromJson — contract violations', () {
    for (final key in [
      'url',
      'is_safe',
      'should_block',
      'category',
      'threat_level',
      'checked_at',
    ]) {
      test('missing $key throws FormatException', () {
        final json = _decode(_phishingCheckJson)..remove(key);
        expect(() => UrlReputationResult.fromJson(json),
            throwsA(isA<FormatException>()));
      });
    }
  });

  group('DomainReputation.fromJson — GET /api/v1/url/reputation/{domain}',
      () {
    test('parses live DNS/TLS enrichment', () {
      final rep = DomainReputation.fromJson(_decode(_reputationNoRdapJson));
      expect(rep.domain, 'example.com');
      expect(rep.category, UrlCategory.uncategorized);
      expect(rep.threatLevel, SeverityLevel.info);
      expect(rep.isMalicious, isFalse);
      expect(rep.isBlocked, isFalse);
      expect(rep.sources, ['dns', 'tls']);
      expect(rep.ipAddress, '93.184.216.34');
      expect(rep.asn, 'AS15133 Edgecast');
      expect(rep.country, 'US');
      expect(rep.riskScore, 0.1);
      expect(rep.reputationScore, closeTo(90.0, 0.001));
    });

    test('treats Go zero-time first_seen as an absent registration date',
        () {
      final rep = DomainReputation.fromJson(_decode(_reputationNoRdapJson));
      expect(rep.registeredAt, isNull);
      // ageInDays is 0 when the registration date is unknown; UI must check
      // registeredAt for null before rendering an age row.
      expect(rep.ageInDays, 0);
      expect(rep.lastChecked, DateTime.utc(2026, 6, 10, 12));
    });

    test('exposes TLS details only when the backend inspected TLS', () {
      final withTls =
          DomainReputation.fromJson(_decode(_reputationNoRdapJson));
      expect(withTls.certValid, isTrue);
      expect(withTls.ssl, isNotNull);
      expect(withTls.ssl!.hasValidSsl, isTrue);
      expect(withTls.ssl!.issuer, 'DigiCert Inc');

      // cert_valid carries omitempty on a *bool: absent when TLS could not
      // be inspected.
      final withoutTls =
          DomainReputation.fromJson(_decode(_reputationBlockedJson));
      expect(withoutTls.certValid, isNull);
      expect(withoutTls.ssl, isNull);
    });

    test('parses a blocked threat-intel hit with a real registration date',
        () {
      final rep = DomainReputation.fromJson(_decode(_reputationBlockedJson));
      expect(rep.isMalicious, isTrue);
      expect(rep.isBlocked, isTrue);
      expect(rep.isOnBlocklist, isTrue);
      expect(rep.threatLevel, SeverityLevel.high);
      expect(rep.threatLevel, isNot(SeverityLevel.info));
      expect(rep.registeredAt, DateTime.utc(2026, 5, 20));
      expect(rep.isNewlyRegistered, isTrue);
      expect(rep.hasSuspiciousTld, isTrue);
      expect(rep.registrar, 'NameCheap, Inc.');
      expect(rep.isSuspicious, isTrue);
    });

    test('missing required fields throw FormatException', () {
      for (final key in [
        'domain',
        'category',
        'threat_level',
        'risk_score',
        'is_malicious',
        'is_blocked',
      ]) {
        final json = _decode(_reputationNoRdapJson)..remove(key);
        expect(() => DomainReputation.fromJson(json),
            throwsA(isA<FormatException>()),
            reason: 'expected a FormatException when "$key" is missing');
      }
    });
  });

  group('UrlReportResult.fromJson — POST /api/v1/url/report (201)', () {
    test('parses the created report receipt', () {
      final report = UrlReportResult.fromJson(_decode(_reportResultJson));
      expect(report.id, '1c0a5c4e-88f1-4a3e-9c5e-2f0d7b3dcb6e');
      expect(report.status, 'pending_review');
      expect(report.createdAt, DateTime.utc(2026, 6, 10, 12));
      expect(report.message, 'Report received and queued for review');
    });

    test('missing id/status/created_at throws FormatException', () {
      for (final key in ['id', 'status', 'created_at']) {
        final json = _decode(_reportResultJson)..remove(key);
        expect(() => UrlReportResult.fromJson(json),
            throwsA(isA<FormatException>()),
            reason: 'expected a FormatException when "$key" is missing');
      }
    });
  });
}
