/// Social Media Monitor Screen
/// Monitors social media for security and privacy issues

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../providers/social_media_provider.dart';
import '../../services/security/social_media_monitor_service.dart';

class SocialMediaScreen extends StatefulWidget {
  const SocialMediaScreen({super.key});

  @override
  State<SocialMediaScreen> createState() => _SocialMediaScreenState();
}

class _SocialMediaScreenState extends State<SocialMediaScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _usernameController = TextEditingController();
  SocialPlatform _selectedPlatform = SocialPlatform.twitter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SocialMediaProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Social Media Monitor',
        showBackButton: true,
        actions: [
          Consumer<SocialMediaProvider>(
            builder: (context, provider, _) => GlassAppBarAction(
              icon: provider.isScanning ? Icons.stop : Icons.refresh,
              onTap: () {
                HapticFeedback.mediumImpact();
                if (!provider.isScanning) {
                  provider.scanAllAccounts();
                }
              },
            ),
          ),
        ],
      ),
      body: Consumer<SocialMediaProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
            );
          }

          return Column(
            children: [
              // Status card
              _buildStatusCard(provider),
              const SizedBox(height: 16),
              // Stats row
              _buildStatsRow(provider),
              const SizedBox(height: 16),
              // Tab bar
              _buildTabBar(),
              const SizedBox(height: 16),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAccountsTab(provider),
                    _buildAlertsTab(provider),
                    _buildPrivacyTab(provider),
                    _buildExposuresTab(provider),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddAccountDialog,
        backgroundColor: GlassTheme.primaryAccent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Add Account'),
      ),
    );
  }

  Widget _buildStatusCard(SocialMediaProvider provider) {
    final hasAlerts = provider.activeAlerts.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassCard(
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: (hasAlerts ? GlassTheme.errorColor : GlassTheme.successColor)
                    .withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                hasAlerts ? Icons.warning_rounded : Icons.verified_user,
                color: hasAlerts ? GlassTheme.errorColor : GlassTheme.successColor,
                size: 28,
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
                        : 'All Clear',
                    style: TextStyle(
                      color: hasAlerts ? GlassTheme.errorColor : GlassTheme.successColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Monitoring ${provider.accounts.length} accounts',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
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
            Icons.person_off,
            GlassTheme.errorColor,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Privacy Score',
            '${provider.averagePrivacyScore}%',
            Icons.privacy_tip,
            _getPrivacyColor(provider.averagePrivacyScore),
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Exposures',
            provider.exposures.length.toString(),
            Icons.visibility,
            GlassTheme.warningColor,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: GlassCard(
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
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
                color: Colors.white.withOpacity(0.6),
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: GlassTheme.glassDecoration(),
            child: TabBar(
              controller: _tabController,
              indicatorColor: GlassTheme.primaryAccent,
              labelColor: GlassTheme.primaryAccent,
              unselectedLabelColor: Colors.white54,
              isScrollable: true,
              tabs: const [
                Tab(icon: Icon(Icons.account_circle), text: 'Accounts'),
                Tab(icon: Icon(Icons.warning), text: 'Alerts'),
                Tab(icon: Icon(Icons.privacy_tip), text: 'Privacy'),
                Tab(icon: Icon(Icons.visibility), text: 'Exposure'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountsTab(SocialMediaProvider provider) {
    if (provider.accounts.isEmpty) {
      return _buildEmptyState(
        Icons.account_circle_outlined,
        'No Accounts',
        'Add social media accounts to monitor',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: provider.accounts.length,
      itemBuilder: (context, index) =>
          _buildAccountCard(provider.accounts[index], provider),
    );
  }

  Widget _buildAccountCard(SocialAccount account, SocialMediaProvider provider) {
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
                  color: platformColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getPlatformIcon(account.platform),
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
                      '@${account.username}',
                      style: const TextStyle(
                        color: Colors.white,
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
                          Icon(
                            Icons.verified,
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
                        .withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
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
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => provider.scanAccount(account.id),
                style: ElevatedButton.styleFrom(
                  backgroundColor: platformColor,
                  foregroundColor: Colors.white,
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
      decoration: BoxDecoration(
        color: _getPrivacyColor(score).withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _getPrivacyColor(score).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shield,
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
        Icons.check_circle,
        'No Alerts',
        'No impersonation attempts detected',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: provider.alerts.length,
      itemBuilder: (context, index) =>
          _buildAlertCard(provider.alerts[index], provider),
    );
  }

  Widget _buildAlertCard(ImpersonationAlert alert, SocialMediaProvider provider) {
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
                  color: threatColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.person_off,
                  color: threatColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Impersonation Detected',
                      style: TextStyle(
                        color: threatColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      alert.platform.displayName,
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
                  color: threatColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
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
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Fake Account:',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '@${alert.impersonatorUsername}',
                      style: const TextStyle(
                        color: Colors.white,
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
                        color: Colors.white.withOpacity(0.5),
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
                    Icon(Icons.insights, size: 14, color: Colors.white.withOpacity(0.5)),
                    const SizedBox(width: 4),
                    Text(
                      'Similarity: ${(alert.similarityScore * 100).toInt()}%',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
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
                color: Colors.white.withOpacity(0.6),
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
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    indicator,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
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
                child: const Text(
                  'Dismiss',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => provider.reportImpersonator(alert.id),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.errorColor,
                ),
                child: const Text(
                  'Report',
                  style: TextStyle(color: Colors.white),
                ),
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
        Icons.privacy_tip_outlined,
        'No Privacy Data',
        'Add accounts to see privacy analysis',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
    final score = account.privacyScore!;
    final platformColor = Color(SocialMediaProvider.getPlatformColor(account.platform));

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: platformColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getPlatformIcon(account.platform),
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
                      '@${account.username}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      account.platform.displayName,
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
                      color: Colors.white.withOpacity(0.5),
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
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score.overallScore / 100,
              backgroundColor: Colors.white.withOpacity(0.1),
              color: _getPrivacyColor(score.overallScore),
              minHeight: 8,
            ),
          ),
          if (score.settings.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Privacy Settings',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
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
                    Icon(
                      setting.isOptimal ? Icons.check_circle : Icons.warning,
                      color: setting.isOptimal
                          ? GlassTheme.successColor
                          : GlassTheme.warningColor,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        setting.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      setting.currentValue,
                      style: TextStyle(
                        color: setting.isOptimal
                            ? Colors.white.withOpacity(0.5)
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
                      const Icon(
                        Icons.arrow_right,
                        color: GlassTheme.primaryAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          rec,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
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
        Icons.visibility_off,
        'No Exposures Found',
        'Your data appears to be secure',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: provider.exposures.length,
      itemBuilder: (context, index) =>
          _buildExposureCard(provider.exposures[index]),
    );
  }

  Widget _buildExposureCard(DataExposure exposure) {
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
                  color: severityColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.visibility,
                  color: severityColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exposure.type.displayName,
                      style: TextStyle(
                        color: severityColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      exposure.source,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: severityColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
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
              color: Colors.white.withOpacity(0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: GlassTheme.primaryAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lightbulb,
                  color: GlassTheme.primaryAccent,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    exposure.recommendation,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
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

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withOpacity(0.4)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showAddAccountDialog() {
    _usernameController.clear();
    _selectedPlatform = SocialPlatform.twitter;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Add Social Account',
                style: TextStyle(
                  color: Colors.white,
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
                                ? color.withOpacity(0.3)
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? color : Colors.transparent,
                            ),
                          ),
                          child: Icon(
                            _getPlatformIcon(platform),
                            color: isSelected ? color : Colors.white54,
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
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Username (without @)',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  prefixIcon: const Icon(Icons.alternate_email, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
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
                      if (mounted) Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(
                        SocialMediaProvider.getPlatformColor(_selectedPlatform)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Add Account',
                    style: TextStyle(
                      color: Colors.white,
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

  IconData _getPlatformIcon(SocialPlatform platform) {
    switch (platform) {
      case SocialPlatform.facebook:
        return Icons.facebook;
      case SocialPlatform.instagram:
        return Icons.camera_alt;
      case SocialPlatform.twitter:
        return Icons.tag;
      case SocialPlatform.linkedin:
        return Icons.work;
      case SocialPlatform.tiktok:
        return Icons.music_note;
      case SocialPlatform.snapchat:
        return Icons.camera;
      case SocialPlatform.youtube:
        return Icons.play_circle;
      case SocialPlatform.reddit:
        return Icons.forum;
      case SocialPlatform.whatsapp:
        return Icons.chat;
      case SocialPlatform.telegram:
        return Icons.send;
    }
  }

  Color _getPrivacyColor(int score) {
    if (score >= 80) return GlassTheme.successColor;
    if (score >= 60) return const Color(0xFF8BC34A);
    if (score >= 40) return GlassTheme.warningColor;
    if (score >= 20) return const Color(0xFFFF5722);
    return GlassTheme.errorColor;
  }

  Color _getThreatColor(String level) {
    switch (level.toLowerCase()) {
      case 'critical':
        return GlassTheme.errorColor;
      case 'high':
        return const Color(0xFFFF5722);
      case 'medium':
        return GlassTheme.warningColor;
      default:
        return const Color(0xFFFFEB3B);
    }
  }
}
