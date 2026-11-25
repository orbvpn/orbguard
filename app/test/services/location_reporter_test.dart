import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:orbguard/services/device_agent/location_reporter.dart';

/// When OrbGuard may put the system's "Allow location?" question on screen.
///
/// The device agent reports a position on a timer, and it starts the moment
/// the app does. It used to ask for location itself, so the question landed
/// on top of the first screen of a new install, before the person had been
/// told what OrbGuard is. Only something the person just pressed may ask.
void main() {
  final Position here = Position(
    latitude: 52.37,
    longitude: 4.89,
    timestamp: DateTime.utc(2026, 11, 25, 9),
    accuracy: 8,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  late int asked;
  late LocationPermission standing;
  late LocationPermission answer;
  late bool servicesOn;

  LocationReporter reporter() => LocationReporter(
        serviceEnabled: () async => servicesOn,
        checkPermission: () async => standing,
        requestPermission: () async {
          asked++;
          return standing = answer;
        },
        currentPosition: (_) async => here,
        lastKnownPosition: () async => null,
      );

  setUp(() {
    asked = 0;
    standing = LocationPermission.denied;
    answer = LocationPermission.whileInUse;
    servicesOn = true;
  });

  test('a report on a timer never asks, and says location is not allowed',
      () async {
    final LocationFixResult fix = await reporter().getCurrentFix();

    expect(asked, 0);
    expect(fix.isAvailable, isFalse);
    expect(fix.unavailableReason,
        'location access has not been allowed for OrbGuard');
  });

  test('a report on a timer reads the position once access was allowed',
      () async {
    standing = LocationPermission.whileInUse;

    final LocationFixResult fix = await reporter().getCurrentFix();

    expect(asked, 0);
    expect(fix.isAvailable, isTrue);
    expect(fix.location!['latitude'], 52.37);
  });

  test('something the person pressed may ask, once', () async {
    final LocationFixResult fix = await reporter().getCurrentFix(mayAsk: true);

    expect(asked, 1);
    expect(fix.isAvailable, isTrue);
  });

  test('asking and being refused is reported as refused', () async {
    answer = LocationPermission.denied;

    final LocationFixResult fix = await reporter().getCurrentFix(mayAsk: true);

    expect(asked, 1);
    expect(fix.unavailableReason, 'location permission denied by user');
  });

  test('a standing refusal is never asked again, even from a press', () async {
    standing = LocationPermission.deniedForever;

    final LocationFixResult fix = await reporter().getCurrentFix(mayAsk: true);

    expect(asked, 0);
    expect(fix.unavailableReason, contains('system settings'));
  });

  test('requestAccess asks and says whether access now stands', () async {
    expect(await reporter().requestAccess(), isTrue);
    expect(asked, 1);
  });

  test('requestAccess does not ask when access already stands', () async {
    standing = LocationPermission.always;

    expect(await reporter().requestAccess(), isTrue);
    expect(asked, 0);
  });

  test('requestAccess is false when the person says no', () async {
    answer = LocationPermission.denied;

    expect(await reporter().requestAccess(), isFalse);
    expect(asked, 1);
  });

  test('requestAccess is false, without asking, when location is off',
      () async {
    servicesOn = false;

    expect(await reporter().requestAccess(), isFalse);
    expect(asked, 0);
  });
}
