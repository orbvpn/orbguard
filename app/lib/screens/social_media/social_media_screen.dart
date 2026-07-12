// Social Media Monitor Screen
// Monitors social media for security and privacy issues

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../providers/social_media_provider.dart';
import '../../services/security/social_media_monitor_service.dart';

class SocialMediaScreen extends StatefulWidget {
  const SocialMediaScreen({super.key});

  @override
  State<SocialMediaScreen> createState() => _SocialMediaScreenState();
}

class _SocialMediaScreenState extends State<SocialMediaScreen> {
  final _usernameController = TextEditingController();
  SocialPlatform _selectedPlatform = SocialPlatform.twitter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SocialMediaProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SocialMediaProvider>(
      builder: (context, provider, _) {
        return GlassTabPage(
          title: 'Social Media Monitor',
          hasSearch: true,
          searchHint: 'Search accounts...',
          headerContent: provider.isLoading
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    // Actions row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Add Account button
                          ElevatedButton.icon(
                            onPressed: _showAddAccountDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: GlassTheme.primaryAccent,
                              foregroundColor: Brand.onLime,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            icon: const DuotoneIcon('add_circle', size: 20),
                            label: const Text('Add Account'),
                          ),
                          IconButton(
                            icon: DuotoneIcon(
                              provider.isScanning ? 'stop' : 'refresh',
                              size: 22,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            onPressed: () {
                              HapticFeedback.mediumImpact();
                              if (!provider.isScanning) {
                                provider.scanAllAccounts();
                              }
                            },
                            tooltip: provider.isScanning ? 'Stop Scan' : 'Refresh',
                          ),
                        ],
                      ),
                    ),
                    // Status card
                    _buildStatusCard(provider),
                    const SizedBox(height: 16),
                    // Stats row
                    _buildStatsRow(provider),
                    const SizedBox(height: 16),
                  ],
                ),
          tabs: [
            GlassTab(
              label: 'Accounts',
              iconPath: 'user_circle',
              content: provider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
                    )
                  : _buildAccountsTab(provider),
            ),
            GlassTab(
              label: 'Alerts',
              iconPath: 'danger_triangle',
              content: provider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
                    )
                  : _buildAlertsTab(provider),
            ),
            GlassTab(
              label: 'Privacy',
              iconPath: 'shield',
              content: provider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
                    )
                  : _buildPrivacyTab(provider),
            ),
            GlassTab(
              label: 'Exposure',
              iconPath: 'magnifer',
              content: provider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
                    )
                  : _buildExposuresTab(provider),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusCard(SocialMediaProvider provider) {
    final hasAlerts = provider.activeAlerts.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassCard(
        margin: EdgeInsets.zero,
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: (hasAlerts ? GlassTheme.errorColor : GlassTheme.successColor)
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
              ),
              child: Center(
                child: DuotoneIcon(
                  hasAlerts ? 'danger_triangle' : 'verified_check',
                  size: 28,
                  color: hasAlerts ? GlassTheme.errorColor : GlassTheme.successColor,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasAlerts
                        ? '${provider.activeAlerts.length} Active Alerts'
                        : 'All Clear', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasAlerts ? GlassTheme.errorColor : GlassTheme.successColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Monitoring ${provider.accounts.length} accounts', maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (provider.isScanning)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: GlassTheme.primaryAccent,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(SocialMediaProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildStatCard(
            'Impersonation',
            provider.alerts.length.toString(),
            'user_block',
            GlassTheme.errorColor,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Privacy Score',
            '${provider.averagePrivacyScore}%',
            'shield_check',
            _getPrivacyColor(provider.averagePrivacyScore),
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Exposures',
            provider.exposures.length.toString(),
            'eye',
            GlassTheme.warningColor,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, String iconName, Color color) {
    return Expanded(
      child: GlassCard(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            DuotoneIcon(iconName, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountsTab(SocialMediaProvider provider) {
    if (provider.accounts.isEmpty) {
      return _buildEmptyState(
        'user_circle',
        'No Accounts',
        'Add social media accounts to monitor',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: provider.accounts.length,
      itemBuilder: (context, index) =>
          _buildAccountCard(provider.accounts[index], provider),
    );
  }

  Widget _buildAccountCard(SocialAccount account, SocialMediaProvider provider) {
    final cs = Theme.of(context).colorScheme;
    // vendor identity — platform brand color from provider
    final platformColor = Color(SocialMediaProvider.getPlatformColor(account.platform));
    final hasPrivacyScore = account.privacyScore != null;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => _showAccountDetails(account, provider),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: platformColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                ),
                child: DuotoneIcon(
                  _getPlatformSvgIcon(account.platform),
                  color: platformColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@${account.username}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          account.platform.displayName,
                          style: TextStyle(
                            color: platformColor,
                            fontSize: 12,
                          ),
                        ),
                        if (account.isVerified) ...[
                          const SizedBox(width: 6),
                          DuotoneIcon(
                            'verified_check',
                            color: platformColor,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (hasPrivacyScore)
                _buildPrivacyBadge(account.privacyScore!.overallScore),
            ],
          ),
          if (hasPrivacyScore && account.privacyScore!.risks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: account.privacyScore!.risks.take(3).map((risk) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Color(SocialMediaProvider.getSeverityColor(risk.severity))
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                  ),
                  child: Text(
                    risk.title,
                    style: TextStyle(
                      color: Color(SocialMediaProvider.getSeverityColor(risk.severity)),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => provider.removeAccount(account.id),
                child: Text(
                  'Remove',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => provider.scanAccount(account.id),
                style: ElevatedButton.styleFrom(
                  backgroundColor: platformColor, // vendor identity
                  foregroundColor: Colors.white, // vendor identity (on platform fill)
                ),
                child: const Text('Scan'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyBadge(int score) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: GlassTheme.tintedGlassDecoration(
        tintColor: _getPrivacyColor(score),
        radius: GlassTheme.radiusXSmall,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(
            'shield_check',
            color: _getPrivacyColor(score),
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            '$score%',
            style: TextStyle(
              color: _getPrivacyColor(score),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsTab(SocialMediaProvider provider) {
    if (provider.alerts.isEmpty) {
      return _buildEmptyState(
        'check_circle',
        'No Alerts',
        'No impersonation attempts detected',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: provider.alerts.length,
      itemBuilder: (context, index) =>
          _buildAlertCard(provider.alerts[index], provider),
    );
  }

  Widget _buildAlertCard(ImpersonationAlert alert, SocialMediaProvider provider) {
    final cs = Theme.of(context).colorScheme;
    // vendor identity — platform brand color from provider
    final platformColor = Color(SocialMediaProvider.getPlatformColor(alert.platform));
    final threatColor = _getThreatColor(alert.threatLevel);

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: threatColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                ),
                child: Center(
                  child: DuotoneIcon(
                    'user_block',
                    color: threatColor,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Impersonation Detected', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: threatColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      alert.platform.displayName, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: platformColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: threatColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                ),
                child: Text(
                  alert.threatLevel,
                  style: TextStyle(
                    color: threatColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Fake Account:',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '@${alert.impersonatorUsername}',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'Your Account:',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '@${alert.targetUsername}',
                      style: const TextStyle(
                        color: GlassTheme.primaryAccent,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    DuotoneIcon('chart', size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'Similarity: ${(alert.similarityScore * 100).toInt()}%',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (alert.indicators.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Indicators',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: alert.indicators.map((indicator) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                  ),
                  child: Text(
                    indicator,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {},
                child: Text(
                  'Dismiss',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => provider.reportImpersonator(alert.id),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.errorColor,
                  foregroundColor: Brand.onDanger,
                ),
                child: const Text('Report'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyTab(SocialMediaProvider provider) {
    if (provider.accounts.isEmpty) {
      return _buildEmptyState(
        'shield_check',
        'No Privacy Data',
        'Add accounts to see privacy analysis',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: provider.accounts.length,
      itemBuilder: (context, index) {
        final account = provider.accounts[index];
        if (account.privacyScore == null) {
          return const SizedBox.shrink();
        }
        return _buildPrivacyCard(account);
      },
    );
  }

  Widget _buildPrivacyCard(SocialAccount account) {
    final cs = Theme.of(context).colorScheme;
    final score = account.privacyScore!;
    // vendor identity — platform brand color from provider
    final platformColor = Color(SocialMediaProvider.getPlatformColor(account.platform));

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: platformColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                ),
                child: DuotoneIcon(
                  _getPlatformSvgIcon(account.platform),
                  color: platformColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@${account.username}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      account.platform.displayName, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: platformColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${score.overallScore}%',
                    style: TextStyle(
                      color: _getPrivacyColor(score.overallScore),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    score.riskLevel,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
            child: LinearProgressIndicator(
              value: score.overallScore / 100,
              backgroundColor: cs.onSurface.withValues(alpha: 0.06),
              color: _getPrivacyColor(score.overallScore),
              minHeight: 8,
            ),
          ),
          if (score.settings.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Privacy Settings',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...score.settings.values.take(5).map((setting) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    DuotoneIcon(
                      setting.isOptimal ? 'check_circle' : 'danger_triangle',
                      color: setting.isOptimal
                          ? GlassTheme.successColor
                          : GlassTheme.warningColor,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        setting.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      setting.currentValue,
                      style: TextStyle(
                        color: setting.isOptimal
                            ? cs.onSurfaceVariant
                            : GlassTheme.warningColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (score.recommendations.isNotEmpty) ...[
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Recommendations',
                style: TextStyle(
                  color: GlassTheme.primaryAccent,
                  fontSize: 13,
                ),
              ),
              children: score.recommendations.map((rec) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DuotoneIcon(
                        'alt_arrow_right',
                        color: GlassTheme.primaryAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          rec,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExposuresTab(SocialMediaProvider provider) {
    if (provider.exposures.isEmpty) {
      return _buildEmptyState(
        'eye_closed',
        'No Exposures Found',
        'Your data appears to be secure',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: provider.exposures.length,
      itemBuilder: (context, index) =>
          _buildExposureCard(provider.exposures[index]),
    );
  }

  Widget _buildExposureCard(DataExposure exposure) {
    final cs = Theme.of(context).colorScheme;
    final severityColor = Color(SocialMediaProvider.getSeverityColor(exposure.severity));

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                ),
                child: Center(
                  child: DuotoneIcon(
                    'eye',
                    color: severityColor,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exposure.type.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: severityColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      exposure.source, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                ),
                child: Text(
                  exposure.severity.name.toUpperCase(),
                  style: TextStyle(
                    color: severityColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            exposure.description,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: GlassTheme.primaryAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
            ),
            child: Row(
              children: [
                const DuotoneIcon(
                  'lightbulb_bolt',
                  color: GlassTheme.primaryAccent,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    exposure.recommendation,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String iconName, String title, String subtitle) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DuotoneIcon(iconName,
              size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showAddAccountDialog() {
    _usernameController.clear();
    _selectedPlatform = SocialPlatform.twitter;
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(GlassTheme.radiusLarge)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Add Social Account',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              // Platform selector
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: SocialPlatform.values.take(6).map((platform) {
                    final isSelected = platform == _selectedPlatform;
                    // vendor identity — platform brand color from provider
                    final color = Color(SocialMediaProvider.getPlatformColor(platform));
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedPlatform = platform),
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? color.withValues(alpha: 0.3)
                                : cs.onSurface.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                            border: Border.all(
                              color: isSelected ? color : Colors.transparent,
                            ),
                          ),
                          child: Center(
                            child: DuotoneIcon(
                              _getPlatformSvgIcon(platform),
                              color: isSelected ? color : cs.onSurfaceVariant,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _usernameController,
                style: TextStyle(color: cs.onSurface),
                decoration: InputDecoration(
                  hintText: 'Username (without @)',
                  hintStyle: TextStyle(color: cs.onSurfaceVariant),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(12),
                    child: DuotoneIcon('hashtag',
                        color: cs.onSurfaceVariant, size: 24),
                  ),
                  filled: true,
                  fillColor: cs.onSurface.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (_usernameController.text.isNotEmpty) {
                      final provider = context.read<SocialMediaProvider>();
                      await provider.addAccount(
                        _selectedPlatform,
                        _usernameController.text,
                      );
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    // vendor identity — platform brand color from provider
                    backgroundColor: Color(
                        SocialMediaProvider.getPlatformColor(_selectedPlatform)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                    ),
                  ),
                  child: const Text(
                    'Add Account',
                    style: TextStyle(
                      color: Colors.white, // vendor identity (on platform fill)
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccountDetails(SocialAccount account, SocialMediaProvider provider) {
    // Navigate to detailed view or show modal
  }

  String _getPlatformSvgIcon(SocialPlatform platform) {
    switch (platform) {
      case SocialPlatform.facebook:
        return 'share';
      case SocialPlatform.instagram:
        return 'camera';
      case SocialPlatform.twitter:
        return 'hashtag';
      case SocialPlatform.linkedin:
        return 'user_id';
      case SocialPlatform.tiktok:
        return 'play_circle';
      case SocialPlatform.snapchat:
        return 'camera_minimalistic';
      case SocialPlatform.youtube:
        return 'play_circle';
      case SocialPlatform.reddit:
        return 'chat_round';
      case SocialPlatform.whatsapp:
        return 'chat_dots';
      case SocialPlatform.telegram:
        return 'forward';
    }
  }

  Color _getPrivacyColor(int score) {
    if (score >= 80) return GlassTheme.successColor;
    if (score >= 60) return AppColors.successDark;
    if (score >= 40) return GlassTheme.warningColor;
    if (score >= 20) return AppColors.severityHigh;
    return AppColors.severityCritical;
  }

  Color _getThreatColor(String level) {
    switch (level.toLowerCase()) {
      case 'critical':
        return AppColors.severityCritical;
      case 'high':
        return AppColors.severityHigh;
      case 'medium':
        return AppColors.severityMedium;
      default:
        return AppColors.severityLow;
    }
  }
}
