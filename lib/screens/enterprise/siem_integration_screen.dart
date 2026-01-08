/// Enterprise SIEM Integration Screen
/// Manages SIEM tool connections (Splunk, ELK, ArcSight, etc.)
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';

class SiemIntegrationScreen extends StatefulWidget {
  const SiemIntegrationScreen({super.key});

  @override
  State<SiemIntegrationScreen> createState() => _SiemIntegrationScreenState();
}

class _SiemIntegrationScreenState extends State<SiemIntegrationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  final List<SiemConnection> _connections = [];
  final List<EventForwarder> _forwarders = [];
  final List<SiemAlert> _alerts = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _connections.addAll(_getSampleConnections());
      _forwarders.addAll(_getSampleForwarders());
      _alerts.addAll(_getSampleAlerts());
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'SIEM Integration',
        actions: [
          IconButton(
            icon: const DuotoneIcon('add_circle', size: 24),
            tooltip: 'Add Connection',
            onPressed: () => _showAddConnectionDialog(context),
          ),
          IconButton(
            icon: const DuotoneIcon('refresh', size: 24),
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GlassTheme.primaryAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Connections'),
            Tab(text: 'Forwarders'),
            Tab(text: 'Alerts'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildConnectionsTab(),
                _buildForwardersTab(),
                _buildAlertsTab(),
              ],
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
            _buildStatCard('Events/min', '2.4K', GlassTheme.primaryAccent),
            const SizedBox(width: 12),
            _buildStatCard('Errors', '3', GlassTheme.errorColor),
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
          _buildEmptyState('No Connections', 'Add a SIEM connection to get started')
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
              onTap: () => _showAddConnectionDialog(context, siemType: siem['name'] as String),
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
                    Text(connection.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(connection.type, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
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
        // Add forwarder button
        GlassCard(
          onTap: () => _showAddForwarderDialog(context),
          child: Row(
            children: [
              GlassSvgIconBox(icon: 'add_circle', color: GlassTheme.primaryAccent),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add Event Forwarder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('Configure event forwarding rules', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              const DuotoneIcon('alt_arrow_right', size: 24, color: Colors.white38),
            ],
          ),
        ),
        const SizedBox(height: 24),

        const GlassSectionHeader(title: 'Active Forwarders'),
        if (_forwarders.isEmpty)
          _buildEmptyState('No Forwarders', 'Create forwarders to send events to SIEM')
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
                    Text(forwarder.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('To: ${forwarder.destination}', style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats
        Row(
          children: [
            _buildStatCard('Total', '${_alerts.length}', GlassTheme.primaryAccent),
            const SizedBox(width: 12),
            _buildStatCard('Critical', _alerts.where((a) => a.severity == 'Critical').length.toString(), GlassTheme.errorColor),
            const SizedBox(width: 12),
            _buildStatCard('Active', _alerts.where((a) => !a.isAcknowledged).length.toString(), GlassTheme.warningColor),
          ],
        ),
        const SizedBox(height: 24),

        const GlassSectionHeader(title: 'SIEM Alerts'),
        if (_alerts.isEmpty)
          _buildEmptyState('No Alerts', 'SIEM alerts will appear here')
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

    return GlassCard(
      onTap: () => _showAlertDetails(context, alert),
      tintColor: alert.isAcknowledged ? null : severityColor,
      child: Row(
        children: [
          GlassSvgIconBox(icon: 'bell_bing', color: severityColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alert.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(alert.source, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
                const SizedBox(height: 4),
                Text(alert.description, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GlassBadge(text: alert.severity, color: severityColor, fontSize: 10),
              const SizedBox(height: 4),
              Text(_formatTime(alert.timestamp), style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
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

  void _showAddConnectionDialog(BuildContext context, {String? siemType}) {
    final nameController = TextEditingController();
    final endpointController = TextEditingController();
    final tokenController = TextEditingController();
    String selectedType = siemType ?? 'Splunk';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [GlassTheme.gradientTop, GlassTheme.gradientBottom],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add SIEM Connection', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  dropdownColor: GlassTheme.gradientTop,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'SIEM Type',
                    labelStyle: TextStyle(color: Colors.white.withAlpha(128)),
                    enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: GlassTheme.primaryAccent)),
                  ),
                  items: ['Splunk', 'Elastic', 'ArcSight', 'QRadar', 'Sentinel', 'Chronicle']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => selectedType = v!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Connection Name',
                    labelStyle: TextStyle(color: Colors.white.withAlpha(128)),
                    enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: GlassTheme.primaryAccent)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: endpointController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Endpoint URL',
                    hintText: 'https://your-siem.example.com:8088',
                    hintStyle: TextStyle(color: Colors.white.withAlpha(77)),
                    labelStyle: TextStyle(color: Colors.white.withAlpha(128)),
                    enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: GlassTheme.primaryAccent)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: tokenController,
                  style: const TextStyle(color: Colors.white),
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'API Token / HEC Token',
                    labelStyle: TextStyle(color: Colors.white.withAlpha(128)),
                    enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: GlassTheme.primaryAccent)),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (nameController.text.isNotEmpty && endpointController.text.isNotEmpty) {
                            setState(() {
                              _connections.add(SiemConnection(
                                id: DateTime.now().millisecondsSinceEpoch.toString(),
                                name: nameController.text,
                                type: selectedType,
                                endpoint: endpointController.text,
                                isConnected: true,
                                eventsPerMinute: 0,
                                eventsSent: 0,
                                errors: 0,
                                lastSync: DateTime.now(),
                              ));
                            });
                            Navigator.pop(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GlassTheme.primaryAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Connect'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddForwarderDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Add Event Forwarder', style: TextStyle(color: Colors.white)),
        content: const Text('Configure which events to forward to your SIEM.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: GlassTheme.primaryAccent, foregroundColor: Colors.white),
            child: const Text('Create'),
          ),
        ],
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
                        Text(connection.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const DuotoneIcon('refresh', size: 18),
                      label: const Text('Test Connection'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GlassTheme.primaryAccent,
                        side: const BorderSide(color: GlassTheme.primaryAccent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() => _connections.remove(connection));
                        Navigator.pop(context);
                      },
                      icon: const DuotoneIcon('trash_bin_minimalistic', size: 18),
                      label: const Text('Remove'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GlassTheme.errorColor,
                        side: const BorderSide(color: GlassTheme.errorColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAlertDetails(BuildContext context, SiemAlert alert) {
    // Similar to connection details
    Navigator.pop(context);
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

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  List<SiemConnection> _getSampleConnections() {
    return [
      SiemConnection(
        id: '1',
        name: 'Production Splunk',
        type: 'Splunk',
        endpoint: 'https://splunk.company.com:8088/services/collector',
        isConnected: true,
        eventsPerMinute: 2400,
        eventsSent: 1847293,
        errors: 12,
        lastSync: DateTime.now().subtract(const Duration(seconds: 30)),
      ),
      SiemConnection(
        id: '2',
        name: 'Azure Sentinel',
        type: 'Sentinel',
        endpoint: 'https://company.sentinel.azure.com',
        isConnected: true,
        eventsPerMinute: 890,
        eventsSent: 524891,
        errors: 0,
        lastSync: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
      SiemConnection(
        id: '3',
        name: 'Backup ELK',
        type: 'Elastic',
        endpoint: 'https://elk.company.com:9200',
        isConnected: false,
        eventsPerMinute: 0,
        eventsSent: 98234,
        errors: 47,
        lastSync: DateTime.now().subtract(const Duration(hours: 3)),
      ),
    ];
  }

  List<EventForwarder> _getSampleForwarders() {
    return [
      EventForwarder(
        id: '1',
        name: 'Security Events',
        destination: 'Production Splunk',
        eventTypes: ['threat.detected', 'alert.critical', 'scan.complete'],
        format: 'JSON',
        batchSize: 100,
        isEnabled: true,
      ),
      EventForwarder(
        id: '2',
        name: 'Compliance Events',
        destination: 'Azure Sentinel',
        eventTypes: ['policy.violation', 'access.denied', 'audit.log'],
        format: 'CEF',
        batchSize: 50,
        isEnabled: true,
      ),
    ];
  }

  List<SiemAlert> _getSampleAlerts() {
    return [
      SiemAlert(
        id: '1',
        title: 'High Volume Data Transfer',
        description: 'Unusual data transfer detected from endpoint LAPTOP-042',
        source: 'Splunk',
        severity: 'Critical',
        timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
        isAcknowledged: false,
      ),
      SiemAlert(
        id: '2',
        title: 'Multiple Failed Logins',
        description: 'Brute force attack detected on user account',
        source: 'Sentinel',
        severity: 'High',
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        isAcknowledged: false,
      ),
      SiemAlert(
        id: '3',
        title: 'Suspicious Process',
        description: 'PowerShell execution with encoded command detected',
        source: 'Splunk',
        severity: 'Medium',
        timestamp: DateTime.now().subtract(const Duration(hours: 3)),
        isAcknowledged: true,
      ),
    ];
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
}

class SiemAlert {
  final String id;
  final String title;
  final String description;
  final String source;
  final String severity;
  final DateTime timestamp;
  bool isAcknowledged;

  SiemAlert({
    required this.id,
    required this.title,
    required this.description,
    required this.source,
    required this.severity,
    required this.timestamp,
    required this.isAcknowledged,
  });
}
