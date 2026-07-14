// Native (VM/AOT) implementation of PlatformInfo.
//
// Exact delegation to dart:io Platform so behavior on Android/iOS/macOS/
// Windows/Linux is byte-for-byte what `Platform.*` returned before the
// abstraction was introduced. Never imported on the web (see
// platform_info.dart's conditional export).

import 'dart:io' as io;

/// Web-safe platform checks. See platform_info.dart for how the
/// implementation is selected.
abstract final class PlatformInfo {
  /// True only when running in a browser (dart2js/wasm build).
  static const bool isWeb = false;

  static bool get isAndroid => io.Platform.isAndroid;
  static bool get isIOS => io.Platform.isIOS;
  static bool get isMacOS => io.Platform.isMacOS;
  static bool get isWindows => io.Platform.isWindows;
  static bool get isLinux => io.Platform.isLinux;
  static bool get isFuchsia => io.Platform.isFuchsia;

  /// Native desktop (macOS/Windows/Linux). Always false on web.
  static bool get isDesktop => isMacOS || isWindows || isLinux;

  /// Native mobile (Android/iOS). Always false on web.
  static bool get isMobile => isAndroid || isIOS;

  /// 'android' | 'ios' | 'macos' | 'windows' | 'linux' | 'fuchsia'
  /// (dart:io values); 'web' in a browser.
  static String get operatingSystem => io.Platform.operatingSystem;

  static String get operatingSystemVersion =>
      io.Platform.operatingSystemVersion;

  static String get localHostname => io.Platform.localHostname;

  static String get pathSeparator => io.Platform.pathSeparator;

  /// Process environment. Empty on web, where there is none.
  static Map<String, String> get environment => io.Platform.environment;
}
