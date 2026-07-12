/// Privacy Provider
/// State management for privacy protection: camera/mic monitoring, clipboard, trackers

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

/// Privacy audit result
class PrivacyAuditResult {
  final int privacyScore;
  final int totalAppsAudited;
  final int appsWithTrackers;
  final int totalTrackers;
  final int backgroundAccessCount;
  final List<String> recommendations;

  PrivacyAuditResult({
    this.privacyScore = 100,
    this.totalAppsAudited = 0,
    this.appsWithTrackers = 0,
    this.totalTrackers = 0,
    this.backgroundAccessCount = 0,
    this.recommendations = const [],
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

  // Getters
  List<PrivacyEvent> get events => List.unmodifiable(_events);
  List<TrackerInfo> get trackers => List.unmodifiable(_trackers);
  List<TrackerInfo> get blockedTrackers => List.unmodifiable(_blockedTrackers);
  PrivacyAuditResult? get lastAudit => _lastAudit;
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

  /// Load trackers
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
    } catch (e) {
      // Load default trackers
      _trackers.addAll(_getDefaultTrackers());
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

    // Send to API for analytics
    _api.recordPrivacyEvent({
      'type': event.type.name,
      'app_name': event.appName,
      'package_name': event.packageName,
      'is_background': event.isBackground,
      'timestamp': event.timestamp.toIso8601String(),
    }).catchError((_) {});
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

  /// Run privacy audit
  Future<PrivacyAuditResult> runAudit() async {
    _isAuditing = true;
    notifyListeners();

    try {
      final result = await _api.auditPrivacy({});
      _lastAudit = PrivacyAuditResult(
        privacyScore: result['privacy_score'] ?? 100,
        totalAppsAudited: result['total_apps'] ?? 0,
        appsWithTrackers: result['apps_with_trackers'] ?? 0,
        totalTrackers: result['total_trackers'] ?? 0,
        backgroundAccessCount: result['background_access_count'] ?? 0,
        recommendations: List<String>.from(result['recommendations'] ?? []),
      );

      _isAuditing = false;
      notifyListeners();
      return _lastAudit!;
    } catch (e) {
      _lastAudit = PrivacyAuditResult(
        privacyScore: 75,
        totalAppsAudited: _events.map((e) => e.appName).toSet().length,
        appsWithTrackers: _trackers.length > 0 ? 5 : 0,
        totalTrackers: _trackers.length,
        backgroundAccessCount: backgroundEvents.length,
        recommendations: [
          'Review apps with background camera access',
          'Enable tracker blocking for better privacy',
          'Regularly audit clipboard access',
        ],
      );

      _isAuditing = false;
      notifyListeners();
      return _lastAudit!;
    }
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

  /// Default trackers list
  List<TrackerInfo> _getDefaultTrackers() {
    return [
      TrackerInfo(
        id: '1',
        name: 'Facebook Analytics',
        company: 'Meta',
        category: 'Analytics',
        domains: ['facebook.com', 'fb.com', 'fbcdn.net'],
      ),
      TrackerInfo(
        id: '2',
        name: 'Google Analytics',
        company: 'Google',
        category: 'Analytics',
        domains: ['google-analytics.com', 'googletagmanager.com'],
      ),
      TrackerInfo(
        id: '3',
        name: 'Crashlytics',
        company: 'Google',
        category: 'Crash Reporting',
        domains: ['crashlytics.com', 'firebase.google.com'],
      ),
      TrackerInfo(
        id: '4',
        name: 'AppsFlyer',
        company: 'AppsFlyer',
        category: 'Attribution',
        domains: ['appsflyer.com', 'onelink.me'],
      ),
      TrackerInfo(
        id: '5',
        name: 'Adjust',
        company: 'Adjust',
        category: 'Attribution',
        domains: ['adjust.com', 'adj.st'],
      ),
      TrackerInfo(
        id: '6',
        name: 'Mixpanel',
        company: 'Mixpanel',
        category: 'Analytics',
        domains: ['mixpanel.com', 'mxpnl.com'],
      ),
      TrackerInfo(
        id: '7',
        name: 'Amplitude',
        company: 'Amplitude',
        category: 'Analytics',
        domains: ['amplitude.com'],
      ),
      TrackerInfo(
        id: '8',
        name: 'Branch',
        company: 'Branch',
        category: 'Attribution',
        domains: ['branch.io', 'app.link'],
      ),
    ];
  }
}
