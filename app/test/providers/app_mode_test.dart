import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/models/app_mode.dart';
import 'package:orbguard/providers/settings_provider.dart';

/// P1.1 — the app-mode flag: defaults to the consumer Guard experience and
/// survives a restart, so Pro users aren't dropped back to Guard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to Guard', () async {
    final p = SettingsProvider();
    await p.init();
    expect(p.appMode, AppMode.guard);
    expect(p.isProMode, isFalse);
  });

  test('setAppMode(pro) persists across a fresh provider', () async {
    final p = SettingsProvider();
    await p.init();
    await p.setAppMode(AppMode.pro);
    expect(p.appMode, AppMode.pro);

    final restarted = SettingsProvider();
    await restarted.init();
    expect(restarted.appMode, AppMode.pro, reason: 'mode should persist');
    expect(restarted.isProMode, isTrue);
  });

  test('toggleAppMode flips Guard <-> Pro', () async {
    final p = SettingsProvider();
    await p.init();
    await p.toggleAppMode();
    expect(p.appMode, AppMode.pro);
    await p.toggleAppMode();
    expect(p.appMode, AppMode.guard);
  });

  test('AppMode.fromName is safe for unknown / null', () {
    expect(AppMode.fromName('pro'), AppMode.pro);
    expect(AppMode.fromName('guard'), AppMode.guard);
    expect(AppMode.fromName(null), AppMode.guard);
    expect(AppMode.fromName('garbage'), AppMode.guard);
  });

  test('onboarding flag defaults false and persists once completed', () async {
    final p = SettingsProvider();
    await p.init();
    expect(p.hasSeenOnboarding, isFalse);

    await p.completeOnboarding();
    expect(p.hasSeenOnboarding, isTrue);

    final restarted = SettingsProvider();
    await restarted.init();
    expect(restarted.hasSeenOnboarding, isTrue,
        reason: 'onboarding should not show again after completion');
  });

  test('priming + first-check latches default false and persist once set',
      () async {
    final p = SettingsProvider();
    await p.init();
    expect(p.permissionsPrimed, isFalse);
    expect(p.firstCheckDone, isFalse);

    await p.completePriming();
    await p.markFirstCheckDone();
    expect(p.permissionsPrimed, isTrue);
    expect(p.firstCheckDone, isTrue);

    final restarted = SettingsProvider();
    await restarted.init();
    expect(restarted.permissionsPrimed, isTrue,
        reason: 'priming must not show again');
    expect(restarted.firstCheckDone, isTrue,
        reason: 'the auto first-check must fire exactly once, ever');
  });
}
