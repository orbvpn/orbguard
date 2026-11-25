// The platform the app runs on, as a value a screen can take in.
//
// A screen that shows or hides a feature by platform takes a
// `TargetPlatform?` that defaults to this, so a widget test on a macOS host
// can still draw the Android, iPhone and desktop versions of it.

import 'package:flutter/foundation.dart';

import 'platform_info.dart';

/// The platform this build runs on, or null in a browser, where none of the
/// native features exist.
TargetPlatform? hostPlatform() {
  if (PlatformInfo.isWeb) return null;
  if (PlatformInfo.isAndroid) return TargetPlatform.android;
  if (PlatformInfo.isIOS) return TargetPlatform.iOS;
  if (PlatformInfo.isMacOS) return TargetPlatform.macOS;
  if (PlatformInfo.isWindows) return TargetPlatform.windows;
  if (PlatformInfo.isLinux) return TargetPlatform.linux;
  return null;
}

/// True for Android and iPhone.
bool isPhonePlatform(TargetPlatform? platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.iOS;

/// The word copy uses for this device: "phone", "Mac" or "computer". The
/// same words as `DeviceWords.noun`, for a given platform.
String deviceNounFor(TargetPlatform? platform) => switch (platform) {
      TargetPlatform.android || TargetPlatform.iOS => 'phone',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows || TargetPlatform.linux => 'computer',
      _ => 'device',
    };
