/// URL Protection Screen
/// Main screen for URL/web protection

library url_protection_screen;

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../models/api/url_reputation.dart';
import '../../providers/url_provider.dart';
import '../../widgets/url/url_widgets.dart';

/// Main URL protection screen
class UrlProtectionScreen extends StatefulWidget {
  const UrlProtectionScreen({super.key});

  @override
  State<UrlProtectionScreen> createState() => _UrlProtectionScreenState();
}

class _UrlProtectionScreenState extends State<UrlProtectionScreen>
    with SingleTickerProviderStateMixin {
  final UrlProvider _provider = UrlProvider();
  late TabController _tabController;
  bool _isInitialized = false;
  UrlReputationResult? _checkResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initProvider();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
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
                        foregroundColor: Colors.green,
                      ),
                      icon: const Icon(Icons.check, size: 18),
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
                        foregroundColor: Colors.red,
                      ),
                      icon: const Icon(Icons.block, size: 18),
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
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => _ListManagementSheet(
        provider: _provider,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'URL Protection',
        showBackButton: true,
        actions: [
          GlassAppBarAction(
            icon: Icons.list_alt,
            onTap: _showListManagementSheet,
            tooltip: 'Manage Lists',
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
              child: Container(
                decoration: GlassTheme.glassDecoration(),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: GlassTheme.primaryAccent,
                  labelColor: GlassTheme.primaryAccent,
                  unselectedLabelColor: Colors.white54,
                  tabs: const [
                    Tab(text: 'Check'),
                    Tab(text: 'History'),
                    Tab(text: 'Stats'),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: !_isInitialized
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // Check tab
                    _buildCheckTab(),

                    // History tab
                    _buildHistoryTab(),

                    // Stats tab
                    _buildStatsTab(),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 20),
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

          const SizedBox(height: 20),

          // Recent threats
          if (_provider.recentThreats.isNotEmpty) ...[
            _buildSectionHeader('Recent Threats', onViewAll: () {
              _tabController.animateTo(1);
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
    final history = _provider.history;

    return history.isEmpty
        ? _buildEmptyHistoryState()
        : ListView.builder(
            padding: const EdgeInsets.all(16),
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
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: const Color(0xFF1D1E33),
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
                                    backgroundColor: Colors.red,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: Colors.grey[700],
            ),
            const SizedBox(height: 16),
            Text(
              'No URL History',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'URLs you check will appear here',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
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
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Stats card
          UrlStatsCard(stats: _provider.stats),
          const SizedBox(height: 20),

          // Protection status
          _buildProtectionStatus(),
          const SizedBox(height: 20),

          // List summary
          _buildListSummary(),
        ],
      ),
    );
  }

  Widget _buildProtectionStatus() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Protection Status',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          _StatusRow(
            icon: Icons.security,
            label: 'URL Scanning',
            status: 'Active',
            statusColor: Colors.green,
          ),
          const SizedBox(height: 12),
          _StatusRow(
            icon: Icons.cloud_sync,
            label: 'Threat Intelligence',
            status: 'Connected',
            statusColor: Colors.green,
          ),
          const SizedBox(height: 12),
          _StatusRow(
            icon: Icons.dns,
            label: 'DNS Filtering',
            status: 'Via OrbNet VPN',
            statusColor: GlassTheme.primaryAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildListSummary() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Custom Lists',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
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
                  icon: Icons.check_circle,
                  label: 'Whitelist',
                  count: _provider.whitelist.length,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ListCountCard(
                  icon: Icons.block,
                  label: 'Blacklist',
                  count: _provider.blacklist.length,
                  color: Colors.red,
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
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
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
  final IconData icon;
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
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[500]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withAlpha(50),
            borderRadius: BorderRadius.circular(4),
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
  final IconData icon;
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
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[400],
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
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Manage Lists',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF00D9FF),
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
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: const Color(0xFF0A0E21),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
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
                      isWhitelist ? Colors.green : Colors.red,
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
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
