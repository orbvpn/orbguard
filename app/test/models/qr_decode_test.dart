/// Golden decode tests for POST /api/v1/qr/scan.
///
/// Fixtures mirror the exact JSON emitted by the live backend
/// (orbguard.lab/internal/api/handlers/qr_security.go encodes
/// models.QRScanResult directly; struct tags in
/// internal/domain/models/qr_security.go):
/// {id, raw_content, content_type, parsed_content?, threat_level,
///  threat_score (0-100), threats[], is_safe, should_block, warnings,
///  recommendations, url_preview?, scanned_at,
///  analysis_duration (Go time.Duration = nanoseconds)}.
/// `threat_level` is one of safe|low|medium|high|critical|unknown.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/models/api/sms_analysis.dart';
import 'package:orbguard/models/api/threat_indicator.dart';

/// A malicious URL QR code with a threat-intel match.
/// analysis_duration is 1.5s in Go nanoseconds.
const _phishingScanJson = '''
{
  "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "raw_content": "https://bit.ly/3xy",
  "content_type": "url",
  "parsed_content": {
    "url": {
      "full_url": "https://bit.ly/3xy",
      "scheme": "https",
      "host": "bit.ly",
      "path": "/3xy",
      "query": "",
      "fragment": "",
      "resolved_url": "https://secure-bank-login.xyz/verify"
    }
  },
  "threat_level": "high",
  "threat_score": 78.5,
  "threats": [
    {
      "type": "phishing_url",
      "severity": "high",
      "description": "QR code resolves to a known phishing site",
      "evidence": "https://secure-bank-login.xyz/verify",
      "threat_intel_match": {
        "indicator_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
        "indicator_type": "url",
        "campaign": "BankHarvest 2026",
        "confidence": 95
      }
    }
  ],
  "is_safe": false,
  "should_block": true,
  "warnings": ["Shortened URL hides the real destination"],
  "recommendations": ["Do not open this link"],
  "scanned_at": "2026-06-10T12:00:00Z",
  "analysis_duration": 1500000000
}
''';

/// A clean URL QR code; threats is an empty array and the omitempty
/// sections (parsed_content/url_preview) are absent.
const _safeScanJson = '''
{
  "id": "3f2c1b0a-1111-4222-8333-444455556666",
  "raw_content": "https://example.com",
  "content_type": "url",
  "threat_level": "safe",
  "threat_score": 0,
  "threats": [],
  "is_safe": true,
  "should_block": false,
  "warnings": [],
  "recommendations": [],
  "scanned_at": "2026-06-10T12:00:00Z",
  "analysis_duration": 250000000
}
''';

Map<String, dynamic> _decode(String fixture) =>
    jsonDecode(fixture) as Map<String, dynamic>;

void main() {
  group('QrThreatLevel.fromString — backend enum mapping', () {
    test('maps every backend value onto the matching enum entry', () {
      expect(QrThreatLevel.fromString('safe'), QrThreatLevel.safe);
      expect(QrThreatLevel.fromString('low'), QrThreatLevel.low);
      expect(QrThreatLevel.fromString('medium'), QrThreatLevel.medium);
      expect(QrThreatLevel.fromString('high'), QrThreatLevel.high);
      expect(QrThreatLevel.fromString('critical'), QrThreatLevel.critical);
      expect(QrThreatLevel.fromString('unknown'), QrThreatLevel.unknown);
    });

    test("'high' never maps to safe", () {
      final level = QrThreatLevel.fromString('high');
      expect(level, isNot(QrThreatLevel.safe));
      expect(level.uiLevel, isNot(SmsThreatLevel.safe));
      expect(level.uiLevel, SmsThreatLevel.dangerous);
    });

    test('throws FormatException on unrecognized values instead of '
        'defaulting', () {
      expect(() => QrThreatLevel.fromString('severe'),
          throwsA(isA<FormatException>()));
      expect(() => QrThreatLevel.fromString(''),
          throwsA(isA<FormatException>()));
    });
  });

  group('QrScanResult.fromJson — malicious QR payload', () {
    late QrScanResult result;

    setUp(() {
      result = QrScanResult.fromJson(_decode(_phishingScanJson));
    });

    test('parses identity and content fields', () {
      expect(result.id, 'f47ac10b-58cc-4372-a567-0e02b2c3d479');
      expect(result.rawContent, 'https://bit.ly/3xy');
      expect(result.content, 'https://bit.ly/3xy'); // legacy alias
      expect(result.contentType, 'url');
      expect(result.scannedAt, DateTime.utc(2026, 6, 10, 12));
    });

    test('parses threat level and never presents high as safe', () {
      expect(result.qrThreatLevel, QrThreatLevel.high);
      expect(result.qrThreatLevel, isNot(QrThreatLevel.safe));
      expect(result.threatLevel, SmsThreatLevel.dangerous);
      expect(result.isSafe, isFalse);
      expect(result.shouldBlock, isTrue);
    });

    test('keeps the native 0-100 threat score and derives 0-1 risk score',
        () {
      expect(result.threatScore, 78.5);
      expect(result.riskScore, closeTo(0.785, 0.0001));
    });

    test('parses threats with severity and threat-intel match', () {
      expect(result.threats, hasLength(1));
      final threat = result.threats.single;
      expect(threat.type, 'phishing_url');
      expect(threat.severity, SeverityLevel.high);
      expect(threat.evidence, 'https://secure-bank-login.xyz/verify');
      final match = threat.threatIntelMatch;
      expect(match, isNotNull);
      expect(match!.indicatorId, '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d');
      expect(match.indicatorType, 'url');
      expect(match.campaign, 'BankHarvest 2026');
      expect(match.confidence, 95);
    });

    test('parses the parsed_content map keyed by content kind', () {
      expect(result.parsedContent, isNotNull);
      final url = result.parsedContent!['url'] as Map<String, dynamic>;
      expect(url['host'], 'bit.ly');
      expect(url['resolved_url'], 'https://secure-bank-login.xyz/verify');
    });

    test('converts Go nanosecond analysis_duration to a Duration', () {
      expect(result.analysisDuration, const Duration(milliseconds: 1500));
    });

    test('joins recommendations and warnings into the UI recommendation',
        () {
      expect(result.recommendation, contains('Do not open this link'));
      expect(result.recommendation,
          contains('Shortened URL hides the real destination'));
    });
  });

  group('QrScanResult.fromJson — safe QR payload', () {
    test('parses a clean scan with empty threat list', () {
      final result = QrScanResult.fromJson(_decode(_safeScanJson));
      expect(result.qrThreatLevel, QrThreatLevel.safe);
      expect(result.threatLevel, SmsThreatLevel.safe);
      expect(result.threatScore, 0);
      expect(result.riskScore, 0);
      expect(result.threats, isEmpty);
      expect(result.hasThreats, isFalse);
      expect(result.isSafe, isTrue);
      expect(result.shouldBlock, isFalse);
      expect(result.parsedContent, isNull);
      expect(result.recommendation, isNull);
      expect(result.analysisDuration, const Duration(milliseconds: 250));
    });
  });

  group('QrScanResult.fromJson — contract violations surface as errors', () {
    test('missing threat_level throws FormatException', () {
      final json = _decode(_safeScanJson)..remove('threat_level');
      expect(() => QrScanResult.fromJson(json),
          throwsA(isA<FormatException>()));
    });

    test('missing scanned_at throws FormatException', () {
      final json = _decode(_safeScanJson)..remove('scanned_at');
      expect(() => QrScanResult.fromJson(json),
          throwsA(isA<FormatException>()));
    });

    test('unrecognized threat_level throws instead of defaulting to safe',
        () {
      final json = _decode(_phishingScanJson)..['threat_level'] = 'extreme';
      expect(() => QrScanResult.fromJson(json),
          throwsA(isA<FormatException>()));
    });
  });
}
