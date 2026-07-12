/// Enterprise SIEM Integration Service
///
/// Provides security event forwarding to SIEM platforms:
/// - Support for major SIEM platforms (Splunk, QRadar, Sentinel, etc.)
/// - Multiple event formats (CEF, LEEF, Syslog, JSON)
/// - Event batching and delivery management
/// - Webhook notifications for real-time alerts
/// - Event filtering and transformation
/// - Delivery status tracking and retry logic

import 'dart:async';
import 'dart:convert';
import '../../api/orbguard_api_client.dart';

/// Supported SIEM platforms
enum SIEMPlatform {
  splunk('Splunk', 'Splunk Enterprise/Cloud'),
  qradar('QRadar', 'IBM QRadar SIEM'),
  sentinel('Microsoft Sentinel', 'Azure Sentinel'),
  elasticSiem('Elastic SIEM', 'Elasticsearch Security'),
  chronicle('Chronicle', 'Google Chronicle'),
  sumologic('Sumo Logic', 'Sumo Logic Cloud SIEM'),
  logrhythm('LogRhythm', 'LogRhythm SIEM'),
  arcsight('ArcSight', 'Micro Focus ArcSight'),
  syslog('Syslog', 'Generic Syslog Server'),
  webhook('Webhook', 'Custom Webhook Endpoint'),
  custom('Custom', 'Custom SIEM Integration');

  final String displayName;
  final String description;

  const SIEMPlatform(this.displayName, this.description);
}

/// Event format types
enum EventFormat {
  cef('CEF', 'Common Event Format'),
  leef('LEEF', 'Log Event Extended Format'),
  json('JSON', 'JSON Format'),
  syslog('Syslog', 'RFC 5424 Syslog'),
  xml('XML', 'XML Format'),
  custom('Custom', 'Custom Format Template');

  final String displayName;
  final String description;

  const EventFormat(this.displayName, this.description);
}

/// Event severity levels
enum EventSeverity {
  critical('Critical', 10),
  high('High', 7),
  medium('Medium', 5),
  low('Low', 3),
  info('Informational', 1);

  final String displayName;
  final int cefSeverity;

  const EventSeverity(this.displayName, this.cefSeverity);
}

/// Security event types
enum SecurityEventType {
  // Threat events
  malwareDetected('Malware Detected'),
  phishingBlocked('Phishing Blocked'),
  networkThreat('Network Threat'),
  intrusionAttempt('Intrusion Attempt'),

  // Access events
  loginSuccess('Login Success'),
  loginFailed('Login Failed'),
  logoutEvent('Logout'),
  mfaChallenge('MFA Challenge'),
  accessDenied('Access Denied'),
  privilegeEscalation('Privilege Escalation'),

  // Device events
  deviceEnrolled('Device Enrolled'),
  deviceUnenrolled('Device Unenrolled'),
  deviceCompromised('Device Compromised'),
  deviceLocked('Device Locked'),
  deviceWiped('Device Wiped'),

  // Policy events
  policyViolation('Policy Violation'),
  policyUpdated('Policy Updated'),
  complianceAlert('Compliance Alert'),

  // Data events
  dataExfiltration('Data Exfiltration'),
  sensitiveDataAccess('Sensitive Data Access'),
  encryptionFailure('Encryption Failure'),

  // Network events
  vpnConnected('VPN Connected'),
  vpnDisconnected('VPN Disconnected'),
  dnsBlocked('DNS Blocked'),
  firewallBlock('Firewall Block');

  final String displayName;

  const SecurityEventType(this.displayName);
}

/// SIEM integration configuration
class SIEMConfiguration {
  final String id;
  final String name;
  final SIEMPlatform platform;
  final String endpoint;
  final EventFormat format;
  final Map<String, String> credentials;
  final Map<String, dynamic> settings;
  final Set<SecurityEventType> enabledEvents;
  final EventSeverity minimumSeverity;
  final bool isEnabled;
  final bool batchEvents;
  final int batchSize;
  final int batchIntervalSeconds;
  final DateTime createdAt;
  final DateTime? lastEventAt;

  SIEMConfiguration({
    required this.id,
    required this.name,
    required this.platform,
    required this.endpoint,
    this.format = EventFormat.json,
    this.credentials = const {},
    this.settings = const {},
    this.enabledEvents = const {},
    this.minimumSeverity = EventSeverity.low,
    this.isEnabled = true,
    this.batchEvents = true,
    this.batchSize = 100,
    this.batchIntervalSeconds = 60,
    DateTime? createdAt,
    this.lastEventAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory SIEMConfiguration.fromJson(Map<String, dynamic> json) {
    return SIEMConfiguration(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      platform: _parsePlatform(json['platform'] as String?),
      endpoint: json['endpoint'] as String? ?? '',
      format: _parseFormat(json['format'] as String?),
      credentials: (json['credentials'] as Map<String, dynamic>?)
              ?.cast<String, String>() ??
          {},
      settings: (json['settings'] as Map<String, dynamic>?) ?? {},
      enabledEvents: (json['enabled_events'] as List<dynamic>?)
              ?.map((e) => _parseEventType(e as String))
              .whereType<SecurityEventType>()
              .toSet() ??
          {},
      minimumSeverity: _parseSeverity(json['minimum_severity'] as String?),
      isEnabled: json['is_enabled'] as bool? ?? true,
      batchEvents: json['batch_events'] as bool? ?? true,
      batchSize: json['batch_size'] as int? ?? 100,
      batchIntervalSeconds: json['batch_interval_seconds'] as int? ?? 60,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      lastEventAt: json['last_event_at'] != null
          ? DateTime.tryParse(json['last_event_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform.name,
        'endpoint': endpoint,
        'format': format.name,
        'credentials': credentials,
        'settings': settings,
        'enabled_events': enabledEvents.map((e) => e.name).toList(),
        'minimum_severity': minimumSeverity.name,
        'is_enabled': isEnabled,
        'batch_events': batchEvents,
        'batch_size': batchSize,
        'batch_interval_seconds': batchIntervalSeconds,
      };

  static SIEMPlatform _parsePlatform(String? name) {
    if (name == null) return SIEMPlatform.custom;
    return SIEMPlatform.values.firstWhere(
      (p) => p.name.toLowerCase() == name.toLowerCase(),
      orElse: () => SIEMPlatform.custom,
    );
  }

  static EventFormat _parseFormat(String? name) {
    if (name == null) return EventFormat.json;
    return EventFormat.values.firstWhere(
      (f) => f.name.toLowerCase() == name.toLowerCase(),
      orElse: () => EventFormat.json,
    );
  }

  static EventSeverity _parseSeverity(String? name) {
    if (name == null) return EventSeverity.low;
    return EventSeverity.values.firstWhere(
      (s) => s.name.toLowerCase() == name.toLowerCase(),
      orElse: () => EventSeverity.low,
    );
  }

  static SecurityEventType? _parseEventType(String name) {
    try {
      return SecurityEventType.values.firstWhere(
        (e) => e.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Security event to forward
class SecurityEvent {
  final String id;
  final SecurityEventType type;
  final EventSeverity severity;
  final String source;
  final String? deviceId;
  final String? userId;
  final String message;
  final Map<String, dynamic> details;
  final String? sourceIp;
  final String? destinationIp;
  final DateTime timestamp;

  SecurityEvent({
    required this.id,
    required this.type,
    required this.severity,
    required this.source,
    this.deviceId,
    this.userId,
    required this.message,
    this.details = const {},
    this.sourceIp,
    this.destinationIp,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convert to CEF format
  String toCEF({String vendor = 'OrbGuard', String product = 'Security'}) {
    final extension = <String>[];

    if (deviceId != null) extension.add('deviceExternalId=$deviceId');
    if (userId != null) extension.add('duser=$userId');
    if (sourceIp != null) extension.add('src=$sourceIp');
    if (destinationIp != null) extension.add('dst=$destinationIp');
    extension.add('rt=${timestamp.millisecondsSinceEpoch}');
    extension.add('msg=${_escapeValue(message)}');

    for (final entry in details.entries) {
      extension.add('cs1Label=${entry.key} cs1=${_escapeValue(entry.value.toString())}');
    }

    return 'CEF:0|$vendor|$product|1.0|${type.name}|${type.displayName}|${severity.cefSeverity}|${extension.join(' ')}';
  }

  /// Convert to LEEF format
  String toLEEF({String vendor = 'OrbGuard', String product = 'Security'}) {
    final attributes = <String>[];

    attributes.add('devTime=${timestamp.toIso8601String()}');
    if (deviceId != null) attributes.add('devName=$deviceId');
    if (userId != null) attributes.add('usrName=$userId');
    if (sourceIp != null) attributes.add('src=$sourceIp');
    if (destinationIp != null) attributes.add('dst=$destinationIp');
    attributes.add('msg=${_escapeValue(message)}');

    for (final entry in details.entries) {
      attributes.add('${entry.key}=${_escapeValue(entry.value.toString())}');
    }

    return 'LEEF:2.0|$vendor|$product|1.0|${type.name}|${attributes.join('\t')}';
  }

  /// Convert to Syslog format (RFC 5424)
  String toSyslog({String appName = 'OrbGuard'}) {
    final pri = _calculateSyslogPriority(severity);
    final timestamp = this.timestamp.toUtc().toIso8601String();
    final hostname = deviceId ?? '-';
    final procId = id;
    final msgId = type.name;

    return '<$pri>1 $timestamp $hostname $appName $procId $msgId - $message';
  }

  int _calculateSyslogPriority(EventSeverity severity) {
    // Facility: security/authorization (4) * 8 + severity
    const facility = 4;
    final syslogSeverity = switch (severity) {
      EventSeverity.critical => 2, // Critical
      EventSeverity.high => 3,     // Error
      EventSeverity.medium => 4,   // Warning
      EventSeverity.low => 5,      // Notice
      EventSeverity.info => 6,     // Informational
    };
    return facility * 8 + syslogSeverity;
  }

  /// Convert to JSON format
  Map<String, dynamic> toJson() => {
        'id': id,
        'event_type': type.name,
        'event_type_display': type.displayName,
        'severity': severity.name,
        'severity_level': severity.cefSeverity,
        'source': source,
        'device_id': deviceId,
        'user_id': userId,
        'message': message,
        'details': details,
        'source_ip': sourceIp,
        'destination_ip': destinationIp,
        'timestamp': timestamp.toIso8601String(),
      };

  String _escapeValue(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('=', '\\=')
        .replaceAll('|', '\\|');
  }
}

/// Event delivery status
class EventDeliveryStatus {
  final String eventId;
  final String integrationId;
  final bool delivered;
  final DateTime? deliveredAt;
  final int attempts;
  final String? error;
  final DateTime nextRetryAt;

  EventDeliveryStatus({
    required this.eventId,
    required this.integrationId,
    required this.delivered,
    this.deliveredAt,
    this.attempts = 0,
    this.error,
    DateTime? nextRetryAt,
  }) : nextRetryAt = nextRetryAt ?? DateTime.now();

  factory EventDeliveryStatus.fromJson(Map<String, dynamic> json) {
    return EventDeliveryStatus(
      eventId: json['event_id'] as String? ?? '',
      integrationId: json['integration_id'] as String? ?? '',
      delivered: json['delivered'] as bool? ?? false,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.tryParse(json['delivered_at'] as String)
          : null,
      attempts: json['attempts'] as int? ?? 0,
      error: json['error'] as String?,
      nextRetryAt: json['next_retry_at'] != null
          ? DateTime.tryParse(json['next_retry_at'] as String)
          : null,
    );
  }
}

/// SIEM Integration statistics
class SIEMStatistics {
  final String integrationId;
  final int totalEvents;
  final int deliveredEvents;
  final int failedEvents;
  final int pendingEvents;
  final double deliveryRate;
  final double averageLatencyMs;
  final DateTime periodStart;
  final DateTime periodEnd;

  SIEMStatistics({
    required this.integrationId,
    required this.totalEvents,
    required this.deliveredEvents,
    required this.failedEvents,
    required this.pendingEvents,
    required this.deliveryRate,
    required this.averageLatencyMs,
    required this.periodStart,
    required this.periodEnd,
  });

  factory SIEMStatistics.fromJson(Map<String, dynamic> json) {
    return SIEMStatistics(
      integrationId: json['integration_id'] as String? ?? '',
      totalEvents: json['total_events'] as int? ?? 0,
      deliveredEvents: json['delivered_events'] as int? ?? 0,
      failedEvents: json['failed_events'] as int? ?? 0,
      pendingEvents: json['pending_events'] as int? ?? 0,
      deliveryRate: (json['delivery_rate'] as num?)?.toDouble() ?? 0.0,
      averageLatencyMs: (json['average_latency_ms'] as num?)?.toDouble() ?? 0.0,
      periodStart: json['period_start'] != null
          ? DateTime.parse(json['period_start'] as String)
          : DateTime.now().subtract(const Duration(hours: 24)),
      periodEnd: json['period_end'] != null
          ? DateTime.parse(json['period_end'] as String)
          : DateTime.now(),
    );
  }
}

/// SIEM Integration Service
class SIEMIntegrationService {
  final OrbGuardApiClient _client = OrbGuardApiClient.instance;

  // Configurations
  final List<SIEMConfiguration> _configurations = [];

  // Event queue for batching
  final Map<String, List<SecurityEvent>> _eventQueues = {};

  // Batch timers
  final Map<String, Timer> _batchTimers = {};

  // Stream controllers
  final _eventController = StreamController<SecurityEvent>.broadcast();
  final _deliveryController = StreamController<EventDeliveryStatus>.broadcast();

  Stream<SecurityEvent> get eventStream => _eventController.stream;
  Stream<EventDeliveryStatus> get deliveryStream => _deliveryController.stream;

  // Getters
  List<SIEMConfiguration> get configurations => List.unmodifiable(_configurations);

  /// Initialize the service
  Future<void> initialize() async {
    await loadConfigurations();
    _startBatchTimers();
  }

  /// Load SIEM configurations
  Future<void> loadConfigurations() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/enterprise/siem/configurations',
      );

      final configs = (response['configurations'] as List<dynamic>?)
              ?.map((c) => SIEMConfiguration.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [];

      _configurations.clear();
      _configurations.addAll(configs);
    } catch (e) {
      // Use empty list on error
    }
  }

  /// Create a new SIEM integration
  Future<SIEMConfiguration?> createConfiguration({
    required String name,
    required SIEMPlatform platform,
    required String endpoint,
    EventFormat format = EventFormat.json,
    Map<String, String>? credentials,
    Map<String, dynamic>? settings,
    Set<SecurityEventType>? enabledEvents,
    EventSeverity minimumSeverity = EventSeverity.low,
    bool batchEvents = true,
    int batchSize = 100,
    int batchIntervalSeconds = 60,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/enterprise/siem/configurations',
        data: {
          'name': name,
          'platform': platform.name,
          'endpoint': endpoint,
          'format': format.name,
          'credentials': credentials,
          'settings': settings,
          'enabled_events': enabledEvents?.map((e) => e.name).toList() ??
              SecurityEventType.values.map((e) => e.name).toList(),
          'minimum_severity': minimumSeverity.name,
          'batch_events': batchEvents,
          'batch_size': batchSize,
          'batch_interval_seconds': batchIntervalSeconds,
        },
      );

      final config = SIEMConfiguration.fromJson(response);
      _configurations.add(config);
      _initializeQueue(config);

      return config;
    } catch (e) {
      return null;
    }
  }

  /// Update a SIEM configuration
  Future<bool> updateConfiguration(
    String configId, {
    String? name,
    String? endpoint,
    EventFormat? format,
    Map<String, String>? credentials,
    Map<String, dynamic>? settings,
    Set<SecurityEventType>? enabledEvents,
    EventSeverity? minimumSeverity,
    bool? isEnabled,
    bool? batchEvents,
    int? batchSize,
    int? batchIntervalSeconds,
  }) async {
    try {
      await _client.put<void>(
        '/enterprise/siem/configurations/$configId',
        data: {
          if (name != null) 'name': name,
          if (endpoint != null) 'endpoint': endpoint,
          if (format != null) 'format': format.name,
          if (credentials != null) 'credentials': credentials,
          if (settings != null) 'settings': settings,
          if (enabledEvents != null)
            'enabled_events': enabledEvents.map((e) => e.name).toList(),
          if (minimumSeverity != null) 'minimum_severity': minimumSeverity.name,
          if (isEnabled != null) 'is_enabled': isEnabled,
          if (batchEvents != null) 'batch_events': batchEvents,
          if (batchSize != null) 'batch_size': batchSize,
          if (batchIntervalSeconds != null)
            'batch_interval_seconds': batchIntervalSeconds,
        },
      );

      await loadConfigurations();
      _restartBatchTimers();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Delete a SIEM configuration
  Future<bool> deleteConfiguration(String configId) async {
    try {
      await _client.delete<void>('/enterprise/siem/configurations/$configId');

      _configurations.removeWhere((c) => c.id == configId);
      _eventQueues.remove(configId);
      _batchTimers[configId]?.cancel();
      _batchTimers.remove(configId);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Test a SIEM configuration
  Future<Map<String, dynamic>> testConfiguration(String configId) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/enterprise/siem/configurations/$configId/test',
      );

      return {
        'success': response['success'] as bool? ?? false,
        'latency_ms': response['latency_ms'],
        'message': response['message'],
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Test failed: ${e.toString()}',
      };
    }
  }

  /// Forward a security event
  Future<void> forwardEvent(SecurityEvent event) async {
    _eventController.add(event);

    for (final config in _configurations) {
      if (!config.isEnabled) continue;
      if (!config.enabledEvents.contains(event.type)) continue;
      if (event.severity.cefSeverity < config.minimumSeverity.cefSeverity) {
        continue;
      }

      if (config.batchEvents) {
        _queueEvent(config.id, event);
      } else {
        await _sendEvent(config, [event]);
      }
    }
  }

  /// Queue an event for batch delivery
  void _queueEvent(String configId, SecurityEvent event) {
    _eventQueues.putIfAbsent(configId, () => []);
    _eventQueues[configId]!.add(event);

    final config = _configurations.firstWhere((c) => c.id == configId);
    if (_eventQueues[configId]!.length >= config.batchSize) {
      _flushQueue(configId);
    }
  }

  /// Flush event queue for a configuration
  Future<void> _flushQueue(String configId) async {
    final events = _eventQueues[configId];
    if (events == null || events.isEmpty) return;

    final eventsCopy = List<SecurityEvent>.from(events);
    events.clear();

    final config = _configurations.firstWhere(
      (c) => c.id == configId,
      orElse: () => throw Exception('Configuration not found'),
    );

    await _sendEvent(config, eventsCopy);
  }

  /// Send events to SIEM
  Future<void> _sendEvent(
    SIEMConfiguration config,
    List<SecurityEvent> events,
  ) async {
    if (events.isEmpty) return;

    try {
      // Format events based on configuration
      final formattedEvents = events.map((e) => _formatEvent(config, e)).toList();

      await _client.post<void>(
        '/enterprise/siem/forward',
        data: {
          'integration_id': config.id,
          'events': formattedEvents,
          'format': config.format.name,
        },
      );

      // Emit delivery success
      for (final event in events) {
        _deliveryController.add(EventDeliveryStatus(
          eventId: event.id,
          integrationId: config.id,
          delivered: true,
          deliveredAt: DateTime.now(),
          attempts: 1,
        ));
      }
    } catch (e) {
      // Emit delivery failure
      for (final event in events) {
        _deliveryController.add(EventDeliveryStatus(
          eventId: event.id,
          integrationId: config.id,
          delivered: false,
          attempts: 1,
          error: e.toString(),
          nextRetryAt: DateTime.now().add(const Duration(minutes: 5)),
        ));
      }

      // Re-queue for retry (in production, use proper retry mechanism)
      _eventQueues.putIfAbsent(config.id, () => []);
      _eventQueues[config.id]!.addAll(events);
    }
  }

  /// Format event based on configuration
  dynamic _formatEvent(SIEMConfiguration config, SecurityEvent event) {
    return switch (config.format) {
      EventFormat.cef => event.toCEF(),
      EventFormat.leef => event.toLEEF(),
      EventFormat.syslog => event.toSyslog(),
      EventFormat.json => event.toJson(),
      EventFormat.xml => _eventToXml(event),
      EventFormat.custom => _applyCustomTemplate(config, event),
    };
  }

  String _eventToXml(SecurityEvent event) {
    return '''<event>
  <id>${event.id}</id>
  <type>${event.type.name}</type>
  <severity>${event.severity.name}</severity>
  <source>${event.source}</source>
  <message><![CDATA[${event.message}]]></message>
  <timestamp>${event.timestamp.toIso8601String()}</timestamp>
  ${event.deviceId != null ? '<deviceId>${event.deviceId}</deviceId>' : ''}
  ${event.userId != null ? '<userId>${event.userId}</userId>' : ''}
  ${event.sourceIp != null ? '<sourceIp>${event.sourceIp}</sourceIp>' : ''}
  ${event.destinationIp != null ? '<destinationIp>${event.destinationIp}</destinationIp>' : ''}
</event>''';
  }

  String _applyCustomTemplate(SIEMConfiguration config, SecurityEvent event) {
    // Use custom template from settings if available
    final template = config.settings['template'] as String? ?? '{{json}}';

    return template
        .replaceAll('{{json}}', jsonEncode(event.toJson()))
        .replaceAll('{{cef}}', event.toCEF())
        .replaceAll('{{leef}}', event.toLEEF())
        .replaceAll('{{syslog}}', event.toSyslog())
        .replaceAll('{{id}}', event.id)
        .replaceAll('{{type}}', event.type.name)
        .replaceAll('{{severity}}', event.severity.name)
        .replaceAll('{{message}}', event.message)
        .replaceAll('{{timestamp}}', event.timestamp.toIso8601String());
  }

  /// Initialize event queues
  void _initializeQueue(SIEMConfiguration config) {
    _eventQueues.putIfAbsent(config.id, () => []);
    _startBatchTimer(config);
  }

  /// Start batch timers for all configurations
  void _startBatchTimers() {
    for (final config in _configurations) {
      if (config.isEnabled && config.batchEvents) {
        _startBatchTimer(config);
      }
    }
  }

  /// Start batch timer for a configuration
  void _startBatchTimer(SIEMConfiguration config) {
    _batchTimers[config.id]?.cancel();

    if (!config.batchEvents || !config.isEnabled) return;

    _batchTimers[config.id] = Timer.periodic(
      Duration(seconds: config.batchIntervalSeconds),
      (_) => _flushQueue(config.id),
    );
  }

  /// Restart all batch timers
  void _restartBatchTimers() {
    for (final timer in _batchTimers.values) {
      timer.cancel();
    }
    _batchTimers.clear();
    _startBatchTimers();
  }

  /// Get statistics for an integration
  Future<SIEMStatistics?> getStatistics(
    String configId, {
    String period = '24h',
  }) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/enterprise/siem/configurations/$configId/stats',
        queryParameters: {'period': period},
      );

      return SIEMStatistics.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// Get pending events count
  int getPendingEventsCount(String configId) {
    return _eventQueues[configId]?.length ?? 0;
  }

  /// Get all pending events count
  int get totalPendingEvents {
    return _eventQueues.values.fold(0, (sum, queue) => sum + queue.length);
  }

  /// Force flush all queues
  Future<void> flushAllQueues() async {
    for (final configId in _eventQueues.keys.toList()) {
      await _flushQueue(configId);
    }
  }

  /// Create common security events

  /// Log malware detection
  Future<void> logMalwareDetected({
    required String deviceId,
    required String malwareName,
    required String filePath,
    String? userId,
    String? sourceIp,
  }) async {
    await forwardEvent(SecurityEvent(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: SecurityEventType.malwareDetected,
      severity: EventSeverity.critical,
      source: 'OrbGuard Antimalware',
      deviceId: deviceId,
      userId: userId,
      message: 'Malware detected: $malwareName in $filePath',
      details: {
        'malware_name': malwareName,
        'file_path': filePath,
        'action': 'quarantined',
      },
      sourceIp: sourceIp,
    ));
  }

  /// Log policy violation
  Future<void> logPolicyViolation({
    required String deviceId,
    required String policyId,
    required String policyName,
    required String violationDetails,
    String? userId,
    EventSeverity severity = EventSeverity.high,
  }) async {
    await forwardEvent(SecurityEvent(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: SecurityEventType.policyViolation,
      severity: severity,
      source: 'OrbGuard Policy Engine',
      deviceId: deviceId,
      userId: userId,
      message: 'Policy violation: $policyName - $violationDetails',
      details: {
        'policy_id': policyId,
        'policy_name': policyName,
        'violation_details': violationDetails,
      },
    ));
  }

  /// Log login event
  Future<void> logLoginEvent({
    required String userId,
    required bool success,
    String? deviceId,
    String? sourceIp,
    String? failureReason,
  }) async {
    await forwardEvent(SecurityEvent(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: success ? SecurityEventType.loginSuccess : SecurityEventType.loginFailed,
      severity: success ? EventSeverity.info : EventSeverity.medium,
      source: 'OrbGuard Authentication',
      deviceId: deviceId,
      userId: userId,
      message: success
          ? 'User $userId logged in successfully'
          : 'Failed login attempt for user $userId: ${failureReason ?? "unknown reason"}',
      details: {
        'success': success,
        if (failureReason != null) 'failure_reason': failureReason,
      },
      sourceIp: sourceIp,
    ));
  }

  /// Log device event
  Future<void> logDeviceEvent({
    required String deviceId,
    required SecurityEventType eventType,
    required String message,
    String? userId,
    Map<String, dynamic>? details,
    EventSeverity severity = EventSeverity.info,
  }) async {
    await forwardEvent(SecurityEvent(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: eventType,
      severity: severity,
      source: 'OrbGuard Device Management',
      deviceId: deviceId,
      userId: userId,
      message: message,
      details: details ?? {},
    ));
  }

  /// Log VPN event
  Future<void> logVPNEvent({
    required String deviceId,
    required bool connected,
    String? userId,
    String? sourceIp,
    String? vpnServer,
  }) async {
    await forwardEvent(SecurityEvent(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: connected
          ? SecurityEventType.vpnConnected
          : SecurityEventType.vpnDisconnected,
      severity: EventSeverity.info,
      source: 'OrbGuard VPN',
      deviceId: deviceId,
      userId: userId,
      message: connected
          ? 'VPN connected to $vpnServer'
          : 'VPN disconnected',
      details: {
        'connected': connected,
        if (vpnServer != null) 'vpn_server': vpnServer,
      },
      sourceIp: sourceIp,
    ));
  }

  /// Dispose resources
  void dispose() {
    for (final timer in _batchTimers.values) {
      timer.cancel();
    }
    _batchTimers.clear();
    _eventController.close();
    _deliveryController.close();
  }
}
