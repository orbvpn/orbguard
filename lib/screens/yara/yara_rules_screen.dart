/// YARA Rules Screen
/// YARA malware scanning rules management interface

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';

class YaraRulesScreen extends StatefulWidget {
  const YaraRulesScreen({super.key});

  @override
  State<YaraRulesScreen> createState() => _YaraRulesScreenState();
}

class _YaraRulesScreenState extends State<YaraRulesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  bool _isScanning = false;
  final List<YaraRule> _rules = [];
  final List<YaraScanResult> _scanResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRules();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRules() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _rules.addAll(_getSampleRules());
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'YARA Rules',
        actions: [
          GlassAppBarAction(
            svgIcon: AppIcons.fileDownload,
            onTap: () => _showUploadDialog(context),
            tooltip: 'Upload',
          ),
          GlassAppBarAction(
            svgIcon: AppIcons.refresh,
            onTap: _isLoading ? null : _loadRules,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GlassTheme.primaryAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Rules'),
            Tab(text: 'Scan'),
            Tab(text: 'Results'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRulesTab(),
                _buildScanTab(),
                _buildResultsTab(),
              ],
            ),
    );
  }

  Widget _buildRulesTab() {
    if (_rules.isEmpty) {
      return _buildEmptyState(
        icon: AppIcons.code,
        title: 'No YARA Rules',
        subtitle: 'Upload or sync YARA rules to start scanning',
      );
    }

    final groupedRules = <String, List<YaraRule>>{};
    for (final rule in _rules) {
      groupedRules.putIfAbsent(rule.category, () => []).add(rule);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats
        Row(
          children: [
            _buildStatCard('Total Rules', _rules.length.toString(), GlassTheme.primaryAccent),
            const SizedBox(width: 12),
            _buildStatCard('Enabled', _rules.where((r) => r.isEnabled).length.toString(), GlassTheme.successColor),
          ],
        ),
        const SizedBox(height: 16),

        // Rules by category
        ...groupedRules.entries.map((entry) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassSectionHeader(title: entry.key),
                ...entry.value.map((rule) => _buildRuleCard(rule)),
              ],
            )),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleCard(YaraRule rule) {
    final severityColor = _getSeverityColor(rule.severity);

    return GlassCard(
      onTap: () => _showRuleDetails(context, rule),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: AppIcons.code,
                color: rule.isEnabled ? severityColor : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      rule.author ?? 'Unknown author',
                      style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                value: rule.isEnabled,
                onChanged: (v) => setState(() => rule.isEnabled = v),
                activeColor: GlassTheme.successColor,
              ),
            ],
          ),
          if (rule.description != null) ...[
            const SizedBox(height: 8),
            Text(
              rule.description!,
              style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              GlassBadge(text: rule.severity.toUpperCase(), color: severityColor, fontSize: 10),
              const SizedBox(width: 8),
              GlassBadge(text: '${rule.matchCount} matches', color: GlassTheme.primaryAccent, fontSize: 10),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'YARA Scan',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan files or data against ${_rules.where((r) => r.isEnabled).length} enabled rules',
            style: TextStyle(color: Colors.white.withAlpha(153)),
          ),
          const SizedBox(height: 24),

          // Scan options
          _buildScanOption(
            icon: AppIcons.smartphone,
            title: 'Scan Device',
            subtitle: 'Scan installed apps and files',
            onTap: () => _startScan('device'),
          ),
          _buildScanOption(
            icon: AppIcons.folder,
            title: 'Scan Directory',
            subtitle: 'Scan a specific folder',
            onTap: () => _startScan('directory'),
          ),
          _buildScanOption(
            icon: AppIcons.file,
            title: 'Scan File',
            subtitle: 'Scan a single file',
            onTap: () => _startScan('file'),
          ),
          _buildScanOption(
            icon: AppIcons.cpu,
            title: 'Scan Memory',
            subtitle: 'Scan running processes',
            onTap: () => _startScan('memory'),
          ),

          if (_isScanning) ...[
            const SizedBox(height: 24),
            GlassCard(
              child: Column(
                children: [
                  const CircularProgressIndicator(color: GlassTheme.primaryAccent),
                  const SizedBox(height: 16),
                  const Text('Scanning...', style: TextStyle(color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(
                    'Checking against ${_rules.where((r) => r.isEnabled).length} rules',
                    style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScanOption({
    required String icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GlassCard(
      onTap: _isScanning ? null : onTap,
      child: Row(
        children: [
          GlassSvgIconBox(icon: icon, color: GlassTheme.primaryAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
              ],
            ),
          ),
          DuotoneIcon(AppIcons.chevronRight, color: Colors.white54, size: 20),
        ],
      ),
    );
  }

  Widget _buildResultsTab() {
    if (_scanResults.isEmpty) {
      return _buildEmptyState(
        icon: AppIcons.clipboardCheck,
        title: 'No Scan Results',
        subtitle: 'Run a scan to see results here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _scanResults.length,
      itemBuilder: (context, index) {
        return _buildResultCard(_scanResults[index]);
      },
    );
  }

  Widget _buildResultCard(YaraScanResult result) {
    final severityColor = _getSeverityColor(result.severity);

    return GlassCard(
      tintColor: result.matches.isNotEmpty ? severityColor : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: result.matches.isNotEmpty ? AppIcons.dangerTriangle : AppIcons.checkCircle,
                color: result.matches.isNotEmpty ? severityColor : GlassTheme.successColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.targetName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      result.matches.isNotEmpty ? '${result.matches.length} rules matched' : 'No threats detected',
                      style: TextStyle(
                        color: result.matches.isNotEmpty ? severityColor : GlassTheme.successColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatTime(result.scannedAt),
                style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11),
              ),
            ],
          ),
          if (result.matches.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: result.matches.take(4).map((m) => GlassBadge(text: m, color: severityColor, fontSize: 10)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required String icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(icon, size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(153))),
        ],
      ),
    );
  }

  void _startScan(String type) {
    setState(() => _isScanning = true);

    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        _isScanning = false;
        _scanResults.insert(0, YaraScanResult(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          targetName: type == 'device' ? 'Device Scan' : 'File Scan',
          targetType: type,
          scannedAt: DateTime.now(),
          matches: type == 'device' ? ['Mimikatz_Generic', 'CobaltStrike_Beacon'] : [],
          severity: type == 'device' ? 'high' : 'low',
        ));
        _tabController.animateTo(2);
      });
    });
  }

  void _showRuleDetails(BuildContext context, YaraRule rule) {
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
              Text(rule.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (rule.description != null)
                Text(rule.description!, style: TextStyle(color: Colors.white.withAlpha(179))),
              const SizedBox(height: 20),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Category', rule.category),
                    _buildDetailRow('Severity', rule.severity.toUpperCase()),
                    _buildDetailRow('Author', rule.author ?? 'Unknown'),
                    _buildDetailRow('Matches', '${rule.matchCount}'),
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
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showUploadDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Upload YARA Rules', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Select a .yar or .yara file to upload custom rules.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Browse', style: TextStyle(color: GlassTheme.primaryAccent)),
          ),
        ],
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return GlassTheme.errorColor;
      case 'high':
        return const Color(0xFFFF5722);
      case 'medium':
        return GlassTheme.warningColor;
      case 'low':
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  List<YaraRule> _getSampleRules() {
    return [
      YaraRule(name: 'Mimikatz_Generic', category: 'Credential Theft', severity: 'critical', author: 'Florian Roth', matchCount: 42, description: 'Detects Mimikatz credential dumping tool'),
      YaraRule(name: 'CobaltStrike_Beacon', category: 'C2 Framework', severity: 'critical', author: 'OTX', matchCount: 28, description: 'Detects Cobalt Strike Beacon payloads'),
      YaraRule(name: 'Ransomware_Generic', category: 'Ransomware', severity: 'high', author: 'ESET', matchCount: 15, description: 'Generic ransomware detection rule'),
      YaraRule(name: 'Webshell_PHP', category: 'Webshell', severity: 'high', author: 'SANS', matchCount: 8, description: 'Detects PHP webshells'),
      YaraRule(name: 'Emotet_Dropper', category: 'Banking Trojan', severity: 'high', author: 'Proofpoint', matchCount: 22, description: 'Detects Emotet malware dropper'),
    ];
  }
}

class YaraRule {
  final String name;
  final String category;
  final String severity;
  final String? author;
  final String? description;
  final int matchCount;
  bool isEnabled;

  YaraRule({
    required this.name,
    required this.category,
    required this.severity,
    this.author,
    this.description,
    this.matchCount = 0,
    this.isEnabled = true,
  });
}

class YaraScanResult {
  final String id;
  final String targetName;
  final String targetType;
  final DateTime scannedAt;
  final List<String> matches;
  final String severity;

  YaraScanResult({
    required this.id,
    required this.targetName,
    required this.targetType,
    required this.scannedAt,
    required this.matches,
    required this.severity,
  });
}
