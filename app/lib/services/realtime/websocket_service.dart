/// WebSocket Service for Real-time Threat Alerts
/// Connects to OrbGuard Lab WebSocket endpoint for live threat updates

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_config.dart';
import '../../models/api/threat_indicator.dart';

/// WebSocket connection states
enum WebSocketState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// WebSocket service for real-time threat updates
class WebSocketService {
  static WebSocketService? _instance;
  static WebSocketService get instance => _instance ??= WebSocketService._();

  WebSocketService._();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  WebSocketState _state = WebSocketState.disconnected;
  int _reconnectAttempts = 0;
  DateTime? _lastMessageTime;

  // Configuration
  static const int _maxReconnectAttempts = 10;
  static const int _pingIntervalSeconds = 30;
  static const int _reconnectDelayBaseMs = 1000;
  static const int _maxReconnectDelayMs = 60000;

  // Callbacks
  final _stateController = StreamController<WebSocketState>.broadcast();
  final _messageController = StreamController<ThreatEvent>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  // Subscriptions for filtering
  final Set<String> _subscribedSeverities = {};
  final Set<String> _subscribedPlatforms = {};
  final Set<String> _subscribedCampaigns = {};

  /// Stream of connection state changes
  Stream<WebSocketState> get stateStream => _stateController.stream;

  /// Stream of incoming threat events
  Stream<ThreatEvent> get messageStream => _messageController.stream;

  /// Stream of error messages
  Stream<String> get errorStream => _errorController.stream;

  /// Current connection state
  WebSocketState get state => _state;

  /// Check if connected
  bool get isConnected => _state == WebSocketState.connected;

  /// Get WebSocket URL
  String get _wsUrl {
    final baseUrl = ApiConfig.baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return '$baseUrl/ws/threats';
  }

  /// Connect to WebSocket server
  Future<void> connect() async {
    if (_state == WebSocketState.connected ||
        _state == WebSocketState.connecting) {
      return;
    }

    _setState(WebSocketState.connecting);

    try {
      // Get auth token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('orbguard_auth_token');
      final deviceId = prefs.getString('orbguard_device_id');

      // Build headers
      final headers = <String, String>{
        'X-Client-Version': '1.0.0',
        'X-Platform': Platform.isIOS ? 'ios' : 'android',
      };

      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
      if (deviceId != null) {
        headers['X-Device-ID'] = deviceId;
      }

      // Create WebSocket connection
      _channel = IOWebSocketChannel.connect(
        Uri.parse(_wsUrl),
        headers: headers,
        pingInterval: Duration(seconds: _pingIntervalSeconds),
      );

      // Listen to messages
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _setState(WebSocketState.connected);
      _reconnectAttempts = 0;
      _startPingTimer();

      // Send subscription preferences
      _sendSubscriptions();

      print('WebSocket connected to $_wsUrl');
    } catch (e) {
      _onError(e);
    }
  }

  /// Disconnect from WebSocket server
  Future<void> disconnect() async {
    _stopPingTimer();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _subscription?.cancel();
    _subscription = null;

    await _channel?.sink.close();
    _channel = null;

    _setState(WebSocketState.disconnected);
    _reconnectAttempts = 0;

    print('WebSocket disconnected');
  }

  /// Subscribe to specific severity levels
  void subscribeSeverities(List<String> severities) {
    _subscribedSeverities
      ..clear()
      ..addAll(severities);
    _sendSubscriptions();
  }

  /// Subscribe to specific platforms
  void subscribePlatforms(List<String> platforms) {
    _subscribedPlatforms
      ..clear()
      ..addAll(platforms);
    _sendSubscriptions();
  }

  /// Subscribe to specific campaigns
  void subscribeCampaigns(List<String> campaigns) {
    _subscribedCampaigns
      ..clear()
      ..addAll(campaigns);
    _sendSubscriptions();
  }

  /// Send a message to the server
  void send(Map<String, dynamic> message) {
    if (_state != WebSocketState.connected || _channel == null) {
      print('Cannot send message: not connected');
      return;
    }

    try {
      _channel!.sink.add(jsonEncode(message));
    } catch (e) {
      print('Error sending message: $e');
    }
  }

  /// Handle incoming message
  void _onMessage(dynamic message) {
    _lastMessageTime = DateTime.now();

    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final eventType = data['type'] as String?;

      switch (eventType) {
        case 'threat':
          final event = ThreatEvent.fromJson(data);
          if (_shouldDeliverEvent(event)) {
            _messageController.add(event);
          }
          break;

        case 'pong':
          // Server responded to ping
          break;

        case 'subscribed':
          print('Subscription confirmed: ${data['filters']}');
          break;

        case 'error':
          final errorMsg = data['message'] as String? ?? 'Unknown error';
          _errorController.add(errorMsg);
          break;

        default:
          print('Unknown message type: $eventType');
      }
    } catch (e) {
      print('Error parsing message: $e');
    }
  }

  /// Handle WebSocket error
  void _onError(dynamic error) {
    print('WebSocket error: $error');
    _setState(WebSocketState.error);
    _errorController.add(error.toString());
    _scheduleReconnect();
  }

  /// Handle WebSocket close
  void _onDone() {
    print('WebSocket connection closed');
    if (_state != WebSocketState.disconnected) {
      _setState(WebSocketState.disconnected);
      _scheduleReconnect();
    }
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('Max reconnection attempts reached');
      _setState(WebSocketState.error);
      _errorController.add('Connection failed after $_maxReconnectAttempts attempts');
      return;
    }

    _reconnectTimer?.cancel();

    // Exponential backoff with jitter
    final delay = _calculateReconnectDelay();
    print('Scheduling reconnect in ${delay}ms (attempt ${_reconnectAttempts + 1})');

    _setState(WebSocketState.reconnecting);
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _reconnectAttempts++;
      connect();
    });
  }

  /// Calculate reconnect delay with exponential backoff
  int _calculateReconnectDelay() {
    final baseDelay = _reconnectDelayBaseMs * (1 << _reconnectAttempts);
    final cappedDelay = baseDelay.clamp(0, _maxReconnectDelayMs);
    // Add jitter (0-25% of delay)
    final jitter = (cappedDelay * 0.25 * (DateTime.now().millisecond / 1000)).toInt();
    return cappedDelay + jitter;
  }

  /// Start ping timer to keep connection alive
  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(
      Duration(seconds: _pingIntervalSeconds),
      (_) => _sendPing(),
    );
  }

  /// Stop ping timer
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Send ping to server
  void _sendPing() {
    if (_state == WebSocketState.connected) {
      send({'type': 'ping', 'timestamp': DateTime.now().toIso8601String()});
    }
  }

  /// Send subscription preferences to server
  void _sendSubscriptions() {
    if (_state != WebSocketState.connected) return;

    final filters = <String, dynamic>{};

    if (_subscribedSeverities.isNotEmpty) {
      filters['severities'] = _subscribedSeverities.toList();
    }
    if (_subscribedPlatforms.isNotEmpty) {
      filters['platforms'] = _subscribedPlatforms.toList();
    }
    if (_subscribedCampaigns.isNotEmpty) {
      filters['campaigns'] = _subscribedCampaigns.toList();
    }

    send({
      'type': 'subscribe',
      'filters': filters,
    });
  }

  /// Check if event should be delivered based on subscriptions
  bool _shouldDeliverEvent(ThreatEvent event) {
    // If no filters, deliver all events
    if (_subscribedSeverities.isEmpty &&
        _subscribedPlatforms.isEmpty &&
        _subscribedCampaigns.isEmpty) {
      return true;
    }

    // Check severity filter
    if (_subscribedSeverities.isNotEmpty &&
        !_subscribedSeverities.contains(event.severity.value)) {
      return false;
    }

    // Check platform filter
    if (_subscribedPlatforms.isNotEmpty &&
        !event.platforms.any((p) => _subscribedPlatforms.contains(p.value))) {
      return false;
    }

    // Check campaign filter
    if (_subscribedCampaigns.isNotEmpty &&
        event.campaignId != null &&
        !_subscribedCampaigns.contains(event.campaignId)) {
      return false;
    }

    return true;
  }

  /// Update connection state
  void _setState(WebSocketState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _stateController.close();
    _messageController.close();
    _errorController.close();
  }
}

/// Threat event from WebSocket
class ThreatEvent {
  final String id;
  final String type;
  final String value;
  final SeverityLevel severity;
  final List<ThreatPlatform> platforms;
  final String? campaignId;
  final String? campaignName;
  final String? description;
  final List<String> tags;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  ThreatEvent({
    required this.id,
    required this.type,
    required this.value,
    required this.severity,
    required this.platforms,
    this.campaignId,
    this.campaignName,
    this.description,
    required this.tags,
    required this.timestamp,
    this.metadata,
  });

  factory ThreatEvent.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;

    return ThreatEvent(
      id: data['id'] as String? ?? '',
      type: data['indicator_type'] as String? ?? data['type'] as String? ?? 'unknown',
      value: data['value'] as String? ?? '',
      severity: SeverityLevel.fromString(data['severity'] as String? ?? 'info'),
      platforms: (data['platforms'] as List<dynamic>?)
              ?.map((p) => ThreatPlatform.fromString(p as String))
              .toList() ??
          [],
      campaignId: data['campaign_id'] as String?,
      campaignName: data['campaign_name'] as String?,
      description: data['description'] as String?,
      tags: (data['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      timestamp: data['timestamp'] != null
          ? DateTime.parse(data['timestamp'] as String)
          : DateTime.now(),
      metadata: data['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Check if this is a critical threat
  bool get isCritical =>
      severity == SeverityLevel.critical || severity == SeverityLevel.high;

  /// Check if this affects current platform
  bool affectsPlatform(String platform) {
    return platforms.any((p) => p.value == platform || p == ThreatPlatform.both);
  }
}
