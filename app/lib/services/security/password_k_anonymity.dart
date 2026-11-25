// Password breach check by k-anonymity.
//
// The password is hashed on this device. Only the first five characters of the
// SHA-1 hash are sent; the server answers with every known suffix for that
// prefix, and the comparison happens here. The password and the full hash never
// leave the device.

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/api/sms_analysis.dart';

class PasswordRangeQuery {
  /// The five hex characters sent to the server.
  final String prefix;

  /// The remaining 35 hex characters. Never sent.
  final String suffix;

  const PasswordRangeQuery._(this.prefix, this.suffix);

  factory PasswordRangeQuery.fromPassword(String password) {
    final hash = sha1.convert(utf8.encode(password)).toString().toUpperCase();
    return PasswordRangeQuery._(hash.substring(0, 5), hash.substring(5));
  }
}

/// Parses the `POST /darkweb/password/range` response into suffix -> count.
///
/// Throws [FormatException] for a missing or empty list: every prefix has known
/// suffixes, so an empty answer means the check did not happen and must never
/// be read as "password not found".
Map<String, int> parsePasswordRange(Object? data) {
  final raw = data is Map ? data['suffixes'] : null;
  if (raw is! List || raw.isEmpty) {
    throw const FormatException('Password range response has no suffixes');
  }
  final range = <String, int>{};
  for (final entry in raw) {
    if (entry is! Map ||
        entry['suffix'] is! String ||
        entry['count'] is! num) {
      throw const FormatException('Malformed password range entry');
    }
    range[(entry['suffix'] as String).toUpperCase()] =
        (entry['count'] as num).toInt();
  }
  return range;
}

/// Compares the local suffix with the range. Padding entries have count 0 and
/// do not count as a match.
PasswordBreachResult evaluatePasswordRange(
  PasswordRangeQuery query,
  Map<String, int> range,
) {
  final count = range[query.suffix] ?? 0;
  final isBreached = count > 0;
  return PasswordBreachResult(
    isBreached: isBreached,
    exposureCount: isBreached ? count : 0,
    recommendation: isBreached
        ? 'This password appears in known data breaches. Change it everywhere you use it.'
        : 'This password was not found in known data breaches.',
    riskLevel: isBreached ? 'compromised' : 'safe',
    checkedAt: DateTime.now(),
  );
}
