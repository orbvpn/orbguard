// What macOS says of a file's code signature.
//
// The signature is read natively, through the Security framework, on the
// `com.orb.guard/system` channel (`codeSignatures`). That works inside the
// App Sandbox, which the shipping Mac build runs in, where running the
// `codesign` tool does not.
//
// Honesty rules:
//  - a signature macOS would not let the app read is [MacSignature.unknown],
//    never "unsigned"
//  - a file in a folder System Integrity Protection guards was put there by
//    Apple, so it is trusted without a check of its own; Apple's own shell
//    scripts there carry no signature at all
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum MacSignature {
  /// Signed by Apple.
  apple,

  /// Signed by a developer, and intact.
  valid,

  /// Not signed at all.
  unsigned,

  /// Signed, but changed since it was signed.
  broken,

  /// macOS would not let it be read. Says nothing either way.
  unknown,
}

@immutable
class MacCodeSignature {
  const MacCodeSignature({
    required this.path,
    required this.state,
    this.authority,
    this.teamId,
    this.identifier,
  });

  /// One entry of the native answer.
  factory MacCodeSignature.fromWire(String path, Object? wire) {
    final Map<Object?, Object?> m =
        wire is Map ? wire : const <Object?, Object?>{};
    final MacSignature state = switch (m['status']) {
      'apple' => MacSignature.apple,
      'valid' => MacSignature.valid,
      'unsigned' => MacSignature.unsigned,
      'broken' => MacSignature.broken,
      _ => MacSignature.unknown,
    };
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    return MacCodeSignature(
      path: path,
      state: state,
      authority: text(m['authority']),
      teamId: text(m['teamId']),
      identifier: text(m['identifier']),
    );
  }

  final String path;
  final MacSignature state;

  /// The name on the signing certificate.
  final String? authority;
  final String? teamId;
  final String? identifier;

  /// Signed, whether or not it still checks out.
  bool get signed =>
      state == MacSignature.apple ||
      state == MacSignature.valid ||
      state == MacSignature.broken;

  bool get intact => state == MacSignature.apple || state == MacSignature.valid;

  /// The row the Code signing tab lists for it, or null when it could not
  /// be read and so says nothing.
  Map<String, dynamic>? get appRow {
    if (state == MacSignature.unknown) return null;
    final String name = path.split('/').where((s) => s.isNotEmpty).last;
    return {
      'name': name.endsWith('.app') ? name.substring(0, name.length - 4) : name,
      'bundle_id': identifier ?? '',
      'path': path,
      'is_signed': signed,
      'is_valid': intact,
      'developer': state == MacSignature.apple ? 'Apple' : (authority ?? ''),
      'team_id': teamId,
      'source': 'local',
    };
  }

  /// The rows for [read], those that could be read.
  static List<Map<String, dynamic>> appRows(Iterable<MacCodeSignature> read) =>
      [
        for (final MacCodeSignature s in read)
          if (s.appRow case final Map<String, dynamic> row) row,
      ];

  /// Why no signature could be read, when none of [read] could; else null.
  static String? unreadable(Iterable<MacCodeSignature> read) =>
      read.isNotEmpty && read.every((s) => s.state == MacSignature.unknown)
          ? 'macOS did not let OrbGuard read the signatures of these apps.'
          : null;

  static const MethodChannel _channel = MethodChannel('com.orb.guard/system');

  /// Whether [path] is in a folder System Integrity Protection guards. Only
  /// Apple's signed installers can write there, even as an administrator.
  static bool isProtectedBySip(String path) =>
      path.startsWith('/System/') ||
      path.startsWith('/bin/') ||
      path.startsWith('/sbin/') ||
      path.startsWith('/Library/Apple/') ||
      (path.startsWith('/usr/') && !path.startsWith('/usr/local/'));

  /// The signatures of [paths], read natively. A path the native side did
  /// not answer for, or every path when there is no native side, is
  /// [MacSignature.unknown].
  static Future<Map<String, MacCodeSignature>> read(
    List<String> paths, {
    MethodChannel channel = _channel,
  }) async {
    Map<Object?, Object?> wire = const {};
    if (paths.isNotEmpty) {
      try {
        wire = await channel.invokeMethod<Map<Object?, Object?>>(
                'codeSignatures', {'paths': paths}) ??
            const {};
      } on MissingPluginException {
        wire = const {};
      } on PlatformException {
        wire = const {};
      }
    }
    return {
      for (final String p in paths) p: MacCodeSignature.fromWire(p, wire[p]),
    };
  }
}
