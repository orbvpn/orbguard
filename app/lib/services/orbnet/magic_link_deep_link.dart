// lib/services/orbnet/magic_link_deep_link.dart
//
// Handles the incoming magic-link deep link. The OrbGuard-branded sign-in email
// (backend chooses this when the request carried client=orbguard) links to
//   orbguard://login?code=<token>
// Tapping it opens OrbGuard (scheme registered in AndroidManifest / Info.plist)
// and this listener exchanges the code for a session — the same code the user
// could otherwise paste on the login screen, so it just skips the copy/paste.

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Extracts the magic-link `code` from an `orbguard://login?code=…` URI.
/// Returns null for any other link so unrelated deep links are ignored.
String? magicCodeFromUri(Uri uri) {
  if (uri.scheme != 'orbguard') return null;
  if (uri.host != 'login' && !uri.pathSegments.contains('login')) return null;
  final code = uri.queryParameters['code'];
  if (code == null || code.trim().isEmpty) return null;
  return code.trim();
}

/// Listens for magic-link deep links (cold-start + while running) and invokes
/// [onCode] with the extracted code. Best-effort and self-contained; never
/// throws into the caller. Call [dispose] to stop listening.
class MagicLinkDeepLinkHandler {
  MagicLinkDeepLinkHandler(this._onCode);

  final Future<void> Function(String code) _onCode;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Cold start: the app was launched by tapping the link.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) await _handle(initial);
    } catch (e) {
      debugPrint('[OrbGuard] initial deep link error: $e');
    }

    // Warm: links received while the app is already running.
    _sub = _appLinks.uriLinkStream.listen(
      (uri) => _handle(uri),
      onError: (Object e) => debugPrint('[OrbGuard] deep link stream error: $e'),
    );
  }

  Future<void> _handle(Uri uri) async {
    final code = magicCodeFromUri(uri);
    if (code == null) return;
    try {
      await _onCode(code);
    } catch (e) {
      debugPrint('[OrbGuard] magic-link deep link sign-in failed: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
