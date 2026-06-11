// Privacy Provider
// State management for privacy protection: camera/mic monitoring, clipboard, trackers

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../services/api/orbguard_api_client.dart';

/// Privacy event type
enum PrivacyEventType {
  cameraAccess('Camera Access'),
  microphoneAccess('Microphone Access'),
  clipboardRead('Clipboard Read'),
  clipboardWrite('Clipboard Write'),
  locationAccess('Location Access'),
  contactsAccess('Contacts Access'),
  screenCapture('Screen Capture');

  final String displayName;
  const PrivacyEventType(this.displayName);
}

/// Privacy event
class PrivacyEvent {
  final String id;
  final PrivacyEventType type;
  final String appName;
  final String? packageName;
  final DateTime timestamp;
  final bool isBackground;
  final String? additionalInfo;

  PrivacyEvent({
    required this.id,
    required this.type,
    required this.appName,
    this.packageName,
    required this.timestamp,
    this.isBackground = false,
    this.additionalInfo,
  });
}

/// Tracker info
class TrackerInfo {
  final String id;
  final String name;
  final String company;
  final String category;
  final String? description;
  final List<String> domains;
  final bool isBlocked;

  TrackerInfo({
    required this.id,
    required this.name,
    required this.company,
    required this.category,
    this.description,
    this.domains = const [],
    this.isBlocked = false,
  });
}

/// Clipboard check result
class ClipboardCheckResult {
  final String content;
  final bool isSuspicious;
  final String? threatType;
  final String? description;

  ClipboardCheckResult({
    required this.content,
    this.isSuspicious = false,
    this.threatType,
    this.description,
  });
}

/// Privacy audit result (computed by the backend /privacy/audit endpoint
/// from the real per-app access data recorded on this device).
class PrivacyAuditResult {
  final int privacyScore;
  final String? grade;
  final String? riskLevel;
  final int totalAppsAudited;
  final int appsWithTrackers;
  final int totalTrackers;
  final int backgroundAccessCount;
  final List<String> recommendations;
  final List<String> issues;

  PrivacyAuditResult({
    required this.privacyScore,
    this.grade,
    this.riskLevel,
    this.totalAppsAudited = 0,
    this.appsWithTrackers = 0,
    this.totalTrackers = 0,
    this.backgroundAccessCount = 0,
    this.recommendations = const [],
    this.issues = const [],
  });
}

/// Privacy Provider
class PrivacyProvider extends ChangeNotifier {
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // State
  final List<PrivacyEvent> _events = [];
  final List<TrackerInfo> _trackers = [];
  final List<TrackerInfo> _blockedTrackers = [];
  PrivacyAuditResult? _lastAudit;

  bool _isLoading = false;
  bool _isAuditing = false;
  bool _cameraMonitoringEnabled = true;
  bool _micMonitoringEnabled = true;
  bool _clipboardProtectionEnabled = true;
  bool _trackerBlockingEnabled = true;
  String? _error;
  String? _trackersLoadError;
  String? _auditUnavailableReason;

  // Getters
  List<PrivacyEvent> get events => List.unmodifiable(_events);
  List<TrackerInfo> get trackers => List.unmodifiable(_trackers);
  List<TrackerInfo> get blockedTrackers => List.unmodifiable(_blockedTrackers);
  PrivacyAuditResult? get lastAudit => _lastAudit;

  /// Set when the tracker catalogue could not be loaded from the backend;
  /// [trackers] is empty in that case (never a fabricated list).
  String? get trackersLoadError => _trackersLoadError;

  /// Set when the last audit attempt could not produce a real result
  /// (offline backend, unregistered device, or no recorded privacy data).
  String? get auditUnavailableReason => _auditUnavailableReason;

  bool get isLoading => _isLoading;
  bool get isAuditing => _isAuditing;
  bool get cameraMonitoringEnabled => _cameraMonitoringEnabled;
  bool get micMonitoringEnabled => _micMonitoringEnabled;
  bool get clipboardProtectionEnabled => _clipboardProtectionEnabled;
  bool get trackerBlockingEnabled => _trackerBlockingEnabled;
  String? get error => _error;

  /// Recent camera events
  List<PrivacyEvent> get recentCameraEvents => _events
      .where((e) => e.type == PrivacyEventType.cameraAccess)
      .take(10)
      .toList();

  /// Recent microphone events
  List<PrivacyEvent> get recentMicEvents => _events
      .where((e) => e.type == PrivacyEventType.microphoneAccess)
      .take(10)
      .toList();

  /// Background access events
  List<PrivacyEvent> get backgroundEvents =>
      _events.where((e) => e.isBackground).toList();

  /// Initialize provider
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      await Future.wait([
        loadTrackers(),
        loadRecentEvents(),
      ]);
    } catch (e) {
      _error = 'Failed to initialize: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load trackers from the live backend.
  ///
  /// On failure the catalogue stays empty and [trackersLoadError] is set —
  /// no hardcoded fallback list is presented as live data.
  Future<void> loadTrackers() async {
    try {
      final data = await _api.getTrackers();
      _trackers.clear();

      for (final tracker in data) {
        _trackers.add(TrackerInfo(
          id: tracker.id,
          name: tracker.name,
          company: tracker.company ?? 'Unknown',
          category: tracker.category,
          description: tracker.description,
          domains: tracker.domains ?? [],
          isBlocked: false,
        ));
      }

      _blockedTrackers.clear();
      _blockedTrackers.addAll(_trackers.where((t) => t.isBlocked));
      _trackersLoadError = null;
    } catch (e) {
      _trackers.clear();
      _blockedTrackers.clear();
      _trackersLoadError = 'Tracker catalogue unavailable: $e';
      debugPrint('PrivacyProvider: $_trackersLoadError');
    }
    notifyListeners();
  }

  /// Load recent events
  Future<void> loadRecentEvents() async {
    // Events are recorded locally on device
    // This would typically load from local storage
  }

  /// Record privacy event
  void recordEvent(PrivacyEvent event) {
    _events.insert(0, event);
    if (_events.length > 1000) {
      _events.removeLast();
    }
    notifyListeners();

    // Send to API for analytics; failures are logged, not silently dropped.
    _api.recordPrivacyEvent({
      'type': event.type.name,
      'app_name': event.appName,
      'package_name': event.packageName,
      'is_background': event.isBackground,
      'timestamp': event.timestamp.toIso8601String(),
    }).catchError((Object e) {
      debugPrint('PrivacyProvider: failed to record privacy event: $e');
      return false;
    });
  }

  /// Check clipboard for threats
  Future<ClipboardCheckResult> checkClipboard(String content) async {
    try {
      final result = await _api.checkClipboard(content);
      return ClipboardCheckResult(
        content: content,
        isSuspicious: result['is_suspicious'] ?? false,
        threatType: result['threat_type'],
        description: result['description'],
      );
    } catch (e) {
      // Local check for crypto address swapping
      final cryptoPatterns = [
        RegExp(r'^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$'), // Bitcoin
        RegExp(r'^0x[a-fA-F0-9]{40}$'), // Ethereum
        RegExp(r'^[LM3][a-km-zA-HJ-NP-Z1-9]{26,33}$'), // Litecoin
      ];

      for (final pattern in cryptoPatterns) {
        if (pattern.hasMatch(content)) {
          return ClipboardCheckResult(
            content: content,
            isSuspicious: true,
            threatType: 'crypto_address',
            description: 'Cryptocurrency address detected - verify before use',
          );
        }
      }

      return ClipboardCheckResult(content: content);
    }
  }

  /// Check if domain should be blocked
  Future<bool> shouldBlockDomain(String domain) async {
    if (!_trackerBlockingEnabled) return false;

    // Check local blocklist first
    for (final tracker in _blockedTrackers) {
      if (tracker.domains.any((d) => domain.contains(d) || d.contains(domain))) {
        return true;
      }
    }

    // Check with API
    try {
      return await _api.shouldBlockDomain(domain);
    } catch (e) {
      return false;
    }
  }

  /// Run a privacy audit against the live backend
  /// (POST /privacy/audit, models.PrivacyAuditResult).
  ///
  /// The request is built exclusively from the real per-app access events
  /// recorded on this device. When no real data or no backend result is
  /// available the audit is reported as unavailable
  /// ([auditUnavailableReason]) and null is returned — never a fabricated
  /// score.
  Future<PrivacyAuditResult?> runAudit() async {
    _isAuditing = true;
    _auditUnavailableReason = null;
    _error = null;
    notifyListeners();

    if (_events.isEmpty) {
      _auditUnavailableReason =
          'Privacy audit unavailable: no camera/microphone/clipboard access '
          'events have been recorded on this device yet, so there is no real '
          'data to audit.';
      _isAuditing = false;
      notifyListeners();
      return null;
    }

    final deviceId = await _resolveDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      _auditUnavailableReason =
          'Privacy audit unavailable: this device has no stable device '
          'identifier, which the audit endpoint requires.';
      _isAuditing = false;
      notifyListeners();
      return null;
    }

    try {
      final result = await _api.auditPrivacy({
        'device_id': deviceId,
        'apps': _buildAppPrivacyInfo(),
      });

      final issues = (result['issues'] as List<dynamic>? ?? const [])
          .map((i) => (i as Map)['title']?.toString() ?? '')
          .where((t) => t.isNotEmpty)
          .toList();
      final riskyApps = result['risky_apps'] as List<dynamic>? ?? const [];

      _lastAudit = PrivacyAuditResult(
        privacyScore:
            ((result['overall_score'] as num?)?.toDouble() ?? 0).round(),
        grade: result['overall_grade'] as String?,
        riskLevel: result['risk_level'] as String?,
        totalAppsAudited: _appNamesWithEvents().length,
        appsWithTrackers: riskyApps
            .where((a) => ((a as Map)['tracker_count'] as num? ?? 0) > 0)
            .length,
        totalTrackers: (result['tracker_count'] as num?)?.toInt() ?? 0,
        backgroundAccessCount: backgroundEvents.length,
        recommendations:
            List<String>.from(result['recommendations'] ?? const []),
        issues: issues,
      );

      _isAuditing = false;
      notifyListeners();
      return _lastAudit;
    } catch (e) {
      _auditUnavailableReason = 'Privacy audit unavailable: $e';
      _error = _auditUnavailableReason;
      debugPrint('PrivacyProvider: $_auditUnavailableReason');
      _isAuditing = false;
      notifyListeners();
      return null;
    }
  }

  /// Distinct app names observed in recorded events.
  Set<String> _appNamesWithEvents() =>
      _events.map((e) => e.packageName ?? e.appName).toSet();

  /// Aggregate the recorded on-device privacy events into the
  /// models.AppPrivacyInfo shape the backend audit expects. Only fields that
  /// were genuinely measured on this device are included.
  List<Map<String, dynamic>> _buildAppPrivacyInfo() {
    final byApp = <String, List<PrivacyEvent>>{};
    for (final event in _events) {
      final key = event.packageName ?? event.appName;
      byApp.putIfAbsent(key, () => []).add(event);
    }

    Map<String, dynamic> accessSummary(
      List<PrivacyEvent> appEvents,
      bool Function(PrivacyEventType) matches,
    ) {
      final relevant = appEvents.where((e) => matches(e.type)).toList();
      final background = relevant.where((e) => e.isBackground).length;
      DateTime? last;
      for (final e in relevant) {
        if (last == null || e.timestamp.isAfter(last)) last = e.timestamp;
      }
      return {
        'total_access': relevant.length,
        'background_use': background,
        if (last != null) 'last_access': last.toUtc().toIso8601String(),
        'is_granted': relevant.isNotEmpty,
        'was_denied': false,
      };
    }

    final apps = <Map<String, dynamic>>[];
    byApp.forEach((key, appEvents) {
      DateTime lastActivity = appEvents.first.timestamp;
      for (final e in appEvents) {
        if (e.timestamp.isAfter(lastActivity)) lastActivity = e.timestamp;
      }
      apps.add({
        'package_name': appEvents.first.packageName ?? key,
        'app_name': appEvents.first.appName,
        'camera_access': accessSummary(
            appEvents, (t) => t == PrivacyEventType.cameraAccess),
        'microphone_access': accessSummary(
            appEvents, (t) => t == PrivacyEventType.microphoneAccess),
        'location_access': accessSummary(
            appEvents, (t) => t == PrivacyEventType.locationAccess),
        'clipboard_access': accessSummary(
            appEvents,
            (t) =>
                t == PrivacyEventType.clipboardRead ||
                t == PrivacyEventType.clipboardWrite),
        'background_activity':
            appEvents.where((e) => e.isBackground).length,
        'last_activity': lastActivity.toUtc().toIso8601String(),
      });
    });
    return apps;
  }

  /// Resolve the same stable device identifier the API client registers with
  /// (the audit endpoint requires it; the client does not expose its own).
  Future<String?> _resolveDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        return (await deviceInfo.androidInfo).id;
      } else if (Platform.isIOS) {
        return (await deviceInfo.iosInfo).identifierForVendor;
      } else if (Platform.isMacOS) {
        return (await deviceInfo.macOsInfo).systemGUID;
      } else if (Platform.isWindows) {
        return (await deviceInfo.windowsInfo).deviceId;
      } else if (Platform.isLinux) {
        return (await deviceInfo.linuxInfo).machineId;
      }
    } catch (e) {
      debugPrint('PrivacyProvider: failed to resolve device id: $e');
    }
    return null;
  }

  /// Toggle tracker blocking
  void toggleTrackerBlocking(String trackerId) {
    final index = _trackers.indexWhere((t) => t.id == trackerId);
    if (index >= 0) {
      final tracker = _trackers[index];
      _trackers[index] = TrackerInfo(
        id: tracker.id,
        name: tracker.name,
        company: tracker.company,
        category: tracker.category,
        description: tracker.description,
        domains: tracker.domains,
        isBlocked: !tracker.isBlocked,
      );

      _blockedTrackers.clear();
      _blockedTrackers.addAll(_trackers.where((t) => t.isBlocked));
      notifyListeners();
    }
  }

  /// Update monitoring settings
  void setCameraMonitoring(bool enabled) {
    _cameraMonitoringEnabled = enabled;
    notifyListeners();
  }

  void setMicMonitoring(bool enabled) {
    _micMonitoringEnabled = enabled;
    notifyListeners();
  }

  void setClipboardProtection(bool enabled) {
    _clipboardProtectionEnabled = enabled;
    notifyListeners();
  }

  void setTrackerBlocking(bool enabled) {
    _trackerBlockingEnabled = enabled;
    notifyListeners();
  }

  /// Clear events
  void clearEvents() {
    _events.clear();
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
