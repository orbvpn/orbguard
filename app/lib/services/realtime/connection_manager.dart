/// Connection Manager
/// Manages WebSocket connection lifecycle, network monitoring, and auto-reconnection

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'websocket_service.dart';
import 'threat_stream.dart';

/// Connection manager for handling network changes and connection lifecycle
class ConnectionManager {
  static ConnectionManager? _instance;
  static ConnectionManager get instance => _instance ??= ConnectionManager._();

  ConnectionManager._();

  final WebSocketService _wsService = WebSocketService.instance;
  final ThreatStreamService _streamService = ThreatStreamService.instance;
  final Connectivity _connectivity = Connectivity();

  StreamSubscription? _connectivitySubscription;
  Timer? _healthCheckTimer;

  bool _autoConnect = true;
  bool _isInitialized = false;
  List<ConnectivityResult> _lastConnectivity = [];
  DateTime? _lastHealthCheck;

  // Configuration
  static const int _healthCheckIntervalSeconds = 60;
  static const String _keyAutoConnect = 'connection_auto_connect';

  /// Initialize connection manager
  Future<void> init() async {
    if (_isInitialized) return;

    // Load preferences
    final prefs = await SharedPreferences.getInstance();
    _autoConnect = prefs.getBool(_keyAutoConnect) ?? true;

    // Initialize threat stream
    await _streamService.init();

    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    // Check initial connectivity
    _lastConnectivity = await _connectivity.checkConnectivity();

    // Start health check timer
    _startHealthCheck();

    _isInitialized = true;

    // Auto-connect if enabled and we have network
    if (_autoConnect && _hasNetwork()) {
      await connect();
    }
  }

  /// Connect to threat stream
  Future<void> connect() async {
    if (!_hasNetwork()) {
      print('No network connection available');
      return;
    }

    await _streamService.connect();
  }

  /// Disconnect from threat stream
  Future<void> disconnect() async {
    await _streamService.disconnect();
  }

  /// Check if connected
  bool get isConnected => _streamService.isConnected;

  /// Get connection state
  WebSocketState get connectionState => _streamService.connectionState;

  /// Get auto-connect setting
  bool get autoConnect => _autoConnect;

  /// Set auto-connect setting
  Future<void> setAutoConnect(bool value) async {
    _autoConnect = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoConnect, value);

    if (value && !isConnected && _hasNetwork()) {
      await connect();
    }
  }

  /// Stream of connection state changes
  Stream<WebSocketState> get stateStream => _streamService.stateStream;

  /// Stream of threat events
  Stream<ThreatEvent> get eventStream => _streamService.eventStream;

  /// Get connection health info
  ConnectionHealth getConnectionHealth() {
    return ConnectionHealth(
      isConnected: isConnected,
      state: connectionState,
      hasNetwork: _hasNetwork(),
      networkTypes: _lastConnectivity,
      lastHealthCheck: _lastHealthCheck,
      eventsReceived: _streamService.totalEventsReceived,
      lastEventTime: _streamService.lastEventTime,
    );
  }

  /// Handle connectivity changes
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hadNetwork = _hasNetwork();
    _lastConnectivity = results;
    final hasNetwork = _hasNetwork();

    print('Connectivity changed: $results (had: $hadNetwork, has: $hasNetwork)');

    if (!hadNetwork && hasNetwork) {
      // Network restored - reconnect
      if (_autoConnect) {
        print('Network restored, reconnecting...');
        connect();
      }
    } else if (hadNetwork && !hasNetwork) {
      // Network lost - the WebSocket will handle this
      print('Network lost');
    }
  }

  /// Check if we have network connectivity
  bool _hasNetwork() {
    return _lastConnectivity.isNotEmpty &&
        !_lastConnectivity.every((r) => r == ConnectivityResult.none);
  }

  /// Start health check timer
  void _startHealthCheck() {
    _stopHealthCheck();
    _healthCheckTimer = Timer.periodic(
      Duration(seconds: _healthCheckIntervalSeconds),
      (_) => _performHealthCheck(),
    );
  }

  /// Stop health check timer
  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  /// Perform health check
  void _performHealthCheck() {
    _lastHealthCheck = DateTime.now();

    // Check if we should be connected but aren't
    if (_autoConnect && _hasNetwork() && !isConnected) {
      final state = connectionState;
      if (state != WebSocketState.connecting &&
          state != WebSocketState.reconnecting) {
        print('Health check: should be connected but not, reconnecting...');
        connect();
      }
    }
  }

  /// Dispose resources
  void dispose() {
    _stopHealthCheck();
    _connectivitySubscription?.cancel();
    _streamService.dispose();
    _wsService.dispose();
    _isInitialized = false;
  }
}

/// Connection health information
class ConnectionHealth {
  final bool isConnected;
  final WebSocketState state;
  final bool hasNetwork;
  final List<ConnectivityResult> networkTypes;
  final DateTime? lastHealthCheck;
  final int eventsReceived;
  final DateTime? lastEventTime;

  ConnectionHealth({
    required this.isConnected,
    required this.state,
    required this.hasNetwork,
    this.networkTypes = const [],
    this.lastHealthCheck,
    required this.eventsReceived,
    this.lastEventTime,
  });

  /// Get the primary network type
  ConnectivityResult? get networkType =>
      networkTypes.isNotEmpty ? networkTypes.first : null;

  /// Get human-readable status
  String get statusText {
    if (!hasNetwork) return 'No network';
    switch (state) {
      case WebSocketState.connected:
        return 'Connected';
      case WebSocketState.connecting:
        return 'Connecting...';
      case WebSocketState.reconnecting:
        return 'Reconnecting...';
      case WebSocketState.error:
        return 'Connection error';
      case WebSocketState.disconnected:
        return 'Disconnected';
    }
  }

  /// Get network type text
  String get networkTypeText {
    switch (networkType) {
      case ConnectivityResult.wifi:
        return 'WiFi';
      case ConnectivityResult.mobile:
        return 'Mobile';
      case ConnectivityResult.ethernet:
        return 'Ethernet';
      case ConnectivityResult.vpn:
        return 'VPN';
      case ConnectivityResult.bluetooth:
        return 'Bluetooth';
      case ConnectivityResult.other:
        return 'Other';
      case ConnectivityResult.none:
      case null:
        return 'None';
    }
  }

  /// Check if connection is healthy
  bool get isHealthy {
    if (!hasNetwork) return false;
    if (!isConnected) return false;

    // Check if we've received events recently (within 5 minutes)
    if (lastEventTime != null) {
      final age = DateTime.now().difference(lastEventTime!);
      if (age.inMinutes > 5) {
        // Might be stale, but not necessarily unhealthy
      }
    }

    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      'is_connected': isConnected,
      'state': state.name,
      'has_network': hasNetwork,
      'network_type': networkType?.name,
      'last_health_check': lastHealthCheck?.toIso8601String(),
      'events_received': eventsReceived,
      'last_event_time': lastEventTime?.toIso8601String(),
    };
  }
}

/// Background connection service for keeping connection alive
class BackgroundConnectionService {
  static BackgroundConnectionService? _instance;
  static BackgroundConnectionService get instance =>
      _instance ??= BackgroundConnectionService._();

  BackgroundConnectionService._();

  bool _isRunning = false;
  Timer? _keepAliveTimer;

  /// Start background service
  void start() {
    if (_isRunning) return;
    _isRunning = true;

    // Keep connection alive every 5 minutes
    _keepAliveTimer = Timer.periodic(
      Duration(minutes: 5),
      (_) => _keepAlive(),
    );
  }

  /// Stop background service
  void stop() {
    _isRunning = false;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  /// Keep connection alive
  void _keepAlive() {
    final manager = ConnectionManager.instance;
    if (manager.autoConnect && !manager.isConnected) {
      manager.connect();
    }
  }

  bool get isRunning => _isRunning;
}
