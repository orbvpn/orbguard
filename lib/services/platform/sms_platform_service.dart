/// SMS Platform Service
/// Flutter-side platform channel for Android SMS integration
library sms_platform_service;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/orbguard_api_client.dart';
import '../../models/api/sms_analysis.dart';
import '../../providers/sms_provider.dart';

/// SMS Platform Service - Handles native Android SMS integration
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

  // Settings
  bool _isInitialized = false;
  SmsProvider? _smsProvider;

  /// Stream of incoming SMS messages
  Stream<SmsMessage> get smsStream => _smsStreamController.stream;

  /// Initialize the service
  Future<void> init({SmsProvider? smsProvider}) async {
    if (_isInitialized) return;

    _smsProvider = smsProvider;
    _isInitialized = true;

    debugPrint('SmsPlatformService: Initialized');
  }

  /// Set the SMS provider for state management
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

      // Add to provider
      _smsProvider?.addMessage(message);

      // Analyze the message
      final result = await _analyzeMessage(message);

      // Send result back to native
      if (result != null) {
        await _sendAnalysisResult(message.id, result);
      }
    } catch (e) {
      debugPrint('SmsPlatformService: Error processing SMS: $e');
    }
  }

  /// Analyze an SMS message
  Future<SmsAnalysisResult?> _analyzeMessage(SmsMessage message) async {
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

  /// Check if SMS permission is granted
  Future<bool> checkSmsPermission() async {
    try {
      final result = await _channel.invokeMethod<Map>('checkSmsPermission');
      return result?['hasPermission'] as bool? ?? false;
    } catch (e) {
      debugPrint('SmsPlatformService: Permission check failed: $e');
      return false;
    }
  }

  /// Request SMS permission
  Future<void> requestSmsPermission() async {
    try {
      await _channel.invokeMethod('requestSmsPermission');
    } catch (e) {
      debugPrint('SmsPlatformService: Permission request failed: $e');
    }
  }

  /// Read SMS inbox from device
  Future<List<SmsMessage>> readSmsInbox({int limit = 100}) async {
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
            (data['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
          ),
          isRead: data['isRead'] as bool? ?? false,
        );
      }).toList();
    } catch (e) {
      debugPrint('SmsPlatformService: Failed to read inbox: $e');
      return [];
    }
  }

  /// Update SMS protection settings
  Future<void> updateSettings({
    bool protectionEnabled = true,
    bool notifyOnThreat = true,
    bool autoBlockDangerous = false,
  }) async {
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
