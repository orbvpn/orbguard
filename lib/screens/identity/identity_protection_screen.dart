// Identity Protection Screen
// Monitor and protect against identity theft

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/identity_protection_provider.dart';
import '../../services/security/identity_theft_protection_service.dart';

class IdentityProtectionScreen extends StatefulWidget {
  const IdentityProtectionScreen({super.key});

  @override
  State<IdentityProtectionScreen> createState() =>
      _IdentityProtectionScreenState();
}

class _IdentityProtectionScreenState extends State<IdentityProtectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IdentityProtectionProvider>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<IdentityProtectionProvider>(
      builder: (context, provider, _) {
        return GlassTabPage(
          title: 'Identity Protection',
          hasSearch: true,
          searchHint: 'Search assets...',
          headerContent: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (provider.isScanning)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: GlassTheme.primaryAccent,
                      ),
                    ),
                  )
                else
                  IconButton(
                    icon: const DuotoneIcon('refresh', size: 22, color: Colors.white),
                    onPressed: () => provider.scanAllAssets(),
                    tooltip: 'Refresh',
                  ),
                IconButton(
                  icon: const DuotoneIcon('add_circle', size: 22, color: Colors.white),
                  onPressed: () => _showAddAssetSheet(context, provider),
                  tooltip: 'Add Asset',
                ),
              ],
            ),
          ),
          tabs: [
            GlassTab(
              label: 'Overview',
              iconPath: 'user',
              content: provider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: GlassTheme.primaryAccent,
                      ),
                    )
                  : _buildOverviewTab(provider),
            ),
            GlassTab(
              label: 'Assets',
              iconPath: 'shield_check',
              content: provider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: GlassTheme.primaryAccent,
                      ),
                    )
                  : _buildAssetsTab(provider),
            ),
            GlassTab(
              label: 'Alerts',
              iconPath: 'danger_triangle',
              content: provider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: GlassTheme.primaryAccent,
                      ),
                    )
                  : _buildAlertsTab(provider),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOverviewTab(IdentityProtectionProvider provider) {
    final summary = provider.summary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Protection Score Card
        _buildProtectionScoreCard(provider),
        const SizedBox(height: 16),

        // Quick Stats
        _buildQuickStats(provider),
        const SizedBox(height: 16),

        // Credit Freeze Status
        _buildCreditFreezeCard(provider),
        const SizedBox(height: 16),

        // Recommendations
        if (summary != null && summary.recommendations.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Recommendations',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...summary.recommendations.map((r) => _buildRecommendationCard(r)),
        ],
      ],
    );
  }

  Widget _buildProtectionScoreCard(IdentityProtectionProvider provider) {
    final score = provider.protectionScore;
    final grade = provider.protectionGrade;
    final gradeColor = _getGradeColor(grade);

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: gradeColor,
                      width: 4,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          grade,
                          style: TextStyle(
                            color: gradeColor,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '$score/100',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Protection Score',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getScoreDescription(score),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildMiniStat(
                          'Assets',
                          provider.monitoredAssets.length.toString(),
                        ),
                        const SizedBox(width: 16),
                        _buildMiniStat(
                          'Alerts',
                          provider.activeAlerts.length.toString(),
                        ),
                        const SizedBox(width: 16),
                        _buildMiniStat(
                          'Frozen (self)',
                          '${provider.frozenBureausCount}/3',
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: GlassTheme.primaryAccent,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats(IdentityProtectionProvider provider) {
    return Row(
      children: [
        _buildStatCard(
          'Critical Alerts',
          provider.criticalAlerts.length.toString(),
          'danger_circle',
          GlassTheme.errorColor,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          'Active Alerts',
          provider.activeAlerts.length.toString(),
          'danger_triangle',
          GlassTheme.warningColor,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          'Live Monitored',
          provider.monitoredAssets
              .where((a) => a.supportsLiveScan)
              .length
              .toString(),
          'shield_check',
          GlassTheme.successColor,
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, String icon, Color color) {
    return Expanded(
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              DuotoneIcon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreditFreezeCard(IdentityProtectionProvider provider) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const DuotoneIcon(
                  'shield_check',
                  color: GlassTheme.primaryAccent,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Credit Freeze Status',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Text(
                  '${provider.frozenBureausCount}/3 Self-Reported',
                  style: TextStyle(
                    color: provider.frozenBureausCount == 3
                        ? GlassTheme.successColor
                        : Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'OrbGuard cannot freeze credit on your behalf. Use each '
              'bureau\'s official freeze page, then record your status '
              'here — it is stored as self-reported and is not verified.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            ...CreditBureau.values.map((bureau) {
              final status = provider.freezeStatus[bureau];
              final isFrozen = status?.isFrozen ?? false;

              return GlassContainer(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(IdentityProtectionProvider.getBureauColor(
                                bureau))
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: DuotoneIcon(
                          isFrozen ? 'lock' : 'lock_unlocked',
                          size: 18,
                          color: Color(
                              IdentityProtectionProvider.getBureauColor(bureau)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bureau.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            isFrozen
                                ? 'Frozen (self-reported)'
                                : 'Not frozen (self-reported)',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isFrozen
                                  ? GlassTheme.successColor
                                  : Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Open ${bureau.displayName}\'s official '
                          'freeze page',
                      icon: const DuotoneIcon(
                        'link',
                        size: 18,
                        color: GlassTheme.primaryAccent,
                      ),
                      onPressed: () => _openOfficialFreezePage(
                        context,
                        provider,
                        bureau,
                      ),
                    ),
                    Switch(
                      value: isFrozen,
                      activeThumbColor: GlassTheme.successColor,
                      onChanged: (value) =>
                          provider.setSelfReportedFreeze(bureau, value),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _openOfficialFreezePage(
    BuildContext context,
    IdentityProtectionProvider provider,
    CreditBureau bureau,
  ) async {
    final url = Uri.parse(provider.officialFreezeUrl(bureau));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final launched =
          await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
                'Could not open ${bureau.displayName}\'s freeze page '
                '($url). Open it manually in your browser.'),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              'Could not open ${bureau.displayName}\'s freeze page: $e'),
        ),
      );
    }
  }

  Widget _buildRecommendationCard(String recommendation) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: GlassTheme.primaryAccent.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: DuotoneIcon(
              'lightbulb',
              color: GlassTheme.primaryAccent,
              size: 20,
            ),
          ),
        ),
        title: Text(
          recommendation,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        trailing: const DuotoneIcon(
          'alt_arrow_right',
          color: Colors.white24,
          size: 16,
        ),
      ),
    );
  }

  Widget _buildAssetsTab(IdentityProtectionProvider provider) {
    if (provider.monitoredAssets.isEmpty) {
      return _buildEmptyState(
        icon: 'shield_check',
        title: 'No Assets Monitored',
        subtitle: 'Add your personal information to monitor for exposure',
        action: TextButton.icon(
          onPressed: () => _showAddAssetSheet(context, provider),
          icon: const DuotoneIcon('add_circle', size: 18),
          label: const Text('Add Asset'),
        ),
      );
    }

    final groupedAssets = <AssetType, List<MonitoredAsset>>{};
    for (final asset in provider.monitoredAssets) {
      groupedAssets.putIfAbsent(asset.type, () => []).add(asset);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: groupedAssets.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
              child: Row(
                children: [
                  DuotoneIcon(
                    _getAssetIcon(entry.key),
                    size: 18,
                    color: GlassTheme.primaryAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.key.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...entry.value.map((asset) => _buildAssetCard(asset, provider)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildAssetCard(MonitoredAsset asset, IdentityProtectionProvider provider) {
    final statusColor =
        Color(IdentityProtectionProvider.getStatusColor(asset.status));

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: DuotoneIcon(
              _getAssetIcon(asset.type),
              color: statusColor,
              size: 24,
            ),
          ),
        ),
        title: Text(
          asset.maskedValue,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        subtitle: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                asset.status == MonitoringStatus.unavailable
                    ? '${asset.status.displayName} — no live data source'
                    : asset.status.displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ),
            if (asset.alertCount > 0) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: GlassTheme.errorColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${asset.alertCount} alerts',
                  style: const TextStyle(
                    color: GlassTheme.errorColor,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: const DuotoneIcon('trash_bin_minimalistic', color: Colors.white38, size: 20),
          onPressed: () => _confirmRemoveAsset(context, asset, provider),
        ),
      ),
    );
  }

  Widget _buildAlertsTab(IdentityProtectionProvider provider) {
    if (provider.alerts.isEmpty) {
      return _buildEmptyState(
        icon: 'bell',
        title: 'No Alerts',
        subtitle: 'Your identity appears to be safe',
        color: GlassTheme.successColor,
      );
    }

    final activeAlerts = provider.alerts.where((a) => !a.isResolved).toList();
    final resolvedAlerts = provider.alerts.where((a) => a.isResolved).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (activeAlerts.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Active Alerts',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...activeAlerts.map((alert) => _buildAlertCard(alert, provider)),
          const SizedBox(height: 16),
        ],
        if (resolvedAlerts.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Resolved Alerts',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...resolvedAlerts.map((alert) => _buildAlertCard(alert, provider)),
        ],
      ],
    );
  }

  Widget _buildAlertCard(IdentityAlert alert, IdentityProtectionProvider provider) {
    final severityColor =
        Color(IdentityProtectionProvider.getSeverityColor(alert.severity));

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: severityColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: DuotoneIcon(
                      _getAlertIcon(alert.type),
                      color: severityColor,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: alert.isResolved ? Colors.white54 : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        alert.type.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: alert.isResolved
                        ? GlassTheme.successColor
                        : severityColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    alert.isResolved ? 'RESOLVED' : alert.severity.displayName.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              alert.description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
            if (alert.recommendedActions.isNotEmpty && !alert.isResolved) ...[
              const SizedBox(height: 12),
              const Text(
                'Recommended Actions:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              ...alert.recommendedActions.take(3).map((action) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '• ',
                          style: TextStyle(
                            color: GlassTheme.primaryAccent,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            action,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
            if (!alert.isResolved) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!alert.isAcknowledged)
                    TextButton(
                      onPressed: () => provider.acknowledgeAlert(alert.id),
                      child: const Text('Acknowledge'),
                    ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => provider.resolveAlert(alert.id),
                    child: const Text('Resolve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required String icon,
    required String title,
    required String subtitle,
    Color color = GlassTheme.primaryAccent,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuotoneIcon(icon, size: 64, color: color.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }

  String _getAssetIcon(AssetType type) {
    switch (type) {
      case AssetType.ssn:
        return 'user_id';
      case AssetType.creditCard:
        return 'card';
      case AssetType.bankAccount:
        return 'wallet';
      case AssetType.email:
        return 'letter';
      case AssetType.phone:
        return 'smartphone';
      case AssetType.driversLicense:
        return 'user_id';
      case AssetType.passport:
        return 'user_id';
      case AssetType.address:
        return 'home';
      case AssetType.dateOfBirth:
        return 'calendar';
      case AssetType.mothersMaidenName:
        return 'user';
      case AssetType.medicalId:
        return 'shield_check';
      case AssetType.other:
        return 'file';
    }
  }

  String _getAlertIcon(IdentityAlertType type) {
    switch (type) {
      case IdentityAlertType.ssnExposure:
        return 'user_id';
      case IdentityAlertType.creditInquiry:
        return 'magnifer';
      case IdentityAlertType.newAccount:
        return 'user_plus';
      case IdentityAlertType.addressChange:
        return 'home';
      case IdentityAlertType.bankAccountExposure:
        return 'wallet';
      case IdentityAlertType.publicRecords:
        return 'folder';
      case IdentityAlertType.darkWebExposure:
        return 'incognito';
      case IdentityAlertType.dataBrokerExposure:
        return 'database';
      case IdentityAlertType.paydayLoan:
        return 'money_bag';
      case IdentityAlertType.sexOffenderRegistry:
        return 'danger_triangle';
      case IdentityAlertType.courtRecords:
        return 'document';
      case IdentityAlertType.utilityAccount:
        return 'power';
    }
  }

  Color _getGradeColor(String grade) {
    switch (grade) {
      case 'A':
        return const Color(0xFF4CAF50);
      case 'B':
        return const Color(0xFF8BC34A);
      case 'C':
        return const Color(0xFFFFEB3B);
      case 'D':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFFFF5722);
    }
  }

  String _getScoreDescription(int score) {
    if (score >= 90) return 'Excellent protection';
    if (score >= 80) return 'Good protection';
    if (score >= 70) return 'Fair protection';
    if (score >= 60) return 'Needs improvement';
    return 'At risk';
  }

  void _showAddAssetSheet(
    BuildContext context,
    IdentityProtectionProvider provider,
  ) {
    AssetType? selectedType;
    final valueController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                GlassTheme.gradientTop,
                GlassTheme.gradientBottom,
              ],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add Asset for Monitoring',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Email addresses are checked against live breach and '
                  'data-broker sources. Other asset types are stored only '
                  'on this device (masked and hashed) and are shown as '
                  '"Unavailable" until a live data source exists for them.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Asset Type',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AssetType.values.where((t) => t != AssetType.other).map((type) {
                    final isSelected = type == selectedType;
                    return ChoiceChip(
                      avatar: DuotoneIcon(
                        _getAssetIcon(type),
                        size: 18,
                        color: isSelected
                            ? Colors.white
                            : GlassTheme.primaryAccent,
                      ),
                      label: Text(type == AssetType.email
                          ? '${type.displayName} • Live'
                          : type.displayName),
                      selected: isSelected,
                      selectedColor: GlassTheme.primaryAccent,
                      backgroundColor:
                          GlassTheme.primaryAccent.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : GlassTheme.primaryAccent,
                        fontSize: 12,
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => selectedType = type);
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: valueController,
                  style: const TextStyle(color: Colors.white),
                  obscureText: selectedType == AssetType.ssn ||
                      selectedType == AssetType.bankAccount,
                  decoration: InputDecoration(
                    labelText: selectedType != null
                        ? 'Enter ${selectedType!.displayName}'
                        : 'Select asset type first',
                    labelStyle: const TextStyle(color: Colors.white54),
                    enabled: selectedType != null,
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(
                        color: GlassTheme.primaryAccent,
                      ),
                    ),
                    disabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedType != null &&
                            valueController.text.isNotEmpty
                        ? () async {
                            await provider.addMonitoredAsset(
                              type: selectedType!,
                              value: valueController.text,
                            );
                            if (context.mounted) Navigator.pop(context);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GlassTheme.primaryAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white12,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: provider.isAddingAsset
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Add for Monitoring'),
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmRemoveAsset(
    BuildContext context,
    MonitoredAsset asset,
    IdentityProtectionProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text(
          'Remove Asset?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Stop monitoring ${asset.maskedValue}?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.removeMonitoredAsset(asset.id);
              Navigator.pop(context);
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: GlassTheme.errorColor),
            ),
          ),
        ],
      ),
    );
  }
}
