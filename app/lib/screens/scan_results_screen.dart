// lib/screens/scan_results_screen.dart
// State-of-the-art scan results screen

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../presentation/widgets/duotone_icon.dart';

class ScanResultsScreen extends StatefulWidget {
  final List<ThreatDetection> threats;
  final int itemsScanned;
  final Duration scanDuration;

  const ScanResultsScreen({
    super.key,
    required this.threats,
    this.itemsScanned = 0,
    this.scanDuration = Duration.zero,
  });

  @override
  State<ScanResultsScreen> createState() => _ScanResultsScreenState();
}

class _ScanResultsScreenState extends State<ScanResultsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final critical = widget.threats.where((t) => t.severity == 'CRITICAL').toList();
    final high = widget.threats.where((t) => t.severity == 'HIGH').toList();
    final medium = widget.threats.where((t) => t.severity == 'MEDIUM').toList();
    final low = widget.threats.where((t) => t.severity == 'LOW').toList();
    final isClean = widget.threats.isEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: Theme.of(context).canvasColor,
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(isClean, critical.length, high.length),
            ),
            leading: IconButton(
              icon: DuotoneIcon('alt_arrow_left',
                  color: Theme.of(context).colorScheme.onSurface, size: 24),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: DuotoneIcon('share',
                    color: Theme.of(context).colorScheme.onSurface, size: 24),
                onPressed: () => _shareResults(),
              ),
              IconButton(
                icon: DuotoneIcon('info_circle',
                    color: Theme.of(context).colorScheme.onSurface, size: 24),
                onPressed: () => _showScanDetails(),
              ),
            ],
          ),

          // Content
          SliverToBoxAdapter(
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.translate(
                    offset: Offset(0, _slideAnimation.value),
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats Cards
                    _buildStatsRow(critical.length, high.length, medium.length, low.length),
                    const SizedBox(height: 24),

                    // Scan Summary
                    _buildScanSummary(),
                    const SizedBox(height: 24),

                    if (isClean) ...[
                      _buildCleanDeviceCard(),
                    ] else ...[
                      // Threat List
                      if (critical.isNotEmpty) ...[
                        _buildSectionHeader('Critical Threats', Colors.red, critical.length),
                        ...critical.map((t) => _buildThreatCard(t, Colors.red)),
                        const SizedBox(height: 24),
                      ],

                      if (high.isNotEmpty) ...[
                        _buildSectionHeader('High Priority', Colors.orange, high.length),
                        ...high.map((t) => _buildThreatCard(t, Colors.orange)),
                        const SizedBox(height: 24),
                      ],

                      if (medium.isNotEmpty) ...[
                        _buildSectionHeader('Medium Priority', Colors.amber, medium.length),
                        ...medium.map((t) => _buildThreatCard(t, Colors.amber)),
                        const SizedBox(height: 24),
                      ],

                      if (low.isNotEmpty) ...[
                        _buildSectionHeader('Low Priority', Colors.blue, low.length),
                        ...low.map((t) => _buildThreatCard(t, Colors.blue)),
                      ],

                      const SizedBox(height: 24),

                      // Action Button
                      if (critical.isNotEmpty || high.isNotEmpty)
                        _buildRemoveAllButton(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isClean, int critical, int high) {
    final bg = Theme.of(context).canvasColor;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isClean
              ? [Colors.green.withValues(alpha: 0.3), bg]
              : critical > 0
                  ? [Colors.red.withValues(alpha: 0.3), bg]
                  : [Colors.orange.withValues(alpha: 0.3), bg],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            // Status Icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isClean
                    ? Colors.green.withValues(alpha: 0.2)
                    : critical > 0
                        ? Colors.red.withValues(alpha: 0.2)
                        : Colors.orange.withValues(alpha: 0.2),
                boxShadow: [
                  BoxShadow(
                    color: isClean
                        ? Colors.green.withValues(alpha: 0.3)
                        : critical > 0
                            ? Colors.red.withValues(alpha: 0.3)
                            : Colors.orange.withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: DuotoneIcon(
                isClean
                    ? 'shield_check'
                    : critical > 0
                        ? 'shield_cross'
                        : 'danger_triangle',
                size: 50,
                color: isClean
                    ? Colors.green
                    : critical > 0
                        ? Colors.red
                        : Colors.orange,
              ),
            ),
            const SizedBox(height: 16),
            // Status Text
            Text(
              isClean
                  ? 'Device Secure'
                  : '${widget.threats.length} Threat${widget.threats.length > 1 ? 's' : ''} Found',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isClean
                    ? Colors.green
                    : critical > 0
                        ? Colors.red
                        : Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isClean
                  ? 'No threats detected on your device'
                  : 'Action required to secure your device',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(int critical, int high, int medium, int low) {
    return Row(
      children: [
        Expanded(child: _buildStatCard('Critical', critical, Colors.red)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('High', high, Colors.orange)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('Medium', medium, Colors.amber)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('Low', low, Colors.blue)),
      ],
    );
  }

  Widget _buildStatCard(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: count > 0
            ? Border.all(color: color.withValues(alpha: 0.5), width: 1)
            : null,
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: count > 0 ? color : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildSummaryItem('folder_open', 'Scan Stages Completed', _formatNumber(widget.itemsScanned)),
          Container(
            width: 1,
            height: 40,
            color: Theme.of(context).colorScheme.outline,
          ),
          _buildSummaryItem('clock_circle', 'Scan Time', _formatDuration(widget.scanDuration)),
          Container(
            width: 1,
            height: 40,
            color: Theme.of(context).colorScheme.outline,
          ),
          _buildSummaryItem(
            'shield_check',
            'Protection',
            widget.threats.isEmpty ? 'Active' : 'At Risk',
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          DuotoneIcon(icon, size: 20, color: Colors.cyan),
          const SizedBox(height: 8),
          Text(
            value, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCleanDeviceCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withValues(alpha: 0.2),
            ),
            child: const DuotoneIcon('check_circle', size: 32, color: Colors.green),
          ),
          const SizedBox(height: 16),
          const Text(
            'Your Device is Clean',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No spyware, malware, or suspicious activity was detected. '
            'Your device appears to be secure.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildTipCard(
                  'restart',
                  'Keep Updated',
                  'Regular scans help maintain security',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTipCard(
                  'shield',
                  'Stay Protected',
                  'Avoid unknown app sources',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTipCard(String icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DuotoneIcon(icon, size: 20, color: Colors.green),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThreatCard(ThreatDetection threat, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DuotoneIcon(
              _getThreatSvgIcon(threat.type),
              color: color,
              size: 22,
            ),
          ),
          title: Text(
            threat.name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              threat.description,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Type', _formatThreatType(threat.type)),
                  _buildDetailRow('Location', threat.path),
                  _buildDetailRow('Risk Level', threat.severity),
                  if (threat.metadata.containsKey('networkType'))
                    _buildDetailRow('Network', threat.metadata['networkType'] ?? ''),
                  if (threat.metadata.containsKey('dnsServers') && threat.metadata['dnsServers'] != 'none')
                    _buildDetailRow('DNS', threat.metadata['dnsServers'] ?? ''),
                  if (threat.requiresRoot)
                    _buildDetailRow('Removal', 'Requires elevated access'),
                ],
              ),
            ),
            // Show consequence if available
            if (threat.metadata.containsKey('consequence')) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DuotoneIcon('danger_triangle', color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        threat.metadata['consequence'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Show recommendation if available
            if (threat.metadata.containsKey('recommendation')) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.cyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DuotoneIcon('lightbulb', color: Colors.cyan, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        threat.metadata['recommendation'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.cyan),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Actions are capability-based: only remediations the app can
            // actually perform are offered — no simulated quarantine.
            if (_isDismissOnly(threat))
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _dismissThreat(threat),
                  icon: const DuotoneIcon('check_circle', size: 18, color: Colors.cyan),
                  label: const Text('Dismiss Warning'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.cyan,
                    side: const BorderSide(color: Colors.cyan),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              )
            else if (_hasNativeRemediation(threat)) ...[
              if (threat.type.toLowerCase() == 'package') ...[
                _buildGuidanceRow(
                  'Automatic uninstall requires elevated access. If removal '
                  'fails, uninstall manually: Settings > Apps > ${threat.name}.',
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _removeThreat(threat),
                  icon: const DuotoneIcon('trash_bin_minimalistic', size: 18, color: Colors.white),
                  label: const Text('Remove'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ] else ...[
              _buildGuidanceRow(
                'Manual removal required — OrbGuard cannot remediate this '
                'threat type automatically. Follow the recommendation above, '
                'then dismiss this warning.',
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _dismissThreat(threat),
                  icon: const DuotoneIcon('check_circle', size: 18, color: Colors.cyan),
                  label: const Text('Dismiss Warning'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.cyan,
                    side: const BorderSide(color: Colors.cyan),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Threat types the native layer can actually remediate
  /// (SpywareScanner.removeThreat: kill process / delete file / pm uninstall;
  /// IOSSpywareScanner.removeThreat on iOS).
  bool _hasNativeRemediation(ThreatDetection threat) {
    final type = threat.type.toLowerCase();
    return type == 'process' || type == 'file' || type == 'package';
  }

  /// Informational findings with nothing on the device to remove —
  /// dismissing the warning is the only honest action.
  bool _isDismissOnly(ThreatDetection threat) {
    final type = threat.type.toLowerCase();
    return type == 'network' || type == 'behavioral' || threat.severity == 'LOW';
  }

  Widget _buildGuidanceRow(String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DuotoneIcon('info_circle', color: Colors.blueGrey, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoveAllButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _showRemoveAllDialog(),
        icon: const DuotoneIcon('trash_bin_2', size: 24, color: Colors.white),
        label: const Text('Remove All Threats'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  String _getThreatSvgIcon(String type) {
    switch (type.toLowerCase()) {
      case 'network':
        return 'wi_fi_router_round';
      case 'process':
        return 'cpu';
      case 'file':
        return 'file';
      case 'package':
        return 'smartphone';
      case 'permission':
        return 'crown';
      case 'accessibility':
        return 'eye';
      default:
        return 'bug';
    }
  }

  String _formatThreatType(String type) {
    switch (type.toLowerCase()) {
      case 'network':
        return 'Network Connection';
      case 'process':
        return 'Running Process';
      case 'file':
        return 'File System';
      case 'package':
        return 'Installed App';
      case 'permission':
        return 'Permission Issue';
      case 'accessibility':
        return 'Accessibility Service';
      case 'database':
        return 'Database Entry';
      case 'memory':
        return 'Memory Analysis';
      default:
        return type;
    }
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}s';
    }
    return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
  }

  /// Copies a plain-text scan report to the clipboard — a real export, not a
  /// fake "exported" toast.
  Future<void> _shareResults() async {
    HapticFeedback.lightImpact();

    final buffer = StringBuffer()
      ..writeln('OrbGuard Scan Report')
      ..writeln('Generated: ${DateTime.now().toIso8601String()}')
      ..writeln('Scan stages completed: ${widget.itemsScanned}')
      ..writeln('Duration: ${_formatDuration(widget.scanDuration)}')
      ..writeln('Threats found: ${widget.threats.length}')
      ..writeln();
    for (final threat in widget.threats) {
      buffer
        ..writeln('[${threat.severity}] ${threat.name} '
            '(${_formatThreatType(threat.type)})')
        ..writeln('  ${threat.description}')
        ..writeln('  Location: ${threat.path}');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showScanDetails() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Scan Details',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildDetailItem('Scan Stages Completed', _formatNumber(widget.itemsScanned)),
            _buildDetailItem('Duration', _formatDuration(widget.scanDuration)),
            _buildDetailItem('Threats Found', widget.threats.length.toString()),
            _buildDetailItem('Scan Type', 'Full System Scan'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _removeThreat(ThreatDetection threat) {
    HapticFeedback.mediumImpact();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Threat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              threat.name,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 12),
            Text(
              _getRemovalDescription(threat),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _executeRemoval(threat);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  String _getRemovalDescription(ThreatDetection threat) {
    switch (threat.type.toLowerCase()) {
      case 'process':
        return 'This will terminate the suspicious process. The app may need elevated access.';
      case 'file':
        return 'This will permanently delete the suspicious file from your device.';
      case 'package':
        return 'This will uninstall the suspicious application from your device.';
      default:
        return 'This will remove the detected threat from your device.';
    }
  }

  /// Dismiss an informational warning. This only removes the warning from
  /// the results list — it changes nothing on the device, and says so.
  void _dismissThreat(ThreatDetection threat) {
    HapticFeedback.lightImpact();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Dismiss Warning'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              threat.name,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyan),
            ),
            const SizedBox(height: 12),
            Text(
              'This removes the warning from the scan results. It does not '
              'change anything on your device.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _executeDismiss(threat);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  void _executeDismiss(ThreatDetection threat) async {
    setState(() {
      widget.threats.remove(threat);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            DuotoneIcon('check_circle', color: Colors.cyan, size: 24),
            SizedBox(width: 12),
            Text('Warning dismissed'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (widget.threats.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) Navigator.pop(context);
    }
  }

  void _executeRemoval(ThreatDetection threat) async {
    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Text('Removing ${threat.name}...'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    // Call the real native removal (kill process / delete file / uninstall).
    // Failures are surfaced honestly — the threat is never silently
    // re-labelled as "dismissed".
    try {
      const platform = MethodChannel('com.orb.guard/system');
      final result = await platform.invokeMethod('removeThreat', {
        'id': threat.id,
        'type': threat.type,
        'path': threat.path,
        'requiresRoot': threat.requiresRoot,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (result['success'] == true) {
        setState(() {
          widget.threats.remove(threat);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                DuotoneIcon('check_circle', color: Colors.green, size: 24),
                SizedBox(width: 12),
                Text('Threat removed successfully'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );

        if (widget.threats.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) Navigator.pop(context);
        }
      } else {
        _showRemovalFailure(
          threat,
          result['error'] as String? ??
              (threat.requiresRoot
                  ? 'Removal requires elevated access, which is not available on this device.'
                  : 'The system could not remove this threat.'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showRemovalFailure(threat, 'Removal is not available: $e');
    }
  }

  void _showRemovalFailure(ThreatDetection threat, String reason) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const DuotoneIcon('danger_circle', color: Colors.orange, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Could not remove "${threat.name}": $reason '
                'Manual removal is required.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _showRemoveAllDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove All Threats'),
        content: const Text(
          'This removes every threat OrbGuard can act on: suspicious '
          'processes, files and apps are removed via the system, and '
          'informational warnings are dismissed. Threats that need manual '
          'action are kept in the list.\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              HapticFeedback.heavyImpact();
              _executeRemoveAll();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove All'),
          ),
        ],
      ),
    );
  }

  /// Really remove/dismiss every threat the app has a capability for, and
  /// report an honest per-outcome summary.
  Future<void> _executeRemoveAll() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 16),
            Text('Removing threats...'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 10),
      ),
    );

    const platform = MethodChannel('com.orb.guard/system');
    final snapshot = List<ThreatDetection>.from(widget.threats);
    var removed = 0;
    var dismissed = 0;
    var failed = 0;
    var manual = 0;

    for (final threat in snapshot) {
      if (_isDismissOnly(threat)) {
        widget.threats.remove(threat);
        dismissed++;
        continue;
      }
      if (!_hasNativeRemediation(threat)) {
        manual++;
        continue;
      }
      try {
        final result = await platform.invokeMethod('removeThreat', {
          'id': threat.id,
          'type': threat.type,
          'path': threat.path,
          'requiresRoot': threat.requiresRoot,
        });
        if (result['success'] == true) {
          widget.threats.remove(threat);
          removed++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() {});

    final parts = <String>[
      if (removed > 0) '$removed removed',
      if (dismissed > 0) '$dismissed dismissed',
      if (failed > 0) '$failed failed',
      if (manual > 0) '$manual need manual action',
    ];
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          parts.isEmpty ? 'No threats to remove' : parts.join(', '),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );

    if (widget.threats.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) Navigator.pop(context);
    }
  }
}
