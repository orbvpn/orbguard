/// URL Protection Screen
/// Main screen for URL/web protection
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../models/api/url_reputation.dart';
import '../../providers/url_provider.dart';
import '../../widgets/url/url_widgets.dart';

/// Main URL protection screen
class UrlProtectionScreen extends StatefulWidget {
  const UrlProtectionScreen({super.key});

  @override
  State<UrlProtectionScreen> createState() => _UrlProtectionScreenState();
}

class _UrlProtectionScreenState extends State<UrlProtectionScreen> {
  final UrlProvider _provider = UrlProvider();
  final GlobalKey<GlassTabPageState> _tabPageKey = GlobalKey<GlassTabPageState>();
  bool _isInitialized = false;
  UrlReputationResult? _checkResult;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initProvider();
  }

  Future<void> _initProvider() async {
    await _provider.init();
    _provider.addListener(_onProviderChanged);
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

  Future<void> _checkUrl(String url) async {
    final result = await _provider.checkUrl(url);
    if (mounted && result != null) {
      setState(() {
        _checkResult = result;
      });
    }
  }

  void _showDomainDetails(String domain) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    await _provider.getDomainDetails(domain);

    if (mounted) {
      Navigator.pop(context); // Close loading dialog
      if (_provider.currentDomainDetails != null) {
        _showDomainDetailsSheet(_provider.currentDomainDetails!);
      }
    }
  }

  void _showDomainDetailsSheet(DomainReputation domain) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GlassTheme.radiusLarge),
        ),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.4),
                    borderRadius:
                        BorderRadius.circular(GlassTheme.radiusXSmall),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              DomainDetailsCard(domain: domain),
              const SizedBox(height: 16),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _provider.addToWhitelist(domain.domain);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${domain.domain} added to whitelist'),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accentInk,
                      ),
                      icon: DuotoneIcon('check_circle',
                          size: 18, color: AppColors.accentInk),
                      label: const Text('Whitelist'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _provider.addToBlacklist(domain.domain);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${domain.domain} added to blacklist'),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.errorInk,
                      ),
                      icon: DuotoneIcon('forbidden',
                          size: 18, color: AppColors.errorInk),
                      label: const Text('Blacklist'),
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

  void _showListManagementSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GlassTheme.radiusLarge),
        ),
      ),
      isScrollControlled: true,
      builder: (context) => _ListManagementSheet(
        provider: _provider,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return GlassTabPage(
        title: 'URL Protection',
        tabs: [
          GlassTab(
            label: 'Check',
            iconPath: 'shield_check',
            content: const Center(child: CircularProgressIndicator()),
          ),
          GlassTab(
            label: 'History',
            iconPath: 'history',
            content: const SizedBox(),
          ),
          GlassTab(
            label: 'Stats',
            iconPath: 'chart',
            content: const SizedBox(),
          ),
        ],
      );
    }

    return GlassTabPage(
      key: _tabPageKey,
      title: 'URL Protection',
      hasSearch: true,
      searchHint: 'Search URLs...',
      onSearchChanged: _onSearchChanged,
      // Screen-level action icon lives in the header pill.
      actions: [
        GestureDetector(
          onTap: _showListManagementSheet,
          child: DuotoneIcon('clipboard_text',
              size: 22, color: Theme.of(context).colorScheme.onSurface),
        ),
      ],
      tabs: [
        GlassTab(
          label: 'Check',
          iconPath: 'shield_check',
          content: _buildCheckTab(),
        ),
        GlassTab(
          label: 'History',
          iconPath: 'history',
          content: _buildHistoryTab(),
        ),
        GlassTab(
          label: 'Stats',
          iconPath: 'chart',
          content: _buildStatsTab(),
        ),
      ],
    );
  }

  Widget _buildCheckTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // URL input
          UrlInputWidget(
            onCheck: _checkUrl,
            isChecking: _provider.isCheckingUrl,
          ),

          // Result
          if (_checkResult != null) ...[
            const SizedBox(height: 24),
            UrlResultCard(
              result: _checkResult!,
              onTap: () => _showDomainDetails(_checkResult!.domain),
              onWhitelist: () {
                _provider.addToWhitelist(_checkResult!.domain);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${_checkResult!.domain} added to whitelist'),
                  ),
                );
              },
              onBlacklist: () {
                _provider.addToBlacklist(_checkResult!.domain);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${_checkResult!.domain} added to blacklist'),
                  ),
                );
              },
            ),
          ],

          const SizedBox(height: 24),

          // Recent threats
          if (_provider.recentThreats.isNotEmpty) ...[
            _buildSectionHeader('Recent Threats', onViewAll: () {
              _tabPageKey.currentState?.animateToTab(1);
            }),
            const SizedBox(height: 12),
            ...List.generate(
              _provider.recentThreats.take(3).length,
              (index) {
                final entry = _provider.recentThreats[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: UrlHistoryItem(
                    entry: entry,
                    onTap: entry.result != null
                        ? () => _showDomainDetails(entry.result!.domain)
                        : null,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    var history = _provider.history;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      history = history.where((entry) {
        return entry.url.toLowerCase().contains(_searchQuery) ||
            (entry.result?.domain.toLowerCase().contains(_searchQuery) ?? false);
      }).toList();
    }

    return history.isEmpty
        ? _buildEmptyHistoryState()
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: history.length + 1, // +1 for clear button
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Text(
                        '${history.length} URLs checked',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      if (_searchQuery.isEmpty)
                        TextButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor:
                                    Theme.of(context).colorScheme.surface,
                                title: const Text('Clear History'),
                                content: const Text(
                                  'Are you sure you want to clear all URL check history?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _provider.clearHistory();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.error,
                                      foregroundColor: Brand.onDanger,
                                    ),
                                    child: const Text('Clear'),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: const Text('Clear All'),
                        ),
                    ],
                  ),
                );
              }

              final entry = history[index - 1];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: UrlHistoryItem(
                  entry: entry,
                  onTap: entry.result != null
                      ? () => _showDomainDetails(entry.result!.domain)
                      : null,
                  onDelete: () => _provider.removeFromHistory(entry.id),
                ),
              );
            },
          );
  }

  Widget _buildEmptyHistoryState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DuotoneIcon(
              'history',
              size: 64,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty ? 'No Results Found' : 'No URL History',
              style: BrandText.title(size: 18, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No URLs match your search'
                  : 'URLs you check will appear here',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        children: [
          // Stats card
          UrlStatsCard(stats: _provider.stats),
          const SizedBox(height: 24),

          // Protection status
          _buildProtectionStatus(),
          const SizedBox(height: 24),

          // List summary
          _buildListSummary(),
        ],
      ),
    );
  }

  Widget _buildProtectionStatus() {
    final scanning = _scanningStatus();
    final threatIntel = _threatIntelStatus();
    return GlassCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Protection Status',
            style: BrandText.title(),
          ),
          const SizedBox(height: 16),
          _StatusRow(
            icon: 'shield_check',
            label: 'URL Scanning',
            status: scanning.$1,
            statusColor: scanning.$2,
          ),
          const SizedBox(height: 12),
          _StatusRow(
            icon: 'refresh',
            label: 'Threat Intelligence',
            status: threatIntel.$1,
            statusColor: threatIntel.$2,
          ),
          if (_provider.listSyncError != null) ...[
            const SizedBox(height: 12),
            Text(
              'Threat intelligence sync error: ${_provider.listSyncError}',
              style: TextStyle(color: AppColors.errorInk, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  /// URL scanning pipeline state derived from real provider signals: a check
  /// in flight, a completed backend round-trip, or an error. Never claims
  /// "Active" before a real URL check has actually returned.
  (String, Color) _scanningStatus() {
    final cs = Theme.of(context).colorScheme;
    if (_provider.isCheckingUrl) return ('Checking...', cs.onSurfaceVariant);
    if (_provider.history.any((e) => e.result != null)) {
      return ('Active', AppColors.accentInk);
    }
    if (_provider.error != null) return ('Error', AppColors.errorInk);
    return ('Ready', cs.onSurfaceVariant);
  }

  /// Threat-intelligence backend connectivity, from the outcome of the
  /// custom-list sync round-trip fired on init. Never claims "Connected"
  /// before a real backend call has succeeded.
  (String, Color) _threatIntelStatus() {
    final cs = Theme.of(context).colorScheme;
    if (_provider.listsSynced) return ('Connected', AppColors.accentInk);
    if (_provider.listSyncError != null) return ('Error', AppColors.errorInk);
    return ('Checking...', cs.onSurfaceVariant);
  }

  Widget _buildListSummary() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Custom Lists',
                style: BrandText.title(),
              ),
              const Spacer(),
              TextButton(
                onPressed: _showListManagementSheet,
                child: const Text('Manage'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ListCountCard(
                  icon: 'check_circle',
                  label: 'Whitelist',
                  count: _provider.whitelist.length,
                  color: AppColors.accentInk,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ListCountCard(
                  icon: 'forbidden',
                  label: 'Blacklist',
                  count: _provider.blacklist.length,
                  color: AppColors.errorInk,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onViewAll}) {
    return Row(
      children: [
        Text(
          title,
          style: BrandText.title(),
        ),
        const Spacer(),
        if (onViewAll != null)
          TextButton(
            onPressed: onViewAll,
            child: const Text('View All'),
          ),
      ],
    );
  }
}

/// Status row widget
class _StatusRow extends StatelessWidget {
  final String icon;
  final String label;
  final String status;
  final Color statusColor;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        DuotoneIcon(icon, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withAlpha(50),
            borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
          ),
          child: Text(
            status,
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// List count card
class _ListCountCard extends StatelessWidget {
  final String icon;
  final String label;
  final int count;
  final Color color;

  const _ListCountCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: GlassTheme.badgeGlassDecoration(tintColor: color),
      child: Row(
        children: [
          DuotoneIcon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              Text(
                count.toString(),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// List management bottom sheet
class _ListManagementSheet extends StatefulWidget {
  final UrlProvider provider;

  const _ListManagementSheet({required this.provider});

  @override
  State<_ListManagementSheet> createState() => _ListManagementSheetState();
}

class _ListManagementSheetState extends State<_ListManagementSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _domainController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    widget.provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _domainController.dispose();
    widget.provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  void _addDomain(bool isWhitelist) {
    final domain = _domainController.text.trim();
    if (domain.isEmpty) return;

    if (isWhitelist) {
      widget.provider.addToWhitelist(domain);
    } else {
      widget.provider.addToBlacklist(domain);
    }

    _domainController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.4),
                    borderRadius:
                        BorderRadius.circular(GlassTheme.radiusXSmall),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Manage Lists',
                  style: BrandText.title(size: 18),
                ),
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            indicatorColor: AppColors.accentInk,
            tabs: [
              Tab(text: 'Whitelist (${widget.provider.whitelist.length})'),
              Tab(text: 'Blacklist (${widget.provider.blacklist.length})'),
            ],
          ),

          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildListTab(true, scrollController),
                _buildListTab(false, scrollController),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListTab(bool isWhitelist, ScrollController scrollController) {
    final list =
        isWhitelist ? widget.provider.whitelist : widget.provider.blacklist;

    return Column(
      children: [
        // Add domain
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _domainController,
                  decoration: InputDecoration(
                    hintText: 'Enter domain (e.g., example.com)',
                    hintStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(GlassTheme.radiusXSmall),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => _addDomain(isWhitelist),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isWhitelist ? AppColors.success : AppColors.error,
                  foregroundColor:
                      isWhitelist ? Brand.onLime : Brand.onDanger,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                child: const Text('Add'),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    'No domains in ${isWhitelist ? 'whitelist' : 'blacklist'}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final entry = list[index];
                    return UrlListTile(
                      entry: entry,
                      onRemove: () => isWhitelist
                          ? widget.provider.removeFromWhitelist(entry.domain)
                          : widget.provider.removeFromBlacklist(entry.domain),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
