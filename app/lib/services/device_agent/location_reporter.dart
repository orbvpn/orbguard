// Location Reporter
// Reads real GPS fixes via geolocator and converts them to the exact
// models.Location JSON shape the backend persists
// (POST /api/v1/device/{device_id}/location):
//   { latitude, longitude, accuracy_meters, altitude, speed, bearing,
//     provider, timestamp }
//
// When location genuinely cannot be obtained (permission denied, services
// off, timeout with no cached fix) an explicit unavailable result with the
// reason is returned — never a fabricated coordinate.

import 'dart:async';
import 'dart:developer' as developer;
import '../../utils/platform_info.dart';

import 'package:geolocator/geolocator.dart';

class LocationFixResult {
  /// Backend-shaped models.Location JSON, null when unavailable.
  final Map<String, dynamic>? location;

  /// Honest reason when [location] is null.
  final String? unavailableReason;

  /// Raw position for distance math (significant-change filtering).
  final Position? position;

  const LocationFixResult.available(this.location, this.position)
      : unavailableReason = null;

  const LocationFixResult.unavailable(this.unavailableReason)
      : location = null,
        position = null;

  bool get isAvailable => location != null;
}

class LocationReporter {
  /// The five calls into the system are parameters so a test can stand in
  /// for the device. Left out, each one is the real `Geolocator` call.
  LocationReporter({
    Future<bool> Function()? serviceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<Position> Function(Duration timeout)? currentPosition,
    Future<Position?> Function()? lastKnownPosition,
  })  : _serviceEnabled = serviceEnabled ?? Geolocator.isLocationServiceEnabled,
        _checkPermission = checkPermission ?? Geolocator.checkPermission,
        _requestPermission = requestPermission ?? Geolocator.requestPermission,
        _currentPosition = currentPosition ?? _freshPosition,
        _lastKnownPosition =
            lastKnownPosition ?? Geolocator.getLastKnownPosition;

  final Future<bool> Function() _serviceEnabled;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final Future<Position> Function(Duration timeout) _currentPosition;
  final Future<Position?> Function() _lastKnownPosition;

  static Future<Position> _freshPosition(Duration timeout) =>
      Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );

  /// Puts the system's "Allow location?" question on screen when access has
  /// not been decided yet, and answers whether access stands afterwards.
  ///
  /// Call it only from something the person just pressed: "Locate this
  /// device", or switching remote locate on. It does not ask when access
  /// already stands, when it was refused for good, or when location is
  /// switched off for the whole device.
  Future<bool> requestAccess() async =>
      await _ensurePermission(mayAsk: true) == null;

  /// Acquires a fresh GPS fix. Falls back to the OS-cached last-known
  /// position (clearly marked with provider "last_known" and its original
  /// timestamp) only when a fresh fix times out.
  ///
  /// [mayAsk] is false unless the person just pressed something. The agent
  /// reports on a timer that starts with the app, and it answers a remote
  /// "locate" while the phone may be in someone else's hands: neither may
  /// put a permission question on screen. Without access they get an honest
  /// "not allowed" and try again next time.
  Future<LocationFixResult> getCurrentFix({
    Duration timeout = const Duration(seconds: 30),
    bool mayAsk = false,
  }) async {
    final permission = await _ensurePermission(mayAsk: mayAsk);
    if (permission != null) {
      developer.log('location unavailable: $permission',
          name: 'LocationReporter');
      return LocationFixResult.unavailable(permission);
    }

    try {
      final position = await _currentPosition(timeout);
      return LocationFixResult.available(_toBackendJson(position), position);
    } on TimeoutException {
      // Fresh fix timed out — surface the cached fix honestly if one exists.
      try {
        final last = await _lastKnownPosition();
        if (last != null) {
          developer.log(
            'fresh GPS fix timed out; reporting OS-cached last-known position '
            'from ${last.timestamp.toIso8601String()}',
            name: 'LocationReporter',
          );
          return LocationFixResult.available(
            _toBackendJson(last, providerOverride: 'last_known'),
            last,
          );
        }
      } catch (e) {
        developer.log('getLastKnownPosition failed: $e',
            name: 'LocationReporter');
      }
      return const LocationFixResult.unavailable(
        'GPS fix timed out and no cached position is available',
      );
    } on LocationServiceDisabledException {
      return const LocationFixResult.unavailable(
        'location services are disabled on this device',
      );
    } catch (e) {
      return LocationFixResult.unavailable('failed to read location: $e');
    }
  }

  /// Returns null when permission is in place, otherwise the honest reason
  /// location is unavailable.
  Future<String?> _ensurePermission({required bool mayAsk}) async {
    final serviceEnabled = await _serviceEnabled();
    if (!serviceEnabled) {
      return 'location services are disabled on this device';
    }

    var permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      if (!mayAsk) return 'location access has not been allowed for OrbGuard';
      permission = await _requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return 'location permission denied by user';
    }
    if (permission == LocationPermission.deniedForever) {
      return 'location permission permanently denied, enable it in system '
          'settings';
    }
    return null;
  }

  Map<String, dynamic> _toBackendJson(
    Position position, {
    String? providerOverride,
  }) {
    return {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy_meters': position.accuracy,
      'altitude': position.altitude,
      'speed': position.speed,
      'bearing': position.heading,
      'provider':
          providerOverride ?? (PlatformInfo.isAndroid ? 'fused' : 'gps'),
      'timestamp': position.timestamp.toUtc().toIso8601String(),
    };
  }

  /// Meters between two fixes — used for significant-change filtering.
  double distanceMeters(Position a, Position b) =>
      Geolocator.distanceBetween(
          a.latitude, a.longitude, b.latitude, b.longitude);
}
