/// STIX/TAXII 2.1 Integration Screen
/// Enterprise threat intelligence sharing via STIX/TAXII protocol
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/api/orbguard_api_client.dart';

class StixTaxiiScreen extends StatefulWidget {
  const StixTaxiiScreen({super.key});

  @override
  State<StixTaxiiScreen> createState() => _StixTaxiiScreenState();
}

class _StixTaxiiScreenState extends State<StixTaxiiScreen> {
  bool _isLoading = false;
  String? _error;
  final List<TaxiiServer> _servers = [];
  final List<TaxiiCollection> _collections = [];
  final List<StixObject> _stixObjects = [];

  final _api = OrbGuardApiClient.instance;

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
      // Load servers, collections, and objects in parallel
      final results = await Future.wait([
        _api.getTaxiiServers(),
        _api.getTaxiiCollections(),
      ]);

      final serversData = results[0];
      final collectionsData = results[1];

      // Load STIX objects from all collections
      final List<Map<String, dynamic>> allObjects = [];
      for (final collection in collectionsData) {
        final collectionId = collection['id'] as String?;
        if (collectionId != null) {
          try {
            final objects = await _api.getStixObjects(collectionId);
            allObjects.addAll(objects);
          } catch (_) {
            // Continue loading other collections if one fails
          }
        }
      }

      setState(() {
        _servers.clear();
        _servers.addAll(serversData.map((json) => TaxiiServer.fromJson(json)));

        _collections.clear();
        _collections.addAll(collectionsData.map((json) => TaxiiCollection.fromJson(json)));

        _stixObjects.clear();
        _stixObjects.addAll(allObjects.map((json) => StixObject.fromJson(json)));

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Widget _buildTabContent(Widget content) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppColors.accentInk));
    }
    if (_error != null) {
      return _buildErrorState(_error!);
    }
    return content;
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DuotoneIcon('danger_triangle', size: 48, color: GlassTheme.errorColor.withAlpha(180)),
            const SizedBox(height: 16),
            Text(
              'Failed to Load Data',
              style: TextStyle(
                  color: context.colors.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(color: context.colors.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _loadData,
              icon: const DuotoneIcon('refresh', size: 18),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentInk,
                side: BorderSide(color: AppColors.accentInk),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassTabPage(
      title: 'STIX/TAXII 2.1',
      tabs: [
        GlassTab(
          label: 'Servers',
          iconPath: 'server',
          content: _buildTabContent(_buildServersTab()),
        ),
        GlassTab(
          label: 'Collections',
          iconPath: 'file',
          content: _buildTabContent(_buildCollectionsTab()),
        ),
        GlassTab(
          label: 'Objects',
          iconPath: 'shield',
          content: _buildTabContent(_buildObjectsTab()),
        ),
      ],
      headerContent: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: DuotoneIcon('refresh', size: 22, color: context.colors.onSurface),
              onPressed: _isLoading ? null : _loadData,
              tooltip: 'Refresh',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServersTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Info card
        GlassCard(
          margin: EdgeInsets.zero,
          child: Row(
            children: [
              GlassSvgIconBox(icon: 'info_circle', color: GlassTheme.primaryAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TAXII 2.1 Protocol',
                        style: TextStyle(
                            color: context.colors.onSurface,
                            fontWeight: FontWeight.bold)),
                    Text(
                      'Trusted Automated Exchange of Intelligence Information',
                      style: TextStyle(
                          color: context.colors.onSurfaceVariant,
                          fontSize: 12),
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
            _buildStatCard('Servers', '${_servers.length}', AppColors.accentInk),
            const SizedBox(width: 12),
            _buildStatCard('Connected', '${_servers.where((s) => s.isConnected).length}', AppColors.accentInk),
            const SizedBox(width: 12),
            _buildStatCard('Collections', '${_collections.length}', AppColors.chartColors[4]),
          ],
        ),
        const SizedBox(height: 24),

        // Servers
        const GlassSectionHeader(title: 'TAXII Servers'),
        if (_servers.isEmpty)
          _buildEmptyState('No Servers', 'No TAXII servers are available from the backend')
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
            Text(label,
                style: TextStyle(
                    color: context.colors.onSurfaceVariant, fontSize: 12)),
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
              GlassSvgIconBox(
                icon: 'server_square',
                color: server.isConnected ? GlassTheme.successColor : GlassTheme.errorColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(server.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.colors.onSurface,
                            fontWeight: FontWeight.bold)),
                    Text(server.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.colors.onSurfaceVariant,
                            fontSize: 12)),
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
            style: TextStyle(
                color: context.colors.onSurfaceVariant,
                fontSize: 11,
                fontFamily: 'monospace'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildServerStat('folder', '${server.collectionCount}', 'Collections'),
              const SizedBox(width: 16),
              _buildServerStat('refresh', _formatTime(server.lastSync), 'Last Sync'),
              const SizedBox(width: 16),
              GlassBadge(text: 'TAXII ${server.version}', color: GlassTheme.primaryAccent, fontSize: 10),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServerStat(String icon, String value, String label) {
    final cs = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DuotoneIcon(icon,
            size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
        const SizedBox(width: 4),
        Text(value,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 10)),
      ],
    );
  }

  Widget _buildCollectionsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
        const SizedBox(height: 24),

        // Collections
        if (_collections.isEmpty)
          _buildEmptyState('No Collections', 'The TAXII server exposes no collections')
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
        backgroundColor: context.colors.onSurface.withValues(alpha: 0.06),
        selectedColor: GlassTheme.primaryAccent.withAlpha(50),
        labelStyle: TextStyle(
            color: selected
                ? AppColors.accentInk
                : context.colors.onSurfaceVariant,
            fontSize: 12),
        checkmarkColor: AppColors.accentInk,
      ),
    );
  }

  Widget _buildCollectionCard(TaxiiCollection collection) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: 'folder',
                color: collection.canRead
                    ? GlassTheme.primaryAccent
                    : context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(collection.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.colors.onSurface,
                            fontWeight: FontWeight.bold)),
                    Text(collection.description,
                        style: TextStyle(
                            color: context.colors.onSurfaceVariant,
                            fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${collection.objectCount}',
                      style: TextStyle(
                          color: context.colors.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                  Text('objects',
                      style: TextStyle(
                          color: context.colors.onSurfaceVariant
                              .withValues(alpha: 0.7),
                          fontSize: 10)),
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
                style: TextStyle(
                    color:
                        context.colors.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: collection.mediaTypes
                .take(3)
                .map((type) => GlassBadge(
                    text: type.split('/').last,
                    color: context.colors.onSurfaceVariant,
                    fontSize: 9))
                .toList(),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                  margin: EdgeInsets.zero,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DuotoneIcon(_getStixTypeIcon(entry.key), color: _getStixTypeColor(entry.key), size: 24),
                      const SizedBox(height: 4),
                      Text('${entry.value.length}',
                          style: TextStyle(
                              color: context.colors.onSurface,
                              fontWeight: FontWeight.bold)),
                      Text(entry.key.replaceAll('-', ' '),
                          style: TextStyle(
                              color: context.colors.onSurfaceVariant,
                              fontSize: 9),
                          textAlign: TextAlign.center),
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
          GlassSvgIconBox(
            icon: _getStixTypeIcon(obj.type),
            color: _getStixTypeColor(obj.type),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(obj.name ?? obj.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    GlassBadge(text: obj.type, color: _getStixTypeColor(obj.type), fontSize: 10),
                    const SizedBox(width: 8),
                    Text('v${obj.specVersion}',
                        style: TextStyle(
                            color: context.colors.onSurfaceVariant
                                .withValues(alpha: 0.7),
                            fontSize: 10)),
                  ],
                ),
                if (obj.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    obj.description!,
                    style: TextStyle(
                        color: context.colors.onSurfaceVariant, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Text(_formatTime(obj.created),
              style: TextStyle(
                  color:
                      context.colors.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 10)),
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
            Text(title,
                style: TextStyle(
                    color: context.colors.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle,
                style: TextStyle(color: context.colors.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  void _showServerDetails(BuildContext context, TaxiiServer server) {
    final cs = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            gradient: GlassTheme.backgroundGradient(isDark: context.isDark),
            borderRadius:
                const BorderRadius.vertical(
                top: Radius.circular(GlassTheme.radiusLarge)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  GlassSvgIconBox(icon: 'server_square', color: GlassTheme.primaryAccent, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(server.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        GlassBadge(text: 'TAXII ${server.version}', color: GlassTheme.primaryAccent),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(server.description, style: TextStyle(color: cs.onSurface)),
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
            ],
          ),
        ),
      ),
    );
  }

  void _showObjectDetails(BuildContext context, StixObject obj) {
    final cs = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: GlassTheme.backgroundGradient(isDark: context.isDark),
          borderRadius: const BorderRadius.vertical(
                top: Radius.circular(GlassTheme.radiusLarge)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GlassSvgIconBox(icon: _getStixTypeIcon(obj.type), color: _getStixTypeColor(obj.type), size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(obj.name ?? 'STIX Object',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      GlassBadge(text: obj.type, color: _getStixTypeColor(obj.type)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (obj.description != null) ...[
              Text(obj.description!, style: TextStyle(color: cs.onSurface)),
              const SizedBox(height: 16),
            ],
            GlassContainer(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                'ID: ${obj.id}',
                style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontFamily: 'monospace',
                    fontSize: 11),
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
          Text(label,
              style: TextStyle(color: context.colors.onSurfaceVariant)),
          Flexible(
            child: Text(value,
                style: TextStyle(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  String _getStixTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'indicator':
        return 'danger_triangle';
      case 'malware':
        return 'bug';
      case 'threat-actor':
        return 'user';
      case 'campaign':
        return 'flag';
      case 'attack-pattern':
        return 'structure';
      case 'vulnerability':
        return 'shield';
      case 'tool':
        return 'wrench';
      case 'identity':
        return 'user_circle';
      default:
        return 'widget_5';
    }
  }

  Color _getStixTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'indicator':
        return GlassTheme.warningColor;
      case 'malware':
        return GlassTheme.errorColor;
      case 'threat-actor':
        return AppColors.chartColors[4];
      case 'campaign':
        return AppColors.chartColors[3];
      case 'attack-pattern':
        return AppColors.severityCritical;
      case 'vulnerability':
        return AppColors.secondaryInk;
      case 'tool':
        return AppColors.severityInfo;
      default:
        return AppColors.accentInk;
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

  factory TaxiiServer.fromJson(Map<String, dynamic> json) {
    return TaxiiServer(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? json['name'] as String? ?? 'Unknown Server',
      description: json['description'] as String? ?? '',
      discoveryUrl: json['discovery_url'] as String? ?? json['url'] as String? ?? '',
      version: json['version'] as String? ?? '2.1',
      isConnected: json['is_connected'] as bool? ?? json['connected'] as bool? ?? false,
      collectionCount: json['collection_count'] as int? ?? json['collections'] as int? ?? 0,
      lastSync: json['last_sync'] != null
          ? DateTime.tryParse(json['last_sync'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
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

  factory TaxiiCollection.fromJson(Map<String, dynamic> json) {
    return TaxiiCollection(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? json['name'] as String? ?? 'Unknown Collection',
      description: json['description'] as String? ?? '',
      serverName: json['server_name'] as String? ?? json['server'] as String? ?? 'Unknown Server',
      canRead: json['can_read'] as bool? ?? true,
      canWrite: json['can_write'] as bool? ?? false,
      objectCount: json['object_count'] as int? ?? json['objects'] as int? ?? 0,
      mediaTypes: (json['media_types'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          ['application/stix+json;version=2.1'],
    );
  }
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

  factory StixObject.fromJson(Map<String, dynamic> json) {
    // Extract type from STIX ID if not provided (format: type--uuid)
    String type = json['type'] as String? ?? '';
    if (type.isEmpty && json['id'] != null) {
      final id = json['id'] as String;
      if (id.contains('--')) {
        type = id.split('--').first;
      }
    }

    return StixObject(
      id: json['id'] as String? ?? '',
      type: type,
      specVersion: json['spec_version'] as String? ?? '2.1',
      name: json['name'] as String?,
      description: json['description'] as String?,
      created: json['created'] != null
          ? DateTime.tryParse(json['created'] as String) ?? DateTime.now()
          : DateTime.now(),
      modified: json['modified'] != null
          ? DateTime.tryParse(json['modified'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
