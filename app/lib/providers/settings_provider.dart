// Settings Provider
// State management for app settings and configuration

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_mode.dart';
import '../services/notifications/notification_service.dart';
import '../services/telemetry/telemetry_service.dart';

/// Protection feature settings
class ProtectionSettings {
  final bool smsProtectionEnabled;
  final bool urlProtectionEnabled;
  final bool qrProtectionEnabled;
  final bool appSecurityEnabled;
  final bool networkProtectionEnabled;
  final bool darkWebMonitoringEnabled;
  final bool realTimeAlertsEnabled;
  final bool autoBlockThreats;

  ProtectionSettings({
    this.smsProtectionEnabled = true,
    this.urlProtectionEnabled = true,
    this.qrProtectionEnabled = true,
    this.appSecurityEnabled = true,
    this.networkProtectionEnabled = true,
    this.darkWebMonitoringEnabled = true,
    this.realTimeAlertsEnabled = true,
    this.autoBlockThreats = false,
  });

  ProtectionSettings copyWith({
    bool? smsProtectionEnabled,
    bool? urlProtectionEnabled,
    bool? qrProtectionEnabled,
    bool? appSecurityEnabled,
    bool? networkProtectionEnabled,
    bool? darkWebMonitoringEnabled,
    bool? realTimeAlertsEnabled,
    bool? autoBlockThreats,
  }) {
    return ProtectionSettings(
      smsProtectionEnabled: smsProtectionEnabled ?? this.smsProtectionEnabled,
      urlProtectionEnabled: urlProtectionEnabled ?? this.urlProtectionEnabled,
      qrProtectionEnabled: qrProtectionEnabled ?? this.qrProtectionEnabled,
      appSecurityEnabled: appSecurityEnabled ?? this.appSecurityEnabled,
      networkProtectionEnabled: networkProtectionEnabled ?? this.networkProtectionEnabled,
      darkWebMonitoringEnabled: darkWebMonitoringEnabled ?? this.darkWebMonitoringEnabled,
      realTimeAlertsEnabled: realTimeAlertsEnabled ?? this.realTimeAlertsEnabled,
      autoBlockThreats: autoBlockThreats ?? this.autoBlockThreats,
    );
  }
}

/// Notification settings
class NotificationSettings {
  final bool pushNotificationsEnabled;
  final bool threatAlertsEnabled;
  final bool breachAlertsEnabled;
  final bool scanCompletedAlerts;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool quietHoursEnabled;
  final int quietHoursStart; // Hour of day (0-23)
  final int quietHoursEnd;

  NotificationSettings({
    this.pushNotificationsEnabled = true,
    this.threatAlertsEnabled = true,
    this.breachAlertsEnabled = true,
    this.scanCompletedAlerts = false,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.quietHoursEnabled = false,
    this.quietHoursStart = 22,
    this.quietHoursEnd = 7,
  });

  NotificationSettings copyWith({
    bool? pushNotificationsEnabled,
    bool? threatAlertsEnabled,
    bool? breachAlertsEnabled,
    bool? scanCompletedAlerts,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? quietHoursEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
  }) {
    return NotificationSettings(
      pushNotificationsEnabled: pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      threatAlertsEnabled: threatAlertsEnabled ?? this.threatAlertsEnabled,
      breachAlertsEnabled: breachAlertsEnabled ?? this.breachAlertsEnabled,
      scanCompletedAlerts: scanCompletedAlerts ?? this.scanCompletedAlerts,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
    );
  }
}

/// Privacy settings
class PrivacySettings {
  final bool analyticsEnabled;
  final bool crashReportingEnabled;
  final bool shareAnonymousData;
  final bool localDataOnly;
  final bool biometricLockEnabled;
  final int autoLockTimeout; // Minutes, 0 = never
  final bool hideNotificationContent;

  PrivacySettings({
    this.analyticsEnabled = true,
    this.crashReportingEnabled = true,
    this.shareAnonymousData = false,
    this.localDataOnly = false,
    this.biometricLockEnabled = false,
    this.autoLockTimeout = 0,
    this.hideNotificationContent = false,
  });

  PrivacySettings copyWith({
    bool? analyticsEnabled,
    bool? crashReportingEnabled,
    bool? shareAnonymousData,
    bool? localDataOnly,
    bool? biometricLockEnabled,
    int? autoLockTimeout,
    bool? hideNotificationContent,
  }) {
    return PrivacySettings(
      analyticsEnabled: analyticsEnabled ?? this.analyticsEnabled,
      crashReportingEnabled: crashReportingEnabled ?? this.crashReportingEnabled,
      shareAnonymousData: shareAnonymousData ?? this.shareAnonymousData,
      localDataOnly: localDataOnly ?? this.localDataOnly,
      biometricLockEnabled: biometricLockEnabled ?? this.biometricLockEnabled,
      autoLockTimeout: autoLockTimeout ?? this.autoLockTimeout,
      hideNotificationContent: hideNotificationContent ?? this.hideNotificationContent,
    );
  }
}

/// Scan settings
class ScanSettings {
  final bool autoScanEnabled;
  final int scanFrequencyHours; // Hours between auto scans
  final bool scanOnWifiOnly;
  final bool deepScanEnabled;

  ScanSettings({
    this.autoScanEnabled = true,
    this.scanFrequencyHours = 24,
    this.scanOnWifiOnly = true,
    this.deepScanEnabled = false,
  });

  ScanSettings copyWith({
    bool? autoScanEnabled,
    int? scanFrequencyHours,
    bool? scanOnWifiOnly,
    bool? deepScanEnabled,
  }) {
    return ScanSettings(
      autoScanEnabled: autoScanEnabled ?? this.autoScanEnabled,
      scanFrequencyHours: scanFrequencyHours ?? this.scanFrequencyHours,
      scanOnWifiOnly: scanOnWifiOnly ?? this.scanOnWifiOnly,
      deepScanEnabled: deepScanEnabled ?? this.deepScanEnabled,
    );
  }
}

/// API/Server settings
class ApiSettings {
  final String serverUrl;
  final bool useCustomServer;
  final int connectionTimeout;
  final bool enableWebSocket;
  final String? apiKey;

  ApiSettings({
    this.serverUrl = 'https://guard.orbai.world',
    this.useCustomServer = false,
    this.connectionTimeout = 30,
    this.enableWebSocket = true,
    this.apiKey,
  });

  ApiSettings copyWith({
    String? serverUrl,
    bool? useCustomServer,
    int? connectionTimeout,
    bool? enableWebSocket,
    String? apiKey,
  }) {
    return ApiSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      useCustomServer: useCustomServer ?? this.useCustomServer,
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      enableWebSocket: enableWebSocket ?? this.enableWebSocket,
      apiKey: apiKey ?? this.apiKey,
    );
  }
}

/// Settings Provider
class SettingsProvider extends ChangeNotifier {
  SharedPreferences? _prefs;

  // Settings
  ProtectionSettings _protection = ProtectionSettings();
  NotificationSettings _notifications = NotificationSettings();
  PrivacySettings _privacy = PrivacySettings();
  ScanSettings _scan = ScanSettings();
  ApiSettings _api = ApiSettings();

  bool _isLoading = false;
  String? _error;

  // Appearance — app-wide light/dark/system theme (persisted).
  static const String _kThemeMode = 'app_theme_mode';
  ThemeMode _themeMode = ThemeMode.system;

  // Experience mode — the consumer "Guard" surface (default) vs the opt-in
  // "Pro" expert console (persisted). Gates navigation only; see [AppMode].
  static const String _kAppMode = 'app_mode';
  AppMode _appMode = AppMode.guard;

  // Whether the first-run onboarding has been completed (persisted).
  static const String _kOnboarded = 'onboarding_complete';
  bool _hasSeenOnboarding = false;

  // Getters
  ProtectionSettings get protection => _protection;
  NotificationSettings get notifications => _notifications;
  PrivacySettings get privacy => _privacy;
  ScanSettings get scan => _scan;
  ApiSettings get api => _api;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ThemeMode get themeMode => _themeMode;
  AppMode get appMode => _appMode;
  bool get isProMode => _appMode.isPro;
  bool get hasSeenOnboarding => _hasSeenOnboarding;

  /// Update the app theme mode and persist it.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kThemeMode, mode.name);
  }

  /// Switch between the Guard (consumer) and Pro (expert) experience and
  /// persist it. Navigation-only; no data or screens are removed.
  Future<void> setAppMode(AppMode mode) async {
    if (mode == _appMode) return;
    _appMode = mode;
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kAppMode, mode.name);
  }

  /// Convenience toggle between Guard and Pro.
  Future<void> toggleAppMode() =>
      setAppMode(_appMode.isPro ? AppMode.guard : AppMode.pro);

  /// Mark the first-run onboarding as complete (persisted).
  Future<void> completeOnboarding() async {
    if (_hasSeenOnboarding) return;
    _hasSeenOnboarding = true;
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kOnboarded, true);
  }

  /// Initialize provider
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      _prefs = await SharedPreferences.getInstance();
      _themeMode = _parseThemeMode(_prefs!.getString(_kThemeMode));
      _appMode = AppMode.fromName(_prefs!.getString(_kAppMode));
      _hasSeenOnboarding = _prefs!.getBool(_kOnboarded) ?? false;
      await _loadSettings();
      await _syncNotificationService();
    } catch (e) {
      _error = 'Failed to load settings: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  ThemeMode _parseThemeMode(String? v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// Load settings from storage
  Future<void> _loadSettings() async {
    if (_prefs == null) return;

    // Protection settings
    _protection = ProtectionSettings(
      smsProtectionEnabled: _prefs!.getBool('prot_sms') ?? true,
      urlProtectionEnabled: _prefs!.getBool('prot_url') ?? true,
      qrProtectionEnabled: _prefs!.getBool('prot_qr') ?? true,
      appSecurityEnabled: _prefs!.getBool('prot_app') ?? true,
      networkProtectionEnabled: _prefs!.getBool('prot_network') ?? true,
      darkWebMonitoringEnabled: _prefs!.getBool('prot_darkweb') ?? true,
      realTimeAlertsEnabled: _prefs!.getBool('prot_realtime') ?? true,
      autoBlockThreats: _prefs!.getBool('prot_autoblock') ?? false,
    );

    // Notification settings
    _notifications = NotificationSettings(
      pushNotificationsEnabled: _prefs!.getBool('notif_push') ?? true,
      threatAlertsEnabled: _prefs!.getBool('notif_threats') ?? true,
      breachAlertsEnabled: _prefs!.getBool('notif_breaches') ?? true,
      scanCompletedAlerts: _prefs!.getBool('notif_scan') ?? false,
      soundEnabled: _prefs!.getBool('notif_sound') ?? true,
      vibrationEnabled: _prefs!.getBool('notif_vibration') ?? true,
      quietHoursEnabled: _prefs!.getBool('notif_quiet') ?? false,
      quietHoursStart: _prefs!.getInt('notif_quiet_start') ?? 22,
      quietHoursEnd: _prefs!.getInt('notif_quiet_end') ?? 7,
    );

    // Privacy settings
    _privacy = PrivacySettings(
      analyticsEnabled: _prefs!.getBool('priv_analytics') ?? true,
      crashReportingEnabled: _prefs!.getBool('priv_crash') ?? true,
      shareAnonymousData: _prefs!.getBool('priv_share') ?? false,
      localDataOnly: _prefs!.getBool('priv_local') ?? false,
      biometricLockEnabled: _prefs!.getBool('priv_biometric') ?? false,
      autoLockTimeout: _prefs!.getInt('priv_lock_timeout') ?? 0,
      hideNotificationContent: _prefs!.getBool('priv_hide_notif') ?? false,
    );

    // Scan settings
    _scan = ScanSettings(
      autoScanEnabled: _prefs!.getBool('scan_auto') ?? true,
      scanFrequencyHours: _prefs!.getInt('scan_freq') ?? 24,
      scanOnWifiOnly: _prefs!.getBool('scan_wifi') ?? true,
      deepScanEnabled: _prefs!.getBool('scan_deep') ?? false,
    );

    // API settings
    _api = ApiSettings(
      serverUrl: _prefs!.getString('api_url') ?? 'https://guard.orbai.world',
      useCustomServer: _prefs!.getBool('api_custom') ?? false,
      connectionTimeout: _prefs!.getInt('api_timeout') ?? 30,
      enableWebSocket: _prefs!.getBool('api_websocket') ?? true,
      apiKey: _prefs!.getString('api_key'),
    );
  }

  /// Update protection settings
  Future<void> updateProtection(ProtectionSettings settings) async {
    _protection = settings;
    notifyListeners();

    if (_prefs != null) {
      await _prefs!.setBool('prot_sms', settings.smsProtectionEnabled);
      await _prefs!.setBool('prot_url', settings.urlProtectionEnabled);
      await _prefs!.setBool('prot_qr', settings.qrProtectionEnabled);
      await _prefs!.setBool('prot_app', settings.appSecurityEnabled);
      await _prefs!.setBool('prot_network', settings.networkProtectionEnabled);
      await _prefs!.setBool('prot_darkweb', settings.darkWebMonitoringEnabled);
      await _prefs!.setBool('prot_realtime', settings.realTimeAlertsEnabled);
      await _prefs!.setBool('prot_autoblock', settings.autoBlockThreats);
    }
  }

  /// Update notification settings
  Future<void> updateNotifications(NotificationSettings settings) async {
    _notifications = settings;
    notifyListeners();

    if (_prefs != null) {
      await _prefs!.setBool('notif_push', settings.pushNotificationsEnabled);
      await _prefs!.setBool('notif_threats', settings.threatAlertsEnabled);
      await _prefs!.setBool('notif_breaches', settings.breachAlertsEnabled);
      await _prefs!.setBool('notif_scan', settings.scanCompletedAlerts);
      await _prefs!.setBool('notif_sound', settings.soundEnabled);
      await _prefs!.setBool('notif_vibration', settings.vibrationEnabled);
      await _prefs!.setBool('notif_quiet', settings.quietHoursEnabled);
      await _prefs!.setInt('notif_quiet_start', settings.quietHoursStart);
      await _prefs!.setInt('notif_quiet_end', settings.quietHoursEnd);
    }

    await _syncNotificationService();
  }

  /// Push notification-related settings into [NotificationService] — the
  /// service owns the actual send gate, so without this the Notifications and
  /// Privacy toggles would persist but never change delivery behavior.
  Future<void> _syncNotificationService() async {
    try {
      final n = NotificationService.instance;
      await n.setEnabled(_notifications.pushNotificationsEnabled);
      await n.setSoundEnabled(_notifications.soundEnabled);
      await n.setVibrationEnabled(_notifications.vibrationEnabled);
      await n.setQuietHours(
        enabled: _notifications.quietHoursEnabled,
        start: _notifications.quietHoursStart,
        end: _notifications.quietHoursEnd,
      );
      await n.setCategoryPreferences(
        threatAlerts: _notifications.threatAlertsEnabled,
        breachAlerts: _notifications.breachAlertsEnabled,
        scanAlerts: _notifications.scanCompletedAlerts,
      );
      await n.setHideContent(_privacy.hideNotificationContent);
    } catch (_) {
      // NotificationService unavailable (e.g. tests) — settings still persist.
    }
  }

  /// Update privacy settings
  Future<void> updatePrivacy(PrivacySettings settings) async {
    _privacy = settings;
    notifyListeners();

    if (_prefs != null) {
      await _prefs!.setBool('priv_analytics', settings.analyticsEnabled);
      await _prefs!.setBool('priv_crash', settings.crashReportingEnabled);
      await _prefs!.setBool('priv_share', settings.shareAnonymousData);
      await _prefs!.setBool('priv_local', settings.localDataOnly);
      await _prefs!.setBool('priv_biometric', settings.biometricLockEnabled);
      await _prefs!.setInt('priv_lock_timeout', settings.autoLockTimeout);
      await _prefs!.setBool('priv_hide_notif', settings.hideNotificationContent);
    }

    // Hide-notification-content is enforced by NotificationService.
    await _syncNotificationService();

    // Analytics/crash opt-out toggles gate the telemetry SDKs live.
    await TelemetryService.instance.applyPrivacySettings(
      analyticsEnabled: settings.analyticsEnabled,
      crashEnabled: settings.crashReportingEnabled,
    );
  }

  /// Update scan settings
  Future<void> updateScan(ScanSettings settings) async {
    _scan = settings;
    notifyListeners();

    if (_prefs != null) {
      await _prefs!.setBool('scan_auto', settings.autoScanEnabled);
      await _prefs!.setInt('scan_freq', settings.scanFrequencyHours);
      await _prefs!.setBool('scan_wifi', settings.scanOnWifiOnly);
      await _prefs!.setBool('scan_deep', settings.deepScanEnabled);
    }
  }

  /// Update API settings
  Future<void> updateApi(ApiSettings settings) async {
    _api = settings;
    notifyListeners();

    if (_prefs != null) {
      await _prefs!.setString('api_url', settings.serverUrl);
      await _prefs!.setBool('api_custom', settings.useCustomServer);
      await _prefs!.setInt('api_timeout', settings.connectionTimeout);
      await _prefs!.setBool('api_websocket', settings.enableWebSocket);
      if (settings.apiKey != null) {
        await _prefs!.setString('api_key', settings.apiKey!);
      }
    }
  }

  /// Reset all settings to defaults
  Future<void> resetAllSettings() async {
    _protection = ProtectionSettings();
    _notifications = NotificationSettings();
    _privacy = PrivacySettings();
    _scan = ScanSettings();
    _api = ApiSettings();
    notifyListeners();

    if (_prefs != null) {
      await _prefs!.clear();
    }
  }

  /// Export settings as JSON
  Map<String, dynamic> exportSettings() {
    return {
      'protection': {
        'sms': _protection.smsProtectionEnabled,
        'url': _protection.urlProtectionEnabled,
        'qr': _protection.qrProtectionEnabled,
        'app': _protection.appSecurityEnabled,
        'network': _protection.networkProtectionEnabled,
        'darkweb': _protection.darkWebMonitoringEnabled,
        'realtime': _protection.realTimeAlertsEnabled,
        'autoblock': _protection.autoBlockThreats,
      },
      'notifications': {
        'push': _notifications.pushNotificationsEnabled,
        'threats': _notifications.threatAlertsEnabled,
        'breaches': _notifications.breachAlertsEnabled,
        'scan': _notifications.scanCompletedAlerts,
        'sound': _notifications.soundEnabled,
        'vibration': _notifications.vibrationEnabled,
        'quiet': _notifications.quietHoursEnabled,
        'quietStart': _notifications.quietHoursStart,
        'quietEnd': _notifications.quietHoursEnd,
      },
      'privacy': {
        'analytics': _privacy.analyticsEnabled,
        'crash': _privacy.crashReportingEnabled,
        'share': _privacy.shareAnonymousData,
        'local': _privacy.localDataOnly,
        'biometric': _privacy.biometricLockEnabled,
        'lockTimeout': _privacy.autoLockTimeout,
        'hideNotif': _privacy.hideNotificationContent,
      },
      'scan': {
        'auto': _scan.autoScanEnabled,
        'freq': _scan.scanFrequencyHours,
        'wifi': _scan.scanOnWifiOnly,
        'deep': _scan.deepScanEnabled,
      },
    };
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
