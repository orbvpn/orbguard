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
/// Honesty contract: this is a DATA-SYNC bridge only. Syncing numbers does not
/// mean calls are being blocked — the call directory only takes effect once the
/// user enables it in Settings > Phone > Call Blocking & Identification on a
/// device signed with the CallKit call-directory capability. [status] reports
/// the real enablement state. The channel is registered only by the iOS host
/// app; every method is a no-op / unavailable on other platforms, and this
/// service NEVER fabricates phone numbers — callers pass real user blocks and
/// real threat-intel phone reputation, or nothing at all.
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
