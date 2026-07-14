// Web implementation of PlatformInfo (also the fallback for any target
// without dart:io). No dart:io import — safe in a browser sandbox.
//
// Every native-platform check is honestly false here: code gated on
// `isAndroid`/`isIOS`/`isDesktop`/... simply never runs on web, which is the
// desired behavior for plugin/MethodChannel/file-system code paths.

/// Web-safe platform checks. See platform_info.dart for how the
/// implementation is selected.
abstract final class PlatformInfo {
  /// True only when running in a browser (dart2js/wasm build).
  static const bool isWeb = true;

  static const bool isAndroid = false;
  static const bool isIOS = false;
  static const bool isMacOS = false;
  static const bool isWindows = false;
  static const bool isLinux = false;
  static const bool isFuchsia = false;

  /// Native desktop (macOS/Windows/Linux). Always false on web.
  static const bool isDesktop = false;

  /// Native mobile (Android/iOS). Always false on web.
  static const bool isMobile = false;

  /// 'android' | 'ios' | 'macos' | 'windows' | 'linux' | 'fuchsia'
  /// (dart:io values); 'web' in a browser.
  static const String operatingSystem = 'web';

  static const String operatingSystemVersion = '';

  static const String localHostname = 'localhost';

  static const String pathSeparator = '/';

  /// Process environment. Empty on web, where there is none.
  static const Map<String, String> environment = {};
}
