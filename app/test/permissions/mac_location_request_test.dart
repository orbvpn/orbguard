import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:orbguard/permissions/universal_permissions.dart';

void main() {
  test('Location Services off: no question, and the step ends', () async {
    var asked = false;
    final granted = await UniversalPermissions.requestMacLocation(
      servicesOn: () async => false,
      request: () async {
        asked = true;
        return LocationPermission.always;
      },
    );
    expect(granted, isFalse);
    expect(asked, isFalse);
  });

  test('a question that is never answered ends after the wait', () async {
    final never = Completer<LocationPermission>();
    final granted = await UniversalPermissions.requestMacLocation(
      servicesOn: () async => true,
      request: () => never.future,
      wait: const Duration(milliseconds: 20),
    );
    expect(granted, isFalse);
  });

  test('allowed reads as granted, refused as not', () async {
    expect(
        await UniversalPermissions.requestMacLocation(
            servicesOn: () async => true,
            request: () async => LocationPermission.always),
        isTrue);
    expect(
        await UniversalPermissions.requestMacLocation(
            servicesOn: () async => true,
            request: () async => LocationPermission.denied),
        isFalse);
  });
}
