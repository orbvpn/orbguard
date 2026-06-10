/// Golden decode tests for the SMS protection endpoints.
///
/// Fixtures mirror the exact JSON emitted by the live backend:
/// - POST /api/v1/sms/analyze -> models.SMSAnalysisResult
///   (orbguard.lab/internal/domain/models/sms.go; handler encodes the
///   result object directly, no envelope). `threat_level` is one of
///   safe|low|medium|high|critical; many fields carry `omitempty` and are
///   absent for clean messages. The raw sender is never echoed (hashed
///   server-side).
/// - GET /api/v1/sms/stats -> per-device stats map built by
///   handlers/sms.go GetStats: {device_id, total_analyzed, threats_detected,
///   threats_by_type, threats_by_level, false_positives_reported,
///   last_24_hours{analyzed,threats}, last_30_days_trend[], last_analyzed_at}
/// - GET /api/v1/sms/patterns -> on-device detection word lists
///   (handlers/sms.go GetPatterns): {version, last_updated, urgency_words,
///   fear_words, reward_words, personal_words, financial_words,
///   url_shorteners, suspicious_tlds}
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:OrbGuard/models/api/sms_analysis.dart';
import 'package:OrbGuard/models/api/threat_indicator.dart';

/// A smishing detection with every section the analyzer can emit.
const _threatAnalysisJson = '''
{
  "id": "0d3aab8a-9d2f-4f4e-b9a7-6f1f0a4f2c11",
  "message_id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "is_threat": true,
  "threat_level": "high",
  "threat_type": "smishing",
  "confidence": 0.92,
  "description": "Message impersonates a bank and contains a malicious link",
  "recommendations": [
    "Do not click the link",
    "Block and report the sender"
  ],
  "urls": [
    {
      "url": "https://bit.ly/3xy",
      "domain": "bit.ly",
      "is_malicious": true,
      "is_shortened": true,
      "expanded_url": "https://secure-bank-login.xyz/verify",
      "category": "phishing",
      "threat_details": "Known phishing infrastructure",
      "confidence": 0.97,
      "indicator_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479"
    }
  ],
  "phone_numbers": ["+15551234567"],
  "emails": [],
  "pattern_matches": [
    {
      "pattern_name": "urgency_pressure",
      "pattern_type": "nlp",
      "matched_text": "act now",
      "confidence": 0.8,
      "description": "Urgency pressure tactic"
    }
  ],
  "sender_analysis": {
    "is_short_code": false,
    "is_alphanumeric": true,
    "is_spoofed": true,
    "spoof_target": "Chase Bank",
    "is_known_brand": false,
    "risk_score": 0.88,
    "notes": "Alphanumeric sender mimicking a bank"
  },
  "intent_analysis": {
    "primary_intent": "credential_theft",
    "urgency": 0.9,
    "fear_factor": 0.7,
    "reward_promise": 0.0,
    "action_required": true,
    "personal_data": false,
    "financial_data": true,
    "suspicious_flags": ["urgency", "financial_request"]
  },
  "analyzed_at": "2026-06-10T12:00:00Z"
}
''';

/// A clean message: every `omitempty` field is absent from the wire.
const _safeAnalysisJson = '''
{
  "id": "3f2c1b0a-1111-4222-8333-444455556666",
  "message_id": "aaaa1111-2222-4333-8444-555566667777",
  "is_threat": false,
  "threat_level": "safe",
  "confidence": 0.1,
  "description": "No threats detected",
  "analyzed_at": "2026-06-10T12:00:00Z"
}
''';

const _statsJson = '''
{
  "device_id": "device-123",
  "total_analyzed": 250,
  "threats_detected": 12,
  "threats_by_type": {"smishing": 7, "phishing": 5},
  "threats_by_level": {"high": 8, "critical": 4},
  "false_positives_reported": 1,
  "last_24_hours": {"analyzed": 14, "threats": 2},
  "last_30_days_trend": [
    {"date": "2026-06-09", "analyzed": 40, "threats": 3},
    {"date": "2026-06-10", "analyzed": 14, "threats": 2}
  ],
  "last_analyzed_at": "2026-06-10T11:58:00Z"
}
''';

const _patternsJson = '''
{
  "version": "1.0.0",
  "last_updated": "2026-06-10T12:00:00Z",
  "urgency_words": ["urgent", "immediately", "act now"],
  "fear_words": ["suspended", "blocked", "fraud"],
  "reward_words": ["won", "prize", "free"],
  "personal_words": ["ssn", "password", "pin"],
  "financial_words": ["credit card", "cvv"],
  "url_shorteners": ["bit.ly", "tinyurl.com"],
  "suspicious_tlds": [".xyz", ".top"]
}
''';

Map<String, dynamic> _decode(String fixture) =>
    jsonDecode(fixture) as Map<String, dynamic>;

void main() {
  group('SmsThreatLevel.fromString — backend level mapping', () {
    test("maps 'safe' to safe", () {
      expect(SmsThreatLevel.fromString('safe'), SmsThreatLevel.safe);
    });

    test("maps 'low' and 'medium' to suspicious", () {
      expect(SmsThreatLevel.fromString('low'), SmsThreatLevel.suspicious);
      expect(SmsThreatLevel.fromString('medium'), SmsThreatLevel.suspicious);
    });

    test("maps 'high' to dangerous — never to safe", () {
      final level = SmsThreatLevel.fromString('high');
      expect(level, SmsThreatLevel.dangerous);
      expect(level, isNot(SmsThreatLevel.safe));
    });

    test("maps 'critical' to critical", () {
      expect(SmsThreatLevel.fromString('critical'), SmsThreatLevel.critical);
    });

    test('throws FormatException on unknown levels instead of defaulting',
        () {
      expect(() => SmsThreatLevel.fromString('severe'),
          throwsA(isA<FormatException>()));
      expect(() => SmsThreatLevel.fromString(''),
          throwsA(isA<FormatException>()));
    });
  });

  group('SmsAnalysisResult.fromJson — threat detection payload', () {
    late SmsAnalysisResult result;

    setUp(() {
      result = SmsAnalysisResult.fromJson(_decode(_threatAnalysisJson));
    });

    test('parses identity and classification fields', () {
      expect(result.id, '0d3aab8a-9d2f-4f4e-b9a7-6f1f0a4f2c11');
      expect(result.messageId, '7c9e6679-7425-40de-944b-e07fc1f90ae7');
      expect(result.isThreat, isTrue);
      expect(result.threatLevel, SmsThreatLevel.dangerous);
      expect(result.rawThreatLevel, 'high');
      expect(result.threatType, SmsThreatType.smishing);
      expect(result.riskScore, 0.92);
      expect(result.analyzedAt, DateTime.utc(2026, 6, 10, 12));
    });

    test('a high-level threat is never presented as safe', () {
      expect(result.threatLevel, isNot(SmsThreatLevel.safe));
      expect(result.shouldBlock, isTrue);
      expect(result.hasThreats, isTrue);
    });

    test('surfaces the classified threat as a one-element threat list', () {
      expect(result.threats, hasLength(1));
      expect(result.threats.single.type, SmsThreatType.smishing);
      expect(result.threats.single.severity, SeverityLevel.high);
      expect(result.threats.single.confidence, 0.92);
    });

    test('parses extracted URLs including the is_shortened wire key', () {
      expect(result.extractedUrls, hasLength(1));
      final url = result.extractedUrls.single;
      expect(url.url, 'https://bit.ly/3xy');
      expect(url.domain, 'bit.ly');
      expect(url.isMalicious, isTrue);
      expect(url.isShortener, isTrue); // wire key is `is_shortened`
      expect(url.expandedUrl, 'https://secure-bank-login.xyz/verify');
      expect(url.categories, ['phishing']);
      expect(url.confidence, 0.97);
    });

    test('parses pattern matches and recommendations', () {
      expect(result.patternMatches, hasLength(1));
      expect(result.patternMatches.single.patternName, 'urgency_pressure');
      expect(result.matchedPatterns, ['urgency_pressure']);
      expect(result.recommendations, hasLength(2));
      expect(result.recommendation, contains('Do not click the link'));
    });

    test('parses sender analysis: spoof_target maps to spoofedBrand and the '
        'raw sender is never echoed by the backend', () {
      final sender = result.senderAnalysis;
      expect(sender, isNotNull);
      expect(sender!.isSpoofed, isTrue);
      expect(sender.spoofedBrand, 'Chase Bank'); // wire key `spoof_target`
      expect(sender.isAlphanumeric, isTrue);
      expect(sender.riskScore, 0.88);
      expect(sender.warnings, ['Alphanumeric sender mimicking a bank']);
      // Privacy: the backend hashes senders server-side and emits no
      // `sender` key, so the field is empty (UI must source it locally).
      expect(sender.sender, isEmpty);
    });

    test('parses intent analysis and derives detected intents', () {
      final intent = result.intentAnalysis;
      expect(intent, isNotNull);
      expect(intent!.primaryIntent, 'credential_theft');
      expect(intent.urgency, 0.9);
      expect(intent.actionRequired, isTrue);
      expect(intent.financialData, isTrue);
      expect(
        result.detectedIntents,
        containsAll([
          SuspiciousIntent.urgency,
          SuspiciousIntent.fear,
          SuspiciousIntent.greed,
        ]),
      );
    });
  });

  group('SmsAnalysisResult.fromJson — clean message (omitempty fields absent)',
      () {
    test('parses without throwing and reports no threats', () {
      final result = SmsAnalysisResult.fromJson(_decode(_safeAnalysisJson));
      expect(result.isThreat, isFalse);
      expect(result.threatLevel, SmsThreatLevel.safe);
      expect(result.threatType, isNull);
      expect(result.threats, isEmpty);
      expect(result.extractedUrls, isEmpty);
      expect(result.recommendations, isEmpty);
      expect(result.recommendation, isNull);
      expect(result.patternMatches, isEmpty);
      expect(result.senderAnalysis, isNull);
      expect(result.intentAnalysis, isNull);
      expect(result.shouldBlock, isFalse);
    });
  });

  group('SmsAnalysisResult.fromJson — contract violations surface as errors',
      () {
    test('missing threat_level throws FormatException', () {
      final json = _decode(_safeAnalysisJson)..remove('threat_level');
      expect(() => SmsAnalysisResult.fromJson(json),
          throwsA(isA<FormatException>()));
    });

    test('missing is_threat throws FormatException', () {
      final json = _decode(_safeAnalysisJson)..remove('is_threat');
      expect(() => SmsAnalysisResult.fromJson(json),
          throwsA(isA<FormatException>()));
    });

    test('missing analyzed_at throws FormatException', () {
      final json = _decode(_safeAnalysisJson)..remove('analyzed_at');
      expect(() => SmsAnalysisResult.fromJson(json),
          throwsA(isA<FormatException>()));
    });

    test('unrecognized threat_level throws instead of defaulting to safe',
        () {
      final json = _decode(_threatAnalysisJson)
        ..['threat_level'] = 'catastrophic';
      expect(() => SmsAnalysisResult.fromJson(json),
          throwsA(isA<FormatException>()));
    });
  });

  group('SmsStatsResult.fromJson — GET /api/v1/sms/stats', () {
    test('parses the per-device stats shape', () {
      final stats = SmsStatsResult.fromJson(_decode(_statsJson));
      expect(stats.deviceId, 'device-123');
      expect(stats.totalAnalyzed, 250);
      expect(stats.threatsDetected, 12);
      expect(stats.threatsByType, {'smishing': 7, 'phishing': 5});
      expect(stats.threatsByLevel, {'high': 8, 'critical': 4});
      expect(stats.falsePositivesReported, 1);
      expect(stats.last24hAnalyzed, 14);
      expect(stats.last24hThreats, 2);
      expect(stats.last30DaysTrend, hasLength(2));
      expect(stats.last30DaysTrend.first.date, '2026-06-09');
      expect(stats.last30DaysTrend.first.threats, 3);
      expect(stats.lastAnalyzedAt, DateTime.utc(2026, 6, 10, 11, 58));
    });

    test('missing total_analyzed throws FormatException', () {
      final json = _decode(_statsJson)..remove('total_analyzed');
      expect(() => SmsStatsResult.fromJson(json),
          throwsA(isA<FormatException>()));
    });

    test('null last_analyzed_at (device never analyzed) parses to null', () {
      final json = _decode(_statsJson)..remove('last_analyzed_at');
      final stats = SmsStatsResult.fromJson(json);
      expect(stats.lastAnalyzedAt, isNull);
    });
  });

  group('SmsDetectionPatterns.fromJson — GET /api/v1/sms/patterns', () {
    test('parses the on-device word-list shape', () {
      final patterns = SmsDetectionPatterns.fromJson(_decode(_patternsJson));
      expect(patterns.version, '1.0.0');
      expect(patterns.lastUpdated, DateTime.utc(2026, 6, 10, 12));
      expect(patterns.urgencyWords, contains('act now'));
      expect(patterns.fearWords, contains('fraud'));
      expect(patterns.rewardWords, contains('prize'));
      expect(patterns.personalWords, contains('password'));
      expect(patterns.financialWords, contains('cvv'));
      expect(patterns.urlShorteners, contains('bit.ly'));
      expect(patterns.suspiciousTlds, contains('.xyz'));
    });
  });
}
