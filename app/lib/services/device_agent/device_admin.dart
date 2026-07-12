// Device Admin Bridge
// Lock and wipe remote commands need OS device-administrator privileges
// (Android DevicePolicyManager / iOS MDM). The native side of that wiring
// is owned by the platform-channel work stream — this bridge only *talks*
// to it over a MethodChannel and reports an explicit, honest unavailable
// state when the native handler is not present or the privilege has not
// been granted. It never fakes success.

import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';

/// Result of a device-admin probe or action.
class DeviceAdminResult {
  /// Whether the action genuinely succeeded.
  final bool ok;

  /// Honest human-readable detail when [ok] is false.
  final String? failureReason;

  const DeviceAdminResult.success()
      : ok = true,
        failureReason = null;

  const DeviceAdminResult.failure(this.failureReason) : ok = false;
}

class DeviceAdminBridge {
  static const _channel = MethodChannel('com.orb.guard/device_admin');

  /// True if the native device-admin handler exists AND the app has been
  /// granted device-administrator privileges. False (with logging) in every
  /// other case — including when the native channel is simply not wired.
  Future<bool> isAdminActive() async {
    if (!Platform.isAndroid) return false;
    try {
      final active = await _channel.invokeMethod<bool>('isAdminActive');
      return active ?? false;
    } on MissingPluginException {
      developer.log(
        'device_admin channel not implemented on native side; '
        'lock/wipe unavailable',
        name: 'DeviceAdminBridge',
      );
      return false;
    } on PlatformException catch (e) {
      developer.log(
        'device_admin isAdminActive failed: ${e.code} ${e.message}',
        name: 'DeviceAdminBridge',
      );
      return false;
    }
  }

  /// Locks the device immediately (DevicePolicyManager.lockNow on Android).
  Future<DeviceAdminResult> lockNow() async {
    if (!Platform.isAndroid) {
      return DeviceAdminResult.failure(
        'remote lock is not supported on ${Platform.operatingSystem}',
      );
    }
    try {
      final ok = await _channel.invokeMethod<bool>('lockNow');
      if (ok == true) return const DeviceAdminResult.success();
      return const DeviceAdminResult.failure(
        'device admin not granted: enable OrbGuard as a device administrator '
        'in Android settings',
      );
    } on MissingPluginException {
      return const DeviceAdminResult.failure(
        'device admin not granted: native device-admin handler is not '
        'implemented in this build',
      );
    } on PlatformException catch (e) {
      return DeviceAdminResult.failure(
        'device admin lock failed: ${e.code} ${e.message ?? ''}'.trim(),
      );
    }
  }

  /// Factory-resets the device (DevicePolicyManager.wipeData on Android).
  Future<DeviceAdminResult> wipe({bool wipeSdCard = false}) async {
    if (!Platform.isAndroid) {
      return DeviceAdminResult.failure(
        'remote wipe is not supported on ${Platform.operatingSystem}',
      );
    }
    try {
      final ok = await _channel.invokeMethod<bool>(
        'wipeData',
        {'wipe_sd_card': wipeSdCard},
      );
      if (ok == true) return const DeviceAdminResult.success();
      return const DeviceAdminResult.failure(
        'device admin not granted: enable OrbGuard as a device administrator '
        'in Android settings',
      );
    } on MissingPluginException {
      return const DeviceAdminResult.failure(
        'device admin not granted: native device-admin handler is not '
        'implemented in this build',
      );
    } on PlatformException catch (e) {
      return DeviceAdminResult.failure(
        'device admin wipe failed: ${e.code} ${e.message ?? ''}'.trim(),
      );
    }
  }
}
