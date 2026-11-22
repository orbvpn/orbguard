import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/services/security/password_k_anonymity.dart';

void main() {
  // SHA-1("password") = 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8
  const fullHash = '5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8';

  test('only a five character prefix is produced for the server', () {
    final query = PasswordRangeQuery.fromPassword('password');
    expect(query.prefix, '5BAA6');
    expect(query.prefix.length, 5);
    expect(query.prefix + query.suffix, fullHash);
    expect(query.prefix.contains(query.suffix), isFalse);
  });

  test('a matching suffix is a breach with its count', () {
    final query = PasswordRangeQuery.fromPassword('password');
    final result = evaluatePasswordRange(query, {query.suffix: 42, 'OTHER': 1});
    expect(result.isBreached, isTrue);
    expect(result.exposureCount, 42);
  });

  test('a padding entry with count 0 is not a breach', () {
    final query = PasswordRangeQuery.fromPassword('password');
    final result = evaluatePasswordRange(query, {query.suffix: 0});
    expect(result.isBreached, isFalse);
    expect(result.exposureCount, 0);
  });

  test('an absent suffix is not a breach', () {
    final query = PasswordRangeQuery.fromPassword('password');
    expect(evaluatePasswordRange(query, {'OTHER': 5}).isBreached, isFalse);
  });

  test('parses suffixes case-insensitively', () {
    final range = parsePasswordRange({
      'suffixes': [
        {'suffix': 'abc', 'count': 3},
      ],
    });
    expect(range, {'ABC': 3});
  });

  test('an empty or malformed answer is an error, never a clean result', () {
    for (final bad in <Object?>[
      null,
      <String, dynamic>{},
      {'suffixes': []},
      {'suffixes': 'x'},
      {
        'suffixes': [
          {'suffix': 'ABC'},
        ],
      },
    ]) {
      expect(() => parsePasswordRange(bad), throwsFormatException);
    }
  });
}
