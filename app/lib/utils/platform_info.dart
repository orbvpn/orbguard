// Platform abstraction — web-safe replacement for dart:io's Platform.
//
// `dart:io`'s `Platform` getters compile on the web (dart2js/dart2wasm stub
// the library) but THROW `UnsupportedError` at runtime, which crashes the app
// the moment any `Platform.is*` check is evaluated in a browser. App code
// must import THIS file instead of using `dart:io` Platform directly.
//
// The conditional export picks the implementation at compile time:
//   - VM/AOT (Android, iOS, macOS, Windows, Linux): `platform_info_io.dart`,
//     an exact delegation to `dart:io` Platform — native behavior unchanged.
//   - Web (JS or Wasm, where `dart.library.io` is false):
//     `platform_info_stub.dart` — `isWeb` is true and every dart:io-only
//     check is honestly false.
export 'platform_info_stub.dart' if (dart.library.io) 'platform_info_io.dart';
