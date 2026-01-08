/// Intelligence Core Screen
/// Central threat intelligence browsing, searching, and indicator checking
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';

class IntelligenceCoreScreen extends StatefulWidget {
  const IntelligenceCoreScreen({super.key});

  @override
  State<IntelligenceCoreScreen> createState() => _IntelligenceCoreScreenState();
}

class _IntelligenceCoreScreenState extends State<IntelligenceCoreScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final List<ThreatIndicator> _indicators = [];
  final List<ThreatIndicator> _searchResults = [];
  final List<IndicatorCheckResult> _checkHistory = [];
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
    _tabController = TabController(length: 3, vsync: this);
    _loadIndicators();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadIndicators() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _indicators.addAll(_getSampleIndicators());
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Intelligence Core',
        actions: [
          IconButton(
            icon: const DuotoneIcon('file', size: 24),
            tooltip: 'Import Indicators',
            onPressed: () => _showImportDialog(context),
          ),
          IconButton(
            icon: const DuotoneIcon('refresh', size: 24),
            onPressed: _isLoading ? null : _loadIndicators,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GlassTheme.primaryAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Browse'),
            Tab(text: 'Check'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildBrowseTab(),
                _buildCheckTab(),
                _buildHistoryTab(),
              ],
            ),
    );
  }

  Widget _buildBrowseTab() {
    final filteredIndicators = _selectedType == 'All'
        ? _indicators
        : _indicators.where((i) => i.type == _selectedType).toList();

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
              _buildStatCard('Malicious', _indicators.where((i) => i.isMalicious).length.toString(), GlassTheme.errorColor),
              const SizedBox(width: 12),
              _buildStatCard('Suspicious', _indicators.where((i) => i.isSuspicious).length.toString(), GlassTheme.warningColor),
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

  Widget _buildIndicatorCard(ThreatIndicator indicator) {
    Color statusColor;
    String statusText;
    if (indicator.isMalicious) {
      statusColor = GlassTheme.errorColor;
      statusText = 'Malicious';
    } else if (indicator.isSuspicious) {
      statusColor = GlassTheme.warningColor;
      statusText = 'Suspicious';
    } else {
      statusColor = GlassTheme.successColor;
      statusText = 'Clean';
    }

    return GlassCard(
      onTap: () => _showIndicatorDetails(context, indicator),
      child: Row(
        children: [
          GlassSvgIconBox(
            icon: _getIndicatorSvgIcon(indicator.type),
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
                    GlassBadge(text: indicator.type, color: GlassTheme.primaryAccent, fontSize: 10),
                    const SizedBox(width: 8),
                    Text(
                      indicator.source,
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
                '${indicator.confidence}% conf',
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
                  onChanged: (value) {
                    // Store for checking
                  },
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

  Widget _buildHistoryCard(IndicatorCheckResult result) {
    return GlassCard(
      child: Row(
        children: [
          GlassSvgIconBox(
            icon: result.found ? 'danger_triangle' : 'check_circle',
            color: result.found ? GlassTheme.errorColor : GlassTheme.successColor,
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
                    GlassBadge(text: result.type, color: GlassTheme.primaryAccent, fontSize: 10),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(result.checkedAt),
                      style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GlassBadge(
            text: result.found ? 'Found' : 'Clean',
            color: result.found ? GlassTheme.errorColor : GlassTheme.successColor,
            fontSize: 10,
          ),
        ],
      ),
    );
  }

  void _checkIndicators() {
    setState(() => _isSearching = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchResults.clear();
        _searchResults.addAll([
          ThreatIndicator(
            id: 'search-1',
            type: 'IP Address',
            value: '192.168.1.100',
            source: 'Local Check',
            confidence: 85,
            isMalicious: true,
            isSuspicious: false,
            tags: ['malware', 'c2'],
            firstSeen: DateTime.now().subtract(const Duration(days: 30)),
            lastSeen: DateTime.now(),
          ),
        ]);
        _checkHistory.insert(
          0,
          IndicatorCheckResult(
            value: '192.168.1.100',
            type: 'IP Address',
            found: true,
            checkedAt: DateTime.now(),
          ),
        );
      });
    });
  }

  void _showIndicatorDetails(BuildContext context, ThreatIndicator indicator) {
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
                    icon: _getIndicatorSvgIcon(indicator.type),
                    color: indicator.isMalicious ? GlassTheme.errorColor : GlassTheme.primaryAccent,
                    size: 56,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          indicator.type,
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
                    _buildDetailRow('Status', indicator.isMalicious ? 'Malicious' : (indicator.isSuspicious ? 'Suspicious' : 'Clean')),
                    _buildDetailRow('Confidence', '${indicator.confidence}%'),
                    _buildDetailRow('Source', indicator.source),
                    _buildDetailRow('First Seen', _formatDate(indicator.firstSeen)),
                    _buildDetailRow('Last Seen', _formatDate(indicator.lastSeen)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('Tags', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: indicator.tags.map((tag) => GlassBadge(text: tag, color: GlassTheme.primaryAccent)).toList(),
              ),
              if (indicator.relatedIndicators != null && indicator.relatedIndicators!.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Related Indicators', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...indicator.relatedIndicators!.map((related) => GlassContainer(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        related,
                        style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12),
                      ),
                    )),
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

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  List<ThreatIndicator> _getSampleIndicators() {
    return [
      ThreatIndicator(
        id: '1',
        type: 'IP Address',
        value: '45.33.32.156',
        source: 'AlienVault OTX',
        confidence: 95,
        isMalicious: true,
        isSuspicious: false,
        tags: ['malware', 'botnet', 'c2'],
        firstSeen: DateTime.now().subtract(const Duration(days: 45)),
        lastSeen: DateTime.now().subtract(const Duration(hours: 2)),
        relatedIndicators: ['evil-domain.com', 'malware.exe'],
      ),
      ThreatIndicator(
        id: '2',
        type: 'Domain',
        value: 'phishing-bank-login.com',
        source: 'PhishTank',
        confidence: 99,
        isMalicious: true,
        isSuspicious: false,
        tags: ['phishing', 'banking', 'credential-theft'],
        firstSeen: DateTime.now().subtract(const Duration(days: 7)),
        lastSeen: DateTime.now().subtract(const Duration(minutes: 30)),
      ),
      ThreatIndicator(
        id: '3',
        type: 'Hash (SHA256)',
        value: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        source: 'VirusTotal',
        confidence: 87,
        isMalicious: true,
        isSuspicious: false,
        tags: ['ransomware', 'lockbit'],
        firstSeen: DateTime.now().subtract(const Duration(days: 14)),
        lastSeen: DateTime.now().subtract(const Duration(days: 1)),
      ),
      ThreatIndicator(
        id: '4',
        type: 'URL',
        value: 'https://suspicious-download.net/update.exe',
        source: 'URLhaus',
        confidence: 78,
        isMalicious: false,
        isSuspicious: true,
        tags: ['dropper', 'suspicious'],
        firstSeen: DateTime.now().subtract(const Duration(days: 3)),
        lastSeen: DateTime.now().subtract(const Duration(hours: 6)),
      ),
      ThreatIndicator(
        id: '5',
        type: 'Email',
        value: 'support@fake-microsoft.xyz',
        source: 'SpamHaus',
        confidence: 92,
        isMalicious: true,
        isSuspicious: false,
        tags: ['phishing', 'impersonation', 'tech-support-scam'],
        firstSeen: DateTime.now().subtract(const Duration(days: 21)),
        lastSeen: DateTime.now().subtract(const Duration(hours: 12)),
      ),
      ThreatIndicator(
        id: '6',
        type: 'IP Address',
        value: '8.8.8.8',
        source: 'Internal',
        confidence: 100,
        isMalicious: false,
        isSuspicious: false,
        tags: ['google', 'dns', 'safe'],
        firstSeen: DateTime.now().subtract(const Duration(days: 365)),
        lastSeen: DateTime.now(),
      ),
    ];
  }
}

class ThreatIndicator {
  final String id;
  final String type;
  final String value;
  final String source;
  final int confidence;
  final bool isMalicious;
  final bool isSuspicious;
  final List<String> tags;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final List<String>? relatedIndicators;

  ThreatIndicator({
    required this.id,
    required this.type,
    required this.value,
    required this.source,
    required this.confidence,
    required this.isMalicious,
    required this.isSuspicious,
    required this.tags,
    required this.firstSeen,
    required this.lastSeen,
    this.relatedIndicators,
  });
}

class IndicatorCheckResult {
  final String value;
  final String type;
  final bool found;
  final DateTime checkedAt;

  IndicatorCheckResult({
    required this.value,
    required this.type,
    required this.found,
    required this.checkedAt,
  });
}
