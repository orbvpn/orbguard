import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/providers/device_security_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two things a person presses that may put the system's location
/// question on screen: switching remote locate on, and "Locate".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int asked;
  late bool answer;

  DeviceSecurityProvider provider() => DeviceSecurityProvider(
        requestLocationAccess: () async {
          asked++;
          return answer;
        },
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    asked = 0;
    answer = true;
  });

  test('switching remote locate on asks for location', () async {
    final DeviceSecurityProvider p = provider();
    await p.updateSettings(p.settings.copyWith(locateEnabled: false));
    expect(asked, 0);

    await p.updateSettings(p.settings.copyWith(locateEnabled: true));

    expect(asked, 1);
    expect(p.settings.locateEnabled, isTrue);
    expect(p.error, isNull);
  });

  test('a refusal leaves remote locate off and says why', () async {
    final DeviceSecurityProvider p = provider();
    await p.updateSettings(p.settings.copyWith(locateEnabled: false));
    answer = false;

    await p.updateSettings(p.settings.copyWith(locateEnabled: true));

    expect(p.settings.locateEnabled, isFalse);
    expect(
      p.error,
      'Remote locate needs location access. Allow location for OrbGuard '
      'in system settings, then switch it on again.',
    );
  });

  test('changing another setting does not ask', () async {
    final DeviceSecurityProvider p = provider();
    expect(p.settings.locateEnabled, isTrue);

    await p.updateSettings(p.settings.copyWith(ringEnabled: false));

    expect(asked, 0);
  });

  test('switching remote locate off does not ask', () async {
    final DeviceSecurityProvider p = provider();

    await p.updateSettings(p.settings.copyWith(locateEnabled: false));

    expect(asked, 0);
    expect(p.settings.locateEnabled, isFalse);
  });

  test('Locate on a device that is not registered does not ask', () async {
    final DeviceSecurityProvider p = provider();

    expect(await p.locateDevice(), isNull);
    expect(asked, 0);
  });
}
