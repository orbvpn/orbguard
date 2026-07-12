/// Dashboard Provider
/// State management for dashboard data with API integration

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/api/orbguard_api_client.dart';
import '../services/realtime/connection_manager.dart';
import '../services/realtime/websocket_service.dart';
import '../models/api/threat_stats.dart';
import '../models/api/threat_indicator.dart';

/// Dashboard data loading state
enum DashboardLoadState {
  initial,
  loading,
  loaded,
  error,
  refreshing,
}

/// Provider for dashboard state management
class DashboardProvider extends ChangeNotifier {
  final OrbGuardApiClient _apiClient = OrbGuardApiClient.instance;
  final ConnectionManager _connectionManager = ConnectionManager.instance;

  // Loading state
  DashboardLoadState _loadState = DashboardLoadState.initial;
  String? _errorMessage;
  DateTime? _lastRefresh;

  // Data
  DashboardSummary? _summary;
  ThreatStats? _stats;
  ProtectionStatus? _protectionStatus;
  List<RecentAlert> _recentAlerts = [];
  List<ThreatEvent> _realtimeEvents = [];

  // Real-time connection
  StreamSubscription? _eventSubscription;
  StreamSubscription? _stateSubscription;
  WebSocketState _connectionState = WebSocketState.disconnected;

  // Auto-refresh timer
  Timer? _refreshTimer;
  static const Duration _autoRefreshInterval = Duration(minutes: 5);

  // Getters
  DashboardLoadState get loadState => _loadState;
  String? get errorMessage => _errorMessage;
  DateTime? get lastRefresh => _lastRefresh;
  bool get isLoading =>
      _loadState == DashboardLoadState.loading ||
      _loadState == DashboardLoadState.refreshing;
  bool get hasError => _loadState == DashboardLoadState.error;
  bool get hasData => _summary != null || _stats != null;

  DashboardSummary? get summary => _summary;
  ThreatStats? get stats => _stats;
  ProtectionStatus? get protectionStatus => _protectionStatus;
  List<RecentAlert> get recentAlerts => List.unmodifiable(_recentAlerts);
  List<ThreatEvent> get realtimeEvents => List.unmodifiable(_realtimeEvents);

  // Connection state
  WebSocketState get connectionState => _connectionState;
  bool get isConnected => _connectionState == WebSocketState.connected;
  ConnectionHealth get connectionHealth => _connectionManager.getConnectionHealth();

  // Protection overview shortcuts
  bool get isProtected => _summary?.protection.isProtected ?? false;
  double get protectionScore => _summary?.protection.protectionScore ?? 0.0;
  String get protectionGrade => _summary?.protection.protectionGrade ?? 'U';

  // Threat overview shortcuts
  int get threatsBlockedToday => _summary?.threats.threatsBlockedToday ?? 0;
  int get threatsBlockedWeek => _summary?.threats.threatsBlockedWeek ?? 0;
  int get activeCampaigns =>
      _summary?.threats.activeCampaignsTargetingDevice ?? 0;
  int get highSeverityThreats => _summary?.threats.highSeverityThreats ?? 0;

  // Device health shortcuts
  DeviceHealthStatus? get deviceHealth => _summary?.deviceHealth;
  bool get deviceIsHealthy => deviceHealth?.isHealthy ?? false;
  double get deviceHealthScore => deviceHealth?.overallScore ?? 0.0;

  /// Initialize the provider
  Future<void> init() async {
    // Initialize connection manager first
    await _connectionManager.init();

    // Subscribe to real-time events
    _eventSubscription = _connectionManager.eventStream.listen(_onEventReceived);
    _stateSubscription =
        _connectionManager.stateStream.listen(_onConnectionStateChanged);

    _connectionState = _connectionManager.connectionState;

    // Load initial data
    await refresh();

    // Start auto-refresh
    _startAutoRefresh();
  }

  /// Refresh all dashboard data
  Future<void> refresh({bool silent = false}) async {
    if (_loadState == DashboardLoadState.loading) return;

    _loadState =
        silent ? DashboardLoadState.refreshing : DashboardLoadState.loading;
    _errorMessage = null;
    if (!silent) notifyListeners();

    try {
      // Fetch data in parallel
      final results = await Future.wait([
        _fetchDashboardSummary(),
        _fetchThreatStats(),
        _fetchProtectionStatus(),
        _fetchRecentAlerts(),
      ]);

      _summary = results[0] as DashboardSummary?;
      _stats = results[1] as ThreatStats?;
      _protectionStatus = results[2] as ProtectionStatus?;
      _recentAlerts = results[3] as List<RecentAlert>? ?? [];

      _loadState = DashboardLoadState.loaded;
      _lastRefresh = DateTime.now();
    } catch (e) {
      _loadState = DashboardLoadState.error;
      _errorMessage = e.toString();
      debugPrint('Dashboard refresh error: $e');
    }

    notifyListeners();
  }

  /// Fetch dashboard summary
  Future<DashboardSummary?> _fetchDashboardSummary() async {
    try {
      return await _apiClient.getDashboardSummary();
    } catch (e) {
      debugPrint('Failed to fetch dashboard summary: $e');
      return null;
    }
  }

  /// Fetch threat stats
  Future<ThreatStats?> _fetchThreatStats() async {
    try {
      return await _apiClient.getStats();
    } catch (e) {
      debugPrint('Failed to fetch threat stats: $e');
      return null;
    }
  }

  /// Fetch protection status
  Future<ProtectionStatus?> _fetchProtectionStatus() async {
    try {
      return await _apiClient.getProtectionStatus();
    } catch (e) {
      debugPrint('Failed to fetch protection status: $e');
      return null;
    }
  }

  /// Fetch recent alerts
  Future<List<RecentAlert>> _fetchRecentAlerts() async {
    try {
      final summary = await _apiClient.getDashboardSummary();
      return summary?.recentAlerts ?? [];
    } catch (e) {
      debugPrint('Failed to fetch recent alerts: $e');
      return [];
    }
  }

  /// Mark alert as read
  Future<void> markAlertAsRead(String alertId) async {
    final index = _recentAlerts.indexWhere((a) => a.id == alertId);
    if (index == -1) return;

    // Optimistic update
    _recentAlerts = List.from(_recentAlerts);
    // Note: Would update isRead if RecentAlert was mutable

    notifyListeners();

    try {
      await _apiClient.markAlertAsRead(alertId);
    } catch (e) {
      debugPrint('Failed to mark alert as read: $e');
    }
  }

  /// Clear all alerts
  Future<void> clearAllAlerts() async {
    _recentAlerts = [];
    notifyListeners();

    try {
      await _apiClient.clearAllAlerts();
    } catch (e) {
      debugPrint('Failed to clear alerts: $e');
    }
  }

  /// Connect to real-time stream
  Future<void> connectRealtime() async {
    await _connectionManager.connect();
  }

  /// Disconnect from real-time stream
  Future<void> disconnectRealtime() async {
    await _connectionManager.disconnect();
  }

  /// Handle incoming real-time event
  void _onEventReceived(ThreatEvent event) {
    // Add to recent events (keep last 20)
    _realtimeEvents = [event, ..._realtimeEvents.take(19)];

    // Update threat counts if critical
    if (event.isCritical) {
      // Trigger silent refresh to update stats
      refresh(silent: true);
    }

    notifyListeners();
  }

  /// Handle connection state change
  void _onConnectionStateChanged(WebSocketState state) {
    _connectionState = state;
    notifyListeners();
  }

  /// Start auto-refresh timer
  void _startAutoRefresh() {
    _stopAutoRefresh();
    _refreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      refresh(silent: true);
    });
  }

  /// Stop auto-refresh timer
  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Get feature status by name
  FeatureStatus? getFeatureStatus(String name) {
    final protection = _summary?.protection;
    if (protection == null) return null;

    switch (name.toLowerCase()) {
      case 'sms':
        return protection.smsProtection;
      case 'web':
        return protection.webProtection;
      case 'app':
        return protection.appProtection;
      case 'network':
        return protection.networkProtection;
      case 'vpn':
        return protection.vpnProtection;
      default:
        return null;
    }
  }

  /// Get threats by severity
  int getThreatsBySeverity(SeverityLevel severity) {
    return _stats?.getCountBySeverity(severity) ?? 0;
  }

  /// Get indicators by type
  int getIndicatorsByType(IndicatorType type) {
    return _stats?.getCountByType(type) ?? 0;
  }

  /// Calculate time since last refresh
  String? get timeSinceRefresh {
    if (_lastRefresh == null) return null;

    final diff = DateTime.now().difference(_lastRefresh!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    _eventSubscription?.cancel();
    _stateSubscription?.cancel();
    super.dispose();
  }
}

/// Lightweight provider for protection status only
class ProtectionStatusProvider extends ChangeNotifier {
  final OrbGuardApiClient _apiClient = OrbGuardApiClient.instance;

  ProtectionStatus? _status;
  bool _isLoading = false;

  ProtectionStatus? get status => _status;
  bool get isLoading => _isLoading;
  bool get isProtected => _status?.isActive ?? false;
  double get score => _status?.score ?? 0.0;
  String get grade => _status?.grade ?? 'U';

  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    try {
      _status = await _apiClient.getProtectionStatus();
    } catch (e) {
      debugPrint('Protection status error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }
}

/// Provider for threat statistics only
class ThreatStatsProvider extends ChangeNotifier {
  final OrbGuardApiClient _apiClient = OrbGuardApiClient.instance;

  ThreatStats? _stats;
  bool _isLoading = false;

  ThreatStats? get stats => _stats;
  bool get isLoading => _isLoading;

  int get totalIndicators => _stats?.totalIndicators ?? 0;
  int get activeIndicators => _stats?.activeIndicators ?? 0;
  int get indicatorsLast24h => _stats?.indicatorsLast24h ?? 0;
  int get criticalCount => _stats?.getCountBySeverity(SeverityLevel.critical) ?? 0;
  int get highCount => _stats?.getCountBySeverity(SeverityLevel.high) ?? 0;

  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    try {
      _stats = await _apiClient.getStats();
    } catch (e) {
      debugPrint('Threat stats error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }
}
