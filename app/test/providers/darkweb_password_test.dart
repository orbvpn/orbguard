import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/providers/darkweb_provider.dart';
import 'package:orbguard/services/security/password_k_anonymity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only the five character prefix is handed to the network layer', () async {
    final provider = DarkWebProvider();
    final sent = <String>[];
    final query = PasswordRangeQuery.fromPassword('correct horse');
    provider.passwordRangeForTest = (prefix) async {
      sent.add(prefix);
      return {query.suffix: 7};
    };

    final result = await provider.checkPassword('correct horse');

    expect(sent, [query.prefix]);
    expect(sent.single.length, 5);
    expect(result?.isBreached, isTrue);
    expect(result?.exposureCount, 7);
  });

  test('a failed check clears the earlier result and reports the failure',
      () async {
    final provider = DarkWebProvider();
    provider.passwordRangeForTest = (_) async => {'NOT-THIS-SUFFIX': 1};
    await provider.checkPassword('first password');
    expect(provider.lastPasswordResult?.isBreached, isFalse);
    expect(provider.passwordError, isNull);

    provider.passwordRangeForTest = (_) async => throw Exception('offline');
    final result = await provider.checkPassword('second password');

    expect(result, isNull);
    expect(provider.lastPasswordResult, isNull,
        reason: 'a stale "not found" card would be a false all-clear');
    expect(provider.passwordError, isNotNull);
  });

  test('a later success clears the failure message', () async {
    final provider = DarkWebProvider();
    provider.passwordRangeForTest = (_) async => throw Exception('offline');
    await provider.checkPassword('some password');
    expect(provider.passwordError, isNotNull);

    provider.passwordRangeForTest = (_) async => {'NOT-THIS-SUFFIX': 1};
    await provider.checkPassword('some password');
    expect(provider.passwordError, isNull);
    expect(provider.lastPasswordResult, isNotNull);
  });
}
