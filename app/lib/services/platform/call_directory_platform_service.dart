/// Call Directory Platform Service
/// Flutter-side bridge for the iOS CallKit call-directory extension.
///
/// The native side of this channel lives in
/// `ios/Runner/CallDirectoryChannelHandler.swift` (channel
/// `com.orb.guard/call_directory`). It writes the block/identify lists into the
/// shared App Group container (`group.com.orb.guard.shared`) that the
/// `OrbGuardCallDirectory` `CXCallDirectoryProvider` extension reads, then asks
/// iOS to reload that extension.
///
/// Honesty contract: this is a DATA-SYNC bridge only. Saving numbers does not
/// mean calls are being blocked: the call directory only takes effect once the
/// person turns OrbGuard on in Settings, Apps, Phone, Call Blocking &
/// Identification (iOS 26 wording; [openSettings] opens that page). [status]
/// reports the real enablement state. The channel is registered only by the
/// iOS host app; every method is a no-op or unavailable on other platforms,
/// and this service NEVER fabricates phone numbers: the only numbers it saves
/// are ones the person chose to block.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thrown when the call-directory capability genuinely does not exist on this
/// platform (non-iOS) or the native channel is not registered in the binary.
class CallDirectoryUnavailableException implements Exception {
  final String message;
  const CallDirectoryUnavailableException(this.message);

  @override
  String toString() => message;
}

/// A caller-ID label for a phone number shown on the incoming-call screen.
class CallIdentificationEntry {
  /// Full number including country code, as a CallKit phone number: digits
  /// only, no '+', spaces or punctuation (e.g. +1 408 555 0123 → 14085550123).
  final int number;

  /// Short label iOS displays, e.g. "OrbGuard: Reported Scam".
  final String label;

  const CallIdentificationEntry({required this.number, required this.label});

  Map<String, dynamic> toMap() => {'number': number, 'label': label};
}

/// Thin bridge over the `com.orb.guard/call_directory` method channel.
class CallDirectoryPlatformService {
  static const _channelName = 'com.orb.guard/call_directory';
  static final CallDirectoryPlatformService _instance =
      CallDirectoryPlatformService._internal();

  factory CallDirectoryPlatformService() => _instance;
  CallDirectoryPlatformService._internal();

  static CallDirectoryPlatformService get instance => _instance;

  final MethodChannel _channel = const MethodChannel(_channelName);

  /// Only iOS ships a CallKit call-directory extension. Android has its own
  /// call-blocking path; every other platform has none.
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Human-readable reason used when [isSupported] is false.
  String get unsupportedReason {
    if (kIsWeb) {
      return 'Call blocking is not available on the web.';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'Call directory channel unavailable.';
      default:
        return '${defaultTargetPlatform.name} does not use the iOS CallKit '
            'call directory.';
    }
  }

  /// Push the current block/identify lists to the shared container and ask iOS
  /// to reload the extension.
  ///
  /// [blockedNumbers] are CallKit phone numbers (country-code-prefixed digits).
  /// [identified] are (number, label) pairs shown as caller ID. Passing empty
  /// lists is valid and honest — it simply clears the directory. The native
  /// side sorts and de-duplicates; callers need not.
  ///
  /// Returns the native sync summary
  /// ({blockedWritten, identifiedWritten, reloadRequested, reloadError}), or
  /// null on unsupported platforms. Throws
  /// [CallDirectoryUnavailableException] if the channel is missing from the
  /// build, and rethrows [PlatformException] (e.g. APP_GROUP_UNAVAILABLE) so a
  /// provisioning gap is never silently swallowed.
  Future<Map<String, dynamic>?> syncNumbers({
    List<int> blockedNumbers = const [],
    List<CallIdentificationEntry> identified = const [],
  }) async {
    if (!isSupported) {
      debugPrint('CallDirectoryPlatformService: syncNumbers skipped '
          '(platform unsupported)');
      return null;
    }
    try {
      final result = await _channel.invokeMethod<Map>('syncNumbers', {
        'blocked': blockedNumbers,
        'identified': identified.map((e) => e.toMap()).toList(),
      });
      return result == null ? null : Map<String, dynamic>.from(result);
    } on MissingPluginException {
      throw const CallDirectoryUnavailableException(
          'Call directory channel is not registered in this build.');
    }
  }

  /// Ask iOS to reload the extension without changing its data.
  Future<bool> reload() async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('reload');
      return ok ?? false;
    } on MissingPluginException {
      throw const CallDirectoryUnavailableException(
          'Call directory channel is not registered in this build.');
    }
  }

  /// Parses a number typed with its country code ("+1 408 555 0123",
  /// "0044 20 7946 0000") into the CallKit form (14085550123). Returns null
  /// without a leading "+" or "00": CallKit matches the full international
  /// number, so a local number would be saved and never match a call.
  static int? parseInternationalNumber(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'[\s\-().]'), '');
    if (s.startsWith('+')) {
      s = s.substring(1);
    } else if (s.startsWith('00')) {
      s = s.substring(2);
    } else {
      return null;
    }
    // E.164: at most 15 digits; no country code plus subscriber is under 7.
    if (!RegExp(r'^[1-9]\d{6,14}$').hasMatch(s)) return null;
    return int.parse(s);
  }

  /// Numbers in the block list the extension reads, ascending.
  Future<List<int>> blockedNumbers() async {
    if (!isSupported) return const [];
    try {
      final result = await _channel.invokeMethod<Map>('list');
      return _numbers(result?['blocked']);
    } on MissingPluginException {
      throw const CallDirectoryUnavailableException(
          'Call directory channel is not registered in this build.');
    }
  }

  /// Adds one number (CallKit form, see [parseInternationalNumber]) to the
  /// block list and asks iOS to reload the extension. Returns the new list.
  /// Rethrows [PlatformException] (e.g. APP_GROUP_UNAVAILABLE).
  Future<List<int>> block(int number) => _edit('block', number);

  /// Removes one number from the block list. Returns the new list.
  Future<List<int>> unblock(int number) => _edit('unblock', number);

  Future<List<int>> _edit(String method, int number) async {
    if (!isSupported) return const [];
    try {
      final result =
          await _channel.invokeMethod<Map>(method, {'number': number});
      return _numbers(result?['blocked']);
    } on MissingPluginException {
      throw const CallDirectoryUnavailableException(
          'Call directory channel is not registered in this build.');
    }
  }

  /// Opens Settings at Call Blocking & Identification, where the person turns
  /// OrbGuard on. Returns false if iOS refused.
  Future<bool> openSettings() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      throw const CallDirectoryUnavailableException(
          'Call directory channel is not registered in this build.');
    }
  }

  static List<int> _numbers(Object? raw) => raw is List
      ? raw.whereType<num>().map((n) => n.toInt()).toList()
      : const [];

  /// Report the stored counts and the REAL enablement state of the extension.
  ///
  /// Keys: {containerAvailable, blockedCount, identifiedCount, extensionStatus
  /// ("enabled"|"disabled"|"unknown"), extensionEnabled, requiresUserEnable,
  /// note}. Returns null on unsupported platforms.
  Future<Map<String, dynamic>?> status() async {
    if (!isSupported) return null;
    try {
      final result = await _channel.invokeMethod<Map>('status');
      return result == null ? null : Map<String, dynamic>.from(result);
    } on MissingPluginException {
      throw const CallDirectoryUnavailableException(
          'Call directory channel is not registered in this build.');
    }
  }
}
