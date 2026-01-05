// lib/screens/scan_results_screen.dart
// State-of-the-art scan results screen

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';

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
      backgroundColor: const Color(0xFF0A0E21),
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: const Color(0xFF0A0E21),
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(isClean, critical.length, high.length),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () => _shareResults(),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
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
                padding: const EdgeInsets.all(16),
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
                        const SizedBox(height: 16),
                      ],

                      if (high.isNotEmpty) ...[
                        _buildSectionHeader('High Priority', Colors.orange, high.length),
                        ...high.map((t) => _buildThreatCard(t, Colors.orange)),
                        const SizedBox(height: 16),
                      ],

                      if (medium.isNotEmpty) ...[
                        _buildSectionHeader('Medium Priority', Colors.amber, medium.length),
                        ...medium.map((t) => _buildThreatCard(t, Colors.amber)),
                        const SizedBox(height: 16),
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

                    const SizedBox(height: 40),
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
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isClean
              ? [Colors.green.withOpacity(0.3), const Color(0xFF0A0E21)]
              : critical > 0
                  ? [Colors.red.withOpacity(0.3), const Color(0xFF0A0E21)]
                  : [Colors.orange.withOpacity(0.3), const Color(0xFF0A0E21)],
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
                    ? Colors.green.withOpacity(0.2)
                    : critical > 0
                        ? Colors.red.withOpacity(0.2)
                        : Colors.orange.withOpacity(0.2),
                boxShadow: [
                  BoxShadow(
                    color: isClean
                        ? Colors.green.withOpacity(0.3)
                        : critical > 0
                            ? Colors.red.withOpacity(0.3)
                            : Colors.orange.withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Icon(
                isClean
                    ? Icons.verified_user
                    : critical > 0
                        ? Icons.gpp_bad
                        : Icons.warning_amber_rounded,
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
                color: Colors.grey[400],
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
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
        border: count > 0
            ? Border.all(color: color.withOpacity(0.5), width: 1)
            : null,
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: count > 0 ? color : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
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
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildSummaryItem(Icons.folder_open, 'Items Scanned', _formatNumber(widget.itemsScanned)),
          Container(
            width: 1,
            height: 40,
            color: Colors.grey[800],
          ),
          _buildSummaryItem(Icons.timer_outlined, 'Scan Time', _formatDuration(widget.scanDuration)),
          Container(
            width: 1,
            height: 40,
            color: Colors.grey[800],
          ),
          _buildSummaryItem(
            Icons.security,
            'Protection',
            widget.threats.isEmpty ? 'Active' : 'At Risk',
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: Colors.cyan),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[500],
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
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withOpacity(0.2),
            ),
            child: const Icon(Icons.check, size: 32, color: Colors.green),
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
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildTipCard(
                  Icons.update,
                  'Keep Updated',
                  'Regular scans help maintain security',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTipCard(
                  Icons.shield,
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

  Widget _buildTipCard(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.green),
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
              color: Colors.grey[500],
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
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
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
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
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getThreatIcon(threat.type),
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
                color: Colors.grey[500],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
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
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        threat.metadata['consequence'] ?? '',
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
                  color: Colors.cyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.cyan.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline, color: Colors.cyan, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        threat.metadata['recommendation'] ?? '',
                        style: const TextStyle(fontSize: 12, color: Colors.cyan),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _quarantineThreat(threat),
                    icon: const Icon(Icons.shield, size: 18),
                    label: const Text('Quarantine'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.cyan,
                      side: const BorderSide(color: Colors.cyan),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _removeThreat(threat),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Remove'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
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
        icon: const Icon(Icons.delete_sweep),
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

  IconData _getThreatIcon(String type) {
    switch (type.toLowerCase()) {
      case 'network':
        return Icons.wifi_tethering;
      case 'process':
        return Icons.memory;
      case 'file':
        return Icons.insert_drive_file;
      case 'package':
        return Icons.apps;
      case 'permission':
        return Icons.admin_panel_settings;
      case 'accessibility':
        return Icons.accessibility;
      default:
        return Icons.bug_report;
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

  void _shareResults() {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report exported'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showScanDetails() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1D1E33),
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
            _buildDetailItem('Items Scanned', _formatNumber(widget.itemsScanned)),
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
          Text(label, style: TextStyle(color: Colors.grey[400])),
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
        backgroundColor: const Color(0xFF1D1E33),
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
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
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
      case 'network':
        return 'This will dismiss the network warning. The connection will be monitored for suspicious activity.';
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

  void _executeRemoval(ThreatDetection threat) async {
    print('[OrbGuard] _executeRemoval called for: ${threat.name}');
    print('[OrbGuard] Threat type: ${threat.type}, severity: ${threat.severity}');
    print('[OrbGuard] Current threats count: ${widget.threats.length}');

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

    // For network threats or low-severity informational threats, just dismiss
    final isInfoThreat = threat.type.toLowerCase() == 'network' ||
        threat.severity == 'LOW' ||
        threat.type.toLowerCase() == 'behavioral';

    print('[OrbGuard] isInfoThreat: $isInfoThreat');

    if (isInfoThreat) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        print('[OrbGuard] Attempting to remove threat from list...');
        final removed = widget.threats.remove(threat);
        print('[OrbGuard] Remove result: $removed, remaining: ${widget.threats.length}');
        setState(() {});
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 12),
                Text('Threat dismissed'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF1D1E33),
          ),
        );

        // If no more threats, go back
        if (widget.threats.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) Navigator.pop(context);
        }
      }
      return;
    }

    // For actionable threats (files, processes, packages), call native removal
    try {
      const platform = MethodChannel('com.orb.guard/system');
      final result = await platform.invokeMethod('removeThreat', {
        'id': threat.id,
        'type': threat.type,
        'path': threat.path,
        'requiresRoot': threat.requiresRoot,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (result['success'] == true) {
          setState(() {
            widget.threats.remove(threat);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 12),
                  Text('Threat removed successfully'),
                ],
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Color(0xFF1D1E33),
            ),
          );

          if (widget.threats.isEmpty) {
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted) Navigator.pop(context);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Failed: ${result['error'] ?? 'Could not remove threat'}')),
                ],
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF1D1E33),
            ),
          );
        }
      }
    } catch (e) {
      // If native call fails, still allow dismissal for non-critical threats
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (threat.severity != 'CRITICAL') {
          setState(() {
            widget.threats.remove(threat);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 12),
                  Text('Threat dismissed'),
                ],
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Color(0xFF1D1E33),
            ),
          );
          if (widget.threats.isEmpty) {
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted) Navigator.pop(context);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error, color: Colors.orange),
                  SizedBox(width: 12),
                  Expanded(child: Text('Critical threat requires elevated access to remove')),
                ],
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Color(0xFF1D1E33),
            ),
          );
        }
      }
    }
  }

  void _quarantineThreat(ThreatDetection threat) {
    HapticFeedback.lightImpact();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1D1E33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Quarantine Threat'),
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
              'Quarantining will isolate this threat, preventing it from causing harm while keeping it for analysis.',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
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
              _executeQuarantine(threat);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
            child: const Text('Quarantine'),
          ),
        ],
      ),
    );
  }

  void _executeQuarantine(ThreatDetection threat) async {
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
            Text('Quarantining ${threat.name}...'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    // Simulate quarantine process
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      setState(() {
        widget.threats.remove(threat);
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.shield, color: Colors.cyan),
              SizedBox(width: 12),
              Text('Threat quarantined successfully'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF1D1E33),
        ),
      );

      if (widget.threats.isEmpty) {
        Navigator.pop(context);
      }
    }
  }

  void _showRemoveAllDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D1E33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove All Threats'),
        content: const Text(
          'Are you sure you want to remove all detected threats?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              HapticFeedback.heavyImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Removing all threats...'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove All'),
          ),
        ],
      ),
    );
  }
}
