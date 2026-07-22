// Forensics Screen
// iOS/Android forensic analysis for Pegasus/spyware detection

import '../../utils/platform_info.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:provider/provider.dart';

import '../../presentation/theme/colors.dart';
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
          actions: [
            GestureDetector(
              onTap: () => _showInfoDialog(context),
              child: DuotoneIcon('info_circle',
                  size: 22,
                  color: Theme.of(context).colorScheme.onSurface),
            ),
          ],
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
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
          Text(
            'Choose Analysis Type',
            style: BrandText.title(size: 18, color: cs.onSurface),
          ),
          const SizedBox(height: 12),

          // Full scan button
          _buildAnalysisButton(
            icon: 'shield_check',
            title: 'Full Forensic Scan',
            description: 'Comprehensive analysis for all known spyware',
            color: AppColors.accentInk,
            onTap: provider.isAnalyzing
                ? null
                : () => provider.runFullAnalysis(),
          ),
          const SizedBox(height: 12),

          // Platform-specific options
          if (PlatformInfo.isIOS) ...[
            _buildAnalysisButton(
              icon: 'power',
              title: 'Shutdown Log Analysis',
              description: 'Check iOS shutdown.log for Pegasus indicators',
              color: AppColors.amberInk,
              onTap: provider.isAnalyzing
                  ? null
                  : () => _showShutdownLogInput(context, provider),
            ),
            const SizedBox(height: 12),
            _buildAnalysisButton(
              icon: 'cloud_storage',
              title: 'Backup Analysis',
              description: 'Upload an iOS backup (.zip) for spyware analysis',
              color: AppColors.secondaryInk,
              onTap: provider.isAnalyzing
                  ? null
                  : () => _pickAndUpload(
                        context,
                        provider,
                        allowedExtensions: const ['zip'],
                        serverAcceptedSuffixes: const ['.zip'],
                        upload: provider.uploadIosBackup,
                      ),
            ),
            const SizedBox(height: 12),
            _buildAnalysisButton(
              icon: 'bug',
              title: 'Sysdiagnose Analysis',
              description:
                  'Upload a sysdiagnose archive (.tar.gz/.tgz/.zip) for deep analysis',
              color: AppColors.chartColors[4], // spectrum purple
              onTap: provider.isAnalyzing
                  ? null
                  : () => _pickAndUpload(
                        context,
                        provider,
                        allowedExtensions: const ['gz', 'tgz', 'zip'],
                        serverAcceptedSuffixes: const ['.tar.gz', '.tgz', '.zip'],
                        upload: provider.uploadSysdiagnose,
                      ),
            ),
          ] else if (PlatformInfo.isAndroid) ...[
            _buildAnalysisButton(
              icon: 'clipboard_text',
              title: 'Capture & Analyze Logs',
              description:
                  "Capture OrbGuard's own process logs and analyze them "
                  '(full-device logs require ADB export)',
              color: AppColors.chartColors[6], // spectrum mint
              onTap: provider.isAnalyzing
                  ? null
                  : () => provider.captureAndAnalyzeLogcat(),
            ),
            const SizedBox(height: 12),
            _buildAnalysisButton(
              icon: 'file_text',
              title: 'Logcat Analysis',
              description: 'Analyze Android system logs for malware',
              color: AppColors.accentInk,
              onTap: provider.isAnalyzing
                  ? null
                  : () => _showLogcatInput(context, provider),
            ),
            const SizedBox(height: 12),
            _buildAnalysisButton(
              icon: 'cloud_storage',
              title: 'Bugreport Analysis',
              description:
                  'Upload an Android bugreport (.zip/.txt) for malware analysis',
              color: AppColors.chartColors[2], // spectrum cyan
              onTap: provider.isAnalyzing
                  ? null
                  : () => _pickAndUpload(
                        context,
                        provider,
                        allowedExtensions: const ['zip', 'txt'],
                        serverAcceptedSuffixes: const ['.zip', '.txt'],
                        upload: provider.uploadAndroidBugreport,
                      ),
            ),
          ],

          // Info section
          const SizedBox(height: 24),
          GlassCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DuotoneIcon('info_circle', size: 24, color: AppColors.accentInk),
                    const SizedBox(width: 12),
                    Text(
                      'About Forensic Analysis',
                      style: BrandText.title(color: cs.onSurface),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Our forensic engine uses indicators of compromise (IOCs) '
                  'from Citizen Lab, Amnesty Tech MVT, and other security researchers '
                  'to detect sophisticated spyware like Pegasus, Predator, and stalkerware.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(ForensicsProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      margin: EdgeInsets.zero,
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
                    AppColors.accentInk,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Analyzing...',
                      style: BrandText.title(color: cs.onSurface),
                    ),
                    Text(
                      provider.currentPhase,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
            child: LinearProgressIndicator(
              value: provider.progress,
              backgroundColor: cs.onSurface.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.accentInk,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(ForensicAnalysisResult result) {
    final cs = Theme.of(context).colorScheme;
    // A failed analysis must never render as "No Threats Found".
    if (result.error != null) {
      return GlassCard(
        margin: EdgeInsets.zero,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(40),
                borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
              ),
              child: Center(
                child: DuotoneIcon('danger_circle',
                    color: AppColors.secondaryInk, size: 28),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${result.type.displayName} Failed',
                    style: BrandText.title(color: AppColors.secondaryInk),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.error!,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: DuotoneIcon('close_circle',
                  color: cs.onSurfaceVariant, size: 24),
              onPressed: () {
                context.read<ForensicsProvider>().clearCurrentAnalysis();
              },
            ),
          ],
        ),
      );
    }

    final hasThreats = result.hasThreat;
    final color = hasThreats ? AppColors.errorInk : AppColors.accentInk;

    return GlassCard(
      margin: EdgeInsets.zero,
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
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
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
                      style: BrandText.title(size: 18, color: color),
                    ),
                    Text(
                      '${result.findings.length} finding(s) from ${result.type.displayName}',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: DuotoneIcon('close_circle',
                  color: cs.onSurfaceVariant, size: 24),
                onPressed: () {
                  context.read<ForensicsProvider>().clearCurrentAnalysis();
                },
              ),
            ],
          ),
          if (result.findings.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(color: cs.outline),
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
                  style: TextStyle(color: AppColors.accentInk),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildFindingRow(ForensicFinding finding) {
    final cs = Theme.of(context).colorScheme;
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurface, fontSize: 14),
              ),
              Text(
                finding.category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Color(finding.severity.color).withAlpha(30),
            borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
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
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      onTap: onTap,
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
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
                  style: BrandText.title(color: cs.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
          DuotoneIcon(
            'alt_arrow_right',
            color: onTap == null
                ? cs.onSurfaceVariant.withValues(alpha: 0.5)
                : cs.onSurfaceVariant,
            size: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(ForensicsProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final history = provider.analysisHistory;

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DuotoneIcon('history',
                size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'No analysis history',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Run a forensic analysis to see results here',
              style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final result = history[index];
        final hasThreats = result.hasThreat;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            margin: EdgeInsets.zero,
            onTap: () => _showAllFindings(context, result),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color:
                        (hasThreats ? AppColors.errorInk : AppColors.accentInk)
                            .withAlpha(30),
                    borderRadius:
                        BorderRadius.circular(GlassTheme.radiusSmall),
                  ),
                  child: Center(
                    child: DuotoneIcon(
                      hasThreats ? 'danger_triangle' : 'check_circle',
                      color: hasThreats
                          ? AppColors.errorInk
                          : AppColors.accentInk,
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
                        style: BrandText.title(color: cs.onSurface),
                      ),
                      Text(
                        '${result.findings.length} findings - ${_formatDate(result.startedAt)}',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                DuotoneIcon('alt_arrow_right',
                    size: 24,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIOCsTab(ForensicsProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final stats = provider.iocStats;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats card
          GlassCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DuotoneIcon('database', size: 24, color: AppColors.accentInk),
                    const SizedBox(width: 12),
                    Text(
                      'IOC Database',
                      style: BrandText.title(size: 18, color: cs.onSurface),
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
                      AppColors.accentInk,
                    ),
                    _buildStatItem(
                      'Retrieved',
                      _formatDate(stats.lastUpdated),
                      AppColors.accentInk,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Breakdown by IOC type — the real per-type counts returned by
          // GET /forensics/iocs/stats (domains, ips, hashes, path_patterns,
          // process_patterns). The backend does not break IOCs down by
          // campaign (Pegasus/Predator/...), so that breakdown is not shown.
          Text(
            'IOC Breakdown',
            style: BrandText.title(size: 18, color: cs.onSurface),
          ),
          const SizedBox(height: 12),

          _buildIOCCategory(
            'Domains',
            stats.domains,
            AppColors.accentInk,
            'global',
          ),
          const SizedBox(height: 12),
          _buildIOCCategory(
            'IP Addresses',
            stats.ips,
            AppColors.chartColors[2], // spectrum cyan
            'server',
          ),
          const SizedBox(height: 12),
          _buildIOCCategory(
            'File Hashes',
            stats.hashes,
            AppColors.chartColors[4], // spectrum purple
            'hashtag',
          ),
          const SizedBox(height: 12),
          _buildIOCCategory(
            'Path Patterns',
            stats.pathPatterns,
            AppColors.amberInk,
            'folder',
          ),
          const SizedBox(height: 12),
          _buildIOCCategory(
            'Process Patterns',
            stats.processPatterns,
            AppColors.secondaryInk,
            'cpu',
          ),

          // Sources
          const SizedBox(height: 24),
          GlassCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Intelligence Sources',
                  style: BrandText.title(color: cs.onSurface),
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
          style: BrandText.heading(size: 24, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildIOCCategory(String name, int count, Color color, String icon) {
    return GlassCard(
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
            ),
            child: Center(
              child: DuotoneIcon(icon, color: color, size: 22),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 15),
            ),
          ),
          Text(
            count.toString(),
            style: BrandText.heading(size: 18, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceRow(String name, String description) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          DuotoneIcon('check_circle', color: AppColors.accentInk, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(color: cs.onSurface)),
                Text(
                  description,
                  style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 12),
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
        title: Text('Forensic Analysis',
            style:
                TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'This module uses advanced forensic techniques to detect '
          'sophisticated spyware like NSO Group\'s Pegasus, Cytrox\'s Predator, '
          'and various stalkerware applications.\n\n'
          'Our IOC database is sourced from Citizen Lab, Amnesty International\'s '
          'Mobile Verification Toolkit (MVT), and our own security research.',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant),
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
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GlassTheme.radiusLarge),
        ),
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
                color: cs.outline,
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  DuotoneIcon(
                    result.hasThreat ? 'danger_triangle' : 'check_circle',
                    color: result.hasThreat
                        ? AppColors.errorInk
                        : AppColors.accentInk,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${result.type.displayName} Results',
                      style: BrandText.title(size: 18, color: cs.onSurface),
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
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: result.findings.length,
                      itemBuilder: (context, index) {
                        final finding = result.findings[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(
                            margin: EdgeInsets.zero,
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
                                        borderRadius: BorderRadius.circular(
                                            GlassTheme.radiusXSmall),
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
                                    Flexible(
                                      child: Text(
                                        finding.category,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: cs.onSurfaceVariant,
                                            fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  finding.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: BrandText.title(color: cs.onSurface),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  finding.description,
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 13),
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
                                          color: Brand.glassFill,
                                          borderRadius: BorderRadius.circular(
                                              GlassTheme.radiusXSmall),
                                        ),
                                        child: Text(
                                          ioc,
                                          style: BrandText.mono(
                                            size: 11,
                                            color: cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GlassTheme.radiusLarge),
        ),
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
              'Shutdown Log Analysis',
              style: BrandText.title(size: 20, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'Paste your iOS shutdown.log content below',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 8,
              style: TextStyle(color: cs.onSurface, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Paste shutdown.log content...',
                hintStyle: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                filled: true,
                fillColor: Brand.glassFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
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
                  foregroundColor: Brand.onLime,
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

  /// Opens a real file picker and uploads the chosen artifact through the
  /// provider's multipart upload flow. Upload progress comes from dio's
  /// onSendProgress and is rendered by the progress card.
  Future<void> _pickAndUpload(
    BuildContext context,
    ForensicsProvider provider, {
    required List<String> allowedExtensions,
    required List<String> serverAcceptedSuffixes,
    required Future<ForensicAnalysisResult?> Function(String path) upload,
  }) async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
    } on PlatformException catch (_) {
      // Some platforms reject uncommon extension filters (e.g. tgz/gz on
      // iOS); fall back to an unfiltered picker and validate below.
      picked = await FilePicker.platform.pickFiles(type: FileType.any);
    } on ArgumentError catch (_) {
      picked = await FilePicker.platform.pickFiles(type: FileType.any);
    }

    final path = picked?.files.single.path;
    if (path == null) return; // user cancelled

    final lowerName = path.split(PlatformInfo.pathSeparator).last.toLowerCase();
    final accepted =
        serverAcceptedSuffixes.any((suffix) => lowerName.endsWith(suffix));
    if (!accepted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unsupported file type "$lowerName" — expected: '
              '${serverAcceptedSuffixes.join(', ')}',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    await upload(path);
  }

  void _showLogcatInput(BuildContext context, ForensicsProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GlassTheme.radiusLarge),
        ),
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
              'Logcat Analysis',
              style: BrandText.title(size: 20, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'Paste Android logcat output below',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 8,
              style: TextStyle(color: cs.onSurface, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Paste logcat output...',
                hintStyle: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                filled: true,
                fillColor: Brand.glassFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
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
                  foregroundColor: Brand.onLime,
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
