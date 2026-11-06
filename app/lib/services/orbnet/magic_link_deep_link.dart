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

/// Normalises whatever the user pasted into a magic-link code.
///
/// The sign-in email renders the token only as a BUTTON — it never shows a
/// readable code — so "paste the code from your email" had nothing to paste and
/// the manual fallback was a dead end. What a user *can* copy is the link, and
/// there are two shapes of it:
///
///  * the URL in the email:  `https://<api>/api/v1/auth/magic-link/mobile?token=T&client=orbguard`
///  * the URL it redirects to: `orbguard://login?code=T`
///
/// OrbNet builds the second from the first with `code = token`, so BOTH query
/// names carry the same value the verify endpoint wants. Accept either, plus a
/// bare code typed by hand. Returns null when the input carries nothing usable.
String? magicCodeFromPastedText(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final uri = Uri.tryParse(text);
  if (uri != null && uri.scheme.isNotEmpty) {
    final fromUri = magicCodeFromUri(uri);
    if (fromUri != null) return fromUri;
    // Any http(s)/orbguard URL: take `code`, else `token`. Never fall through
    // to returning the raw URL — posting a whole URL as the token just yields
    // a confusing "invalid code" from the backend.
    if (uri.scheme == 'http' ||
        uri.scheme == 'https' ||
        uri.scheme == 'orbguard') {
      for (final key in const ['code', 'token']) {
        final v = uri.queryParameters[key]?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }
  }
  return text;
}

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
///
/// [initialLink] and [linkStream] default to app_links; tests pass their own.
class MagicLinkDeepLinkHandler {
  MagicLinkDeepLinkHandler(
    this._onCode, {
    Future<Uri?> Function()? initialLink,
    Stream<Uri> Function()? linkStream,
  }) : _initialLink = initialLink ?? (() => AppLinks().getInitialLink()),
       _linkStream = linkStream ?? (() => AppLinks().uriLinkStream);

  final Future<void> Function(String code) _onCode;
  final Future<Uri?> Function() _initialLink;
  final Stream<Uri> Function() _linkStream;
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Cold start: the app was launched by tapping the link.
    Uri? initial;
    try {
      initial = await _initialLink();
      if (initial != null) await _handle(initial);
    } catch (e) {
      debugPrint('[OrbGuard] initial deep link error: $e');
    }

    // Warm: links received while the app is already running.
    //
    // Every app_links platform hands the launch link to the stream's first
    // listener as well (getInitialLink does not mark it delivered), so the
    // link just handled arrives again as the first event. Redeeming it twice
    // asks the server for a second sign-in, which on a two-factor account
    // means a second code step replacing the one the user is looking at.
    // Only that first echo is skipped; tapping the link again still counts.
    final launchLink = initial;
    var echoPending = launchLink != null;
    _sub = _linkStream().listen(
      (uri) {
        final isEcho = echoPending && uri == launchLink;
        echoPending = false;
        if (!isEcho) unawaited(_handle(uri));
      },
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
