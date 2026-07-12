/// Realtime Provider
/// Flutter state management for real-time threat stream

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/realtime/websocket_service.dart';
import '../services/realtime/threat_stream.dart';
import '../services/realtime/connection_manager.dart';
import '../models/api/threat_indicator.dart';

/// Provider for real-time threat stream state management
class RealtimeProvider extends ChangeNotifier {
  final ConnectionManager _connectionManager = ConnectionManager.instance;
  final ThreatStreamService _streamService = ThreatStreamService.instance;

  // Subscriptions
  StreamSubscription? _stateSubscription;
  StreamSubscription? _eventSubscription;

  // State
  WebSocketState _connectionState = WebSocketState.disconnected;
  bool _isInitialized = false;
  bool _autoConnect = true;
  List<ThreatEvent> _recentEvents = [];
  ThreatEvent? _lastEvent;
  int _unreadCount = 0;
  String? _errorMessage;

  // Filters
  Set<SeverityLevel> _severityFilter = {};
  Set<ThreatPlatform> _platformFilter = {};

  /// Current connection state
  WebSocketState get connectionState => _connectionState;

  /// Check if connected
  bool get isConnected => _connectionState == WebSocketState.connected;

  /// Check if connecting
  bool get isConnecting =>
      _connectionState == WebSocketState.connecting ||
      _connectionState == WebSocketState.reconnecting;

  /// Check if there's an error
  bool get hasError => _connectionState == WebSocketState.error;

  /// Error message if any
  String? get errorMessage => _errorMessage;

  /// Auto-connect setting
  bool get autoConnect => _autoConnect;

  /// Recent threat events
  List<ThreatEvent> get recentEvents => List.unmodifiable(_recentEvents);

  /// Last received event
  ThreatEvent? get lastEvent => _lastEvent;

  /// Unread event count
  int get unreadCount => _unreadCount;

  /// Severity filter
  Set<SeverityLevel> get severityFilter => Set.unmodifiable(_severityFilter);

  /// Platform filter
  Set<ThreatPlatform> get platformFilter => Set.unmodifiable(_platformFilter);

  /// Total events received
  int get totalEventsReceived => _streamService.totalEventsReceived;

  /// Critical events received
  int get criticalEventsReceived => _streamService.totalCriticalEventsReceived;

  /// Connection health
  ConnectionHealth get connectionHealth =>
      _connectionManager.getConnectionHealth();

  /// Initialize the provider
  Future<void> init() async {
    if (_isInitialized) return;

    await _connectionManager.init();
    _autoConnect = _connectionManager.autoConnect;

    // Subscribe to state changes
    _stateSubscription = _connectionManager.stateStream.listen(_onStateChanged);

    // Subscribe to events
    _eventSubscription = _connectionManager.eventStream.listen(_onEventReceived);

    // Load initial state
    _connectionState = _connectionManager.connectionState;
    _recentEvents = _streamService.getRecentEvents(20);

    _isInitialized = true;
    notifyListeners();
  }

  /// Connect to threat stream
  Future<void> connect() async {
    _errorMessage = null;
    notifyListeners();
    await _connectionManager.connect();
  }

  /// Disconnect from threat stream
  Future<void> disconnect() async {
    await _connectionManager.disconnect();
  }

  /// Set auto-connect
  Future<void> setAutoConnect(bool value) async {
    _autoConnect = value;
    await _connectionManager.setAutoConnect(value);
    notifyListeners();
  }

  /// Toggle connection
  Future<void> toggleConnection() async {
    if (isConnected) {
      await disconnect();
    } else {
      await connect();
    }
  }

  /// Set severity filter
  void setSeverityFilter(Set<SeverityLevel> severities) {
    _severityFilter = Set.from(severities);
    _streamService.filterBySeverity(severities.toList());
    notifyListeners();
  }

  /// Add severity to filter
  void addSeverityFilter(SeverityLevel severity) {
    _severityFilter.add(severity);
    _streamService.filterBySeverity(_severityFilter.toList());
    notifyListeners();
  }

  /// Remove severity from filter
  void removeSeverityFilter(SeverityLevel severity) {
    _severityFilter.remove(severity);
    _streamService.filterBySeverity(_severityFilter.toList());
    notifyListeners();
  }

  /// Set platform filter
  void setPlatformFilter(Set<ThreatPlatform> platforms) {
    _platformFilter = Set.from(platforms);
    _streamService.filterByPlatform(platforms.toList());
    notifyListeners();
  }

  /// Clear all filters
  void clearFilters() {
    _severityFilter.clear();
    _platformFilter.clear();
    _streamService.clearFilters();
    notifyListeners();
  }

  /// Mark events as read
  void markAsRead() {
    _unreadCount = 0;
    notifyListeners();
  }

  /// Clear event history
  void clearHistory() {
    _streamService.clearHistory();
    _recentEvents.clear();
    _lastEvent = null;
    notifyListeners();
  }

  /// Reset statistics
  Future<void> resetStats() async {
    await _streamService.resetStats();
    notifyListeners();
  }

  /// Get events filtered by severity
  List<ThreatEvent> getEventsBySeverity(SeverityLevel severity) {
    return _recentEvents.where((e) => e.severity == severity).toList();
  }

  /// Get critical events
  List<ThreatEvent> get criticalEvents {
    return _recentEvents.where((e) => e.isCritical).toList();
  }

  /// Get event statistics
  StreamThreatStats getEventStats() {
    return StreamThreatStats.fromEvents(_recentEvents);
  }

  /// Handle connection state change
  void _onStateChanged(WebSocketState state) {
    _connectionState = state;

    if (state == WebSocketState.error) {
      _errorMessage = 'Connection error. Will retry automatically.';
    } else {
      _errorMessage = null;
    }

    notifyListeners();
  }

  /// Handle incoming event
  void _onEventReceived(ThreatEvent event) {
    _lastEvent = event;
    _unreadCount++;

    // Update recent events (keep last 50)
    _recentEvents.insert(0, event);
    if (_recentEvents.length > 50) {
      _recentEvents = _recentEvents.take(50).toList();
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _eventSubscription?.cancel();
    super.dispose();
  }
}

/// Extension for easier access to connection state
extension WebSocketStateExtension on WebSocketState {
  /// Get display name
  String get displayName {
    switch (this) {
      case WebSocketState.connected:
        return 'Connected';
      case WebSocketState.connecting:
        return 'Connecting';
      case WebSocketState.reconnecting:
        return 'Reconnecting';
      case WebSocketState.disconnected:
        return 'Disconnected';
      case WebSocketState.error:
        return 'Error';
    }
  }

  /// Get icon name (for Material icons)
  String get iconName {
    switch (this) {
      case WebSocketState.connected:
        return 'cloud_done';
      case WebSocketState.connecting:
      case WebSocketState.reconnecting:
        return 'cloud_sync';
      case WebSocketState.disconnected:
        return 'cloud_off';
      case WebSocketState.error:
        return 'error_outline';
    }
  }

  /// Get status color (as int for Color)
  int get statusColor {
    switch (this) {
      case WebSocketState.connected:
        return 0xFF4CAF50; // Green
      case WebSocketState.connecting:
      case WebSocketState.reconnecting:
        return 0xFFFFC107; // Amber
      case WebSocketState.disconnected:
        return 0xFF9E9E9E; // Grey
      case WebSocketState.error:
        return 0xFFF44336; // Red
    }
  }
}

/// Lightweight notifier for connection status only
class ConnectionStatusNotifier extends ChangeNotifier {
  final ConnectionManager _manager = ConnectionManager.instance;
  StreamSubscription? _subscription;

  WebSocketState _state = WebSocketState.disconnected;
  bool _hasNetwork = false;

  WebSocketState get state => _state;
  bool get hasNetwork => _hasNetwork;
  bool get isConnected => _state == WebSocketState.connected;

  void init() {
    _subscription = _manager.stateStream.listen((state) {
      _state = state;
      _hasNetwork = _manager.getConnectionHealth().hasNetwork;
      notifyListeners();
    });

    _state = _manager.connectionState;
    _hasNetwork = _manager.getConnectionHealth().hasNetwork;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
