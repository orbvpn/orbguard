/// Intelligence Core Screen
/// Central threat intelligence browsing, searching, and indicator checking
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/api/orbguard_api_client.dart';
import '../../models/api/threat_indicator.dart' as api;

class IntelligenceCoreScreen extends StatefulWidget {
  /// When true, skips the outer page wrapper (for embedding in other screens)
  final bool embedded;

  const IntelligenceCoreScreen({super.key, this.embedded = false});

  @override
  State<IntelligenceCoreScreen> createState() => _IntelligenceCoreScreenState();
}

class _IntelligenceCoreScreenState extends State<IntelligenceCoreScreen> {
  bool _isLoading = false;
  bool _isSearching = false;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _checkInputController = TextEditingController();
  final List<api.ThreatIndicator> _indicators = [];
  final List<api.ThreatIndicator> _searchResults = [];
  final List<api.IndicatorCheckResult> _checkHistory = [];
  String _selectedType = 'All';

  final List<String> _indicatorTypes = [
    'All',
    'IP Address',
    'Domain',
    'URL',
    'Hash (MD5)',
    'Hash (SHA256)',
    'Email',
    'File Name',
  ];

  @override
  void initState() {
    super.initState();
    _loadIndicators();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _checkInputController.dispose();
    super.dispose();
  }

  Future<void> _loadIndicators() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Add timeout to prevent hanging (5 seconds)
      final response = await OrbGuardApiClient.instance.listIndicators()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        throw Exception('Request timed out');
      });
      if (mounted) {
        setState(() {
          _indicators.clear();
          _indicators.addAll(response.items);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load indicators: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show tabs immediately - don't block on loading
    return GlassTabPage(
      title: 'Intelligence Core',
      hasSearch: true,
      searchHint: 'Search IOCs...',
      embedded: widget.embedded,
      actions: [
        IconButton(
          icon: const DuotoneIcon('file', size: 22, color: Colors.white),
          tooltip: 'Import Indicators',
          onPressed: () => _showImportDialog(context),
        ),
        IconButton(
          icon: const DuotoneIcon('refresh', size: 22, color: Colors.white),
          onPressed: _isLoading ? null : _loadIndicators,
          tooltip: 'Refresh',
        ),
      ],
      tabs: [
        GlassTab(
          label: 'Browse',
          iconPath: 'file',
          content: _buildBrowseTab(),
        ),
        GlassTab(
          label: 'Check',
          iconPath: 'magnifier',
          content: _buildCheckTab(),
        ),
        GlassTab(
          label: 'History',
          iconPath: 'chart',
          content: _buildHistoryTab(),
        ),
      ],
    );
  }

  String _getTypeDisplayName(api.IndicatorType type) {
    switch (type) {
      case api.IndicatorType.ipv4:
      case api.IndicatorType.ipv6:
        return 'IP Address';
      case api.IndicatorType.domain:
        return 'Domain';
      case api.IndicatorType.url:
        return 'URL';
      case api.IndicatorType.md5:
        return 'Hash (MD5)';
      case api.IndicatorType.sha256:
      case api.IndicatorType.sha1:
        return 'Hash (SHA256)';
      case api.IndicatorType.email:
        return 'Email';
      case api.IndicatorType.processName:
      case api.IndicatorType.bundleId:
      case api.IndicatorType.packageName:
        return 'File Name';
      default:
        return type.name;
    }
  }

  Widget _buildBrowseTab() {
    // Show loading state inline
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: GlassTheme.primaryAccent),
            const SizedBox(height: 16),
            Text(
              'Loading indicators...',
              style: TextStyle(color: Colors.white.withAlpha(179)),
            ),
          ],
        ),
      );
    }

    // Show error state
    if (_error != null && _indicators.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DuotoneIcon('danger_circle', size: 48, color: GlassTheme.errorColor),
            const SizedBox(height: 16),
            Text(
              'Failed to load indicators',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadIndicators,
              icon: const DuotoneIcon('refresh', size: 18, color: Colors.white),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: GlassTheme.primaryAccent),
            ),
          ],
        ),
      );
    }

    final filteredIndicators = _selectedType == 'All'
        ? _indicators
        : _indicators.where((i) => _getTypeDisplayName(i.type) == _selectedType).toList();

    return Column(
      children: [
        // Search and Filter Bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Search
              GlassContainer(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const DuotoneIcon('magnifer', size: 20, color: Colors.white38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Search indicators...',
                          hintStyle: TextStyle(color: Colors.white38),
                          border: InputBorder.none,
                        ),
                        onChanged: (value) => setState(() {}),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const DuotoneIcon('close_circle', size: 20, color: Colors.white38),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Type Filter
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _indicatorTypes.map((type) {
                    final isSelected = _selectedType == type;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(type),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() => _selectedType = type);
                        },
                        backgroundColor: Colors.white12,
                        selectedColor: GlassTheme.primaryAccent.withAlpha(50),
                        labelStyle: TextStyle(
                          color: isSelected ? GlassTheme.primaryAccent : Colors.white70,
                          fontSize: 12,
                        ),
                        checkmarkColor: GlassTheme.primaryAccent,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        // Stats
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildStatCard('Total', _indicators.length.toString(), GlassTheme.primaryAccent),
              const SizedBox(width: 12),
              _buildStatCard('Critical', _indicators.where((i) => i.severity == api.SeverityLevel.critical || i.severity == api.SeverityLevel.high).length.toString(), GlassTheme.errorColor),
              const SizedBox(width: 12),
              _buildStatCard('Medium', _indicators.where((i) => i.severity == api.SeverityLevel.medium).length.toString(), GlassTheme.warningColor),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Indicators List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filteredIndicators.length,
            itemBuilder: (context, index) {
              final indicator = filteredIndicators[index];
              if (_searchController.text.isNotEmpty &&
                  !indicator.value.toLowerCase().contains(_searchController.text.toLowerCase())) {
                return const SizedBox.shrink();
              }
              return _buildIndicatorCard(indicator);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicatorCard(api.ThreatIndicator indicator) {
    final statusColor = Color(indicator.severity.color);
    final statusText = indicator.severity.displayName;

    return GlassCard(
      onTap: () => _showIndicatorDetails(context, indicator),
      child: Row(
        children: [
          GlassSvgIconBox(
            icon: _getIndicatorSvgIcon(_getTypeDisplayName(indicator.type)),
            color: statusColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  indicator.value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    GlassBadge(text: _getTypeDisplayName(indicator.type), color: GlassTheme.primaryAccent, fontSize: 10),
                    const SizedBox(width: 8),
                    Text(
                      indicator.sourceName ?? 'Unknown',
                      style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GlassBadge(text: statusText, color: statusColor, fontSize: 10),
              const SizedBox(height: 4),
              Text(
                '${(indicator.confidence * 100).toInt()}% conf',
                style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Check Input
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Check Indicator',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter an IP address, domain, URL, hash, or email to check against threat intelligence',
                  style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _checkInputController,
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Enter indicators (one per line)\ne.g., 192.168.1.1\nmalware.com\n5d41402abc4b2a76b9719d911017c592',
                    hintStyle: TextStyle(color: Colors.white.withAlpha(77)),
                    filled: true,
                    fillColor: Colors.white.withAlpha(13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSearching ? null : () => _checkIndicators(),
                    icon: _isSearching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const DuotoneIcon('magnifer', size: 20),
                    label: Text(_isSearching ? 'Checking...' : 'Check Indicators'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GlassTheme.primaryAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Quick Check Buttons
          const GlassSectionHeader(title: 'Quick Check'),
          Row(
            children: [
              _buildQuickCheckButton('globus', 'IP Address', 'Check IP reputation'),
              const SizedBox(width: 12),
              _buildQuickCheckButton('server', 'Domain', 'Check domain reputation'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildQuickCheckButton('link', 'URL', 'Check URL safety'),
              const SizedBox(width: 12),
              _buildQuickCheckButton('object_scan', 'File Hash', 'Check file hash'),
            ],
          ),

          // Search Results
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 24),
            const GlassSectionHeader(title: 'Results'),
            ..._searchResults.map((indicator) => _buildIndicatorCard(indicator)),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickCheckButton(String icon, String title, String subtitle) {
    return Expanded(
      child: GlassCard(
        onTap: () => _showQuickCheckDialog(context, title),
        child: Row(
          children: [
            GlassSvgIconBox(icon: icon, color: GlassTheme.primaryAccent, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13)),
                  Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_checkHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuotoneIcon('history', size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
            const SizedBox(height: 16),
            const Text(
              'No Check History',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Your indicator checks will appear here',
              style: TextStyle(color: Colors.white.withAlpha(153)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _checkHistory.length,
      itemBuilder: (context, index) {
        final result = _checkHistory[index];
        return _buildHistoryCard(result);
      },
    );
  }

  Widget _buildHistoryCard(api.IndicatorCheckResult result) {
    return GlassCard(
      child: Row(
        children: [
          GlassSvgIconBox(
            icon: result.isThreat ? 'danger_triangle' : 'check_circle',
            color: result.isThreat ? GlassTheme.errorColor : GlassTheme.successColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.value,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                ),
                Row(
                  children: [
                    GlassBadge(text: result.type?.name ?? 'Unknown', color: GlassTheme.primaryAccent, fontSize: 10),
                    const SizedBox(width: 8),
                    if (result.severity != null)
                      GlassBadge(text: result.severity!.displayName, color: Color(result.severity!.color), fontSize: 10),
                  ],
                ),
              ],
            ),
          ),
          GlassBadge(
            text: result.isThreat ? 'Threat' : 'Clean',
            color: result.isThreat ? GlassTheme.errorColor : GlassTheme.successColor,
            fontSize: 10,
          ),
        ],
      ),
    );
  }

  Future<void> _checkIndicators() async {
    final input = _checkInputController.text.trim();
    if (input.isEmpty) return;

    setState(() => _isSearching = true);

    try {
      // Parse input lines into indicator requests
      final lines = input.split('\n').where((l) => l.trim().isNotEmpty).toList();
      final requests = lines.map((value) => api.IndicatorCheckRequest(value: value.trim())).toList();

      // Call the real API
      final results = await OrbGuardApiClient.instance.checkIndicators(requests);

      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _checkHistory.insertAll(0, results);
      });

      // Clear input after successful check
      _checkInputController.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to check indicators: $e')),
      );
    }
  }

  void _showIndicatorDetails(BuildContext context, api.ThreatIndicator indicator) {
    final statusColor = Color(indicator.severity.color);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
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
                  GlassSvgIconBox(
                    icon: _getIndicatorSvgIcon(_getTypeDisplayName(indicator.type)),
                    color: statusColor,
                    size: 56,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getTypeDisplayName(indicator.type),
                          style: TextStyle(color: GlassTheme.primaryAccent, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          indicator.value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
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
                    _buildDetailRow('Severity', indicator.severity.displayName),
                    _buildDetailRow('Confidence', '${(indicator.confidence * 100).toInt()}%'),
                    _buildDetailRow('Source', indicator.sourceName ?? 'Unknown'),
                    if (indicator.firstSeen != null) _buildDetailRow('First Seen', _formatDate(indicator.firstSeen!)),
                    if (indicator.lastSeen != null) _buildDetailRow('Last Seen', _formatDate(indicator.lastSeen!)),
                    if (indicator.campaignName != null) _buildDetailRow('Campaign', indicator.campaignName!),
                  ],
                ),
              ),
              if (indicator.description != null) ...[
                const SizedBox(height: 20),
                const Text('Description', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(indicator.description!, style: TextStyle(color: Colors.white.withAlpha(179))),
              ],
              const SizedBox(height: 20),
              const Text('Tags', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: indicator.tags.map((tag) => GlassBadge(text: tag, color: GlassTheme.primaryAccent)).toList(),
              ),
              if (indicator.mitreTechniques != null && indicator.mitreTechniques!.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('MITRE Techniques', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: indicator.mitreTechniques!.map((t) => GlassBadge(text: t, color: GlassTheme.warningColor)).toList(),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const DuotoneIcon('copy', size: 20),
                      label: const Text('Copy'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GlassTheme.primaryAccent,
                        side: const BorderSide(color: GlassTheme.primaryAccent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: const DuotoneIcon('forbidden', size: 20),
                      label: const Text('Block'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GlassTheme.errorColor,
                        foregroundColor: Colors.white,
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

  void _showQuickCheckDialog(BuildContext context, String type) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: Text('Check $type', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'Enter $type',
            hintStyle: TextStyle(color: Colors.white.withAlpha(77)),
            filled: true,
            fillColor: Colors.white.withAlpha(13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Navigator.pop(context);
                _checkIndicators();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Check'),
          ),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Import Indicators', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const DuotoneIcon('file', size: 24, color: GlassTheme.primaryAccent),
              title: const Text('CSV File', style: TextStyle(color: Colors.white)),
              subtitle: Text('Import from CSV', style: TextStyle(color: Colors.white.withAlpha(128))),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const DuotoneIcon('code', size: 24, color: GlassTheme.primaryAccent),
              title: const Text('STIX/TAXII', style: TextStyle(color: Colors.white)),
              subtitle: Text('Import from TAXII server', style: TextStyle(color: Colors.white.withAlpha(128))),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const DuotoneIcon('programming', size: 24, color: GlassTheme.primaryAccent),
              title: const Text('API', style: TextStyle(color: Colors.white)),
              subtitle: Text('Import via API', style: TextStyle(color: Colors.white.withAlpha(128))),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
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
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _getIndicatorSvgIcon(String type) {
    switch (type.toLowerCase()) {
      case 'ip address':
        return 'globus';
      case 'domain':
        return 'server';
      case 'url':
        return 'link';
      case 'hash (md5)':
      case 'hash (sha256)':
        return 'object_scan';
      case 'email':
        return 'letter';
      case 'file name':
        return 'file';
      default:
        return 'question_circle';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
