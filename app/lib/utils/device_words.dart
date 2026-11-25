// Platform-aware wording for "this device" in user-facing copy.
//
// App Review (macOS 2.1(a), Aug 2026) flagged "Let's check your phone" shown
// on a MacBook. Any copy that names the device must go through [DeviceWords]
// so it reads "phone" on Android/iOS, "Mac" on macOS, and "computer" on
// Windows/Linux.

import 'platform_info.dart';

abstract final class DeviceWords {
  /// "phone" | "Mac" | "computer" — the noun for the device the app runs on.
  static String get noun {
    if (PlatformInfo.isMacOS) return 'Mac';
    if (PlatformInfo.isWindows || PlatformInfo.isLinux) return 'computer';
    if (PlatformInfo.isWeb) return 'device';
    return 'phone';
  }
}
