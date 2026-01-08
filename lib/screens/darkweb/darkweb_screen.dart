/// Dark Web Monitoring Screen
/// Main screen for dark web monitoring and breach alerts

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../models/api/sms_analysis.dart';
import '../../providers/darkweb_provider.dart';
import '../../widgets/darkweb/darkweb_widgets.dart';

class DarkWebScreen extends StatefulWidget {
  const DarkWebScreen({super.key});

  @override
  State<DarkWebScreen> createState() => _DarkWebScreenState();
}

class _DarkWebScreenState extends State<DarkWebScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Dark Web Monitor',
        showBackButton: true,
        actions: [
          GlassAppBarAction(
            svgIcon: 'refresh',
            onTap: () {
              context.read<DarkWebProvider>().refreshAssets();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddAssetSheet(context),
        backgroundColor: GlassTheme.primaryAccent,
        foregroundColor: Colors.black,
        icon: const DuotoneIcon('add_circle', size: 20),
        label: const Text('Add Asset'),
      ),
      body: Column(
        children: [
          // Tab bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
              child: Container(
                decoration: GlassTheme.glassDecoration(),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: GlassTheme.primaryAccent,
                  labelColor: GlassTheme.primaryAccent,
                  unselectedLabelColor: Colors.white54,
                  isScrollable: true,
                  tabs: const [
                    Tab(icon: DuotoneIcon('letter', size: 20), text: 'Email'),
                    Tab(icon: DuotoneIcon('key', size: 20), text: 'Password'),
                    Tab(icon: DuotoneIcon('bell', size: 20), text: 'Alerts'),
                    Tab(icon: DuotoneIcon('chart', size: 20), text: 'Stats'),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Consumer<DarkWebProvider>(
              builder: (context, provider, child) {
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildEmailTab(provider),
                    _buildPasswordTab(provider),
                    _buildAlertsTab(provider),
                    _buildStatsTab(provider),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailTab(DarkWebProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Email check section
          const Text(
            'Check Email Breaches',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check if your email has been compromised in known data breaches.',
            style: TextStyle(
              color: Colors.grey[500],
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
              const Text(
                'Breaches Found',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
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
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Monitored Emails',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: () => _showAddAssetSheet(context,
                    preselectedType: AssetType.email),
                icon: const DuotoneIcon('add_circle', size: 18),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF00D9FF),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Password check section
          const Text(
            'Check Password Breaches',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check if your password has been exposed in data breaches using k-anonymity (your password never leaves your device).',
            style: TextStyle(
              color: Colors.grey[500],
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
          const SizedBox(height: 32),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const DuotoneIcon('shield_check', size: 24, color: Color(0xFF00D9FF)),
                    const SizedBox(width: 12),
                    const Text(
                      'How It Works',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  '1.',
                  'Your password is hashed locally (SHA-1)',
                ),
                _buildInfoRow(
                  '2.',
                  'Only the first 5 characters are sent to the server',
                ),
                _buildInfoRow(
                  '3.',
                  'We return matching hashes to check locally',
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
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: const TextStyle(
              color: Color(0xFF00D9FF),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsTab(DarkWebProvider provider) {
    final alerts = provider.alerts;

    if (alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DuotoneIcon(
              'bell',
              size: 64,
              color: Colors.white.withAlpha(31),
            ),
            const SizedBox(height: 16),
            Text(
              'No breach alerts',
              style: TextStyle(
                color: Colors.white.withAlpha(128),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add assets to monitor for breaches',
              style: TextStyle(
                color: Colors.white.withAlpha(77),
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
                style: const TextStyle(
                  color: Colors.white70,
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
    final stats = provider.stats;
    final assets = provider.assets;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DarkWebStatsCard(stats: stats),
          const SizedBox(height: 24),
          // Monitored assets section
          const Text(
            'Monitored Assets',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
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
                      color: Colors.grey.withAlpha(77),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No assets being monitored',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add emails and other assets to monitor',
                      style: TextStyle(
                        color: Colors.grey[600],
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
              color: Colors.grey[500],
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
    final provider = context.read<DarkWebProvider>();
    AssetType selectedType = preselectedType ?? AssetType.email;
    final controller = TextEditingController();

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
              // Handle bar
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
                'Add Asset to Monitor',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
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
                        backgroundColor: const Color(0xFF2A2B40),
                        selectedColor: const Color(0xFF00D9FF).withAlpha(40),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? const Color(0xFF00D9FF)
                              : Colors.grey,
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
                style: const TextStyle(color: Colors.white),
                keyboardType: selectedType == AssetType.email
                    ? TextInputType.emailAddress
                    : selectedType == AssetType.phone
                        ? TextInputType.phone
                        : TextInputType.text,
                decoration: InputDecoration(
                  hintText: _getHintText(selectedType),
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(12),
                    child: DuotoneIcon(_getAssetIcon(selectedType), size: 24, color: Colors.grey),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF2A2B40),
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
                    if (controller.text.isNotEmpty) {
                      final success =
                          await provider.addAsset(selectedType, controller.text);
                      if (success && context.mounted) {
                        Navigator.pop(context);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D9FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
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
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
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
                      color: Colors.red.withAlpha(40),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        breach.name.isNotEmpty
                            ? breach.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.red,
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          breach.domain,
                          style: TextStyle(
                            color: Colors.grey[400],
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
                  color: Colors.orange,
                ),
              // Description
              if (breach.description != null) ...[
                const SizedBox(height: 24),
                const Text(
                  'About This Breach',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  breach.description!,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
              // Data classes
              if (breach.dataClasses.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  'Exposed Data Types',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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
                  color: Colors.blue.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        DuotoneIcon('lightbulb_bolt', color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Recommended Actions',
                          style: TextStyle(
                            color: Colors.blue,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          DuotoneIcon(icon, size: 20, color: color ?? Colors.grey[500]),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: color ?? Colors.white,
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
          const DuotoneIcon('check_circle', size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey[300],
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const DuotoneIcon('danger_triangle', color: Colors.red, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Breaches for ${asset.displayValue}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${breaches.length} breaches found',
                          style: TextStyle(
                            color: Colors.grey[500],
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text(
          'Remove Asset',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Stop monitoring ${asset.displayValue}?',
          style: const TextStyle(color: Colors.white70),
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
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
