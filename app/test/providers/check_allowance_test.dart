// The one free check: a device's first check costs nothing, and only its
// first. Whether it was used is remembered on the device, so closing the app
// does not hand out another.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/providers/check_allowance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a new install has its free check', () async {
    SharedPreferences.setMockInitialValues({});
    final CheckAllowance allowance =
        CheckAllowance(platform: TargetPlatform.android);

    expect(await allowance.freeCheckUsed(), isFalse);
  });

  test('once used it stays used, for this object and the next launch',
      () async {
    SharedPreferences.setMockInitialValues({});
    final CheckAllowance allowance =
        CheckAllowance(platform: TargetPlatform.android);
    int heard = 0;
    allowance.addListener(() => heard++);

    await allowance.useFreeCheck();

    expect(await allowance.freeCheckUsed(), isTrue);
    expect(heard, 1);
    // What the next launch reads.
    expect(
        await CheckAllowance(platform: TargetPlatform.android).freeCheckUsed(),
        isTrue);
  });

  test('using it twice writes once', () async {
    SharedPreferences.setMockInitialValues({});
    final CheckAllowance allowance =
        CheckAllowance(platform: TargetPlatform.windows);
    int heard = 0;
    allowance.addListener(() => heard++);

    await allowance.useFreeCheck();
    await allowance.useFreeCheck();

    expect(heard, 1);
  });

  test('it carries the platform it was given, not the one it runs on', () {
    expect(CheckAllowance(platform: TargetPlatform.windows).platform,
        TargetPlatform.windows);
    expect(CheckAllowance(platform: null).platform, isNull);
  });

  test('a store that cannot be read gives no second free check', () async {
    final CheckAllowance allowance = CheckAllowance(
      platform: TargetPlatform.android,
      prefs: () async => throw StateError('no store'),
    );

    // Marked used in memory even though it could not be written down.
    await allowance.useFreeCheck();
    expect(await allowance.freeCheckUsed(), isTrue);
  });
}
