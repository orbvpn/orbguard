/// Notification Channels
/// Android notification channel definitions for OrbGuard

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Custom notification channel configuration
class NotificationChannel {
  final String id;
  final String name;
  final String description;
  final Importance importance;
  final Priority priority;
  final bool playSound;
  final bool enableVibration;

  const NotificationChannel({
    required this.id,
    required this.name,
    required this.description,
    required this.importance,
    required this.priority,
    this.playSound = true,
    this.enableVibration = true,
  });
}

/// Pre-defined notification channels
class NotificationChannels {
  NotificationChannels._();

  /// Critical threats - highest priority, bypasses DND
  static const critical = NotificationChannel(
    id: 'orbguard_critical',
    name: 'Critical Alerts',
    description: 'Critical security threats requiring immediate attention',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    enableVibration: true,
  );

  /// High severity threats
  static const high = NotificationChannel(
    id: 'orbguard_high',
    name: 'High Priority Alerts',
    description: 'High severity security threats',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  /// Medium severity threats
  static const medium = NotificationChannel(
    id: 'orbguard_medium',
    name: 'Medium Priority Alerts',
    description: 'Medium severity security events',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    playSound: true,
    enableVibration: true,
  );

  /// Low severity / informational
  static const low = NotificationChannel(
    id: 'orbguard_low',
    name: 'Low Priority Alerts',
    description: 'Low severity security events and information',
    importance: Importance.low,
    priority: Priority.low,
    playSound: false,
    enableVibration: false,
  );

  /// Data breach alerts
  static const breach = NotificationChannel(
    id: 'orbguard_breach',
    name: 'Breach Alerts',
    description: 'Data breach and credential exposure alerts',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  /// Scan complete - threats found
  static const scanThreats = NotificationChannel(
    id: 'orbguard_scan_threats',
    name: 'Scan Results - Threats',
    description: 'Security scan results when threats are found',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  /// Scan complete - no threats
  static const scanComplete = NotificationChannel(
    id: 'orbguard_scan_complete',
    name: 'Scan Results',
    description: 'Security scan completion notifications',
    importance: Importance.low,
    priority: Priority.low,
    playSound: false,
    enableVibration: false,
  );

  /// URL blocked notifications
  static const urlBlocked = NotificationChannel(
    id: 'orbguard_url_blocked',
    name: 'URL Protection',
    description: 'Notifications when dangerous URLs are blocked',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  /// SMS protection notifications
  static const smsProtection = NotificationChannel(
    id: 'orbguard_sms',
    name: 'SMS Protection',
    description: 'Smishing and suspicious SMS alerts',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  /// Network security notifications
  static const network = NotificationChannel(
    id: 'orbguard_network',
    name: 'Network Security',
    description: 'WiFi security and network threat alerts',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  /// App security notifications
  static const appSecurity = NotificationChannel(
    id: 'orbguard_app_security',
    name: 'App Security',
    description: 'Suspicious app and permission alerts',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    playSound: true,
    enableVibration: true,
  );

  /// Privacy alerts
  static const privacy = NotificationChannel(
    id: 'orbguard_privacy',
    name: 'Privacy Alerts',
    description: 'Privacy violation and tracking alerts',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  /// Real-time stream updates
  static const realtime = NotificationChannel(
    id: 'orbguard_realtime',
    name: 'Real-time Updates',
    description: 'Live threat intelligence stream updates',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    playSound: false,
    enableVibration: false,
  );

  /// General notifications
  static const general = NotificationChannel(
    id: 'orbguard_general',
    name: 'General',
    description: 'General OrbGuard notifications',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    playSound: true,
    enableVibration: true,
  );

  /// Background service notifications (persistent)
  static const background = NotificationChannel(
    id: 'orbguard_background',
    name: 'Background Protection',
    description: 'Ongoing protection status',
    importance: Importance.low,
    priority: Priority.low,
    playSound: false,
    enableVibration: false,
  );

  /// All channels for registration
  static const List<NotificationChannel> allChannels = [
    critical,
    high,
    medium,
    low,
    breach,
    scanThreats,
    scanComplete,
    urlBlocked,
    smsProtection,
    network,
    appSecurity,
    privacy,
    realtime,
    general,
    background,
  ];

  /// Get channel by ID
  static NotificationChannel? getById(String id) {
    try {
      return allChannels.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get channels by importance level
  static List<NotificationChannel> getByImportance(Importance importance) {
    return allChannels.where((c) => c.importance == importance).toList();
  }
}

/// Channel groups for organization (Android 8.0+)
class NotificationChannelGroups {
  NotificationChannelGroups._();

  static const security = AndroidNotificationChannelGroup(
    'orbguard_security',
    'Security Alerts',
    description: 'All security-related notifications',
  );

  static const protection = AndroidNotificationChannelGroup(
    'orbguard_protection',
    'Protection Status',
    description: 'Protection and scanning status updates',
  );

  static const system = AndroidNotificationChannelGroup(
    'orbguard_system',
    'System',
    description: 'System and background notifications',
  );

  static const List<AndroidNotificationChannelGroup> allGroups = [
    security,
    protection,
    system,
  ];
}
