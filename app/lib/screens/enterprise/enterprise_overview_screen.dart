/// Enterprise Overview Dashboard Screen
/// Renders the live enterprise statistics reported by the backend
/// (GET /api/v1/enterprise/stats) plus the active conditional access
/// policy count (GET /api/v1/enterprise/policies).
///
/// Every value shown comes from the backend; fields the backend does not
/// report are rendered as "—" (not available) rather than fabricated.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/api/api_interceptors.dart' show ApiError;
import '../../services/api/orbguard_api_client.dart';

class EnterpriseOverviewScreen extends StatefulWidget {
  const EnterpriseOverviewScreen({super.key});

  @override
  State<EnterpriseOverviewScreen> createState() => _EnterpriseOverviewScreenState();
}

class _EnterpriseOverviewScreenState extends State<EnterpriseOverviewScreen> {
  final _api = OrbGuardApiClient.instance;
  bool _isLoading = false;
  String? _errorMessage;
  EnterpriseStats _stats = EnterpriseStats.empty();
  int? _policyCount;
  int? _enabledPolicyCount;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _api.getEnterpriseStats(),
        _api.getEnterprisePolicies(),
      ]);

      final statsData = results[0] as Map<String, dynamic>;
      final policiesData = results[1] as List<Map<String, dynamic>>;

      setState(() {
        _stats = EnterpriseStats.fromJson(statsData);
        _policyCount = policiesData.length;
        _enabledPolicyCount =
            policiesData.where((p) => p['enabled'] == true).length;
        _isLoading = false;
      });
    } catch (e) {
      // /enterprise/stats and /enterprise/policies are optional, config-gated
      // enterprise features; a 404 means they aren't provisioned on this
      // server — degrade to the dashboard's "—" empty state, not an error.
      final gone = e is ApiError && e.statusCode == 404;
      setState(() {
        if (gone) {
          _errorMessage = null;
          _stats = EnterpriseStats.empty();
          _policyCount = null;
          _enabledPolicyCount = null;
        } else {
          _errorMessage = 'Failed to load enterprise data: ${e.toString()}';
        }
        _isLoading = false;
      });
    }
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DuotoneIcon('danger_circle', size: 64, color: GlassTheme.errorColor),
            const SizedBox(height: 16),
            Text(
              'Error Loading Data',
              style: TextStyle(color: context.colors.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'An unknown error occurred',
              style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const DuotoneIcon('refresh', size: 18, color: Brand.onLime),
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

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Enterprise Overview',
      actions: [
        GestureDetector(
          onTap: () {
            if (!_isLoading) _loadData();
          },
          child: DuotoneIcon('refresh', size: 22, color: context.colors.onSurface),
        ),
      ],
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
          : _errorMessage != null
              ? _buildErrorState()
              : Column(
                  children: [
                    // Content
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadData,
                        color: AppColors.accentInk,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          children: [
                            const GlassSectionHeader(title: 'Zero Trust'),
                            _buildZeroTrustSection(),
                            const SizedBox(height: 24),
                            const GlassSectionHeader(title: 'Device Management (MDM)'),
                            _buildMdmSection(),
                            const SizedBox(height: 24),
                            const GlassSectionHeader(title: 'SIEM'),
                            _buildSiemSection(),
                            const SizedBox(height: 24),
                            const GlassSectionHeader(title: 'Compliance'),
                            _buildComplianceSection(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  String _fmt(num? value) => value?.toString() ?? '—';

  String _fmtScore(double? value) =>
      value != null ? value.toStringAsFixed(1) : '—';

  Widget _buildZeroTrustSection() {
    return Column(
      children: [
        Row(
          children: [
            _buildMetricCard(
              'Policies',
              _fmt(_policyCount),
              AppColors.accentInk,
              'clipboard_text',
            ),
            const SizedBox(width: 12),
            _buildMetricCard(
              'Enabled',
              _fmt(_enabledPolicyCount),
              AppColors.accentInk,
              'check_circle',
            ),
            const SizedBox(width: 12),
            _buildMetricCard(
              'Avg Posture',
              _fmtScore(_stats.averagePostureScore),
              GlassTheme.warningColor,
              'shield_check',
            ),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              _buildDetailRow('High-trust devices', _fmt(_stats.highTrustDevices)),
              _buildDetailRow('Low-trust devices', _fmt(_stats.lowTrustDevices)),
              _buildDetailRow('Access decisions today', _fmt(_stats.accessDecisionsToday)),
              _buildDetailRow('Blocked access today', _fmt(_stats.blockedAccessToday)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMdmSection() {
    return Row(
      children: [
        _buildMetricCard(
          'Integrations',
          _fmt(_stats.mdmIntegrations),
          AppColors.accentInk,
          'settings',
        ),
        const SizedBox(width: 12),
        _buildMetricCard(
          'Devices',
          _fmt(_stats.mdmDevices),
          GlassTheme.warningColor,
          'devices',
        ),
        const SizedBox(width: 12),
        _buildMetricCard(
          'Compliant',
          _fmt(_stats.mdmCompliantDevices),
          AppColors.accentInk,
          'check_circle',
        ),
      ],
    );
  }

  Widget _buildSiemSection() {
    return Row(
      children: [
        _buildMetricCard(
          'Integrations',
          _fmt(_stats.siemIntegrations),
          AppColors.accentInk,
          'server',
        ),
        const SizedBox(width: 12),
        _buildMetricCard(
          'Events Sent Today',
          _fmt(_stats.eventsSentToday),
          AppColors.accentInk,
          'upload_minimalistic',
        ),
      ],
    );
  }

  Widget _buildComplianceSection() {
    return Column(
      children: [
        Row(
          children: [
            _buildMetricCard(
              'Reports',
              _fmt(_stats.complianceReports),
              AppColors.accentInk,
              'document',
            ),
            const SizedBox(width: 12),
            _buildMetricCard(
              'Open Findings',
              _fmt(_stats.openFindings),
              GlassTheme.warningColor,
              'danger_triangle',
            ),
            const SizedBox(width: 12),
            _buildMetricCard(
              'Critical',
              _fmt(_stats.criticalFindings),
              GlassTheme.errorColor,
              'danger_circle',
            ),
          ],
        ),
        if (_stats.overallComplianceScore != null) ...[
          const SizedBox(height: 12),
          GlassCard(
            margin: EdgeInsets.zero,
            child: _buildDetailRow(
              'Overall compliance score',
              '${_stats.overallComplianceScore!.toStringAsFixed(1)}%',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMetricCard(String label, String value, Color color, String svgIcon) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DuotoneIcon(svgIcon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 11),
              textAlign: TextAlign.center,
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Enterprise statistics as reported by GET /api/v1/enterprise/stats.
/// All fields are nullable: a field the backend omits renders as "—".
class EnterpriseStats {
  // MDM
  final int? mdmIntegrations;
  final int? mdmDevices;
  final int? mdmCompliantDevices;

  // Zero Trust
  final double? averagePostureScore;
  final int? highTrustDevices;
  final int? lowTrustDevices;
  final int? accessDecisionsToday;
  final int? blockedAccessToday;

  // SIEM
  final int? siemIntegrations;
  final int? eventsSentToday;

  // Compliance
  final double? overallComplianceScore;
  final int? complianceReports;
  final int? openFindings;
  final int? criticalFindings;

  EnterpriseStats({
    this.mdmIntegrations,
    this.mdmDevices,
    this.mdmCompliantDevices,
    this.averagePostureScore,
    this.highTrustDevices,
    this.lowTrustDevices,
    this.accessDecisionsToday,
    this.blockedAccessToday,
    this.siemIntegrations,
    this.eventsSentToday,
    this.overallComplianceScore,
    this.complianceReports,
    this.openFindings,
    this.criticalFindings,
  });

  factory EnterpriseStats.fromJson(Map<String, dynamic> json) {
    int? asInt(dynamic v) => v is num ? v.toInt() : null;
    double? asDouble(dynamic v) => v is num ? v.toDouble() : null;

    return EnterpriseStats(
      mdmIntegrations: asInt(json['mdm_integrations']),
      mdmDevices: asInt(json['mdm_devices']),
      mdmCompliantDevices: asInt(json['mdm_compliant_devices']),
      averagePostureScore: asDouble(json['average_posture_score']),
      highTrustDevices: asInt(json['high_trust_devices']),
      lowTrustDevices: asInt(json['low_trust_devices']),
      accessDecisionsToday: asInt(json['access_decisions_today']),
      blockedAccessToday: asInt(json['blocked_access_today']),
      siemIntegrations: asInt(json['siem_integrations']),
      eventsSentToday: asInt(json['events_sent_today']),
      overallComplianceScore: asDouble(json['overall_compliance_score']),
      complianceReports: asInt(json['compliance_reports']),
      openFindings: asInt(json['open_findings']),
      criticalFindings: asInt(json['critical_findings']),
    );
  }

  factory EnterpriseStats.empty() => EnterpriseStats();
}
