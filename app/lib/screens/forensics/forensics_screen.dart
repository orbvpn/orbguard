/// Forensics Screen
/// iOS/Android forensic analysis for Pegasus/spyware detection

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/forensics_provider.dart';

class ForensicsScreen extends StatefulWidget {
  const ForensicsScreen({super.key});

  @override
  State<ForensicsScreen> createState() => _ForensicsScreenState();
}

class _ForensicsScreenState extends State<ForensicsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ForensicsProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ForensicsProvider>(
      builder: (context, provider, child) {
        return GlassTabPage(
          title: 'Forensic Analysis',
          hasSearch: true,
          searchHint: 'Search analysis...',
          headerContent: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const DuotoneIcon('info_circle', size: 22, color: Colors.white),
                  onPressed: () => _showInfoDialog(context),
                  tooltip: 'Info',
                ),
              ],
            ),
          ),
          tabs: [
            GlassTab(
              label: 'Analyze',
              iconPath: 'magnifer',
              content: _buildAnalyzeTab(provider),
            ),
            GlassTab(
              label: 'History',
              iconPath: 'history',
              content: _buildHistoryTab(provider),
            ),
            GlassTab(
              label: 'IOCs',
              iconPath: 'chart',
              content: _buildIOCsTab(provider),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnalyzeTab(ForensicsProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current analysis progress
          if (provider.isAnalyzing) ...[
            _buildProgressCard(provider),
            const SizedBox(height: 24),
          ],

          // Current result
          if (provider.currentAnalysis != null &&
              !provider.isAnalyzing) ...[
            _buildResultCard(provider.currentAnalysis!),
            const SizedBox(height: 24),
          ],

          // Analysis options
          const Text(
            'Choose Analysis Type',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Full scan button
          _buildAnalysisButton(
            icon: 'shield_check',
            title: 'Full Forensic Scan',
            description: 'Comprehensive analysis for all known spyware',
            color: GlassTheme.primaryAccent,
            onTap: provider.isAnalyzing
                ? null
                : () => provider.runFullAnalysis(),
          ),
          const SizedBox(height: 12),

          // Platform-specific options
          if (Platform.isIOS) ...[
            _buildAnalysisButton(
              icon: 'power',
              title: 'Shutdown Log Analysis',
              description: 'Check iOS shutdown.log for Pegasus indicators',
              color: Colors.orange,
              onTap: provider.isAnalyzing
                  ? null
                  : () => _showShutdownLogInput(context, provider),
            ),
            const SizedBox(height: 12),
            _buildAnalysisButton(
              icon: 'cloud_storage',
              title: 'Backup Analysis',
              description: 'Scan iOS backup for spyware artifacts',
              color: Colors.blue,
              onTap: provider.isAnalyzing
                  ? null
                  : () => _showBackupPathInput(context, provider),
            ),
            const SizedBox(height: 12),
            _buildAnalysisButton(
              icon: 'bug',
              title: 'Sysdiagnose Analysis',
              description: 'Deep analysis of system diagnostics',
              color: Colors.purple,
              onTap: provider.isAnalyzing
                  ? null
                  : () => _showSysdiagnoseInput(context, provider),
            ),
          ] else if (Platform.isAndroid) ...[
            _buildAnalysisButton(
              icon: 'file_text',
              title: 'Logcat Analysis',
              description: 'Analyze Android system logs for malware',
              color: Colors.green,
              onTap: provider.isAnalyzing
                  ? null
                  : () => _showLogcatInput(context, provider),
            ),
          ],

          const SizedBox(height: 12),
          _buildAnalysisButton(
            icon: 'chart',
            title: 'Data Usage Analysis',
            description: 'Detect suspicious network activity patterns',
            color: Colors.teal,
            onTap: provider.isAnalyzing
                ? null
                : () => provider.analyzeDataUsage({}),
          ),

          // Info section
          const SizedBox(height: 32),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DuotoneIcon('info_circle', size: 24, color: GlassTheme.primaryAccent),
                    const SizedBox(width: 12),
                    const Text(
                      'About Forensic Analysis',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Our forensic engine uses indicators of compromise (IOCs) '
                  'from Citizen Lab, Amnesty Tech MVT, and other security researchers '
                  'to detect sophisticated spyware like Pegasus, Predator, and stalkerware.',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(ForensicsProvider provider) {
    return GlassCard(
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    GlassTheme.primaryAccent,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Analyzing...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      provider.currentPhase,
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: provider.progress,
              backgroundColor: Colors.white.withAlpha(20),
              valueColor: AlwaysStoppedAnimation<Color>(
                GlassTheme.primaryAccent,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(ForensicAnalysisResult result) {
    final hasThreats = result.hasThreat;
    final color = hasThreats ? Colors.red : Colors.green;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: DuotoneIcon(
                    hasThreats ? 'danger_triangle' : 'shield_check',
                    color: color,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasThreats ? 'Threats Detected!' : 'No Threats Found',
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${result.findings.length} finding(s) from ${result.type.displayName}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const DuotoneIcon('close_circle', color: Colors.grey, size: 24),
                onPressed: () {
                  context.read<ForensicsProvider>().clearCurrentAnalysis();
                },
              ),
            ],
          ),
          if (result.findings.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 12),
            ...result.findings.take(3).map((finding) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildFindingRow(finding),
                )),
            if (result.findings.length > 3)
              TextButton(
                onPressed: () => _showAllFindings(context, result),
                child: Text(
                  'View all ${result.findings.length} findings',
                  style: TextStyle(color: GlassTheme.primaryAccent),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildFindingRow(ForensicFinding finding) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Color(finding.severity.color),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                finding.title,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              Text(
                finding.category,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Color(finding.severity.color).withAlpha(30),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            finding.severity.displayName,
            style: TextStyle(
              color: Color(finding.severity.color),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisButton({
    required String icon,
    required String title,
    required String description,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GlassCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: DuotoneIcon(icon, color: color, size: 24),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
              ],
            ),
          ),
          DuotoneIcon(
            'alt_arrow_right',
            color: onTap == null ? Colors.grey[700]! : Colors.grey,
            size: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(ForensicsProvider provider) {
    final history = provider.analysisHistory;

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DuotoneIcon('history', size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              'No analysis history',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Run a forensic analysis to see results here',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final result = history[index];
        final hasThreats = result.hasThreat;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            onTap: () => _showAllFindings(context, result),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: (hasThreats ? Colors.red : Colors.green)
                        .withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: DuotoneIcon(
                      hasThreats ? 'danger_triangle' : 'check_circle',
                      color: hasThreats ? Colors.red : Colors.green,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.type.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${result.findings.length} findings - ${_formatDate(result.startedAt)}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                DuotoneIcon('alt_arrow_right', size: 24, color: Colors.grey[600]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIOCsTab(ForensicsProvider provider) {
    final stats = provider.iocStats;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats card
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DuotoneIcon('database', size: 24, color: GlassTheme.primaryAccent),
                    const SizedBox(width: 12),
                    const Text(
                      'IOC Database',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(
                      'Total IOCs',
                      stats.totalIOCs.toString(),
                      GlassTheme.primaryAccent,
                    ),
                    _buildStatItem(
                      'Last Updated',
                      _formatDate(stats.lastUpdated),
                      Colors.green,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Breakdown
          const Text(
            'IOC Categories',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          _buildIOCCategory(
            'Pegasus (NSO Group)',
            stats.pegasusIOCs,
            Colors.red,
            'bug',
          ),
          const SizedBox(height: 12),
          _buildIOCCategory(
            'Predator (Cytrox)',
            stats.predatorIOCs,
            Colors.orange,
            'bug_minimalistic',
          ),
          const SizedBox(height: 12),
          _buildIOCCategory(
            'Stalkerware',
            stats.stalkerwareIOCs,
            Colors.purple,
            'eye',
          ),
          const SizedBox(height: 12),
          _buildIOCCategory(
            'Other Spyware',
            stats.otherIOCs,
            Colors.blue,
            'danger_triangle',
          ),

          // Sources
          const SizedBox(height: 32),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Intelligence Sources',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildSourceRow('Citizen Lab', 'University of Toronto'),
                _buildSourceRow('Amnesty Tech MVT', 'Mobile Verification Toolkit'),
                _buildSourceRow('OrbGuard Lab', 'Proprietary research'),
                _buildSourceRow('Community Reports', 'Verified submissions'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildIOCCategory(String name, int count, Color color, String icon) {
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: DuotoneIcon(icon, color: color, size: 22),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceRow(String name, String description) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          DuotoneIcon('check_circle', color: Colors.green, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white)),
                Text(
                  description,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Forensic Analysis', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This module uses advanced forensic techniques to detect '
          'sophisticated spyware like NSO Group\'s Pegasus, Cytrox\'s Predator, '
          'and various stalkerware applications.\n\n'
          'Our IOC database is sourced from Citizen Lab, Amnesty International\'s '
          'Mobile Verification Toolkit (MVT), and our own security research.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAllFindings(BuildContext context, ForensicAnalysisResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  DuotoneIcon(
                    result.hasThreat ? 'danger_triangle' : 'check_circle',
                    color: result.hasThreat ? Colors.red : Colors.green,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${result.type.displayName} Results',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: result.findings.isEmpty
                  ? Center(
                      child: Text(
                        'No threats detected',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: result.findings.length,
                      itemBuilder: (context, index) {
                        final finding = result.findings[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Color(finding.severity.color)
                                            .withAlpha(30),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        finding.severity.displayName,
                                        style: TextStyle(
                                          color: Color(finding.severity.color),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      finding.category,
                                      style: TextStyle(
                                          color: Colors.grey[500], fontSize: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  finding.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  finding.description,
                                  style: TextStyle(
                                      color: Colors.grey[400], fontSize: 13),
                                ),
                                if (finding.indicators.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: finding.indicators.map((ioc) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withAlpha(10),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          ioc,
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showShutdownLogInput(BuildContext context, ForensicsProvider provider) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Shutdown Log Analysis',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Paste your iOS shutdown.log content below',
              style: TextStyle(color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 8,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Paste shutdown.log content...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: const Color(0xFF2A2B40),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (controller.text.isNotEmpty) {
                    Navigator.pop(context);
                    provider.analyzeShutdownLog(controller.text);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.primaryAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Analyze'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBackupPathInput(BuildContext context, ForensicsProvider provider) {
    _showPathInputSheet(
      context,
      'Backup Analysis',
      'Enter the path to your iOS backup folder',
      (path) => provider.analyzeBackup(path),
    );
  }

  void _showSysdiagnoseInput(BuildContext context, ForensicsProvider provider) {
    _showPathInputSheet(
      context,
      'Sysdiagnose Analysis',
      'Enter the path to your sysdiagnose archive',
      (path) => provider.analyzeSysdiagnose(path),
    );
  }

  void _showLogcatInput(BuildContext context, ForensicsProvider provider) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Logcat Analysis',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Paste Android logcat output below',
              style: TextStyle(color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 8,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Paste logcat output...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: const Color(0xFF2A2B40),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (controller.text.isNotEmpty) {
                    Navigator.pop(context);
                    provider.analyzeLogcat(controller.text);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.primaryAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Analyze'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPathInputSheet(
    BuildContext context,
    String title,
    String hint,
    Function(String) onSubmit,
  ) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(hint, style: TextStyle(color: Colors.grey[500])),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '/path/to/file',
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DuotoneIcon('folder', color: Colors.grey, size: 24),
                ),
                filled: true,
                fillColor: const Color(0xFF2A2B40),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (controller.text.isNotEmpty) {
                    Navigator.pop(context);
                    onSubmit(controller.text);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.primaryAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Analyze'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
