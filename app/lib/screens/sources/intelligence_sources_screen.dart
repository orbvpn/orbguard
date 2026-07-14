/// Intelligence Sources Screen
/// Threat intelligence source management interface.
///
/// Wire format (orbguard.lab internal/domain/models/source.go +
/// handlers/sources.go): GET /api/v1/intel/sources returns
/// {data: [Source...], total} where a Source carries {id, name, slug,
/// description?, category, type, status, api_url?, feed_url?, github_urls?,
/// requires_api_key, reliability, weight, update_interval (nanoseconds),
/// last_fetched?, last_error?, error_count, indicator_count, ...}. Enabled
/// state is derived from status == "active" (the server never emits
/// is_enabled). The enable switch issues PATCH /sources/{slug}
/// {enabled: bool}; the add dialog issues POST /sources
/// {name, slug, type, url, description?}.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/api/orbguard_api_client.dart';

class IntelligenceSourcesScreen extends StatefulWidget {
  const IntelligenceSourcesScreen({super.key});

  @override
  State<IntelligenceSourcesScreen> createState() => _IntelligenceSourcesScreenState();
}

class _IntelligenceSourcesScreenState extends State<IntelligenceSourcesScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  final List<IntelSource> _sources = [];

  /// Slugs with an in-flight enable/disable PATCH (switch shows busy).
  final Set<String> _updatingSlugs = {};

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final api = OrbGuardApiClient.instance;
      final sourcesData = await api.getIntelSources();

      if (!mounted) return;
      setState(() {
        _sources.clear();
        _sources.addAll(sourcesData.map(IntelSource.fromJson));
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load intelligence sources: $e';
        _isLoading = false;
      });
    }
  }

  /// Enables/disables a source via PATCH /sources/{slug} {enabled: bool}.
  /// The local row is only updated from the server's response, so the UI
  /// always reflects the persisted status.
  Future<void> _toggleSource(IntelSource source, bool enabled) async {
    setState(() => _updatingSlugs.add(source.slug));

    try {
      final updated = await OrbGuardApiClient.instance
          .updateSource(source.slug, {'enabled': enabled});

      if (!mounted) return;
      setState(() {
        final index = _sources.indexWhere((s) => s.slug == source.slug);
        if (index >= 0) {
          _sources[index] = IntelSource.fromJson(updated);
        }
        _updatingSlugs.remove(source.slug);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _updatingSlugs.remove(source.slug));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Failed to ${enabled ? 'enable' : 'disable'} ${source.name}: $e'),
          backgroundColor: GlassTheme.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Intelligence Sources',
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
          : _errorMessage != null
              ? _buildErrorState()
              : _sources.isEmpty
                  ? _buildEmptyState()
                  : Column(
                  children: [
                    // Actions row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: DuotoneIcon(AppIcons.addCircle, size: 22, color: context.onSurface),
                            onPressed: () => _showAddSourceDialog(context),
                            tooltip: 'Add Source',
                          ),
                          IconButton(
                            icon: DuotoneIcon(AppIcons.refresh, size: 22, color: context.onSurface),
                            onPressed: _isLoading ? null : _loadSources,
                            tooltip: 'Refresh',
                          ),
                        ],
                      ),
                    ),
                    // Content
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: [
                          // Stats
                          Row(
                            children: [
                              _buildStatCard('Active', _sources.where((s) => s.isEnabled).length.toString(), AppColors.accentInk),
                              const SizedBox(width: 12),
                              _buildStatCard('Total IOCs', _formatIOCCount(_sources.fold(0, (sum, s) => sum + s.indicatorCount)), AppColors.accentInk),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Sources grouped by backend category
                          ..._buildCategorySections(),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  /// Groups sources by their backend category, in a stable display order.
  List<Widget> _buildCategorySections() {
    const categoryOrder = [
      'abuse_ch',
      'phishing',
      'ip_reputation',
      'mobile',
      'general',
      'government',
      'isac',
      'community',
      'premium',
    ];

    final byCategory = <String, List<IntelSource>>{};
    for (final source in _sources) {
      byCategory.putIfAbsent(source.category, () => []).add(source);
    }

    final orderedCategories = [
      ...categoryOrder.where(byCategory.containsKey),
      ...byCategory.keys.where((c) => !categoryOrder.contains(c)),
    ];

    return [
      for (final category in orderedCategories) ...[
        GlassSectionHeader(title: _categoryDisplayName(category)),
        ...byCategory[category]!.map(_buildSourceCard),
      ],
    ];
  }

  String _categoryDisplayName(String category) {
    switch (category) {
      case 'abuse_ch':
        return 'Abuse.ch';
      case 'phishing':
        return 'Phishing';
      case 'ip_reputation':
        return 'IP Reputation';
      case 'mobile':
        return 'Mobile & Spyware';
      case 'general':
        return 'General';
      case 'government':
        return 'Government';
      case 'isac':
        return 'ISAC';
      case 'community':
        return 'Community';
      case 'premium':
        return 'Premium';
      default:
        return category;
    }
  }

  String _formatIOCCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: context.onSurfaceMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceCard(IntelSource source) {
    final cs = Theme.of(context).colorScheme;
    final isUpdating = _updatingSlugs.contains(source.slug);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: _getSourceIcon(source.type),
                color: source.hasError
                    ? GlassTheme.errorColor
                    : source.isEnabled
                        ? GlassTheme.successColor
                        : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      source.type.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isUpdating)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accentInk),
                  ),
                )
              else
                Switch(
                  value: source.isEnabled,
                  onChanged: (v) => _toggleSource(source, v),
                  activeThumbColor: GlassTheme.successColor,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSourceStat(AppIcons.database, '${source.indicatorCount} IOCs'),
              const SizedBox(width: 16),
              _buildSourceStat(AppIcons.clock, 'Fetched ${_formatLastFetched(source.lastFetched)}'),
            ],
          ),
          if (source.description != null && source.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              source.description!,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (source.hasError && source.lastError != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DuotoneIcon(AppIcons.dangerTriangle,
                    size: 14, color: GlassTheme.errorColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    source.lastError!,
                    style: const TextStyle(
                        color: GlassTheme.errorColor, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              GlassBadge(
                text: source.status.toUpperCase(),
                color: source.hasError
                    ? GlassTheme.errorColor
                    : source.isEnabled
                        ? GlassTheme.successColor
                        : cs.onSurfaceVariant,
                fontSize: 10,
              ),
              const SizedBox(width: 8),
              if (source.updateInterval != null)
                GlassBadge(
                  text: 'every ${_formatInterval(source.updateInterval!)}',
                  color: AppColors.chartColors[4],
                  fontSize: 10,
                ),
              if (source.requiresApiKey) ...[
                const SizedBox(width: 8),
                const GlassBadge(text: 'API KEY', color: GlassTheme.warningColor, fontSize: 10),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatLastFetched(DateTime? time) {
    if (time == null) return 'never';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatInterval(Duration interval) {
    if (interval.inHours >= 24 && interval.inHours % 24 == 0) {
      return '${interval.inDays}d';
    }
    if (interval.inMinutes >= 60 && interval.inMinutes % 60 == 0) {
      return '${interval.inHours}h';
    }
    return '${interval.inMinutes}m';
  }

  Widget _buildSourceStat(String icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DuotoneIcon(icon, size: 14, color: context.onSurfaceMuted),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: context.onSurfaceMuted, fontSize: 12)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(AppIcons.intelligence, size: 64, color: AppColors.accentInk.withAlpha(128)),
          const SizedBox(height: 16),
          Text(
            'No Intelligence Sources',
            style: TextStyle(color: context.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Add threat intelligence feeds to enrich your data',
            style: TextStyle(color: context.onSurfaceMuted),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _showAddSourceDialog(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.primaryAccent,
              foregroundColor: Brand.onLime,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DuotoneIcon(AppIcons.addCircle, size: 18, color: Brand.onLime),
                const SizedBox(width: 8),
                const Text('Add Source'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(AppIcons.dangerTriangle, size: 64, color: GlassTheme.errorColor.withAlpha(128)),
          const SizedBox(height: 16),
          Text(
            'Failed to Load Sources',
            style: TextStyle(color: context.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? 'An unexpected error occurred',
              style: TextStyle(color: context.onSurfaceMuted),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadSources,
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.primaryAccent,
              foregroundColor: Brand.onLime,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DuotoneIcon(AppIcons.refresh, size: 18, color: Brand.onLime),
                const SizedBox(width: 8),
                const Text('Retry'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddSourceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _AddSourceDialog(
        onCreated: (created) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(content: Text('Source "${created.name}" created')),
          );
          _loadSources();
        },
      ),
    );
  }

  String _getSourceIcon(String type) {
    switch (type.toLowerCase()) {
      case 'taxii':
        return AppIcons.stixTaxii;
      case 'api':
        return AppIcons.code;
      case 'feed':
        return AppIcons.fileText;
      case 'github':
        return AppIcons.programming;
      case 'community':
        return AppIcons.usersGroup;
      default:
        return AppIcons.intelligence;
    }
  }
}

/// Add-source dialog. Posts {name, slug, type, url, description?} via
/// POST /api/v1/sources and surfaces server-side validation errors inline.
class _AddSourceDialog extends StatefulWidget {
  final void Function(IntelSource created) onCreated;

  const _AddSourceDialog({required this.onCreated});

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _urlController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Mirrors the backend SourceType constants (models/source.go); "manual"
  // and "community" sources do not require a URL.
  static const _types = ['api', 'feed', 'github', 'taxii', 'manual', 'community'];
  String _type = 'feed';

  /// True once the user has manually edited the slug field, which stops
  /// the automatic slug suggestion derived from the name.
  bool _slugEdited = false;

  bool _isSubmitting = false;
  String? _error;

  bool get _urlRequired =>
      _type == 'api' || _type == 'feed' || _type == 'github' || _type == 'taxii';

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Derives a slug suggestion from the source name
  /// (matching the server's ^[a-z0-9][a-z0-9_-]{1,63}$ pattern).
  String _suggestSlug(String name) {
    var slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.length > 64) slug = slug.substring(0, 64);
    return slug;
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final slug = _slugController.text.trim().toLowerCase();
    final url = _urlController.text.trim();
    final description = _descriptionController.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    if (slug.isEmpty) {
      setState(() => _error = 'Slug is required');
      return;
    }
    if (_urlRequired && url.isEmpty) {
      setState(() => _error = 'URL is required for $_type sources');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final created = await OrbGuardApiClient.instance.createSource({
        'name': name,
        'slug': slug,
        'type': _type,
        if (url.isNotEmpty) 'url': url,
        if (description.isNotEmpty) 'description': description,
      });

      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreated(IntelSource.fromJson(created));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = '$e';
      });
    }
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: context.onSurfaceMuted),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      title: Text('Add Intelligence Source', style: TextStyle(color: cs.onSurface)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              style: TextStyle(color: cs.onSurface),
              decoration: _decoration('Source Name'),
              onChanged: (value) {
                if (!_slugEdited) {
                  _slugController.text = _suggestSlug(value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _slugController,
              style: TextStyle(color: cs.onSurface, fontFamily: Brand.fontMono),
              decoration: _decoration('Slug (a-z, 0-9, _, -)'),
              onChanged: (_) => _slugEdited = true,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              dropdownColor: cs.surface,
              style: TextStyle(color: cs.onSurface),
              decoration: _decoration('Type'),
              items: _types
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.toUpperCase())))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? 'feed'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              style: TextStyle(color: cs.onSurface, fontFamily: Brand.fontMono),
              decoration: _decoration(_urlRequired ? 'Feed/API URL' : 'URL (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              style: TextStyle(color: cs.onSurface),
              decoration: _decoration('Description (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DuotoneIcon(AppIcons.dangerTriangle,
                      size: 16, color: GlassTheme.errorColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: GlassTheme.errorColor, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accentInk),
                )
              : Text('Add', style: TextStyle(color: AppColors.accentInk)),
        ),
      ],
    );
  }
}

/// Parsed view of a backend Source (models/source.go). Enabled state is
/// derived from status == "active"; the server never emits is_enabled.
class IntelSource {
  final String name;
  final String slug;
  final String type;
  final String category;
  final String status;
  final int indicatorCount;
  final DateTime? lastFetched;
  final Duration? updateInterval;
  final bool requiresApiKey;
  final String? description;
  final String? lastError;

  IntelSource({
    required this.name,
    required this.slug,
    required this.type,
    required this.category,
    required this.status,
    required this.indicatorCount,
    this.lastFetched,
    this.updateInterval,
    this.requiresApiKey = false,
    this.description,
    this.lastError,
  });

  bool get isEnabled => status == 'active';
  bool get hasError => status == 'error';

  factory IntelSource.fromJson(Map<String, dynamic> json) {
    // Go serializes time.Duration as nanoseconds.
    Duration? interval;
    final rawInterval = json['update_interval'];
    if (rawInterval is num && rawInterval > 0) {
      interval = Duration(microseconds: rawInterval ~/ 1000);
    }

    final rawFetched = json['last_fetched'];
    final lastFetched =
        rawFetched is String ? DateTime.tryParse(rawFetched)?.toLocal() : null;

    return IntelSource(
      name: json['name'] as String? ?? 'Unknown',
      slug: json['slug'] as String? ?? '',
      type: json['type'] as String? ?? 'unknown',
      category: json['category'] as String? ?? 'general',
      status: json['status'] as String? ?? 'disabled',
      indicatorCount: (json['indicator_count'] as num?)?.toInt() ?? 0,
      lastFetched: lastFetched,
      updateInterval: interval,
      requiresApiKey: json['requires_api_key'] as bool? ?? false,
      description: json['description'] as String?,
      lastError: json['last_error'] as String?,
    );
  }
}
