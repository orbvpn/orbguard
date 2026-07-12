/// Threat Stream Service
/// High-level API for managing threat event streams and notifications

import 'dart:async';
import 'dart:collection';

import 'package:shared_preferences/shared_preferences.dart';

import 'websocket_service.dart';
import '../../models/api/threat_indicator.dart';

/// Callback for threat events
typedef ThreatEventCallback = void Function(ThreatEvent event);

/// Callback for connection state changes
typedef ConnectionStateCallback = void Function(WebSocketState state);

/// Threat stream service - manages threat event subscriptions and history
class ThreatStreamService {
  static ThreatStreamService? _instance;
  static ThreatStreamService get instance =>
      _instance ??= ThreatStreamService._();

  ThreatStreamService._();

  final WebSocketService _wsService = WebSocketService.instance;

  // Event history
  final Queue<ThreatEvent> _eventHistory = Queue();
  static const int _maxHistorySize = 100;

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];
  final Map<String, ThreatEventCallback> _eventCallbacks = {};
  final Map<String, ConnectionStateCallback> _stateCallbacks = {};

  // Stats
  int _eventsReceived = 0;
  int _criticalEventsReceived = 0;
  DateTime? _lastEventTime;

  // Persistent storage keys
  static const String _keyEventsReceived = 'threat_stream_events_received';
  static const String _keyCriticalEvents = 'threat_stream_critical_events';

  /// Initialize the threat stream service
  Future<void> init() async {
    // Load stats from storage
    final prefs = await SharedPreferences.getInstance();
    _eventsReceived = prefs.getInt(_keyEventsReceived) ?? 0;
    _criticalEventsReceived = prefs.getInt(_keyCriticalEvents) ?? 0;

    // Subscribe to WebSocket events
    _subscriptions.add(
      _wsService.messageStream.listen(_handleEvent),
    );

    _subscriptions.add(
      _wsService.stateStream.listen(_handleStateChange),
    );
  }

  /// Connect to threat stream
  Future<void> connect() async {
    await _wsService.connect();
  }

  /// Disconnect from threat stream
  Future<void> disconnect() async {
    await _wsService.disconnect();
  }

  /// Check if connected
  bool get isConnected => _wsService.isConnected;

  /// Current connection state
  WebSocketState get connectionState => _wsService.state;

  /// Stream of threat events
  Stream<ThreatEvent> get eventStream => _wsService.messageStream;

  /// Stream of connection state changes
  Stream<WebSocketState> get stateStream => _wsService.stateStream;

  /// Get event history
  List<ThreatEvent> get eventHistory => _eventHistory.toList();

  /// Get recent events (last n)
  List<ThreatEvent> getRecentEvents(int count) {
    return _eventHistory.toList().take(count).toList();
  }

  /// Get critical events from history
  List<ThreatEvent> get criticalEvents {
    return _eventHistory.where((e) => e.isCritical).toList();
  }

  /// Total events received
  int get totalEventsReceived => _eventsReceived;

  /// Critical events received
  int get totalCriticalEventsReceived => _criticalEventsReceived;

  /// Last event time
  DateTime? get lastEventTime => _lastEventTime;

  /// Register a callback for threat events
  String addEventListener(ThreatEventCallback callback) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _eventCallbacks[id] = callback;
    return id;
  }

  /// Remove event listener
  void removeEventListener(String id) {
    _eventCallbacks.remove(id);
  }

  /// Register a callback for connection state changes
  String addStateListener(ConnectionStateCallback callback) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _stateCallbacks[id] = callback;
    return id;
  }

  /// Remove state listener
  void removeStateListener(String id) {
    _stateCallbacks.remove(id);
  }

  /// Subscribe to specific severity levels
  void filterBySeverity(List<SeverityLevel> severities) {
    _wsService.subscribeSeverities(severities.map((s) => s.value).toList());
  }

  /// Subscribe to specific platforms
  void filterByPlatform(List<ThreatPlatform> platforms) {
    _wsService.subscribePlatforms(platforms.map((p) => p.value).toList());
  }

  /// Subscribe to specific campaigns
  void filterByCampaign(List<String> campaignIds) {
    _wsService.subscribeCampaigns(campaignIds);
  }

  /// Clear all filters (receive all events)
  void clearFilters() {
    _wsService.subscribeSeverities([]);
    _wsService.subscribePlatforms([]);
    _wsService.subscribeCampaigns([]);
  }

  /// Clear event history
  void clearHistory() {
    _eventHistory.clear();
  }

  /// Reset statistics
  Future<void> resetStats() async {
    _eventsReceived = 0;
    _criticalEventsReceived = 0;
    _lastEventTime = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyEventsReceived, 0);
    await prefs.setInt(_keyCriticalEvents, 0);
  }

  /// Handle incoming threat event
  void _handleEvent(ThreatEvent event) {
    // Update stats
    _eventsReceived++;
    _lastEventTime = DateTime.now();

    if (event.isCritical) {
      _criticalEventsReceived++;
    }

    // Add to history (newest first)
    _eventHistory.addFirst(event);

    // Trim history if needed
    while (_eventHistory.length > _maxHistorySize) {
      _eventHistory.removeLast();
    }

    // Persist stats periodically (every 10 events)
    if (_eventsReceived % 10 == 0) {
      _persistStats();
    }

    // Notify callbacks
    for (final callback in _eventCallbacks.values) {
      try {
        callback(event);
      } catch (e) {
        print('Error in event callback: $e');
      }
    }
  }

  /// Handle connection state change
  void _handleStateChange(WebSocketState state) {
    for (final callback in _stateCallbacks.values) {
      try {
        callback(state);
      } catch (e) {
        print('Error in state callback: $e');
      }
    }
  }

  /// Persist stats to storage
  Future<void> _persistStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyEventsReceived, _eventsReceived);
      await prefs.setInt(_keyCriticalEvents, _criticalEventsReceived);
    } catch (e) {
      print('Error persisting stats: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _eventCallbacks.clear();
    _stateCallbacks.clear();
    _eventHistory.clear();
  }
}

/// Aggregated threat statistics from stream
class StreamThreatStats {
  final int totalEvents;
  final int criticalEvents;
  final int highEvents;
  final int mediumEvents;
  final int lowEvents;
  final Map<String, int> eventsByType;
  final Map<String, int> eventsByCampaign;
  final DateTime? oldestEvent;
  final DateTime? newestEvent;

  StreamThreatStats({
    required this.totalEvents,
    required this.criticalEvents,
    required this.highEvents,
    required this.mediumEvents,
    required this.lowEvents,
    required this.eventsByType,
    required this.eventsByCampaign,
    this.oldestEvent,
    this.newestEvent,
  });

  /// Calculate stats from event list
  factory StreamThreatStats.fromEvents(List<ThreatEvent> events) {
    int critical = 0, high = 0, medium = 0, low = 0;
    final byType = <String, int>{};
    final byCampaign = <String, int>{};
    DateTime? oldest, newest;

    for (final event in events) {
      // Count by severity
      switch (event.severity) {
        case SeverityLevel.critical:
          critical++;
          break;
        case SeverityLevel.high:
          high++;
          break;
        case SeverityLevel.medium:
          medium++;
          break;
        case SeverityLevel.low:
        case SeverityLevel.info:
          low++;
          break;
        default:
          break;
      }

      // Count by type
      byType[event.type] = (byType[event.type] ?? 0) + 1;

      // Count by campaign
      if (event.campaignId != null) {
        final name = event.campaignName ?? event.campaignId!;
        byCampaign[name] = (byCampaign[name] ?? 0) + 1;
      }

      // Track time range
      if (oldest == null || event.timestamp.isBefore(oldest)) {
        oldest = event.timestamp;
      }
      if (newest == null || event.timestamp.isAfter(newest)) {
        newest = event.timestamp;
      }
    }

    return StreamThreatStats(
      totalEvents: events.length,
      criticalEvents: critical,
      highEvents: high,
      mediumEvents: medium,
      lowEvents: low,
      eventsByType: byType,
      eventsByCampaign: byCampaign,
      oldestEvent: oldest,
      newestEvent: newest,
    );
  }
}
