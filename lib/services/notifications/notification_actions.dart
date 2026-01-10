/// Notification Actions
/// Action identifiers and iOS notification categories

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification action identifiers
class NotificationActions {
  NotificationActions._();

  // Common actions
  static const String viewDetails = 'VIEW_DETAILS';
  static const String dismiss = 'DISMISS';
  static const String openApp = 'OPEN_APP';

  // Threat-specific actions
  static const String blockSender = 'BLOCK_SENDER';
  static const String blockDomain = 'BLOCK_DOMAIN';
  static const String quarantine = 'QUARANTINE';
  static const String allowOnce = 'ALLOW_ONCE';
  static const String addToWhitelist = 'ADD_TO_WHITELIST';
  static const String reportFalsePositive = 'REPORT_FALSE_POSITIVE';

  // Breach actions
  static const String changePassword = 'CHANGE_PASSWORD';
  static const String viewBreachDetails = 'VIEW_BREACH_DETAILS';
  static const String markAsResolved = 'MARK_RESOLVED';

  // Scan actions
  static const String viewScanResults = 'VIEW_SCAN_RESULTS';
  static const String cleanThreats = 'CLEAN_THREATS';
  static const String rescan = 'RESCAN';

  // Network actions
  static const String disconnectWifi = 'DISCONNECT_WIFI';
  static const String enableVpn = 'ENABLE_VPN';

  // App security actions
  static const String uninstallApp = 'UNINSTALL_APP';
  static const String revokePermissions = 'REVOKE_PERMISSIONS';

  // Privacy actions
  static const String blockTracker = 'BLOCK_TRACKER';
  static const String viewPrivacyReport = 'VIEW_PRIVACY_REPORT';

  // Settings actions
  static const String openSettings = 'OPEN_SETTINGS';
  static const String muteChannel = 'MUTE_CHANNEL';
}

/// iOS notification category identifiers
class NotificationCategories {
  NotificationCategories._();

  // Category identifiers
  static const String threatCategory = 'THREAT_CATEGORY';
  static const String breachCategory = 'BREACH_CATEGORY';
  static const String smsCategory = 'SMS_CATEGORY';
  static const String urlCategory = 'URL_CATEGORY';
  static const String scanCategory = 'SCAN_CATEGORY';
  static const String networkCategory = 'NETWORK_CATEGORY';
  static const String appCategory = 'APP_CATEGORY';
  static const String privacyCategory = 'PRIVACY_CATEGORY';
  static const String generalCategory = 'GENERAL_CATEGORY';

  /// iOS notification categories for DarwinInitializationSettings
  static final List<DarwinNotificationCategory> iosCategories = [
    // Threat category with actions
    DarwinNotificationCategory(
      threatCategory,
      actions: [
        DarwinNotificationAction.plain(
          NotificationActions.viewDetails,
          'View Details',
          options: {
            DarwinNotificationActionOption.foreground,
          },
        ),
        DarwinNotificationAction.plain(
          NotificationActions.dismiss,
          'Dismiss',
          options: {
            DarwinNotificationActionOption.destructive,
          },
        ),
        DarwinNotificationAction.plain(
          NotificationActions.reportFalsePositive,
          'Report False Positive',
        ),
      ],
      options: {
        DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
      },
    ),

    // Breach category
    DarwinNotificationCategory(
      breachCategory,
      actions: [
        DarwinNotificationAction.plain(
          NotificationActions.changePassword,
          'Change Password',
          options: {
            DarwinNotificationActionOption.foreground,
          },
        ),
        DarwinNotificationAction.plain(
          NotificationActions.viewBreachDetails,
          'View Details',
          options: {
            DarwinNotificationActionOption.foreground,
          },
        ),
        DarwinNotificationAction.plain(
          NotificationActions.markAsResolved,
          'Mark Resolved',
        ),
      ],
      options: {
        DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
      },
    ),

    // SMS category
    DarwinNotificationCategory(
      smsCategory,
      actions: [
        DarwinNotificationAction.plain(
          NotificationActions.blockSender,
          'Block Sender',
          options: {
            DarwinNotificationActionOption.destructive,
          },
        ),
        DarwinNotificationAction.plain(
          NotificationActions.viewDetails,
          'View Details',
          options: {
            DarwinNotificationActionOption.foreground,
          },
        ),
        DarwinNotificationAction.plain(
          NotificationActions.allowOnce,
          'Allow Once',
        ),
      ],
    ),

    // URL category
    DarwinNotificationCategory(
      urlCategory,
      actions: [
        DarwinNotificationAction.plain(
          NotificationActions.blockDomain,
          'Block Domain',
          options: {
            DarwinNotificationActionOption.destructive,
          },
        ),
        DarwinNotificationAction.plain(
          NotificationActions.addToWhitelist,
          'Allow Site',
        ),
        DarwinNotificationAction.plain(
          NotificationActions.viewDetails,
          'Details',
          options: {
            DarwinNotificationActionOption.foreground,
          },
        ),
      ],
    ),

    // Scan category
    DarwinNotificationCategory(
      scanCategory,
      actions: [
        DarwinNotificationAction.plain(
          NotificationActions.viewScanResults,
          'View Results',
          options: {
            DarwinNotificationActionOption.foreground,
          },
        ),
        DarwinNotificationAction.plain(
          NotificationActions.cleanThreats,
          'Clean Threats',
        ),
        DarwinNotificationAction.plain(
          NotificationActions.rescan,
          'Scan Again',
        ),
      ],
    ),

    // Network category
    DarwinNotificationCategory(
      networkCategory,
      actions: [
        DarwinNotificationAction.plain(
          NotificationActions.disconnectWifi,
          'Disconnect',
          options: {
            DarwinNotificationActionOption.destructive,
          },
        ),
        DarwinNotificationAction.plain(
          NotificationActions.enableVpn,
          'Enable VPN',
          options: {
            DarwinNotificationActionOption.foreground,
          },
        ),
        DarwinNotificationAction.plain(
          NotificationActions.viewDetails,
          'Details',
          options: {
            DarwinNotificationActionOption.foreground,
          },
        ),
      ],
    ),

    // App security category
    DarwinNotificationCategory(
      appCategory,
      actions: [
        DarwinNotificationAction.plain(
          NotificationActions.uninstallApp,
          'Uninstall',
          options: {
            DarwinNotificationActionOption.destructive,
            DarwinNotificationActionOption.foreground,
          },
        ),
        DarwinNotificationAction.plain(
          NotificationActions.viewDetails,
          'View Details',
          options: {
            DarwinNotificationActionOption.foreground,
          },
        ),
      ],
    ),

    // Privacy category
    DarwinNotificationCategory(
      privacyCategory,
      actions: [
        DarwinNotificationAction.plain(
          NotificationActions.blockTracker,
          'Block Tracker',
          options: {
            DarwinNotificationActionOption.destructive,
          },
        ),
        DarwinNotificationAction.plain(
          NotificationActions.viewPrivacyReport,
          'Privacy Report',
          options: {
            DarwinNotificationActionOption.foreground,
          },
        ),
      ],
    ),

    // General category
    DarwinNotificationCategory(
      generalCategory,
      actions: [
        DarwinNotificationAction.plain(
          NotificationActions.openApp,
          'Open',
          options: {
            DarwinNotificationActionOption.foreground,
          },
        ),
        DarwinNotificationAction.plain(
          NotificationActions.dismiss,
          'Dismiss',
        ),
      ],
    ),
  ];
}

/// Android notification action definitions
class AndroidNotificationActions {
  AndroidNotificationActions._();

  /// Threat notification actions
  static const List<AndroidNotificationAction> threatActions = [
    AndroidNotificationAction(
      NotificationActions.viewDetails,
      'View Details',
      showsUserInterface: true,
    ),
    AndroidNotificationAction(
      NotificationActions.dismiss,
      'Dismiss',
      cancelNotification: true,
    ),
    AndroidNotificationAction(
      NotificationActions.reportFalsePositive,
      'Report',
    ),
  ];

  /// Breach notification actions
  static const List<AndroidNotificationAction> breachActions = [
    AndroidNotificationAction(
      NotificationActions.changePassword,
      'Change Password',
      showsUserInterface: true,
    ),
    AndroidNotificationAction(
      NotificationActions.viewBreachDetails,
      'Details',
      showsUserInterface: true,
    ),
  ];

  /// SMS notification actions
  static const List<AndroidNotificationAction> smsActions = [
    AndroidNotificationAction(
      NotificationActions.blockSender,
      'Block Sender',
    ),
    AndroidNotificationAction(
      NotificationActions.viewDetails,
      'View',
      showsUserInterface: true,
    ),
  ];

  /// URL notification actions
  static const List<AndroidNotificationAction> urlActions = [
    AndroidNotificationAction(
      NotificationActions.blockDomain,
      'Block Domain',
    ),
    AndroidNotificationAction(
      NotificationActions.addToWhitelist,
      'Allow',
    ),
  ];

  /// Scan notification actions
  static const List<AndroidNotificationAction> scanActions = [
    AndroidNotificationAction(
      NotificationActions.viewScanResults,
      'View Results',
      showsUserInterface: true,
    ),
    AndroidNotificationAction(
      NotificationActions.cleanThreats,
      'Clean',
    ),
  ];

  /// Network notification actions
  static const List<AndroidNotificationAction> networkActions = [
    AndroidNotificationAction(
      NotificationActions.disconnectWifi,
      'Disconnect',
    ),
    AndroidNotificationAction(
      NotificationActions.enableVpn,
      'Enable VPN',
      showsUserInterface: true,
    ),
  ];
}

/// Action handler for processing notification actions
class NotificationActionHandler {
  NotificationActionHandler._();

  /// Handle an action by ID
  static Future<void> handleAction(
    String actionId,
    String? payload, {
    Function(String route, Map<String, dynamic>? args)? navigate,
    Function(String message)? showToast,
  }) async {
    switch (actionId) {
      case NotificationActions.viewDetails:
        _handleViewDetails(payload, navigate);
        break;

      case NotificationActions.dismiss:
        // Notification already dismissed
        break;

      case NotificationActions.blockSender:
        await _handleBlockSender(payload, showToast);
        break;

      case NotificationActions.blockDomain:
        await _handleBlockDomain(payload, showToast);
        break;

      case NotificationActions.changePassword:
        _handleChangePassword(payload, navigate);
        break;

      case NotificationActions.viewScanResults:
        navigate?.call('/scan-results', null);
        break;

      case NotificationActions.cleanThreats:
        await _handleCleanThreats(payload, showToast);
        break;

      case NotificationActions.disconnectWifi:
        await _handleDisconnectWifi(showToast);
        break;

      case NotificationActions.enableVpn:
        navigate?.call('/vpn', null);
        break;

      case NotificationActions.reportFalsePositive:
        await _handleReportFalsePositive(payload, showToast);
        break;

      case NotificationActions.openApp:
      case NotificationActions.openSettings:
        navigate?.call('/', null);
        break;

      default:
        // Unknown action
        break;
    }
  }

  static void _handleViewDetails(
    String? payload,
    Function(String route, Map<String, dynamic>? args)? navigate,
  ) {
    if (payload == null || navigate == null) return;

    // Parse payload and navigate to appropriate screen
    try {
      final data = _parsePayload(payload);
      final type = data['type'] as String?;

      switch (type) {
        case 'threat':
          navigate('/threat-details', data);
          break;
        case 'breach':
          navigate('/breach-details', data);
          break;
        case 'sms':
          navigate('/sms-protection', data);
          break;
        case 'url':
          navigate('/url-protection', data);
          break;
        case 'scan':
          navigate('/scan-results', data);
          break;
        default:
          navigate('/dashboard', null);
      }
    } catch (_) {
      navigate?.call('/dashboard', null);
    }
  }

  static Future<void> _handleBlockSender(
    String? payload,
    Function(String message)? showToast,
  ) async {
    if (payload == null) return;

    try {
      final data = _parsePayload(payload);
      final sender = data['sender'] as String?;

      if (sender != null) {
        // TODO: Integrate with SMS blocking service
        showToast?.call('Blocked sender: $sender');
      }
    } catch (_) {
      showToast?.call('Failed to block sender');
    }
  }

  static Future<void> _handleBlockDomain(
    String? payload,
    Function(String message)? showToast,
  ) async {
    if (payload == null) return;

    try {
      final data = _parsePayload(payload);
      final url = data['url'] as String?;

      if (url != null) {
        final domain = Uri.tryParse(url)?.host ?? url;
        // TODO: Integrate with URL blocking service
        showToast?.call('Blocked domain: $domain');
      }
    } catch (_) {
      showToast?.call('Failed to block domain');
    }
  }

  static void _handleChangePassword(
    String? payload,
    Function(String route, Map<String, dynamic>? args)? navigate,
  ) {
    // Navigate to breach details with change password flag
    if (payload != null) {
      try {
        final data = _parsePayload(payload);
        data['action'] = 'change_password';
        navigate?.call('/breach-details', data);
      } catch (_) {
        navigate?.call('/dark-web-monitoring', null);
      }
    } else {
      navigate?.call('/dark-web-monitoring', null);
    }
  }

  static Future<void> _handleCleanThreats(
    String? payload,
    Function(String message)? showToast,
  ) async {
    // TODO: Integrate with threat cleaning service
    showToast?.call('Starting threat cleanup...');
  }

  static Future<void> _handleDisconnectWifi(
    Function(String message)? showToast,
  ) async {
    // TODO: Integrate with network service
    showToast?.call('Disconnecting from WiFi...');
  }

  static Future<void> _handleReportFalsePositive(
    String? payload,
    Function(String message)? showToast,
  ) async {
    if (payload == null) return;

    try {
      // TODO: Integrate with reporting service
      showToast?.call('Thank you for the feedback');
    } catch (_) {
      showToast?.call('Failed to submit report');
    }
  }

  static Map<String, dynamic> _parsePayload(String payload) {
    // Simple JSON parsing - real implementation would use dart:convert
    try {
      final Map<String, dynamic> result = {};
      // Basic parsing for key-value pairs
      if (payload.startsWith('{')) {
        // Assume JSON format
        final stripped = payload.substring(1, payload.length - 1);
        final pairs = stripped.split(',');
        for (final pair in pairs) {
          final kv = pair.split(':');
          if (kv.length == 2) {
            final key = kv[0].trim().replaceAll('"', '');
            var value = kv[1].trim().replaceAll('"', '');
            result[key] = value;
          }
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }
}
