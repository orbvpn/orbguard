/// Enterprise SIEM Integration Screen
/// Manages SIEM tool connections (Splunk, ELK, ArcSight, etc.)
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/api/orbguard_api_client.dart';

class SiemIntegrationScreen extends StatefulWidget {
  const SiemIntegrationScreen({super.key});

  @override
  State<SiemIntegrationScreen> createState() => _SiemIntegrationScreenState();
}

class _SiemIntegrationScreenState extends State<SiemIntegrationScreen> {
  bool _isLoading = false;
  String? _error;
  final List<SiemConnection> _connections = [];
  final List<EventForwarder> _forwarders = [];
  final List<SiemAlert> _alerts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = OrbGuardApiClient.instance;
      final results = await Future.wait([
        api.getSiemConnections(),
        api.getSiemForwarders(),
        api.getSiemAlerts(),
      ]);

      final connectionsData = results[0];
      final forwardersData = results[1];
      final alertsData = results[2];

      setState(() {
        _connections.clear();
        _forwarders.clear();
        _alerts.clear();

        _connections.addAll(
          connectionsData.map((json) => SiemConnection.fromJson(json)),
        );
        _forwarders.addAll(
          forwardersData.map((json) => EventForwarder.fromJson(json)),
        );
        _alerts.addAll(
          alertsData.map((json) => SiemAlert.fromJson(json)),
        );

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassTabPage(
      title: 'SIEM Integration',
      tabs: [
        GlassTab(
          label: 'Connections',
          iconPath: 'server',
          content: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
              : _error != null
                  ? _buildErrorState(_error!)
                  : _buildConnectionsTab(),
        ),
        GlassTab(
          label: 'Forwarders',
          iconPath: 'cloud_storage',
          content: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
              : _error != null
                  ? _buildErrorState(_error!)
                  : _buildForwardersTab(),
        ),
        GlassTab(
          label: 'Alerts',
          iconPath: 'shield',
          content: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
              : _error != null
                  ? _buildErrorState(_error!)
                  : _buildAlertsTab(),
        ),
      ],
      headerContent: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: const DuotoneIcon('refresh', size: 22, color: Colors.white),
              onPressed: _isLoading ? null : _loadData,
              tooltip: 'Refresh',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats
        Row(
          children: [
            _buildStatCard('Connected', _connections.where((c) => c.isConnected).length.toString(), GlassTheme.successColor),
            const SizedBox(width: 12),
            _buildStatCard('Events/min', _formatEventsPerMin(_connections.fold(0, (sum, c) => sum + c.eventsPerMinute)), GlassTheme.primaryAccent),
            const SizedBox(width: 12),
            _buildStatCard('Errors', _connections.fold(0, (sum, c) => sum + c.errors).toString(), GlassTheme.errorColor),
          ],
        ),
        const SizedBox(height: 24),

        // Supported SIEMs
        const GlassSectionHeader(title: 'Supported Platforms'),
        _buildSupportedSiems(),
        const SizedBox(height: 24),

        // Active Connections
        const GlassSectionHeader(title: 'Active Connections'),
        if (_connections.isEmpty)
          _buildEmptyState('No Connections',
              'No SIEM integrations are configured on the server')
        else
          ..._connections.map((conn) => _buildConnectionCard(conn)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportedSiems() {
    final siems = [
      {'name': 'Splunk', 'icon': 'chart', 'color': const Color(0xFF65A637)},
      {'name': 'Elastic', 'icon': 'magnifer', 'color': const Color(0xFF00BFB3)},
      {'name': 'ArcSight', 'icon': 'shield_check', 'color': const Color(0xFF00A3E0)},
      {'name': 'QRadar', 'icon': 'radar_2', 'color': const Color(0xFF054ADA)},
      {'name': 'Sentinel', 'icon': 'cloud_storage', 'color': const Color(0xFF0078D4)},
      {'name': 'Chronicle', 'icon': 'history', 'color': const Color(0xFF4285F4)},
    ];

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: siems.length,
        itemBuilder: (context, index) {
          final siem = siems[index];
          return Container(
            width: 90,
            margin: const EdgeInsets.only(right: 12),
            child: GlassCard(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DuotoneIcon(siem['icon'] as String, size: 32, color: siem['color'] as Color),
                  const SizedBox(height: 8),
                  Text(
                    siem['name'] as String,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionCard(SiemConnection connection) {
    return GlassCard(
      onTap: () => _showConnectionDetails(context, connection),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: _getSiemIcon(connection.type),
                color: connection.isConnected ? GlassTheme.successColor : GlassTheme.errorColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(connection.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(connection.type, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GlassBadge(
                    text: connection.isConnected ? 'Connected' : 'Disconnected',
                    color: connection.isConnected ? GlassTheme.successColor : GlassTheme.errorColor,
                    fontSize: 10,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${connection.eventsPerMinute} events/min',
                    style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            connection.endpoint,
            style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 11, fontFamily: 'monospace'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildConnectionStat('upload_minimalistic', '${connection.eventsSent}', 'Sent'),
              const SizedBox(width: 16),
              _buildConnectionStat('danger_circle', '${connection.errors}', 'Errors'),
              const SizedBox(width: 16),
              _buildConnectionStat('clock_circle', _formatTime(connection.lastSync), 'Last Sync'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStat(String icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DuotoneIcon(icon, size: 14, color: Colors.white38),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(77), fontSize: 10)),
      ],
    );
  }

  Widget _buildForwardersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const GlassSectionHeader(title: 'Active Forwarders'),
        if (_forwarders.isEmpty)
          _buildEmptyState('No Forwarders',
              'No event forwarders are configured on the server')
        else
          ..._forwarders.map((forwarder) => _buildForwarderCard(forwarder)),
      ],
    );
  }

  Widget _buildForwarderCard(EventForwarder forwarder) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: 'plain',
                color: forwarder.isEnabled ? GlassTheme.primaryAccent : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(forwarder.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('To: ${forwarder.destination}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
                  ],
                ),
              ),
              Switch(
                value: forwarder.isEnabled,
                onChanged: (v) => setState(() => forwarder.isEnabled = v),
                activeTrackColor: GlassTheme.successColor.withAlpha(128),
                activeThumbColor: GlassTheme.successColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: forwarder.eventTypes.map((type) => GlassBadge(text: type, color: GlassTheme.primaryAccent, fontSize: 10)).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Format: ${forwarder.format}', style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11)),
              const SizedBox(width: 16),
              Text('Batch: ${forwarder.batchSize}', style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsTab() {
    final criticalCount = _alerts
        .where((a) => a.severity.toLowerCase() == 'critical')
        .length;
    final forwardedCount = _alerts.where((a) => a.forwarded).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats
        Row(
          children: [
            _buildStatCard('Total', '${_alerts.length}', GlassTheme.primaryAccent),
            const SizedBox(width: 12),
            _buildStatCard('Critical', '$criticalCount', GlassTheme.errorColor),
            const SizedBox(width: 12),
            _buildStatCard('Forwarded', '$forwardedCount', GlassTheme.successColor),
          ],
        ),
        const SizedBox(height: 24),

        const GlassSectionHeader(title: 'SIEM Alerts'),
        if (_alerts.isEmpty)
          _buildEmptyState('No Alerts',
              'No security events have flowed through the SIEM event path yet')
        else
          ..._alerts.map((alert) => _buildAlertCard(alert)),
      ],
    );
  }

  Widget _buildAlertCard(SiemAlert alert) {
    Color severityColor;
    switch (alert.severity.toLowerCase()) {
      case 'critical':
        severityColor = GlassTheme.errorColor;
        break;
      case 'high':
        severityColor = const Color(0xFFFF5722);
        break;
      case 'medium':
        severityColor = GlassTheme.warningColor;
        break;
      default:
        severityColor = GlassTheme.successColor;
    }

    final String forwardLabel;
    final Color forwardColor;
    if (alert.forwarded) {
      forwardLabel = 'Forwarded';
      forwardColor = GlassTheme.successColor;
    } else if (alert.forwardError != null) {
      forwardLabel = 'Failed';
      forwardColor = GlassTheme.errorColor;
    } else {
      forwardLabel = 'Pending';
      forwardColor = GlassTheme.warningColor;
    }

    return GlassCard(
      tintColor: alert.forwardError != null ? severityColor : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(icon: 'bell_bing', color: severityColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    if (alert.source.isNotEmpty)
                      Text(alert.source, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
                    if (alert.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(alert.description, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GlassBadge(text: _capitalize(alert.severity), color: severityColor, fontSize: 10),
                  const SizedBox(height: 4),
                  GlassBadge(text: forwardLabel, color: forwardColor, fontSize: 10),
                  const SizedBox(height: 4),
                  Text(_formatTime(alert.createdAt), style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10)),
                ],
              ),
            ],
          ),
          if (alert.forwardError != null) ...[
            const SizedBox(height: 8),
            Text(
              'Forward error: ${alert.forwardError}',
              style: TextStyle(color: GlassTheme.errorColor.withAlpha(204), fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            DuotoneIcon('inbox', size: 48, color: GlassTheme.primaryAccent.withAlpha(128)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(153))),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DuotoneIcon('danger_circle', size: 48, color: GlassTheme.errorColor.withAlpha(180)),
            const SizedBox(height: 16),
            const Text(
              'Failed to Load Data',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadData,
              icon: const DuotoneIcon('refresh', size: 18),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: GlassTheme.primaryAccent,
                side: const BorderSide(color: GlassTheme.primaryAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConnectionDetails(BuildContext context, SiemConnection connection) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [GlassTheme.gradientTop, GlassTheme.gradientBottom],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  GlassSvgIconBox(icon: _getSiemIcon(connection.type), color: GlassTheme.primaryAccent, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(connection.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        GlassBadge(text: connection.type, color: GlassTheme.primaryAccent),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Status', connection.isConnected ? 'Connected' : 'Disconnected'),
                    _buildDetailRow('Endpoint', connection.endpoint),
                    _buildDetailRow('Events/min', '${connection.eventsPerMinute}'),
                    _buildDetailRow('Total Sent', '${connection.eventsSent}'),
                    _buildDetailRow('Errors', '${connection.errors}'),
                    _buildDetailRow('Last Sync', _formatTime(connection.lastSync)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withAlpha(153))),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _getSiemIcon(String type) {
    switch (type.toLowerCase()) {
      case 'splunk':
        return 'chart';
      case 'elastic':
        return 'magnifer';
      case 'arcsight':
        return 'shield_check';
      case 'qradar':
        return 'radar_2';
      case 'sentinel':
        return 'cloud_storage';
      case 'chronicle':
        return 'history';
      default:
        return 'server_square';
    }
  }

  String _formatEventsPerMin(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class SiemConnection {
  final String id;
  final String name;
  final String type;
  final String endpoint;
  bool isConnected;
  final int eventsPerMinute;
  final int eventsSent;
  final int errors;
  final DateTime lastSync;

  SiemConnection({
    required this.id,
    required this.name,
    required this.type,
    required this.endpoint,
    required this.isConnected,
    required this.eventsPerMinute,
    required this.eventsSent,
    required this.errors,
    required this.lastSync,
  });

  factory SiemConnection.fromJson(Map<String, dynamic> json) {
    return SiemConnection(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      endpoint: json['endpoint'] as String? ?? '',
      isConnected: json['is_connected'] as bool? ?? json['isConnected'] as bool? ?? false,
      eventsPerMinute: json['events_per_minute'] as int? ?? json['eventsPerMinute'] as int? ?? 0,
      eventsSent: json['events_sent'] as int? ?? json['eventsSent'] as int? ?? 0,
      errors: json['errors'] as int? ?? 0,
      lastSync: json['last_sync'] != null
          ? DateTime.tryParse(json['last_sync'].toString()) ?? DateTime.now()
          : json['lastSync'] != null
              ? DateTime.tryParse(json['lastSync'].toString()) ?? DateTime.now()
              : DateTime.now(),
    );
  }
}

class EventForwarder {
  final String id;
  final String name;
  final String destination;
  final List<String> eventTypes;
  final String format;
  final int batchSize;
  bool isEnabled;

  EventForwarder({
    required this.id,
    required this.name,
    required this.destination,
    required this.eventTypes,
    required this.format,
    required this.batchSize,
    required this.isEnabled,
  });

  factory EventForwarder.fromJson(Map<String, dynamic> json) {
    final eventTypesRaw = json['event_types'] ?? json['eventTypes'] ?? [];
    final List<String> eventTypes = eventTypesRaw is List
        ? eventTypesRaw.map((e) => e.toString()).toList()
        : <String>[];

    return EventForwarder(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      eventTypes: eventTypes,
      format: json['format'] as String? ?? 'JSON',
      batchSize: json['batch_size'] as int? ?? json['batchSize'] as int? ?? 100,
      isEnabled: json['is_enabled'] as bool? ?? json['isEnabled'] as bool? ?? false,
    );
  }
}

/// A persisted SIEM alert from GET /siem/alerts. Mirrors the server shape
/// exactly: {id, integration_id, severity, title, description, source,
/// created_at, forwarded, forward_error}.
class SiemAlert {
  final String id;
  final String? integrationId;
  final String severity;
  final String title;
  final String description;
  final String source;
  final DateTime createdAt;
  final bool forwarded;
  final String? forwardError;

  SiemAlert({
    required this.id,
    required this.integrationId,
    required this.severity,
    required this.title,
    required this.description,
    required this.source,
    required this.createdAt,
    required this.forwarded,
    required this.forwardError,
  });

  factory SiemAlert.fromJson(Map<String, dynamic> json) {
    final forwardError = json['forward_error']?.toString();
    return SiemAlert(
      id: json['id']?.toString() ?? '',
      integrationId: json['integration_id']?.toString(),
      severity: json['severity'] as String? ?? 'info',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      source: json['source'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      forwarded: json['forwarded'] as bool? ?? false,
      forwardError:
          (forwardError == null || forwardError.isEmpty) ? null : forwardError,
    );
  }
}
