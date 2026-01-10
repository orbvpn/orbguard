/// Enterprise Compliance Reporting Screen
/// Generates compliance reports for SOC2, GDPR, HIPAA, PCI-DSS, ISO27001
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/api/orbguard_api_client.dart';

class ComplianceReportingScreen extends StatefulWidget {
  const ComplianceReportingScreen({super.key});

  @override
  State<ComplianceReportingScreen> createState() => _ComplianceReportingScreenState();
}

class _ComplianceReportingScreenState extends State<ComplianceReportingScreen> {
  bool _isLoading = false;
  bool _isGenerating = false;
  String? _error;
  final List<ComplianceFramework> _frameworks = [];
  final List<ComplianceReport> _reports = [];
  final List<ComplianceControl> _controls = [];

  final _api = OrbGuardApiClient.instance;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _api.getComplianceFrameworks(),
        _api.getComplianceReports(),
        _api.getComplianceControls(),
      ]);

      final frameworksData = results[0];
      final reportsData = results[1];
      final controlsData = results[2];

      setState(() {
        _frameworks.clear();
        _reports.clear();
        _controls.clear();

        _frameworks.addAll(frameworksData.map((data) => ComplianceFramework.fromJson(data)));
        _reports.addAll(reportsData.map((data) => ComplianceReport.fromJson(data)));
        _controls.addAll(controlsData.map((data) => ComplianceControl.fromJson(data)));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassTabPage(
      title: 'Compliance Reporting',
      tabs: [
        GlassTab(
          label: 'Frameworks',
          iconPath: 'shield',
          content: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
              : _error != null
                  ? _buildErrorState()
                  : _buildFrameworksTab(),
        ),
        GlassTab(
          label: 'Reports',
          iconPath: 'file',
          content: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
              : _error != null
                  ? _buildErrorState()
                  : _buildReportsTab(),
        ),
        GlassTab(
          label: 'Controls',
          iconPath: 'settings',
          content: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
              : _error != null
                  ? _buildErrorState()
                  : _buildControlsTab(),
        ),
      ],
      headerContent: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: const DuotoneIcon('clock_circle', size: 22, color: Colors.white),
              tooltip: 'Schedule Reports',
              onPressed: () => _showScheduleDialog(context),
            ),
            IconButton(
              icon: const DuotoneIcon('refresh', size: 22, color: Colors.white),
              onPressed: _isLoading ? null : _loadData,
              tooltip: 'Refresh',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrameworksTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Overall compliance score
        _buildOverallComplianceCard(),
        const SizedBox(height: 24),

        // Framework cards
        const GlassSectionHeader(title: 'Compliance Frameworks'),
        ..._frameworks.map((framework) => _buildFrameworkCard(framework)),
      ],
    );
  }

  Widget _buildOverallComplianceCard() {
    final avgCompliance = _frameworks.isEmpty
        ? 0
        : _frameworks.where((f) => f.isEnabled).map((f) => f.complianceScore).fold(0, (a, b) => a + b) ~/
            _frameworks.where((f) => f.isEnabled).length;

    Color scoreColor;
    if (avgCompliance >= 90) {
      scoreColor = GlassTheme.successColor;
    } else if (avgCompliance >= 70) {
      scoreColor = GlassTheme.warningColor;
    } else {
      scoreColor = GlassTheme.errorColor;
    }

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 90,
                  height: 90,
                  child: CircularProgressIndicator(
                    value: avgCompliance / 100,
                    strokeWidth: 8,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                  ),
                ),
                Text(
                  '$avgCompliance%',
                  style: TextStyle(color: scoreColor, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Overall Compliance',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_frameworks.where((f) => f.isEnabled).length} active frameworks monitored',
                    style: TextStyle(color: Colors.white.withAlpha(153)),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _isGenerating ? null : () => _generateFullReport(),
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const DuotoneIcon('chart', size: 18),
                    label: Text(_isGenerating ? 'Generating...' : 'Generate Full Report'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GlassTheme.primaryAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrameworkCard(ComplianceFramework framework) {
    Color statusColor;
    if (!framework.isEnabled) {
      statusColor = Colors.grey;
    } else if (framework.complianceScore >= 90) {
      statusColor = GlassTheme.successColor;
    } else if (framework.complianceScore >= 70) {
      statusColor = GlassTheme.warningColor;
    } else {
      statusColor = GlassTheme.errorColor;
    }

    return GlassCard(
      onTap: () => _showFrameworkDetails(context, framework),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: _getFrameworkIcon(framework.id),
                color: framework.isEnabled ? statusColor : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(framework.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(framework.description, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (framework.isEnabled)
                    Text(
                      '${framework.complianceScore}%',
                      style: TextStyle(color: statusColor, fontSize: 24, fontWeight: FontWeight.bold),
                    )
                  else
                    const GlassBadge(text: 'Disabled', color: Colors.grey, fontSize: 10),
                ],
              ),
            ],
          ),
          if (framework.isEnabled) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: framework.complianceScore / 100,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildFrameworkStat('check_circle', '${framework.passedControls}', 'Passed', GlassTheme.successColor),
                const SizedBox(width: 16),
                _buildFrameworkStat('danger_triangle', '${framework.failedControls}', 'Failed', GlassTheme.errorColor),
                const SizedBox(width: 16),
                _buildFrameworkStat('question_circle', '${framework.totalControls - framework.passedControls - framework.failedControls}', 'N/A', Colors.grey),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFrameworkStat(String icon, String value, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DuotoneIcon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11)),
      ],
    );
  }

  Widget _buildReportsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Generate new report
        GlassCard(
          onTap: () => _showGenerateReportDialog(context),
          child: Row(
            children: [
              GlassSvgIconBox(icon: 'chart_square', color: GlassTheme.primaryAccent),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Generate New Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('Create a custom compliance report', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              const DuotoneIcon('alt_arrow_right', color: Colors.white38, size: 24),
            ],
          ),
        ),
        const SizedBox(height: 24),

        const GlassSectionHeader(title: 'Recent Reports'),
        if (_reports.isEmpty)
          _buildEmptyState('No Reports', 'Generate your first compliance report')
        else
          ..._reports.map((report) => _buildReportCard(report)),
      ],
    );
  }

  Widget _buildReportCard(ComplianceReport report) {
    return GlassCard(
      onTap: () => _showReportDetails(context, report),
      child: Row(
        children: [
          GlassSvgIconBox(
            icon: 'file',
            color: _getFrameworkColor(report.framework),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(report.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(report.framework, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    DuotoneIcon('calendar', size: 12, color: Colors.white.withAlpha(102)),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(report.generatedAt),
                      style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GlassBadge(text: report.format, color: GlassTheme.primaryAccent, fontSize: 10),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const DuotoneIcon('download_minimalistic', size: 20),
                    color: Colors.white54,
                    onPressed: () {},
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const DuotoneIcon('share', size: 20),
                    color: Colors.white54,
                    onPressed: () {},
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlsTab() {
    final grouped = <String, List<ComplianceControl>>{};
    for (final control in _controls) {
      grouped.putIfAbsent(control.category, () => []).add(control);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats
        Row(
          children: [
            _buildStatCard('Total', '${_controls.length}', GlassTheme.primaryAccent),
            const SizedBox(width: 12),
            _buildStatCard('Passing', '${_controls.where((c) => c.status == 'pass').length}', GlassTheme.successColor),
            const SizedBox(width: 12),
            _buildStatCard('Failing', '${_controls.where((c) => c.status == 'fail').length}', GlassTheme.errorColor),
          ],
        ),
        const SizedBox(height: 24),

        // Controls by category
        ...grouped.entries.map((entry) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassSectionHeader(title: entry.key),
                ...entry.value.map((control) => _buildControlCard(control)),
                const SizedBox(height: 16),
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
            Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard(ComplianceControl control) {
    Color statusColor;
    String statusIcon;
    switch (control.status) {
      case 'pass':
        statusColor = GlassTheme.successColor;
        statusIcon = 'check_circle';
        break;
      case 'fail':
        statusColor = GlassTheme.errorColor;
        statusIcon = 'close_circle';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = 'question_circle';
    }

    return GlassCard(
      onTap: () => _showControlDetails(context, control),
      child: Row(
        children: [
          DuotoneIcon(statusIcon, color: statusColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GlassBadge(text: control.controlId, color: GlassTheme.primaryAccent, fontSize: 10),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        control.title,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  control.description,
                  style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 4,
            children: control.frameworks.take(2).map((f) => GlassBadge(text: f, color: _getFrameworkColor(f), fontSize: 9)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            DuotoneIcon('inbox', size: 48, color: GlassTheme.primaryAccent.withAlpha(128)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(153))),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DuotoneIcon('danger_triangle', size: 48, color: GlassTheme.errorColor.withAlpha(180)),
            const SizedBox(height: 16),
            const Text(
              'Failed to Load Data',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'An unknown error occurred',
              style: TextStyle(color: Colors.white.withAlpha(153)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const DuotoneIcon('refresh', size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateFullReport() async {
    setState(() => _isGenerating = true);
    try {
      final reportData = await _api.generateComplianceReport(
        frameworks: _frameworks.where((f) => f.isEnabled).map((f) => f.id).toList(),
        format: 'PDF',
      );
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _reports.insert(0, ComplianceReport.fromJson(reportData));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report generated successfully'),
          backgroundColor: GlassTheme.successColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate report: $e'),
          backgroundColor: GlassTheme.errorColor,
        ),
      );
    }
  }

  void _showFrameworkDetails(BuildContext context, ComplianceFramework framework) {
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
                  GlassSvgIconBox(icon: _getFrameworkIcon(framework.id), color: GlassTheme.primaryAccent, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(framework.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        GlassBadge(
                          text: framework.isEnabled ? '${framework.complianceScore}% Compliant' : 'Disabled',
                          color: framework.isEnabled ? GlassTheme.successColor : Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(framework.description, style: TextStyle(color: Colors.white.withAlpha(204))),
              const SizedBox(height: 20),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Total Controls', '${framework.totalControls}'),
                    _buildDetailRow('Passed', '${framework.passedControls}'),
                    _buildDetailRow('Failed', '${framework.failedControls}'),
                    _buildDetailRow('Last Assessment', _formatDate(framework.lastAssessment)),
                    _buildDetailRow('Next Assessment', _formatDate(framework.nextAssessment)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const DuotoneIcon('play', size: 18),
                      label: const Text('Run Assessment'),
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
                      onPressed: () {
                        Navigator.pop(context);
                        _showGenerateReportDialog(context, framework: framework.id);
                      },
                      icon: const DuotoneIcon('file', size: 18),
                      label: const Text('Generate Report'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GlassTheme.primaryAccent,
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

  void _showGenerateReportDialog(BuildContext context, {String? framework}) {
    String selectedFramework = framework ?? 'SOC2';
    String selectedFormat = 'PDF';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: GlassTheme.gradientTop,
          title: const Text('Generate Report', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedFramework,
                dropdownColor: GlassTheme.gradientTop,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Framework',
                  labelStyle: TextStyle(color: Colors.white.withAlpha(128)),
                ),
                items: ['SOC2', 'GDPR', 'HIPAA', 'PCI-DSS', 'ISO27001', 'All']
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedFramework = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedFormat,
                dropdownColor: GlassTheme.gradientTop,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Format',
                  labelStyle: TextStyle(color: Colors.white.withAlpha(128)),
                ),
                items: ['PDF', 'CSV', 'JSON', 'HTML']
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedFormat = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _generateFullReport();
              },
              style: ElevatedButton.styleFrom(backgroundColor: GlassTheme.primaryAccent, foregroundColor: Colors.white),
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDetails(BuildContext context, ComplianceReport report) {
    // Show report details
  }

  void _showControlDetails(BuildContext context, ComplianceControl control) {
    // Show control details
  }

  void _showScheduleDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Schedule Reports', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const DuotoneIcon('calendar', color: GlassTheme.primaryAccent, size: 24),
              title: const Text('Daily', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const DuotoneIcon('calendar', color: GlassTheme.primaryAccent, size: 24),
              title: const Text('Weekly', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const DuotoneIcon('calendar', color: GlassTheme.primaryAccent, size: 24),
              title: const Text('Monthly', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
          ],
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

  String _getFrameworkIcon(String id) {
    switch (id.toUpperCase()) {
      case 'SOC2':
        return 'verified_check';
      case 'GDPR':
        return 'shield_check';
      case 'HIPAA':
        return 'heart_pulse';
      case 'PCI-DSS':
        return 'card';
      case 'ISO27001':
        return 'shield';
      default:
        return 'clipboard_text';
    }
  }

  Color _getFrameworkColor(String framework) {
    switch (framework.toUpperCase()) {
      case 'SOC2':
        return const Color(0xFF4CAF50);
      case 'GDPR':
        return const Color(0xFF2196F3);
      case 'HIPAA':
        return const Color(0xFFE91E63);
      case 'PCI-DSS':
        return const Color(0xFFFF9800);
      case 'ISO27001':
        return const Color(0xFF9C27B0);
      default:
        return GlassTheme.primaryAccent;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class ComplianceFramework {
  final String id;
  final String name;
  final String description;
  final bool isEnabled;
  final int complianceScore;
  final int totalControls;
  final int passedControls;
  final int failedControls;
  final DateTime lastAssessment;
  final DateTime nextAssessment;

  ComplianceFramework({
    required this.id,
    required this.name,
    required this.description,
    required this.isEnabled,
    required this.complianceScore,
    required this.totalControls,
    required this.passedControls,
    required this.failedControls,
    required this.lastAssessment,
    required this.nextAssessment,
  });

  factory ComplianceFramework.fromJson(Map<String, dynamic> json) {
    return ComplianceFramework(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      isEnabled: json['is_enabled'] as bool? ?? json['isEnabled'] as bool? ?? false,
      complianceScore: json['compliance_score'] as int? ?? json['complianceScore'] as int? ?? 0,
      totalControls: json['total_controls'] as int? ?? json['totalControls'] as int? ?? 0,
      passedControls: json['passed_controls'] as int? ?? json['passedControls'] as int? ?? 0,
      failedControls: json['failed_controls'] as int? ?? json['failedControls'] as int? ?? 0,
      lastAssessment: json['last_assessment'] != null
          ? DateTime.tryParse(json['last_assessment'] as String) ?? DateTime.now()
          : json['lastAssessment'] != null
              ? DateTime.tryParse(json['lastAssessment'] as String) ?? DateTime.now()
              : DateTime.now(),
      nextAssessment: json['next_assessment'] != null
          ? DateTime.tryParse(json['next_assessment'] as String) ?? DateTime.now()
          : json['nextAssessment'] != null
              ? DateTime.tryParse(json['nextAssessment'] as String) ?? DateTime.now()
              : DateTime.now(),
    );
  }
}

class ComplianceReport {
  final String id;
  final String title;
  final String framework;
  final String format;
  final DateTime generatedAt;
  final String size;

  ComplianceReport({
    required this.id,
    required this.title,
    required this.framework,
    required this.format,
    required this.generatedAt,
    required this.size,
  });

  factory ComplianceReport.fromJson(Map<String, dynamic> json) {
    return ComplianceReport(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      framework: json['framework'] as String? ?? '',
      format: json['format'] as String? ?? 'PDF',
      generatedAt: json['generated_at'] != null
          ? DateTime.tryParse(json['generated_at'] as String) ?? DateTime.now()
          : json['generatedAt'] != null
              ? DateTime.tryParse(json['generatedAt'] as String) ?? DateTime.now()
              : DateTime.now(),
      size: json['size'] as String? ?? '0 KB',
    );
  }
}

class ComplianceControl {
  final String id;
  final String controlId;
  final String title;
  final String description;
  final String category;
  final String status;
  final List<String> frameworks;

  ComplianceControl({
    required this.id,
    required this.controlId,
    required this.title,
    required this.description,
    required this.category,
    required this.status,
    required this.frameworks,
  });

  factory ComplianceControl.fromJson(Map<String, dynamic> json) {
    return ComplianceControl(
      id: json['id'] as String? ?? '',
      controlId: json['control_id'] as String? ?? json['controlId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      frameworks: (json['frameworks'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? [],
    );
  }
}
