// Dark Web Monitoring Screen
// Main screen for dark web monitoring and breach alerts

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../models/api/sms_analysis.dart';
import '../../providers/darkweb_provider.dart';
import '../../widgets/darkweb/darkweb_widgets.dart';

class DarkWebScreen extends StatefulWidget {
  const DarkWebScreen({super.key});

  @override
  State<DarkWebScreen> createState() => _DarkWebScreenState();
}

class _DarkWebScreenState extends State<DarkWebScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<DarkWebProvider>(
      builder: (context, provider, child) {
        final cs = Theme.of(context).colorScheme;
        return GlassTabPage(
          title: 'Dark Web Monitor',
          hasSearch: true,
          searchHint: 'Search breaches...',
          // Issue 2: screen-level action icon lives in the header pill.
          actions: [
            GestureDetector(
              onTap: () => context.read<DarkWebProvider>().refreshAssets(),
              child: DuotoneIcon('refresh', size: 22, color: cs.onSurface),
            ),
          ],
          // Issue 3: the primary "Add" action floats bottom-right, not inline.
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddAssetSheet(context),
            backgroundColor: GlassTheme.primaryAccent,
            foregroundColor: Brand.onLime,
            tooltip: 'Add Asset',
            child: DuotoneIcon('add_circle', size: 26, color: Brand.onLime),
          ),
          tabs: [
            GlassTab(
              label: 'Email',
              iconPath: 'global',
              content: _buildEmailTab(provider),
            ),
            GlassTab(
              label: 'Password',
              iconPath: 'magnifer',
              content: _buildPasswordTab(provider),
            ),
            GlassTab(
              label: 'Alerts',
              iconPath: 'danger_triangle',
              content: _buildAlertsTab(provider),
            ),
            GlassTab(
              label: 'Stats',
              iconPath: 'history',
              content: _buildStatsTab(provider),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmailTab(DarkWebProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Email check section
          Text(
            'Check Email Breaches',
            style: BrandText.title(size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Check if your email has been compromised in known data breaches.',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          EmailCheckInput(
            onCheck: (email) => provider.checkEmail(email),
            isChecking: provider.isCheckingEmail,
          ),
          // Result
          if (provider.lastCheckResult != null) ...[
            const SizedBox(height: 24),
            BreachCheckResultCard(result: provider.lastCheckResult!),
            if (provider.lastCheckResult!.breaches.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Breaches Found',
                style: BrandText.title(),
              ),
              const SizedBox(height: 12),
              ...provider.lastCheckResult!.breaches.map((breach) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: BreachCard(
                      breach: breach,
                      onTap: () => _showBreachDetails(context, breach),
                    ),
                  )),
            ],
          ],
          // Monitored emails section
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Monitored Emails',
                style: BrandText.title(size: 18),
              ),
              TextButton.icon(
                onPressed: () => _showAddAssetSheet(context,
                    preselectedType: AssetType.email),
                icon: const DuotoneIcon('add_circle', size: 18),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.secondaryInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildAssetList(
            provider,
            provider.assets.where((a) => a.type == AssetType.email).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordTab(DarkWebProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Password check section
          Text(
            'Check Password Breaches',
            style: BrandText.title(size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Check if your password has appeared in a known data breach. Your password never leaves your device.',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          PasswordCheckInput(
            onCheck: (password) => provider.checkPassword(password),
            isChecking: provider.isCheckingPassword,
          ),
          // Result
          if (provider.lastPasswordResult != null) ...[
            const SizedBox(height: 24),
            PasswordCheckResultCard(result: provider.lastPasswordResult!),
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
                    DuotoneIcon('shield_check', size: 24, color: AppColors.secondaryInk),
                    const SizedBox(width: 12),
                    Text(
                      'How It Works',
                      style: BrandText.title(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  '1.',
                  'Your password is turned into a one-way code on your device',
                ),
                _buildInfoRow(
                  '2.',
                  'Only the first 5 characters of that code are sent to the server',
                ),
                _buildInfoRow(
                  '3.',
                  'We send back possible matches for your device to check',
                ),
                _buildInfoRow(
                  '4.',
                  'Your full password never leaves your device',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String number, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: TextStyle(
              color: AppColors.secondaryInk,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsTab(DarkWebProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final alerts = provider.alerts;

    if (alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DuotoneIcon(
              'bell',
              size: 64,
              color: cs.onSurface.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 16),
            Text(
              'No breach alerts',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add assets to monitor for breaches',
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${alerts.length} alert${alerts.length > 1 ? 's' : ''}',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              if (provider.unreadAlerts.isNotEmpty)
                TextButton(
                  onPressed: () => provider.markAllAlertsAsRead(),
                  child: const Text('Mark all read'),
                ),
            ],
          ),
        ),
        // Alert list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final alert = alerts[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BreachAlertCard(
                  alert: alert,
                  onTap: () {
                    provider.markAlertAsRead(alert.id);
                    _showBreachDetails(context, alert.breach);
                  },
                  onDismiss: () => provider.markAlertAsRead(alert.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatsTab(DarkWebProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final stats = provider.stats;
    final assets = provider.assets;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DarkWebStatsCard(stats: stats),
          const SizedBox(height: 24),
          // Monitored assets section
          Text(
            'Monitored Assets',
            style: BrandText.title(size: 18),
          ),
          const SizedBox(height: 12),
          if (assets.isEmpty)
            GlassCard(
              child: Center(
                child: Column(
                  children: [
                    DuotoneIcon(
                      'add_circle',
                      size: 48,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No assets being monitored',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add emails and other assets to monitor',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            _buildAssetList(provider, assets),
        ],
      ),
    );
  }

  Widget _buildAssetList(DarkWebProvider provider, List<MonitoredAsset> assets) {
    if (assets.isEmpty) {
      return GlassCard(
        child: Center(
          child: Text(
            'No assets in this category',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Column(
      children: assets.map((asset) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: MonitoredAssetCard(
            asset: asset,
            onTap: () {
              // Show breach details for this asset
              final result = provider.getCheckResult(asset.value);
              if (result != null && result.breaches.isNotEmpty) {
                _showAssetBreaches(context, asset, result.breaches);
              }
            },
            onDelete: () => _confirmDeleteAsset(context, provider, asset),
            onToggle: () => provider.toggleMonitoring(asset.id),
          ),
        );
      }).toList(),
    );
  }

  void _showAddAssetSheet(BuildContext context, {AssetType? preselectedType}) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.read<DarkWebProvider>();
    AssetType selectedType = preselectedType ?? AssetType.email;
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(GlassTheme.radiusLarge)),
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
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Add Asset to Monitor',
                style: BrandText.heading(size: 20),
              ),
              const SizedBox(height: 20),
              // Asset type selector
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: AssetType.values
                      .where((t) => t != AssetType.password)
                      .map((type) {
                    final isSelected = type == selectedType;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(type.displayName),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => selectedType = type);
                          }
                        },
                        backgroundColor: cs.surfaceContainerHighest,
                        selectedColor: AppColors.accentPill,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? AppColors.accentInk
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
              // Input field
              TextField(
                controller: controller,
                style: TextStyle(color: cs.onSurface),
                keyboardType: selectedType == AssetType.email
                    ? TextInputType.emailAddress
                    : selectedType == AssetType.phone
                        ? TextInputType.phone
                        : TextInputType.text,
                decoration: InputDecoration(
                  hintText: _getHintText(selectedType),
                  hintStyle: TextStyle(color: cs.onSurfaceVariant),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(12),
                    child: DuotoneIcon(_getAssetIcon(selectedType), size: 24, color: cs.onSurfaceVariant),
                  ),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
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
                    if (controller.text.isNotEmpty) {
                      final success =
                          await provider.addAsset(selectedType, controller.text);
                      if (success && context.mounted) {
                        Navigator.pop(context);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Brand.lime,
                    foregroundColor: Brand.onLime,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                    ),
                  ),
                  child: const Text(
                    'Add & Monitor',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getHintText(AssetType type) {
    switch (type) {
      case AssetType.email:
        return 'Enter email address';
      case AssetType.phone:
        return 'Enter phone number';
      case AssetType.domain:
        return 'Enter domain (e.g., example.com)';
      case AssetType.username:
        return 'Enter username';
      case AssetType.password:
        return 'Enter password';
    }
  }

  String _getAssetIcon(AssetType type) {
    switch (type) {
      case AssetType.email:
        return 'letter';
      case AssetType.phone:
        return 'smartphone';
      case AssetType.domain:
        return 'global';
      case AssetType.username:
        return 'user';
      case AssetType.password:
        return 'key';
    }
  }

  void _showBreachDetails(BuildContext context, BreachInfo breach) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(GlassTheme.radiusLarge)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                  ),
                ),
              ),
              // Breach header
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(40),
                      borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                    ),
                    child: Center(
                      child: Text(
                        breach.name.isNotEmpty
                            ? breach.name[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: AppColors.errorInk,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          breach.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: BrandText.heading(size: 22),
                        ),
                        Text(
                          breach.domain,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Breach info
              if (breach.breachDate != null)
                _buildDetailRow(
                  'Breach Date',
                  '${breach.breachDate!.year}-${breach.breachDate!.month.toString().padLeft(2, '0')}-${breach.breachDate!.day.toString().padLeft(2, '0')}',
                  'calendar',
                ),
              if (breach.pwnCount != null)
                _buildDetailRow(
                  'Accounts Affected',
                  _formatNumber(breach.pwnCount!),
                  'users_group_two_rounded',
                ),
              if (breach.isVerified)
                _buildDetailRow(
                  'Status',
                  'Verified Breach',
                  'verified_check',
                ),
              if (breach.isSensitive)
                _buildDetailRow(
                  'Sensitivity',
                  'Contains Sensitive Data',
                  'danger_triangle',
                  color: AppColors.secondaryInk,
                ),
              // Description
              if (breach.description != null) ...[
                const SizedBox(height: 24),
                Text(
                  'About This Breach',
                  style: BrandText.title(),
                ),
                const SizedBox(height: 8),
                Text(
                  breach.description!,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
              // Data classes
              if (breach.dataClasses.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Exposed Data Types',
                  style: BrandText.title(),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: breach.dataClasses.map((dc) {
                    return DataClassChip(dataClass: dc);
                  }).toList(),
                ),
              ],
              // Recommendations
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.info.withAlpha(25),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        DuotoneIcon('lightbulb_bolt',
                            color: AppColors.secondaryInk, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Recommended Actions',
                          style: TextStyle(
                            color: AppColors.secondaryInk,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildRecommendation(
                        'Change your password for ${breach.domain}'),
                    if (breach.dataClasses
                        .any((dc) => dc.toLowerCase().contains('password')))
                      _buildRecommendation(
                          'Update passwords on other sites using the same password'),
                    if (breach.dataClasses
                        .any((dc) => dc.toLowerCase().contains('email')))
                      _buildRecommendation(
                          'Be alert for phishing emails targeting this address'),
                    _buildRecommendation(
                        'Enable two-factor authentication if available'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, String icon,
      {Color? color}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          DuotoneIcon(icon, size: 20, color: color ?? cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: color ?? cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendation(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DuotoneIcon('check_circle', size: 16, color: AppColors.secondaryInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int count) {
    if (count >= 1000000000) {
      return '${(count / 1000000000).toStringAsFixed(1)}B';
    } else if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  void _showAssetBreaches(
      BuildContext context, MonitoredAsset asset, List<BreachInfo> breaches) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(GlassTheme.radiusLarge)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle bar
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
                  DuotoneIcon('danger_triangle',
                      color: AppColors.errorInk, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Breaches for ${asset.displayValue}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BrandText.title(),
                        ),
                        Text(
                          '${breaches.length} breaches found',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: breaches.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: BreachCard(
                      breach: breaches[index],
                      onTap: () {
                        Navigator.pop(context);
                        _showBreachDetails(context, breaches[index]);
                      },
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

  void _confirmDeleteAsset(
      BuildContext context, DarkWebProvider provider, MonitoredAsset asset) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surface,
        title: Text(
          'Remove Asset',
          style: TextStyle(color: cs.onSurface),
        ),
        content: Text(
          'Stop monitoring ${asset.displayValue}?',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.removeAsset(asset.id);
              Navigator.pop(context);
            },
            child: Text(
              'Remove',
              style: TextStyle(color: AppColors.errorInk),
            ),
          ),
        ],
      ),
    );
  }
}
