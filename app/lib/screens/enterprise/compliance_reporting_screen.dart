/// Enterprise Compliance Reporting Screen
///
/// Wired to the live backend routes:
///   GET  /enterprise/compliance/frameworks  - supported framework list
///   GET  /enterprise/compliance/reports     - generated reports
///   GET  /enterprise/compliance/controls    - control CATALOGS (GDPR/SOC2/CIS)
///   POST /enterprise/compliance/reports     - generate a report (one framework)
///
/// Controls are catalog definitions, not assessments — the backend returns
/// them with status "unknown" and this screen renders that honestly as
/// "Not assessed". Assessed results only exist inside generated reports.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/api/api_interceptors.dart' show ApiError;
import '../../services/api/orbguard_api_client.dart';

class ComplianceReportingScreen extends StatefulWidget {
  const ComplianceReportingScreen({super.key});

  @override
  State<ComplianceReportingScreen> createState() => _ComplianceReportingScreenState();
}

class _ComplianceReportingScreenState extends State<ComplianceReportingScreen> {
  bool _isLoading = false;
  bool _isGenerating = false;
  bool _isLoadingControls = false;
  String? _error;
  final List<ComplianceFramework> _frameworks = [];
  final List<ComplianceReport> _reports = [];
  final List<ComplianceControl> _controls = [];

  /// Frameworks the backend has control catalogs / report generation for.
  static const List<String> _reportableFrameworks = ['gdpr', 'soc2', 'cis'];

  /// null = all catalogs; otherwise one of [_reportableFrameworks].
  String? _controlsFilter;

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
        _api.getComplianceControls(framework: _controlsFilter),
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
        _reports.sort((a, b) {
          final at = a.generatedAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.generatedAt?.millisecondsSinceEpoch ?? 0;
          return bt.compareTo(at);
        });
        _controls.addAll(controlsData.map((data) => ComplianceControl.fromJson(data)));
        _isLoading = false;
      });
    } catch (e) {
      // Compliance reporting is an optional, config-gated enterprise feature;
      // a 404 means it isn't provisioned on this server — degrade to the tabs'
      // normal empty states instead of a scary "Failed to Load Data".
      final gone = e is ApiError && e.statusCode == 404;
      setState(() {
        _isLoading = false;
        if (gone) {
          _error = null;
          _frameworks.clear();
          _reports.clear();
          _controls.clear();
        } else {
          _error = e.toString();
        }
      });
    }
  }

  Future<void> _loadControls(String? framework) async {
    setState(() {
      _controlsFilter = framework;
      _isLoadingControls = true;
    });
    try {
      final controlsData = await _api.getComplianceControls(framework: framework);
      if (!mounted) return;
      setState(() {
        _controls
          ..clear()
          ..addAll(controlsData.map((data) => ComplianceControl.fromJson(data)));
        _isLoadingControls = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingControls = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load controls: $e'),
          backgroundColor: GlassTheme.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassTabPage(
      title: 'Compliance Reporting',
      actions: [
        GestureDetector(
          onTap: () {
            if (!_isLoading) _loadData();
          },
          child:
              DuotoneIcon('refresh', size: 22, color: context.colors.onSurface),
        ),
      ],
      tabs: [
        GlassTab(
          label: 'Frameworks',
          iconPath: 'shield',
          content: _isLoading
              ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
              : _error != null
                  ? _buildErrorState()
                  : _buildFrameworksTab(),
        ),
        GlassTab(
          label: 'Reports',
          iconPath: 'file',
          content: _isLoading
              ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
              : _error != null
                  ? _buildErrorState()
                  : _buildReportsTab(),
        ),
        GlassTab(
          label: 'Controls',
          iconPath: 'settings',
          content: _isLoading
              ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
              : _error != null
                  ? _buildErrorState()
                  : _buildControlsTab(),
        ),
      ],
    );
  }

  // ==========================================================================
  // Frameworks tab
  // ==========================================================================

  Widget _buildFrameworksTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const GlassSectionHeader(title: 'Supported Frameworks'),
        ..._frameworks.map((framework) => _buildFrameworkCard(framework)),
      ],
    );
  }

  bool _isReportable(String id) =>
      _reportableFrameworks.contains(id.toLowerCase());

  Widget _buildFrameworkCard(ComplianceFramework framework) {
    final reportable = _isReportable(framework.id);
    final color = _getFrameworkColor(framework.id);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: _getFrameworkIcon(framework.id),
                color: color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(framework.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.colors.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    Text(framework.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.colors.onSurfaceVariant,
                            fontSize: 12)),
                  ],
                ),
              ),
              GlassBadge(
                text: reportable ? 'Assessable' : 'Reference only',
                color: reportable
                    ? GlassTheme.successColor
                    : context.colors.onSurfaceVariant,
                fontSize: 10,
              ),
            ],
          ),
          if (reportable) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isGenerating
                    ? null
                    : () => _generateReport(framework.id.toLowerCase()),
                icon: const DuotoneIcon('file', size: 18),
                label: const Text('Generate Report'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accentInk,
                  side: BorderSide(color: AppColors.accentInk),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================================
  // Reports tab
  // ==========================================================================

  Widget _buildReportsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        GlassCard(
          margin: EdgeInsets.zero,
          onTap: _isGenerating ? null : () => _showGenerateReportDialog(context),
          child: Row(
            children: [
              GlassSvgIconBox(icon: 'chart_square', color: GlassTheme.primaryAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_isGenerating ? 'Generating…' : 'Generate New Report',
                        style: TextStyle(
                            color: context.colors.onSurface,
                            fontWeight: FontWeight.bold)),
                    Text('Assess GDPR, SOC 2 or CIS controls',
                        style: TextStyle(
                            color: context.colors.onSurfaceVariant,
                            fontSize: 12)),
                  ],
                ),
              ),
              if (_isGenerating)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: context.colors.onSurface),
                )
              else
                DuotoneIcon('alt_arrow_right',
                    color: context.colors.onSurfaceVariant.withValues(alpha: 0.7),
                    size: 24),
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
    final statusColor = _statusColor(report.overallStatus);

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
                Text(report.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.bold)),
                Text(report.framework.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    DuotoneIcon('calendar',
                        size: 12,
                        color: context.colors.onSurfaceVariant
                            .withValues(alpha: 0.7)),
                    const SizedBox(width: 4),
                    Text(
                      report.generatedAt != null
                          ? _formatDate(report.generatedAt!)
                          : 'Not available',
                      style: TextStyle(
                          color: context.colors.onSurfaceVariant
                              .withValues(alpha: 0.7),
                          fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GlassBadge(
                text: _statusLabel(report.overallStatus),
                color: statusColor,
                fontSize: 10,
              ),
              if (report.overallScore != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${report.overallScore!.toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: statusColor, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showReportDetails(BuildContext context, ComplianceReport report) {
    final cs = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            gradient: GlassTheme.backgroundGradient(isDark: context.isDark),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(GlassTheme.radiusLarge)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  GlassSvgIconBox(
                    icon: 'file',
                    color: _getFrameworkColor(report.framework),
                    size: 56,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(report.name,
                            style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        GlassBadge(
                          text: _statusLabel(report.overallStatus),
                          color: _statusColor(report.overallStatus),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (report.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(report.description,
                    style: TextStyle(color: cs.onSurface)),
              ],
              const SizedBox(height: 20),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Framework', report.framework.toUpperCase()),
                    _buildDetailRow(
                        'Overall score',
                        report.overallScore != null
                            ? '${report.overallScore!.toStringAsFixed(1)}%'
                            : 'Not available'),
                    _buildDetailRow('Total controls', '${report.totalControls ?? '—'}'),
                    _buildDetailRow('Passed', '${report.passedControls ?? '—'}'),
                    _buildDetailRow('Failed', '${report.failedControls ?? '—'}'),
                    _buildDetailRow('Partial', '${report.partialControls ?? '—'}'),
                    _buildDetailRow('Findings', '${report.findingsCount ?? '—'}'),
                    _buildDetailRow(
                        'Generated',
                        report.generatedAt != null
                            ? _formatDate(report.generatedAt!)
                            : 'Not available'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // Controls tab (catalog — definitions, not assessments)
  // ==========================================================================

  Widget _buildControlsTab() {
    final grouped = <String, List<ComplianceControl>>{};
    for (final control in _controls) {
      grouped.putIfAbsent(control.category, () => []).add(control);
    }
    final frameworkCount =
        _controls.map((c) => c.framework.toLowerCase()).toSet().length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // These are catalog definitions: the backend has not assessed them.
        GlassContainer(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              DuotoneIcon('info_circle', size: 18, color: AppColors.accentInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Control catalog. Controls are assessed when a report is generated; '
                  'status here is "Not assessed".',
                  style: TextStyle(
                      color: context.colors.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Framework filter (server-side via ?framework=)
        Wrap(
          spacing: 8,
          children: [
            _buildFilterChip('All', null),
            ..._reportableFrameworks.map(
                (f) => _buildFilterChip(f.toUpperCase(), f)),
          ],
        ),
        const SizedBox(height: 24),

        if (_isLoadingControls)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
                child: CircularProgressIndicator(color: AppColors.accentInk)),
          )
        else ...[
          Row(
            children: [
              _buildStatCard('Controls', '${_controls.length}', AppColors.accentInk),
              const SizedBox(width: 12),
              _buildStatCard('Frameworks', '$frameworkCount', AppColors.accentInk),
              const SizedBox(width: 12),
              _buildStatCard('Not assessed', '${_controls.length}',
                  context.colors.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 24),
          ...grouped.entries.map((entry) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GlassSectionHeader(title: entry.key),
                  ...entry.value.map((control) => _buildControlCard(control)),
                  const SizedBox(height: 24),
                ],
              )),
        ],
      ],
    );
  }

  Widget _buildFilterChip(String label, String? value) {
    final selected = _controlsFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: GlassTheme.primaryAccent,
      backgroundColor: context.colors.onSurface.withValues(alpha: 0.06),
      labelStyle: TextStyle(
        color: selected ? Brand.onLime : context.colors.onSurfaceVariant,
        fontSize: 12,
      ),
      onSelected: (sel) {
        if (sel && !selected && !_isLoadingControls) {
          _loadControls(value);
        }
      },
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
            Text(label,
                style: TextStyle(
                    color: context.colors.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard(ComplianceControl control) {
    return GlassCard(
      onTap: () => _showControlDetails(context, control),
      child: Row(
        children: [
          DuotoneIcon('question_circle',
              color: context.colors.onSurfaceVariant, size: 24),
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
                        control.name,
                        style: TextStyle(
                            color: context.colors.onSurface,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  control.description,
                  style: TextStyle(
                      color: context.colors.onSurfaceVariant, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GlassBadge(
                text: control.framework.toUpperCase(),
                color: _getFrameworkColor(control.framework),
                fontSize: 9,
              ),
              const SizedBox(height: 6),
              GlassBadge(
                  text: 'Not assessed',
                  color: context.colors.onSurfaceVariant,
                  fontSize: 9),
            ],
          ),
        ],
      ),
    );
  }

  void _showControlDetails(BuildContext context, ComplianceControl control) {
    final cs = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            gradient: GlassTheme.backgroundGradient(isDark: context.isDark),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(GlassTheme.radiusLarge)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      control.name,
                      style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  GlassBadge(
                      text: 'Not assessed',
                      color: cs.onSurfaceVariant,
                      fontSize: 10),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  GlassBadge(text: control.controlId, color: GlassTheme.primaryAccent, fontSize: 10),
                  GlassBadge(
                    text: control.framework.toUpperCase(),
                    color: _getFrameworkColor(control.framework),
                    fontSize: 10,
                  ),
                  if (control.category.isNotEmpty)
                    GlassBadge(
                        text: control.category,
                        color: cs.onSurfaceVariant,
                        fontSize: 10),
                ],
              ),
              const SizedBox(height: 16),
              Text(control.description,
                  style: TextStyle(color: cs.onSurface)),
              if (control.requirements.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Requirements',
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...control.requirements.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DuotoneIcon('check_circle',
                              size: 16, color: AppColors.accentInk),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(r, style: TextStyle(color: cs.onSurface)),
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // Shared widgets / helpers
  // ==========================================================================

  Widget _buildEmptyState(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            DuotoneIcon('inbox', size: 48, color: GlassTheme.primaryAccent.withAlpha(128)),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    color: context.colors.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle,
                style: TextStyle(color: context.colors.onSurfaceVariant)),
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
            Text(
              'Failed to Load Data',
              style: TextStyle(
                  color: context.colors.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'An unknown error occurred',
              style: TextStyle(color: context.colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const DuotoneIcon('refresh', size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
                foregroundColor: Brand.onLime,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateReport(String framework) async {
    setState(() => _isGenerating = true);
    try {
      final reportData = await _api.generateComplianceReport(framework: framework);
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _reports.insert(0, ComplianceReport.fromJson(reportData));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${framework.toUpperCase()} report generated'),
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

  void _showGenerateReportDialog(BuildContext context) {
    String selectedFramework = _reportableFrameworks.first;
    final cs = context.colors;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: cs.surface,
          title: Text('Generate Report', style: TextStyle(color: cs.onSurface)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'The backend assesses controls for GDPR, SOC 2 and CIS.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedFramework,
                dropdownColor: cs.surface,
                style: TextStyle(color: cs.onSurface),
                decoration: InputDecoration(
                  labelText: 'Framework',
                  labelStyle: TextStyle(color: cs.onSurfaceVariant),
                ),
                items: _reportableFrameworks
                    .map((f) => DropdownMenuItem(value: f, child: Text(f.toUpperCase())))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedFramework = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _generateReport(selectedFramework);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.primaryAccent, foregroundColor: Brand.onLime),
              child: const Text('Generate'),
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
          Text(label,
              style: TextStyle(color: context.colors.onSurfaceVariant)),
          Text(value,
              style: TextStyle(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'compliant':
        return 'Compliant';
      case 'non_compliant':
        return 'Non-compliant';
      case 'partial':
        return 'Partial';
      case null:
        return 'Not available';
      default:
        return 'Unknown';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'compliant':
        return AppColors.accentInk;
      case 'non_compliant':
        return GlassTheme.errorColor;
      case 'partial':
        return GlassTheme.warningColor;
      default:
        return context.colors.onSurfaceVariant;
    }
  }

  String _getFrameworkIcon(String id) {
    switch (id.toUpperCase()) {
      case 'SOC2':
        return 'verified_check';
      case 'GDPR':
        return 'shield_check';
      case 'HIPAA':
        return 'heart_pulse';
      case 'PCI_DSS':
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
        return AppColors.accentInk;
      case 'GDPR':
        return AppColors.chartColors[3];
      case 'HIPAA':
        return AppColors.secondaryInk;
      case 'PCI_DSS':
      case 'PCI-DSS':
        return AppColors.amberInk;
      case 'ISO27001':
        return AppColors.chartColors[4];
      case 'CIS':
        return AppColors.chartColors[2];
      default:
        return GlassTheme.primaryAccent;
    }
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}

/// Framework descriptor from GET /enterprise/compliance/frameworks
/// (the backend reports id/name/description only).
class ComplianceFramework {
  final String id;
  final String name;
  final String description;

  ComplianceFramework({
    required this.id,
    required this.name,
    required this.description,
  });

  factory ComplianceFramework.fromJson(Map<String, dynamic> json) {
    return ComplianceFramework(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

/// Generated compliance report (defensively parsed — fields the backend
/// omits become null and render as "not available").
class ComplianceReport {
  final String id;
  final String name;
  final String description;
  final String framework;
  final String? overallStatus;
  final double? overallScore;
  final int? totalControls;
  final int? passedControls;
  final int? failedControls;
  final int? partialControls;
  final int? findingsCount;
  final DateTime? generatedAt;

  ComplianceReport({
    required this.id,
    required this.name,
    required this.description,
    required this.framework,
    this.overallStatus,
    this.overallScore,
    this.totalControls,
    this.passedControls,
    this.failedControls,
    this.partialControls,
    this.findingsCount,
    this.generatedAt,
  });

  factory ComplianceReport.fromJson(Map<String, dynamic> json) {
    int? asInt(dynamic v) => v is num ? v.toInt() : null;
    double? asDouble(dynamic v) => v is num ? v.toDouble() : null;

    return ComplianceReport(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Compliance Report',
      description: json['description'] as String? ?? '',
      framework: json['framework']?.toString() ?? '',
      overallStatus: json['overall_status'] as String?,
      overallScore: asDouble(json['overall_score']),
      totalControls: asInt(json['total_controls']),
      passedControls: asInt(json['passed_controls']),
      failedControls: asInt(json['failed_controls']),
      partialControls: asInt(json['partial_controls']),
      findingsCount: json['findings'] is List ? (json['findings'] as List).length : null,
      generatedAt: json['generated_at'] != null
          ? DateTime.tryParse(json['generated_at'].toString())
          : null,
    );
  }
}

/// Catalog control definition from GET /enterprise/compliance/controls.
/// Status is always "unknown" here — assessments only exist inside reports.
class ComplianceControl {
  final String controlId;
  final String name;
  final String description;
  final String category;
  final String framework;
  final List<String> requirements;

  ComplianceControl({
    required this.controlId,
    required this.name,
    required this.description,
    required this.category,
    required this.framework,
    required this.requirements,
  });

  factory ComplianceControl.fromJson(Map<String, dynamic> json) {
    return ComplianceControl(
      controlId: json['control_id'] as String? ?? '',
      name: json['control_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'Uncategorized',
      framework: json['framework']?.toString() ?? '',
      requirements: (json['requirements'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}
