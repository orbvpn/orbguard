// Decode tests for ThreatIndicator — GET /api/v1/indicators.
//
// The backend's metadata field has shipped in three shapes over time:
// a JSON object (current, json.RawMessage), a base64-encoded JSON blob
// (older Go []byte marshalling), and absent. All must parse without
// failing the whole indicator list — this is what broke the Intel tab
// with "type 'String' is not a subtype of type 'Map<String, dynamic>?'".

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/models/api/threat_indicator.dart';

Map<String, dynamic> _baseIndicatorJson({dynamic metadata}) => {
      'id': '7d4a2f1e-1234-5678-9abc-def012345678',
      'value': 'cloudfiles.me',
      'type': 'domain',
      'severity': 'critical',
      'confidence': 0.95,
      'tags': ['pegasus', 'nso'],
      'platforms': ['ios', 'android'],
      'source_name': 'citizen-lab',
      'created_at': '2026-01-15T10:00:00Z',
      'updated_at': '2026-06-01T10:00:00Z',
      if (metadata != null) 'metadata': metadata,
    };

void main() {
  group('ThreatIndicator.fromJson metadata shapes', () {
    test('JSON object metadata parses (current backend shape)', () {
      final indicator = ThreatIndicator.fromJson(
        _baseIndicatorJson(metadata: {'campaign': 'pegasus-2026'}),
      );
      expect(indicator.metadata, {'campaign': 'pegasus-2026'});
      expect(indicator.value, 'cloudfiles.me');
    });

    test('base64-encoded JSON metadata parses (legacy Go []byte shape)', () {
      final blob = base64Encode(utf8.encode('{"campaign":"pegasus-2026"}'));
      final indicator = ThreatIndicator.fromJson(
        _baseIndicatorJson(metadata: blob),
      );
      expect(indicator.metadata, {'campaign': 'pegasus-2026'});
    });

    test('JSON-string metadata parses', () {
      final indicator = ThreatIndicator.fromJson(
        _baseIndicatorJson(metadata: '{"campaign":"pegasus-2026"}'),
      );
      expect(indicator.metadata, {'campaign': 'pegasus-2026'});
    });

    test('absent metadata parses to null', () {
      final indicator = ThreatIndicator.fromJson(_baseIndicatorJson());
      expect(indicator.metadata, isNull);
    });

    test('unparseable metadata degrades to null, not a parse failure', () {
      final indicator = ThreatIndicator.fromJson(
        _baseIndicatorJson(metadata: 'not-json-not-base64!'),
      );
      expect(indicator.metadata, isNull);
      expect(indicator.value, 'cloudfiles.me');
    });
  });
}
