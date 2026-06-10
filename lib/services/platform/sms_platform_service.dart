/// SMS Platform Service
/// Flutter-side platform channel for Android SMS integration.
///
/// The native side of this channel lives in
/// `android/app/src/main/kotlin/com/orb/guard/MainActivity.kt`
/// (`setupSmsChannel`) and `SMSAnalyzer.kt`. There is intentionally no iOS
/// implementation: iOS does not expose the SMS inbox to third-party apps, so
/// every inbox-related call on non-Android platforms surfaces an explicit
/// [SmsPlatformUnavailableException] instead of pretending to return an
/// empty-but-clean result.
library sms_platform_service;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/orbguard_api_client.dart';
import '../../models/api/sms_analysis.dart';
import '../../providers/sms_provider.dart';

/// Thrown when an SMS capability genuinely does not exist on this platform
/// (or the native channel is not registered in the running binary).
class SmsPlatformUnavailableException implements Exception {
  final String message;
  const SmsPlatformUnavailableException(this.message);

  @override
  String toString() => message;
}

/// SMS Platform Service - Handles native Android SMS integration.
///
/// This is a singleton because it owns the single [MethodChannel] handler for
/// `com.orb.guard/sms`, but it is *owned and initialized by [SmsProvider]*
/// (constructor-injected there). UI code must never construct or talk to this
/// service directly; it consumes [SmsProvider] instead.
class SmsPlatformService {
  static const _channelName = 'com.orb.guard/sms';
  static final SmsPlatformService _instance = SmsPlatformService._internal();

  factory SmsPlatformService() => _instance;

  SmsPlatformService._internal() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static SmsPlatformService get instance => _instance;

  final MethodChannel _channel = const MethodChannel(_channelName);
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // Callbacks for received SMS
  final StreamController<SmsMessage> _smsStreamController =
      StreamController<SmsMessage>.broadcast();

  bool _isInitialized = false;
  SmsProvider? _smsProvider;

  /// Whether the device SMS inbox is reachable on this platform.
  /// Only Android exposes SMS to apps; iOS/macOS/desktop/web do not.
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Human-readable reason used when [isSupported] is false.
  String get unsupportedReason {
    if (kIsWeb) {
      return 'The SMS inbox is not accessible from the web. '
          'Use the Check tab to analyze message text manually.';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS does not allow apps to read the SMS inbox. '
            'Use the Check tab to analyze message text manually.';
      case TargetPlatform.android:
        return 'SMS channel unavailable.';
      default:
        return '${defaultTargetPlatform.name} does not expose an SMS inbox. '
            'Use the Check tab to analyze message text manually.';
    }
  }

  bool get isInitialized => _isInitialized;

  /// Stream of incoming SMS messages (forwarded from the Android receiver).
  Stream<SmsMessage> get smsStream => _smsStreamController.stream;

  /// Initialize the service. Called by [SmsProvider.init]; the provider owns
  /// this service's lifecycle and receives all incoming messages.
  Future<void> init({SmsProvider? smsProvider}) async {
    if (smsProvider != null) {
      _smsProvider = smsProvider;
    }
    if (_isInitialized) return;
    _isInitialized = true;
    debugPrint('SmsPlatformService: Initialized (supported=$isSupported)');
  }

  /// Set the SMS provider for state management.
  void setSmsProvider(SmsProvider provider) {
    _smsProvider = provider;
  }

  /// Handle method calls from native Android
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onSmsReceived':
        return _onSmsReceived(call.arguments);
      case 'blockSender':
        return _onBlockSender(call.arguments);
      default:
        debugPrint('SmsPlatformService: Unknown method ${call.method}');
        return null;
    }
  }

  /// Handle incoming SMS from native
  Future<void> _onSmsReceived(dynamic arguments) async {
    try {
      final Map<String, dynamic> data = Map<String, dynamic>.from(arguments);

      final message = SmsMessage(
        id: data['id'] as String? ?? '',
        sender: data['sender'] as String? ?? 'Unknown',
        content: data['content'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (data['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );

      debugPrint('SmsPlatformService: Received SMS from ${message.sender}');

      // Notify listeners
      _smsStreamController.add(message);

      final provider = _smsProvider;
      SmsAnalysisResult? result;
      if (provider != null) {
        // Route through the provider so state, stats and persistence all
        // reflect this analysis.
        provider.addMessage(message);
        result = await provider.analyzeMessage(message.id);
      } else {
        // No provider attached (should not happen once main.dart wires the
        // provider) - analyze directly so the native notification path still
        // receives a verdict.
        result = await _analyzeMessageDirect(message);
      }

      // Send result back to native
      if (result != null) {
        await _sendAnalysisResult(message.id, result);
      }
    } catch (e) {
      debugPrint('SmsPlatformService: Error processing SMS: $e');
    }
  }

  /// Analyze an SMS message directly against the backend (fallback path
  /// used only when no provider is attached).
  Future<SmsAnalysisResult?> _analyzeMessageDirect(SmsMessage message) async {
    try {
      final request = SmsAnalysisRequest(
        content: message.content,
        sender: message.sender,
        timestamp: message.timestamp,
      );

      return await _api.analyzeSms(request);
    } catch (e) {
      debugPrint('SmsPlatformService: Analysis failed: $e');
      return null;
    }
  }

  /// Send analysis result back to native
  Future<void> _sendAnalysisResult(
    String messageId,
    SmsAnalysisResult result,
  ) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('onAnalysisComplete', {
        'messageId': messageId,
        'result': {
          'threatLevel': result.threatLevel.name,
          'isThreat': result.hasThreats,
          'confidence': result.riskScore,
          'threatTypes': result.threats.map((t) => t.type.value).toList(),
          'indicators': result.matchedPatterns,
          'recommendations': result.recommendation != null
              ? [result.recommendation!]
              : <String>[],
        },
      });
    } catch (e) {
      debugPrint('SmsPlatformService: Failed to send result: $e');
    }
  }

  /// Handle block sender request from native
  Future<void> _onBlockSender(dynamic arguments) async {
    try {
      final Map<String, dynamic> data = Map<String, dynamic>.from(arguments);
      final sender = data['sender'] as String?;

      if (sender != null && _smsProvider != null) {
        await _smsProvider!.blockSender(sender);
      }
    } catch (e) {
      debugPrint('SmsPlatformService: Error blocking sender: $e');
    }
  }

  /// Check if SMS permission is granted.
  ///
  /// Returns false on platforms without an SMS inbox; throws
  /// [SmsPlatformUnavailableException] if the Android channel itself is
  /// missing from the binary so callers can distinguish "denied" from
  /// "broken".
  Future<bool> checkSmsPermission() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<Map>('checkSmsPermission');
      return result?['hasPermission'] as bool? ?? false;
    } on MissingPluginException {
      throw const SmsPlatformUnavailableException(
          'SMS channel is not registered in this build.');
    }
  }

  /// Request SMS permission (Android runtime permission dialog).
  ///
  /// The result is not delivered synchronously; callers must re-check via
  /// [checkSmsPermission] (e.g. on app resume).
  Future<void> requestSmsPermission() async {
    if (!isSupported) {
      throw SmsPlatformUnavailableException(unsupportedReason);
    }
    try {
      await _channel.invokeMethod('requestSmsPermission');
    } on MissingPluginException {
      throw const SmsPlatformUnavailableException(
          'SMS channel is not registered in this build.');
    }
  }

  /// Read SMS inbox from device.
  ///
  /// Throws [SmsPlatformUnavailableException] on platforms that do not
  /// expose the SMS inbox, and rethrows channel errors. It never converts a
  /// failure into an empty (fake-clean) inbox.
  Future<List<SmsMessage>> readSmsInbox({int limit = 100}) async {
    if (!isSupported) {
      throw SmsPlatformUnavailableException(unsupportedReason);
    }
    try {
      final result = await _channel.invokeMethod<Map>('readSmsInbox', {
        'limit': limit,
      });

      final messages = result?['messages'] as List<dynamic>? ?? [];

      return messages.map((m) {
        final data = Map<String, dynamic>.from(m as Map);
        return SmsMessage(
          id: data['id'] as String? ?? '',
          sender: data['sender'] as String? ?? 'Unknown',
          content: data['content'] as String? ?? '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            (data['timestamp'] as int?) ??
                DateTime.now().millisecondsSinceEpoch,
          ),
          isRead: data['isRead'] as bool? ?? false,
        );
      }).toList();
    } on MissingPluginException {
      throw const SmsPlatformUnavailableException(
          'SMS channel is not registered in this build.');
    }
  }

  /// Update SMS protection settings on the native side.
  Future<void> updateSettings({
    bool protectionEnabled = true,
    bool notifyOnThreat = true,
    bool autoBlockDangerous = false,
  }) async {
    if (!isSupported) {
      debugPrint(
          'SmsPlatformService: updateSettings skipped (platform unsupported)');
      return;
    }
    try {
      await _channel.invokeMethod('updateSettings', {
        'protectionEnabled': protectionEnabled,
        'notifyOnThreat': notifyOnThreat,
        'autoBlockDangerous': autoBlockDangerous,
      });
    } catch (e) {
      debugPrint('SmsPlatformService: Failed to update settings: $e');
    }
  }

  /// Clear native cache
  Future<void> clearCache() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('clearCache');
    } catch (e) {
      debugPrint('SmsPlatformService: Failed to clear cache: $e');
    }
  }

  /// Dispose the service
  void dispose() {
    _smsStreamController.close();
    _isInitialized = false;
  }
}
