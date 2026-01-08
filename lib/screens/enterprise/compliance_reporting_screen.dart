/// Enterprise Compliance Reporting Screen
/// Generates compliance reports for SOC2, GDPR, HIPAA, PCI-DSS, ISO27001
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';

class ComplianceReportingScreen extends StatefulWidget {
  const ComplianceReportingScreen({super.key});

  @override
  State<ComplianceReportingScreen> createState() => _ComplianceReportingScreenState();
}

class _ComplianceReportingScreenState extends State<ComplianceReportingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  bool _isGenerating = false;
  final List<ComplianceFramework> _frameworks = [];
  final List<ComplianceReport> _reports = [];
  final List<ComplianceControl> _controls = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _frameworks.addAll(_getSampleFrameworks());
      _reports.addAll(_getSampleReports());
      _controls.addAll(_getSampleControls());
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Compliance Reporting',
        actions: [
          IconButton(
            icon: const Icon(Icons.schedule),
            tooltip: 'Schedule Reports',
            onPressed: () => _showScheduleDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GlassTheme.primaryAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Frameworks'),
            Tab(text: 'Reports'),
            Tab(text: 'Controls'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFrameworksTab(),
                _buildReportsTab(),
                _buildControlsTab(),
              ],
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
                        : const Icon(Icons.assessment, size: 18),
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
              GlassIconBox(
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
                _buildFrameworkStat(Icons.check_circle, '${framework.passedControls}', 'Passed', GlassTheme.successColor),
                const SizedBox(width: 16),
                _buildFrameworkStat(Icons.warning, '${framework.failedControls}', 'Failed', GlassTheme.errorColor),
                const SizedBox(width: 16),
                _buildFrameworkStat(Icons.help_outline, '${framework.totalControls - framework.passedControls - framework.failedControls}', 'N/A', Colors.grey),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFrameworkStat(IconData icon, String value, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
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
              GlassIconBox(icon: Icons.add_chart, color: GlassTheme.primaryAccent),
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
              const Icon(Icons.chevron_right, color: Colors.white38),
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
          GlassIconBox(
            icon: Icons.description,
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
                    Icon(Icons.calendar_today, size: 12, color: Colors.white.withAlpha(102)),
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
                    icon: const Icon(Icons.download, size: 20),
                    color: Colors.white54,
                    onPressed: () {},
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.share, size: 20),
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
    IconData statusIcon;
    switch (control.status) {
      case 'pass':
        statusColor = GlassTheme.successColor;
        statusIcon = Icons.check_circle;
        break;
      case 'fail':
        statusColor = GlassTheme.errorColor;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
    }

    return GlassCard(
      onTap: () => _showControlDetails(context, control),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor),
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
            Icon(Icons.inbox, size: 48, color: GlassTheme.primaryAccent.withAlpha(128)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(153))),
          ],
        ),
      ),
    );
  }

  void _generateFullReport() {
    setState(() => _isGenerating = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _reports.insert(
          0,
          ComplianceReport(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: 'Full Compliance Report',
            framework: 'All Frameworks',
            format: 'PDF',
            generatedAt: DateTime.now(),
            size: '2.4 MB',
          ),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report generated successfully'),
          backgroundColor: GlassTheme.successColor,
        ),
      );
    });
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
                  GlassIconBox(icon: _getFrameworkIcon(framework.id), color: GlassTheme.primaryAccent, size: 56),
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
                      icon: const Icon(Icons.play_arrow),
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
                      icon: const Icon(Icons.description),
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
              leading: const Icon(Icons.calendar_view_day, color: GlassTheme.primaryAccent),
              title: const Text('Daily', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_view_week, color: GlassTheme.primaryAccent),
              title: const Text('Weekly', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_view_month, color: GlassTheme.primaryAccent),
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

  IconData _getFrameworkIcon(String id) {
    switch (id.toUpperCase()) {
      case 'SOC2':
        return Icons.verified_user;
      case 'GDPR':
        return Icons.privacy_tip;
      case 'HIPAA':
        return Icons.local_hospital;
      case 'PCI-DSS':
        return Icons.credit_card;
      case 'ISO27001':
        return Icons.security;
      default:
        return Icons.policy;
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

  List<ComplianceFramework> _getSampleFrameworks() {
    return [
      ComplianceFramework(
        id: 'SOC2',
        name: 'SOC 2 Type II',
        description: 'Service Organization Control 2',
        isEnabled: true,
        complianceScore: 94,
        totalControls: 64,
        passedControls: 60,
        failedControls: 4,
        lastAssessment: DateTime.now().subtract(const Duration(days: 7)),
        nextAssessment: DateTime.now().add(const Duration(days: 23)),
      ),
      ComplianceFramework(
        id: 'GDPR',
        name: 'GDPR',
        description: 'General Data Protection Regulation',
        isEnabled: true,
        complianceScore: 89,
        totalControls: 48,
        passedControls: 43,
        failedControls: 5,
        lastAssessment: DateTime.now().subtract(const Duration(days: 14)),
        nextAssessment: DateTime.now().add(const Duration(days: 16)),
      ),
      ComplianceFramework(
        id: 'HIPAA',
        name: 'HIPAA',
        description: 'Health Insurance Portability and Accountability Act',
        isEnabled: false,
        complianceScore: 0,
        totalControls: 42,
        passedControls: 0,
        failedControls: 0,
        lastAssessment: DateTime.now(),
        nextAssessment: DateTime.now(),
      ),
      ComplianceFramework(
        id: 'PCI-DSS',
        name: 'PCI-DSS',
        description: 'Payment Card Industry Data Security Standard',
        isEnabled: true,
        complianceScore: 78,
        totalControls: 56,
        passedControls: 44,
        failedControls: 12,
        lastAssessment: DateTime.now().subtract(const Duration(days: 3)),
        nextAssessment: DateTime.now().add(const Duration(days: 27)),
      ),
      ComplianceFramework(
        id: 'ISO27001',
        name: 'ISO 27001',
        description: 'Information Security Management System',
        isEnabled: false,
        complianceScore: 0,
        totalControls: 114,
        passedControls: 0,
        failedControls: 0,
        lastAssessment: DateTime.now(),
        nextAssessment: DateTime.now(),
      ),
    ];
  }

  List<ComplianceReport> _getSampleReports() {
    return [
      ComplianceReport(
        id: '1',
        title: 'SOC 2 Quarterly Report',
        framework: 'SOC2',
        format: 'PDF',
        generatedAt: DateTime.now().subtract(const Duration(days: 2)),
        size: '1.8 MB',
      ),
      ComplianceReport(
        id: '2',
        title: 'GDPR Data Processing Report',
        framework: 'GDPR',
        format: 'PDF',
        generatedAt: DateTime.now().subtract(const Duration(days: 7)),
        size: '2.1 MB',
      ),
      ComplianceReport(
        id: '3',
        title: 'PCI-DSS Gap Analysis',
        framework: 'PCI-DSS',
        format: 'CSV',
        generatedAt: DateTime.now().subtract(const Duration(days: 14)),
        size: '458 KB',
      ),
    ];
  }

  List<ComplianceControl> _getSampleControls() {
    return [
      ComplianceControl(
        id: '1',
        controlId: 'CC6.1',
        title: 'Logical Access Security',
        description: 'System boundaries are defined and access is restricted',
        category: 'Access Control',
        status: 'pass',
        frameworks: ['SOC2', 'ISO27001'],
      ),
      ComplianceControl(
        id: '2',
        controlId: 'CC6.2',
        title: 'Authentication Mechanisms',
        description: 'Multi-factor authentication is implemented',
        category: 'Access Control',
        status: 'pass',
        frameworks: ['SOC2', 'PCI-DSS'],
      ),
      ComplianceControl(
        id: '3',
        controlId: 'Art.32',
        title: 'Security of Processing',
        description: 'Appropriate technical measures to ensure security',
        category: 'Data Protection',
        status: 'pass',
        frameworks: ['GDPR'],
      ),
      ComplianceControl(
        id: '4',
        controlId: 'Req.3.4',
        title: 'Encryption of Cardholder Data',
        description: 'PAN is rendered unreadable anywhere it is stored',
        category: 'Data Protection',
        status: 'fail',
        frameworks: ['PCI-DSS'],
      ),
      ComplianceControl(
        id: '5',
        controlId: 'CC7.2',
        title: 'System Monitoring',
        description: 'Security events are monitored and logged',
        category: 'Monitoring',
        status: 'pass',
        frameworks: ['SOC2', 'ISO27001', 'PCI-DSS'],
      ),
    ];
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
}
