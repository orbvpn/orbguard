/// Browser Platform Service
/// Flutter-side platform channel for Android browser URL monitoring
library browser_platform_service;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/orbguard_api_client.dart';

/// Browser URL threat event
class BrowserThreatEvent {
  final String url;
  final String domain;
  final String threatLevel;
  final double riskScore;
  final List<String> categories;
  final String reason;
  final String browser;
  final bool shouldBlock;

  BrowserThreatEvent({
    required this.url,
    required this.domain,
    required this.threatLevel,
    required this.riskScore,
    required this.categories,
    required this.reason,
    required this.browser,
    required this.shouldBlock,
  });

  factory BrowserThreatEvent.fromMap(Map<String, dynamic> map) {
    return BrowserThreatEvent(
      url: map['url'] as String? ?? '',
      domain: map['domain'] as String? ?? '',
      threatLevel: map['threatLevel'] as String? ?? 'safe',
      riskScore: (map['riskScore'] as num?)?.toDouble() ?? 0.0,
      categories: (map['categories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      reason: map['reason'] as String? ?? '',
      browser: map['browser'] as String? ?? 'Unknown',
      shouldBlock: map['shouldBlock'] as bool? ?? false,
    );
  }
}

/// Browser Platform Service - Handles native Android browser monitoring
class BrowserPlatformService {
  static const _channelName = 'com.orb.guard/browser';
  static final BrowserPlatformService _instance =
      BrowserPlatformService._internal();

  factory BrowserPlatformService() => _instance;

  BrowserPlatformService._internal() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static BrowserPlatformService get instance => _instance;

  final MethodChannel _channel = const MethodChannel(_channelName);
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // Stream controllers
  final StreamController<BrowserThreatEvent> _threatStreamController =
      StreamController<BrowserThreatEvent>.broadcast();

  // Settings
  bool _isInitialized = false;

  /// Stream of browser threat events
  Stream<BrowserThreatEvent> get threatStream => _threatStreamController.stream;

  /// Initialize the service
  Future<void> init() async {
    if (_isInitialized) return;

    _isInitialized = true;

    debugPrint('BrowserPlatformService: Initialized');
  }

  /// Handle method calls from native Android
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'analyzeUrl':
        return _onAnalyzeUrl(call.arguments);
      case 'onThreatDetected':
        return _onThreatDetected(call.arguments);
      default:
        debugPrint('BrowserPlatformService: Unknown method ${call.method}');
        return null;
    }
  }

  /// Handle URL analysis request from native
  Future<void> _onAnalyzeUrl(dynamic arguments) async {
    try {
      final Map<String, dynamic> data = Map<String, dynamic>.from(arguments);

      final url = data['url'] as String? ?? '';
      final domain = data['domain'] as String? ?? '';
      final browser = data['browser'] as String? ?? 'Unknown';

      debugPrint('BrowserPlatformService: Analyzing URL: $url');

      // Analyze the URL using the API client
      final result = await _api.checkUrl(url);

      // Send result back to native
      await _sendAnalysisResult(url, domain, browser, result);
    } catch (e) {
      debugPrint('BrowserPlatformService: Error analyzing URL: $e');
    }
  }

  /// Send analysis result back to native
  Future<void> _sendAnalysisResult(
    String url,
    String domain,
    String browser,
    dynamic result,
  ) async {
    try {
      // Determine threat level based on result
      final isThreat = !result.isSafe || result.riskScore > 0.5;
      final threatLevel = result.riskScore > 0.8
          ? 'critical'
          : result.riskScore > 0.6
              ? 'dangerous'
              : result.riskScore > 0.3
                  ? 'suspicious'
                  : 'safe';

      // Convert categories to strings
      final categoryStrings = result.categories
          ?.map((c) => c.value?.toString() ?? c.toString())
          .toList() ?? <String>[];

      await _channel.invokeMethod('onAnalysisComplete', {
        'url': url,
        'browser': browser,
        'result': {
          'url': url,
          'domain': domain,
          'isThreat': isThreat,
          'threatLevel': threatLevel,
          'riskScore': result.riskScore,
          'categories': categoryStrings,
          'reason': result.recommendation ?? '',
          'shouldBlock': result.shouldBlock,
        },
      });
    } catch (e) {
      debugPrint('BrowserPlatformService: Failed to send result: $e');
    }
  }

  /// Handle threat detected from native
  Future<void> _onThreatDetected(dynamic arguments) async {
    try {
      final Map<String, dynamic> data = Map<String, dynamic>.from(arguments);
      final event = BrowserThreatEvent.fromMap(data);

      debugPrint(
          'BrowserPlatformService: Threat detected - ${event.threatLevel}');

      // Notify stream listeners
      _threatStreamController.add(event);

      // URL provider can be notified through the stream if needed
    } catch (e) {
      debugPrint('BrowserPlatformService: Error handling threat: $e');
    }
  }

  /// Check if browser accessibility permission is granted
  Future<bool> checkBrowserAccessibilityPermission() async {
    try {
      final result = await _channel
          .invokeMethod<Map>('checkBrowserAccessibilityPermission');
      return result?['hasPermission'] as bool? ?? false;
    } catch (e) {
      debugPrint('BrowserPlatformService: Permission check failed: $e');
      return false;
    }
  }

  /// Request browser accessibility permission
  Future<void> requestBrowserAccessibilityPermission() async {
    try {
      await _channel.invokeMethod('requestBrowserAccessibilityPermission');
    } catch (e) {
      debugPrint('BrowserPlatformService: Permission request failed: $e');
    }
  }

  /// Update browser protection settings
  Future<void> updateSettings({
    bool protectionEnabled = true,
    bool notifyOnThreat = true,
    bool blockDangerous = false,
  }) async {
    try {
      await _channel.invokeMethod('updateSettings', {
        'protectionEnabled': protectionEnabled,
        'notifyOnThreat': notifyOnThreat,
        'blockDangerous': blockDangerous,
      });
    } catch (e) {
      debugPrint('BrowserPlatformService: Failed to update settings: $e');
    }
  }

  /// Get analyzed URLs history
  Future<List<Map<String, dynamic>>> getAnalyzedUrls() async {
    try {
      final result = await _channel.invokeMethod<Map>('getAnalyzedUrls');
      final urls = result?['urls'] as List<dynamic>? ?? [];
      return urls.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('BrowserPlatformService: Failed to get URLs: $e');
      return [];
    }
  }

  /// Add domain to whitelist
  Future<void> addToWhitelist(String domain) async {
    try {
      await _channel.invokeMethod('addToWhitelist', {'domain': domain});
    } catch (e) {
      debugPrint('BrowserPlatformService: Failed to add to whitelist: $e');
    }
  }

  /// Remove domain from whitelist
  Future<void> removeFromWhitelist(String domain) async {
    try {
      await _channel.invokeMethod('removeFromWhitelist', {'domain': domain});
    } catch (e) {
      debugPrint('BrowserPlatformService: Failed to remove from whitelist: $e');
    }
  }

  /// Get whitelist
  Future<List<String>> getWhitelist() async {
    try {
      final result = await _channel.invokeMethod<Map>('getWhitelist');
      final domains = result?['domains'] as List<dynamic>? ?? [];
      return domains.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('BrowserPlatformService: Failed to get whitelist: $e');
      return [];
    }
  }

  /// Add domain to blacklist
  Future<void> addToBlacklist(String domain) async {
    try {
      await _channel.invokeMethod('addToBlacklist', {'domain': domain});
    } catch (e) {
      debugPrint('BrowserPlatformService: Failed to add to blacklist: $e');
    }
  }

  /// Remove domain from blacklist
  Future<void> removeFromBlacklist(String domain) async {
    try {
      await _channel.invokeMethod('removeFromBlacklist', {'domain': domain});
    } catch (e) {
      debugPrint('BrowserPlatformService: Failed to remove from blacklist: $e');
    }
  }

  /// Get blacklist
  Future<List<String>> getBlacklist() async {
    try {
      final result = await _channel.invokeMethod<Map>('getBlacklist');
      final domains = result?['domains'] as List<dynamic>? ?? [];
      return domains.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('BrowserPlatformService: Failed to get blacklist: $e');
      return [];
    }
  }

  /// Clear native cache
  Future<void> clearCache() async {
    try {
      await _channel.invokeMethod('clearCache');
    } catch (e) {
      debugPrint('BrowserPlatformService: Failed to clear cache: $e');
    }
  }

  /// Dispose the service
  void dispose() {
    _threatStreamController.close();
    _isInitialized = false;
  }
}
