/// SMS Platform Service
/// Flutter-side platform channel for the Android scam-text checker.
///
/// OrbGuard holds NO SMS permission on any platform and never reads the
/// inbox or listens for incoming texts (Google Play restricts the
/// anti-SMS-phishing use case to pre-qualified vendors). Text reaches the
/// checker only when the user pastes it or shares it to OrbGuard from
/// another app (Android `ACTION_SEND` → `onSharedText` / `getSharedText`).
///
/// The native side of this channel lives in
/// `android/app/src/main/kotlin/com/orb/guard/MainActivity.kt`
/// (`setupSmsChannel`) and `SMSAnalyzer.kt`. [isSupported] (inbox readable)
/// is therefore false everywhere, so every inbox-related path surfaces an
/// explicit unavailable state instead of an empty-but-clean result.
library;

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

  /// Whether the device SMS inbox is readable. Always false: OrbGuard
  /// deliberately holds no SMS permission (see the library doc above).
  bool get isSupported => false;

  /// Whether the native share-sheet channel (`onSharedText`) exists here.
  bool get hasShareChannel =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Human-readable reason used when [isSupported] is false.
  String get unsupportedReason {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'OrbGuard does not read your SMS inbox (Google Play policy). '
          'To check a text, share it to OrbGuard from your Messages app or '
          'paste it in the Check tab.';
    }
    if (kIsWeb) {
      return 'The SMS inbox is not accessible from the web. '
          'Paste a message in the Check tab to analyze it.';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS does not allow apps to read the SMS inbox. '
            'Paste a message in the Check tab to analyze it.';
      default:
        return '${defaultTargetPlatform.name} does not expose an SMS inbox. '
            'Paste a message in the Check tab to analyze it.';
    }
  }

  bool get isInitialized => _isInitialized;

  /// Stream of messages handed to the checker by the native side.
  Stream<SmsMessage> get smsStream => _smsStreamController.stream;

  /// Text shared to OrbGuard via the Android share sheet while running.
  Stream<String> get sharedTextStream => _sharedTextController.stream;
  final StreamController<String> _sharedTextController =
      StreamController<String>.broadcast();

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
      case 'onSharedText':
        return _onSharedText(call.arguments);
      default:
        debugPrint('SmsPlatformService: Unknown method ${call.method}');
        return null;
    }
  }

  /// Text shared into a RUNNING app (ACTION_SEND → MainActivity.onNewIntent).
  Future<void> _onSharedText(dynamic arguments) async {
    final text = (arguments is Map ? arguments['text'] : arguments)?.toString();
    if (text == null || text.trim().isEmpty) return;
    _sharedTextController.add(text.trim());
    _smsProvider?.receiveSharedText(text.trim());
  }

  /// Text shared into a COLD-started app (held natively until Dart asks).
  /// Returns null where there is no share channel or nothing is pending.
  Future<String?> fetchPendingSharedText() async {
    if (!hasShareChannel) return null;
    try {
      final text = await _channel.invokeMethod<String>('getSharedText');
      if (text == null || text.trim().isEmpty) return null;
      return text.trim();
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('SmsPlatformService: getSharedText failed: $e');
      return null;
    }
  }

  /// Handle a message handed over by native
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
    if (!hasShareChannel) return;
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

  /// Update SMS protection settings on the native side.
  Future<void> updateSettings({
    bool protectionEnabled = true,
    bool notifyOnThreat = true,
    bool autoBlockDangerous = false,
  }) async {
    if (!hasShareChannel) return;
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
    if (!hasShareChannel) return;
    try {
      await _channel.invokeMethod('clearCache');
    } catch (e) {
      debugPrint('SmsPlatformService: Failed to clear cache: $e');
    }
  }

  /// Dispose the service
  void dispose() {
    _smsStreamController.close();
    _sharedTextController.close();
    _isInitialized = false;
  }
}
