/// STIX/TAXII 2.1 Integration Screen
/// Enterprise threat intelligence sharing via STIX/TAXII protocol
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';

class StixTaxiiScreen extends StatefulWidget {
  const StixTaxiiScreen({super.key});

  @override
  State<StixTaxiiScreen> createState() => _StixTaxiiScreenState();
}

class _StixTaxiiScreenState extends State<StixTaxiiScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  final List<TaxiiServer> _servers = [];
  final List<TaxiiCollection> _collections = [];
  final List<StixObject> _stixObjects = [];

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
      _servers.addAll(_getSampleServers());
      _collections.addAll(_getSampleCollections());
      _stixObjects.addAll(_getSampleStixObjects());
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'STIX/TAXII 2.1',
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Server',
            onPressed: () => _showAddServerDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GlassTheme.primaryAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Servers'),
            Tab(text: 'Collections'),
            Tab(text: 'Objects'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildServersTab(),
                _buildCollectionsTab(),
                _buildObjectsTab(),
              ],
            ),
    );
  }

  Widget _buildServersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Info card
        GlassCard(
          child: Row(
            children: [
              GlassIconBox(icon: Icons.info_outline, color: GlassTheme.primaryAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TAXII 2.1 Protocol', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(
                      'Trusted Automated Exchange of Intelligence Information',
                      style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Stats
        Row(
          children: [
            _buildStatCard('Servers', '${_servers.length}', GlassTheme.primaryAccent),
            const SizedBox(width: 12),
            _buildStatCard('Connected', '${_servers.where((s) => s.isConnected).length}', GlassTheme.successColor),
            const SizedBox(width: 12),
            _buildStatCard('Collections', '${_collections.length}', const Color(0xFF9C27B0)),
          ],
        ),
        const SizedBox(height: 24),

        // Servers
        const GlassSectionHeader(title: 'TAXII Servers'),
        if (_servers.isEmpty)
          _buildEmptyState('No Servers', 'Add a TAXII server to start sharing threat intelligence')
        else
          ..._servers.map((server) => _buildServerCard(server)),
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

  Widget _buildServerCard(TaxiiServer server) {
    return GlassCard(
      onTap: () => _showServerDetails(context, server),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassIconBox(
                icon: Icons.dns,
                color: server.isConnected ? GlassTheme.successColor : GlassTheme.errorColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(server.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(server.description, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
                  ],
                ),
              ),
              GlassBadge(
                text: server.isConnected ? 'Connected' : 'Disconnected',
                color: server.isConnected ? GlassTheme.successColor : GlassTheme.errorColor,
                fontSize: 10,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            server.discoveryUrl,
            style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 11, fontFamily: 'monospace'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildServerStat(Icons.folder, '${server.collectionCount}', 'Collections'),
              const SizedBox(width: 16),
              _buildServerStat(Icons.sync, _formatTime(server.lastSync), 'Last Sync'),
              const SizedBox(width: 16),
              GlassBadge(text: 'TAXII ${server.version}', color: GlassTheme.primaryAccent, fontSize: 10),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServerStat(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white38),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(77), fontSize: 10)),
      ],
    );
  }

  Widget _buildCollectionsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Filter options
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip('All', true),
              _buildFilterChip('Subscribed', false),
              _buildFilterChip('Published', false),
              _buildFilterChip('Read Only', false),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Collections
        if (_collections.isEmpty)
          _buildEmptyState('No Collections', 'Connect to a TAXII server to view collections')
        else
          ..._collections.map((collection) => _buildCollectionCard(collection)),
      ],
    );
  }

  Widget _buildFilterChip(String label, bool selected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (v) {},
        backgroundColor: Colors.white12,
        selectedColor: GlassTheme.primaryAccent.withAlpha(50),
        labelStyle: TextStyle(color: selected ? GlassTheme.primaryAccent : Colors.white70, fontSize: 12),
        checkmarkColor: GlassTheme.primaryAccent,
      ),
    );
  }

  Widget _buildCollectionCard(TaxiiCollection collection) {
    return GlassCard(
      onTap: () => _showCollectionDetails(context, collection),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassIconBox(
                icon: Icons.folder,
                color: collection.canRead ? GlassTheme.primaryAccent : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(collection.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(collection.description, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${collection.objectCount}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  Text('objects', style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (collection.canRead)
                GlassBadge(text: 'Read', color: GlassTheme.successColor, fontSize: 10),
              const SizedBox(width: 6),
              if (collection.canWrite)
                GlassBadge(text: 'Write', color: GlassTheme.primaryAccent, fontSize: 10),
              const Spacer(),
              Text(
                'Server: ${collection.serverName}',
                style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: collection.mediaTypes.take(3).map((type) => GlassBadge(text: type.split('/').last, color: Colors.grey, fontSize: 9)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildObjectsTab() {
    final typeGroups = <String, List<StixObject>>{};
    for (final obj in _stixObjects) {
      typeGroups.putIfAbsent(obj.type, () => []).add(obj);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Object type stats
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: typeGroups.entries.map((entry) {
              return Container(
                width: 100,
                margin: const EdgeInsets.only(right: 12),
                child: GlassCard(
                  onTap: () {},
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_getStixTypeIcon(entry.key), color: _getStixTypeColor(entry.key), size: 24),
                      const SizedBox(height: 4),
                      Text('${entry.value.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text(entry.key.replaceAll('-', ' '), style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 9), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),

        // Recent objects
        const GlassSectionHeader(title: 'Recent STIX Objects'),
        if (_stixObjects.isEmpty)
          _buildEmptyState('No Objects', 'Sync collections to view STIX objects')
        else
          ..._stixObjects.take(10).map((obj) => _buildStixObjectCard(obj)),
      ],
    );
  }

  Widget _buildStixObjectCard(StixObject obj) {
    return GlassCard(
      onTap: () => _showObjectDetails(context, obj),
      child: Row(
        children: [
          GlassIconBox(
            icon: _getStixTypeIcon(obj.type),
            color: _getStixTypeColor(obj.type),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(obj.name ?? obj.id, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    GlassBadge(text: obj.type, color: _getStixTypeColor(obj.type), fontSize: 10),
                    const SizedBox(width: 8),
                    Text('v${obj.specVersion}', style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10)),
                  ],
                ),
                if (obj.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    obj.description!,
                    style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Text(_formatTime(obj.created), style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10)),
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
            Icon(Icons.inbox, size: 48, color: GlassTheme.primaryAccent.withAlpha(128)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(153)), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  void _showAddServerDialog(BuildContext context) {
    final titleController = TextEditingController();
    final urlController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
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
              const Text('Add TAXII Server', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Connect to a TAXII 2.1 server to share threat intelligence', style: TextStyle(color: Colors.white.withAlpha(153))),
              const SizedBox(height: 24),
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Server Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Discovery URL', hint: 'https://taxii.server.com/taxii2/'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: usernameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Username (Optional)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: passwordController,
                      style: const TextStyle(color: Colors.white),
                      obscureText: true,
                      decoration: _inputDecoration('Password'),
                    ),
                  ),
                ],
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
                        if (titleController.text.isNotEmpty && urlController.text.isNotEmpty) {
                          setState(() {
                            _servers.add(TaxiiServer(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              title: titleController.text,
                              description: 'Custom TAXII server',
                              discoveryUrl: urlController.text,
                              version: '2.1',
                              isConnected: true,
                              collectionCount: 0,
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
    );
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: Colors.white.withAlpha(128)),
      hintStyle: TextStyle(color: Colors.white.withAlpha(77)),
      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: GlassTheme.primaryAccent)),
    );
  }

  void _showServerDetails(BuildContext context, TaxiiServer server) {
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
                  GlassIconBox(icon: Icons.dns, color: GlassTheme.primaryAccent, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(server.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        GlassBadge(text: 'TAXII ${server.version}', color: GlassTheme.primaryAccent),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(server.description, style: TextStyle(color: Colors.white.withAlpha(204))),
              const SizedBox(height: 20),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Status', server.isConnected ? 'Connected' : 'Disconnected'),
                    _buildDetailRow('Discovery URL', server.discoveryUrl),
                    _buildDetailRow('Collections', '${server.collectionCount}'),
                    _buildDetailRow('Last Sync', _formatTime(server.lastSync)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.sync),
                      label: const Text('Sync Now'),
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
                        setState(() => _servers.remove(server));
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.delete),
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

  void _showCollectionDetails(BuildContext context, TaxiiCollection collection) {
    // Show collection details
  }

  void _showObjectDetails(BuildContext context, StixObject obj) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [GlassTheme.gradientTop, GlassTheme.gradientBottom],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GlassIconBox(icon: _getStixTypeIcon(obj.type), color: _getStixTypeColor(obj.type), size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(obj.name ?? 'STIX Object', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      GlassBadge(text: obj.type, color: _getStixTypeColor(obj.type)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (obj.description != null) ...[
              Text(obj.description!, style: TextStyle(color: Colors.white.withAlpha(204))),
              const SizedBox(height: 16),
            ],
            GlassContainer(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                'ID: ${obj.id}',
                style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 11),
              ),
            ),
            const SizedBox(height: 16),
            GlassContainer(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _buildDetailRow('Spec Version', obj.specVersion),
                  _buildDetailRow('Created', _formatDate(obj.created)),
                  _buildDetailRow('Modified', _formatDate(obj.modified)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withAlpha(153))),
          Flexible(
            child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  IconData _getStixTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'indicator':
        return Icons.warning;
      case 'malware':
        return Icons.bug_report;
      case 'threat-actor':
        return Icons.person;
      case 'campaign':
        return Icons.campaign;
      case 'attack-pattern':
        return Icons.pattern;
      case 'vulnerability':
        return Icons.security;
      case 'tool':
        return Icons.build;
      case 'identity':
        return Icons.badge;
      default:
        return Icons.category;
    }
  }

  Color _getStixTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'indicator':
        return GlassTheme.warningColor;
      case 'malware':
        return GlassTheme.errorColor;
      case 'threat-actor':
        return const Color(0xFF9C27B0);
      case 'campaign':
        return const Color(0xFF2196F3);
      case 'attack-pattern':
        return const Color(0xFFFF5722);
      case 'vulnerability':
        return const Color(0xFFE91E63);
      case 'tool':
        return const Color(0xFF607D8B);
      default:
        return GlassTheme.primaryAccent;
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  List<TaxiiServer> _getSampleServers() {
    return [
      TaxiiServer(
        id: '1',
        title: 'MITRE ATT&CK',
        description: 'MITRE ATT&CK knowledge base of adversary tactics and techniques',
        discoveryUrl: 'https://cti-taxii.mitre.org/taxii2/',
        version: '2.1',
        isConnected: true,
        collectionCount: 2,
        lastSync: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      TaxiiServer(
        id: '2',
        title: 'AlienVault OTX',
        description: 'Open Threat Exchange by AlienVault',
        discoveryUrl: 'https://otx.alienvault.com/taxii/',
        version: '2.1',
        isConnected: true,
        collectionCount: 5,
        lastSync: DateTime.now().subtract(const Duration(minutes: 30)),
      ),
      TaxiiServer(
        id: '3',
        title: 'Internal CTI',
        description: 'Internal threat intelligence repository',
        discoveryUrl: 'https://cti.company.com/taxii2/',
        version: '2.1',
        isConnected: false,
        collectionCount: 3,
        lastSync: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ];
  }

  List<TaxiiCollection> _getSampleCollections() {
    return [
      TaxiiCollection(
        id: 'enterprise-attack',
        title: 'Enterprise ATT&CK',
        description: 'ATT&CK for Enterprise covers behaviors adversaries may exhibit',
        serverName: 'MITRE ATT&CK',
        canRead: true,
        canWrite: false,
        objectCount: 1247,
        mediaTypes: ['application/stix+json;version=2.1'],
      ),
      TaxiiCollection(
        id: 'mobile-attack',
        title: 'Mobile ATT&CK',
        description: 'ATT&CK for Mobile covers behaviors against mobile devices',
        serverName: 'MITRE ATT&CK',
        canRead: true,
        canWrite: false,
        objectCount: 342,
        mediaTypes: ['application/stix+json;version=2.1'],
      ),
      TaxiiCollection(
        id: 'otx-pulses',
        title: 'OTX Pulses',
        description: 'Community-contributed threat intelligence pulses',
        serverName: 'AlienVault OTX',
        canRead: true,
        canWrite: true,
        objectCount: 48293,
        mediaTypes: ['application/stix+json;version=2.1', 'application/stix+json;version=2.0'],
      ),
    ];
  }

  List<StixObject> _getSampleStixObjects() {
    return [
      StixObject(
        id: 'indicator--8e2e2d2b-17d4-4cbf-938f-98ee46b3cd3f',
        type: 'indicator',
        specVersion: '2.1',
        name: 'Malicious IP Address',
        description: 'IP address associated with command and control activity',
        created: DateTime.now().subtract(const Duration(hours: 4)),
        modified: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      StixObject(
        id: 'malware--fdd60b30-b67c-41e3-b0b9-f01faf20d111',
        type: 'malware',
        specVersion: '2.1',
        name: 'Emotet',
        description: 'Banking trojan that has evolved into a modular malware platform',
        created: DateTime.now().subtract(const Duration(days: 1)),
        modified: DateTime.now().subtract(const Duration(hours: 6)),
      ),
      StixObject(
        id: 'threat-actor--56f3f0db-b5d5-431c-ae56-c18f02caf500',
        type: 'threat-actor',
        specVersion: '2.1',
        name: 'APT29',
        description: 'Russian state-sponsored threat actor group',
        created: DateTime.now().subtract(const Duration(days: 7)),
        modified: DateTime.now().subtract(const Duration(days: 1)),
      ),
      StixObject(
        id: 'attack-pattern--970cdb5c-02fb-4c38-b17e-d6327cf3c810',
        type: 'attack-pattern',
        specVersion: '2.1',
        name: 'Spearphishing Attachment',
        description: 'Sending emails with a malicious attachment',
        created: DateTime.now().subtract(const Duration(days: 30)),
        modified: DateTime.now().subtract(const Duration(days: 14)),
      ),
      StixObject(
        id: 'campaign--83422c77-904c-4dc1-aff5-5c38f3a2c55c',
        type: 'campaign',
        specVersion: '2.1',
        name: 'Operation SolarWinds',
        description: 'Supply chain attack targeting IT management software',
        created: DateTime.now().subtract(const Duration(days: 60)),
        modified: DateTime.now().subtract(const Duration(days: 30)),
      ),
    ];
  }
}

class TaxiiServer {
  final String id;
  final String title;
  final String description;
  final String discoveryUrl;
  final String version;
  bool isConnected;
  final int collectionCount;
  final DateTime lastSync;

  TaxiiServer({
    required this.id,
    required this.title,
    required this.description,
    required this.discoveryUrl,
    required this.version,
    required this.isConnected,
    required this.collectionCount,
    required this.lastSync,
  });
}

class TaxiiCollection {
  final String id;
  final String title;
  final String description;
  final String serverName;
  final bool canRead;
  final bool canWrite;
  final int objectCount;
  final List<String> mediaTypes;

  TaxiiCollection({
    required this.id,
    required this.title,
    required this.description,
    required this.serverName,
    required this.canRead,
    required this.canWrite,
    required this.objectCount,
    required this.mediaTypes,
  });
}

class StixObject {
  final String id;
  final String type;
  final String specVersion;
  final String? name;
  final String? description;
  final DateTime created;
  final DateTime modified;

  StixObject({
    required this.id,
    required this.type,
    required this.specVersion,
    this.name,
    this.description,
    required this.created,
    required this.modified,
  });
}
