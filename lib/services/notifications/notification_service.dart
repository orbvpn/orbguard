/// Notification Service
/// Core service for local and push notifications

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_channels.dart';
import 'notification_actions.dart';
import '../realtime/websocket_service.dart';
import '../../models/api/threat_indicator.dart';

/// Notification service singleton
class NotificationService {
  static NotificationService? _instance;
  static NotificationService get instance =>
      _instance ??= NotificationService._();

  NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _notificationId = 0;

  // Callbacks
  final _notificationController =
      StreamController<NotificationResponse>.broadcast();
  NotificationActionCallback? _actionCallback;

  // Settings
  bool _enabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _criticalAlertsEnabled = true;
  Set<SeverityLevel> _enabledSeverities = {
    SeverityLevel.critical,
    SeverityLevel.high,
    SeverityLevel.medium,
  };

  // Persistence keys
  static const String _keyEnabled = 'notifications_enabled';
  static const String _keySoundEnabled = 'notifications_sound';
  static const String _keyVibrationEnabled = 'notifications_vibration';
  static const String _keyCriticalEnabled = 'notifications_critical';
  static const String _keySeverities = 'notifications_severities';
  static const String _keyNotificationId = 'notification_id_counter';

  /// Stream of notification taps
  Stream<NotificationResponse> get notificationStream =>
      _notificationController.stream;

  /// Check if notifications are enabled
  bool get isEnabled => _enabled;

  /// Check if sound is enabled
  bool get soundEnabled => _soundEnabled;

  /// Check if vibration is enabled
  bool get vibrationEnabled => _vibrationEnabled;

  /// Check if critical alerts are enabled
  bool get criticalAlertsEnabled => _criticalAlertsEnabled;

  /// Get enabled severities
  Set<SeverityLevel> get enabledSeverities =>
      Set.unmodifiable(_enabledSeverities);

  /// Initialize the notification service
  Future<void> init() async {
    if (_initialized) return;

    // Load settings
    await _loadSettings();

    // Initialize platform-specific settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: NotificationCategories.iosCategories,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationTap,
    );

    // Create Android notification channels
    if (Platform.isAndroid) {
      await _createAndroidChannels();
    }

    _initialized = true;
  }

  /// Request notification permissions
  Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final result = await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
            critical: _criticalAlertsEnabled,
          );
      return result ?? false;
    } else if (Platform.isAndroid) {
      final result = await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return result ?? false;
    }
    return false;
  }

  /// Check if permissions are granted
  Future<bool> hasPermissions() async {
    if (Platform.isAndroid) {
      final result = await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
      return result ?? false;
    }
    // iOS permissions checked at runtime
    return true;
  }

  /// Set action callback
  void setActionCallback(NotificationActionCallback callback) {
    _actionCallback = callback;
  }

  /// Show threat notification
  Future<void> showThreatNotification(ThreatEvent event) async {
    if (!_enabled) return;
    if (!_enabledSeverities.contains(event.severity)) return;

    final channel = _getChannelForSeverity(event.severity);
    final id = _getNextNotificationId();

    final androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: channel.priority,
      category: AndroidNotificationCategory.alarm,
      playSound: _soundEnabled,
      enableVibration: _vibrationEnabled,
      styleInformation: BigTextStyleInformation(
        event.description ?? 'A ${event.severity.value} threat has been detected.',
        contentTitle: _getThreatTitle(event),
        summaryText: event.campaignName ?? event.type,
      ),
      actions: [
        const AndroidNotificationAction(
          NotificationActions.viewDetails,
          'View Details',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          NotificationActions.dismiss,
          'Dismiss',
          cancelNotification: true,
        ),
      ],
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: _soundEnabled,
      interruptionLevel: _getInterruptionLevel(event.severity),
      categoryIdentifier: NotificationCategories.threatCategory,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id,
      _getThreatTitle(event),
      event.description ?? 'Tap to view details',
      details,
      payload: jsonEncode({
        'type': 'threat',
        'event_id': event.id,
        'severity': event.severity.value,
        'indicator_type': event.type,
        'value': event.value,
      }),
    );
  }

  /// Show breach alert notification
  Future<void> showBreachNotification({
    required String title,
    required String body,
    required String breachId,
    SeverityLevel severity = SeverityLevel.high,
  }) async {
    if (!_enabled) return;

    final channel = NotificationChannels.breach;
    final id = _getNextNotificationId();

    final androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: channel.priority,
      category: AndroidNotificationCategory.alarm,
      playSound: _soundEnabled,
      enableVibration: _vibrationEnabled,
      actions: [
        const AndroidNotificationAction(
          NotificationActions.viewDetails,
          'View Details',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          NotificationActions.dismiss,
          'Dismiss',
          cancelNotification: true,
        ),
      ],
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: _soundEnabled,
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: NotificationCategories.breachCategory,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id,
      title,
      body,
      details,
      payload: jsonEncode({
        'type': 'breach',
        'breach_id': breachId,
        'severity': severity.value,
      }),
    );
  }

  /// Show scan complete notification
  Future<void> showScanCompleteNotification({
    required String scanType,
    required int threatsFound,
    required int duration,
  }) async {
    if (!_enabled) return;

    final channel = threatsFound > 0
        ? NotificationChannels.scanThreats
        : NotificationChannels.scanComplete;
    final id = _getNextNotificationId();

    final title = threatsFound > 0
        ? '$threatsFound Threat${threatsFound > 1 ? 's' : ''} Found'
        : 'Scan Complete';
    final body = threatsFound > 0
        ? '$scanType scan found $threatsFound threat${threatsFound > 1 ? 's' : ''}. Tap to review.'
        : '$scanType scan completed in ${duration}s. No threats found.';

    final androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: channel.priority,
      category: AndroidNotificationCategory.status,
      playSound: _soundEnabled && threatsFound > 0,
      enableVibration: _vibrationEnabled && threatsFound > 0,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: threatsFound > 0,
      presentSound: _soundEnabled && threatsFound > 0,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id,
      title,
      body,
      details,
      payload: jsonEncode({
        'type': 'scan',
        'scan_type': scanType,
        'threats_found': threatsFound,
      }),
    );
  }

  /// Show SMS threat notification
  Future<void> showSmsThreatNotification({
    required String sender,
    required String threatType,
    required SeverityLevel severity,
  }) async {
    if (!_enabled) return;
    if (!_enabledSeverities.contains(severity)) return;

    final channel = _getChannelForSeverity(severity);
    final id = _getNextNotificationId();

    final androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: channel.priority,
      category: AndroidNotificationCategory.message,
      playSound: _soundEnabled,
      enableVibration: _vibrationEnabled,
      actions: [
        const AndroidNotificationAction(
          NotificationActions.blockSender,
          'Block Sender',
        ),
        const AndroidNotificationAction(
          NotificationActions.viewDetails,
          'View',
          showsUserInterface: true,
        ),
      ],
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: _soundEnabled,
      interruptionLevel: _getInterruptionLevel(severity),
      categoryIdentifier: NotificationCategories.smsCategory,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id,
      'Suspicious SMS Blocked',
      'Message from $sender detected as $threatType',
      details,
      payload: jsonEncode({
        'type': 'sms',
        'sender': sender,
        'threat_type': threatType,
        'severity': severity.value,
      }),
    );
  }

  /// Show URL blocked notification
  Future<void> showUrlBlockedNotification({
    required String url,
    required String reason,
    required SeverityLevel severity,
  }) async {
    if (!_enabled) return;

    final channel = NotificationChannels.urlBlocked;
    final id = _getNextNotificationId();

    // Extract domain from URL
    final domain = Uri.tryParse(url)?.host ?? url;

    final androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
      playSound: _soundEnabled,
      enableVibration: _vibrationEnabled,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: _soundEnabled,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id,
      'Dangerous Site Blocked',
      '$domain blocked: $reason',
      details,
      payload: jsonEncode({
        'type': 'url',
        'url': url,
        'reason': reason,
        'severity': severity.value,
      }),
    );
  }

  /// Show general notification
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    NotificationChannel? channel,
  }) async {
    if (!_enabled) return;

    final notifChannel = channel ?? NotificationChannels.general;
    final id = _getNextNotificationId();

    final androidDetails = AndroidNotificationDetails(
      notifChannel.id,
      notifChannel.name,
      channelDescription: notifChannel.description,
      importance: notifChannel.importance,
      priority: notifChannel.priority,
      playSound: _soundEnabled,
      enableVibration: _vibrationEnabled,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: _soundEnabled,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(id, title, body, details, payload: payload);
  }

  /// Cancel notification by ID
  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  /// Update badge count (iOS)
  Future<void> updateBadgeCount(int count) async {
    if (Platform.isIOS) {
      // Badge is set via notification, or use a dedicated package
    }
  }

  // Settings methods

  /// Enable/disable notifications
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    await _saveSettings();
  }

  /// Enable/disable sound
  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled = enabled;
    await _saveSettings();
  }

  /// Enable/disable vibration
  Future<void> setVibrationEnabled(bool enabled) async {
    _vibrationEnabled = enabled;
    await _saveSettings();
  }

  /// Enable/disable critical alerts
  Future<void> setCriticalAlertsEnabled(bool enabled) async {
    _criticalAlertsEnabled = enabled;
    await _saveSettings();
  }

  /// Set enabled severities
  Future<void> setEnabledSeverities(Set<SeverityLevel> severities) async {
    _enabledSeverities = Set.from(severities);
    await _saveSettings();
  }

  /// Add severity to enabled list
  Future<void> enableSeverity(SeverityLevel severity) async {
    _enabledSeverities.add(severity);
    await _saveSettings();
  }

  /// Remove severity from enabled list
  Future<void> disableSeverity(SeverityLevel severity) async {
    _enabledSeverities.remove(severity);
    await _saveSettings();
  }

  // Private methods

  Future<void> _createAndroidChannels() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (android == null) return;

    for (final channel in NotificationChannels.allChannels) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          channel.id,
          channel.name,
          description: channel.description,
          importance: channel.importance,
          playSound: channel.playSound,
          enableVibration: channel.enableVibration,
        ),
      );
    }
  }

  NotificationChannel _getChannelForSeverity(SeverityLevel severity) {
    switch (severity) {
      case SeverityLevel.critical:
        return NotificationChannels.critical;
      case SeverityLevel.high:
        return NotificationChannels.high;
      case SeverityLevel.medium:
        return NotificationChannels.medium;
      case SeverityLevel.low:
      case SeverityLevel.info:
      case SeverityLevel.unknown:
        return NotificationChannels.low;
    }
  }

  InterruptionLevel _getInterruptionLevel(SeverityLevel severity) {
    switch (severity) {
      case SeverityLevel.critical:
        return InterruptionLevel.critical;
      case SeverityLevel.high:
        return InterruptionLevel.timeSensitive;
      case SeverityLevel.medium:
        return InterruptionLevel.active;
      case SeverityLevel.low:
      case SeverityLevel.info:
      case SeverityLevel.unknown:
        return InterruptionLevel.passive;
    }
  }

  String _getThreatTitle(ThreatEvent event) {
    switch (event.severity) {
      case SeverityLevel.critical:
        return '🚨 Critical Threat Detected';
      case SeverityLevel.high:
        return '⚠️ High Severity Threat';
      case SeverityLevel.medium:
        return '⚡ Medium Threat Detected';
      case SeverityLevel.low:
      case SeverityLevel.info:
      case SeverityLevel.unknown:
        return 'Threat Alert';
    }
  }

  int _getNextNotificationId() {
    _notificationId++;
    _saveNotificationId();
    return _notificationId;
  }

  Future<void> _saveNotificationId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyNotificationId, _notificationId);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    _enabled = prefs.getBool(_keyEnabled) ?? true;
    _soundEnabled = prefs.getBool(_keySoundEnabled) ?? true;
    _vibrationEnabled = prefs.getBool(_keyVibrationEnabled) ?? true;
    _criticalAlertsEnabled = prefs.getBool(_keyCriticalEnabled) ?? true;
    _notificationId = prefs.getInt(_keyNotificationId) ?? 0;

    final severitiesJson = prefs.getString(_keySeverities);
    if (severitiesJson != null) {
      final list = jsonDecode(severitiesJson) as List;
      _enabledSeverities = list
          .map((s) => SeverityLevel.fromString(s as String))
          .toSet();
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_keyEnabled, _enabled);
    await prefs.setBool(_keySoundEnabled, _soundEnabled);
    await prefs.setBool(_keyVibrationEnabled, _vibrationEnabled);
    await prefs.setBool(_keyCriticalEnabled, _criticalAlertsEnabled);
    await prefs.setString(
      _keySeverities,
      jsonEncode(_enabledSeverities.map((s) => s.value).toList()),
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    _notificationController.add(response);

    if (_actionCallback != null && response.actionId != null) {
      _actionCallback!(response.actionId!, response.payload);
    }
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationTap(NotificationResponse response) {
    // Handle background notification tap
    // This runs in an isolate, so we can't access instance state
    debugPrint('Background notification tapped: ${response.payload}');
  }

  void dispose() {
    _notificationController.close();
  }
}

/// Callback type for notification actions
typedef NotificationActionCallback = void Function(
    String actionId, String? payload);
