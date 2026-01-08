/// Executive Protection Screen
/// BEC and CEO fraud detection and prevention

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/executive_protection_provider.dart';
import '../../services/security/executive_protection_service.dart';

class ExecutiveProtectionScreen extends StatefulWidget {
  const ExecutiveProtectionScreen({super.key});

  @override
  State<ExecutiveProtectionScreen> createState() =>
      _ExecutiveProtectionScreenState();
}

class _ExecutiveProtectionScreenState extends State<ExecutiveProtectionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExecutiveProtectionProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ExecutiveProtectionProvider>(
      builder: (context, provider, _) {
        return GlassPage(
          title: 'Executive Protection',
          body: Column(
            children: [
              // Actions row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const DuotoneIcon('user_plus', size: 22, color: Colors.white),
                      onPressed: () => _showAddExecutiveSheet(context, provider),
                      tooltip: 'Add VIP',
                    ),
                    IconButton(
                      icon: const DuotoneIcon('letter', size: 22, color: Colors.white),
                      onPressed: () => _showAnalyzeMessageSheet(context, provider),
                      tooltip: 'Analyze Message',
                    ),
                  ],
                ),
              ),
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
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white54,
                      tabs: const [
                        Tab(text: 'Dashboard'),
                        Tab(text: 'Alerts'),
                        Tab(text: 'VIPs'),
                      ],
                    ),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: provider.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: GlassTheme.primaryAccent,
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildDashboardTab(provider),
                          _buildAlertsTab(provider),
                          _buildVIPsTab(provider),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDashboardTab(ExecutiveProtectionProvider provider) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Protection Status Card
        _buildStatusCard(provider),
        const SizedBox(height: 16),

        // Quick Stats
        _buildQuickStats(provider),
        const SizedBox(height: 16),

        // Attack Types Overview
        _buildAttackTypesCard(),
        const SizedBox(height: 16),

        // Recent Alerts Preview
        if (provider.alerts.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Recent Threats',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...provider.alerts.take(3).map((alert) => _buildAlertCard(alert, provider)),
        ],
      ],
    );
  }

  Widget _buildStatusCard(ExecutiveProtectionProvider provider) {
    final hasAlerts = provider.criticalAlerts.isNotEmpty;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasAlerts
                    ? GlassTheme.errorColor.withOpacity(0.2)
                    : GlassTheme.successColor.withOpacity(0.2),
              ),
              child: DuotoneIcon(
                hasAlerts ? 'danger_triangle' : 'verified_check',
                size: 40,
                color: hasAlerts
                    ? GlassTheme.errorColor
                    : GlassTheme.successColor,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasAlerts ? 'Threats Detected' : 'Protected',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasAlerts
                        ? '${provider.criticalAlerts.length} critical alert(s) require attention'
                        : 'No impersonation attempts detected',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildStatusBadge(
                        '${provider.executives.length} VIPs',
                        GlassTheme.primaryAccent,
                      ),
                      const SizedBox(width: 8),
                      _buildStatusBadge(
                        '${provider.stats['corporate_domains'] ?? 0} Domains',
                        Colors.white54,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildQuickStats(ExecutiveProtectionProvider provider) {
    return Row(
      children: [
        _buildStatCard(
          'Total Alerts',
          provider.totalAlertsCount.toString(),
          'bell',
          GlassTheme.primaryAccent,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          'High Risk',
          provider.highRiskAlerts.length.toString(),
          'danger_circle',
          GlassTheme.errorColor,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          'VIPs Protected',
          provider.highValueExecutives.length.toString(),
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
              DuotoneIcon(icon, color: color, size: 24),
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
                  color: Colors.white.withOpacity(0.6),
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

  Widget _buildAttackTypesCard() {
    final attackTypes = [
      {'type': ImpersonationType.ceoFraud, 'icon': 'user_circle'},
      {'type': ImpersonationType.vendorFraud, 'icon': 'shop'},
      {'type': ImpersonationType.giftCardScam, 'icon': 'card'},
      {'type': ImpersonationType.w2Scam, 'icon': 'file'},
    ];

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BEC Attack Types We Detect',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: attackTypes.map((at) {
                final type = at['type'] as ImpersonationType;
                final icon = at['icon'] as String;
                return _buildAttackTypeChip(type, icon);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttackTypeChip(ImpersonationType type, String icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: GlassTheme.primaryAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: GlassTheme.primaryAccent.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(icon, size: 16, color: GlassTheme.primaryAccent),
          const SizedBox(width: 6),
          Text(
            type.displayName,
            style: const TextStyle(
              color: GlassTheme.primaryAccent,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsTab(ExecutiveProtectionProvider provider) {
    if (provider.alerts.isEmpty) {
      return _buildEmptyState(
        icon: 'check_circle',
        title: 'No Alerts',
        subtitle: 'No impersonation attempts detected',
        color: GlassTheme.successColor,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.alerts.length,
      itemBuilder: (context, index) {
        return _buildAlertCard(provider.alerts[index], provider);
      },
    );
  }

  Widget _buildAlertCard(
    ImpersonationResult alert,
    ExecutiveProtectionProvider provider,
  ) {
    final riskColor =
        Color(ExecutiveProtectionProvider.getRiskLevelColor(alert.riskLevel));

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
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: riskColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: DuotoneIcon(
                      _getTypeIcon(alert.type),
                      color: riskColor,
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
                        alert.type?.displayName ?? 'Impersonation Detected',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (alert.impersonatedExecutive != null)
                        Text(
                          'Impersonating: ${alert.impersonatedExecutive!.name}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: riskColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        alert.riskLevel.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(alert.confidenceScore * 100).toInt()}% confidence',
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

            // Indicators
            if (alert.indicators.isNotEmpty) ...[
              const Text(
                'Threat Indicators',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...alert.indicators.take(3).map((indicator) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DuotoneIcon(
                          'danger_triangle',
                          size: 14,
                          color: riskColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                indicator.description,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              if (indicator.evidence != null)
                                Text(
                                  indicator.evidence!,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 12),

            // Recommendation
            GlassContainer(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DuotoneIcon(
                    'lightbulb',
                    size: 18,
                    color: GlassTheme.primaryAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alert.recommendation,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
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

  Widget _buildVIPsTab(ExecutiveProtectionProvider provider) {
    if (provider.executives.isEmpty) {
      return _buildEmptyState(
        icon: 'user_plus',
        title: 'No VIPs Configured',
        subtitle: 'Add executive profiles to monitor for impersonation',
        action: TextButton.icon(
          onPressed: () => _showAddExecutiveSheet(context, provider),
          icon: const DuotoneIcon('add_circle', size: 18),
          label: const Text('Add VIP'),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.executives.length,
      itemBuilder: (context, index) {
        return _buildExecutiveCard(provider.executives[index], provider);
      },
    );
  }

  Widget _buildExecutiveCard(
    ExecutiveProfile exec,
    ExecutiveProtectionProvider provider,
  ) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: exec.isHighValue
                ? GlassTheme.warningColor.withOpacity(0.2)
                : GlassTheme.primaryAccent.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              exec.name.isNotEmpty ? exec.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: exec.isHighValue
                    ? GlassTheme.warningColor
                    : GlassTheme.primaryAccent,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Text(
              exec.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (exec.isHighValue) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: GlassTheme.warningColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'HIGH VALUE',
                  style: TextStyle(
                    color: GlassTheme.warningColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exec.email,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
            if (exec.title != null)
              Text(
                exec.title!,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11,
                ),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const DuotoneIcon('trash_bin_minimalistic', color: Colors.white38, size: 24),
          onPressed: () => _confirmRemoveExecutive(context, exec, provider),
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
            DuotoneIcon(icon, size: 64, color: color.withOpacity(0.5)),
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
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
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

  String _getTypeIcon(ImpersonationType? type) {
    if (type == null) return 'danger_triangle';
    switch (type) {
      case ImpersonationType.ceoFraud:
        return 'user_circle';
      case ImpersonationType.vendorFraud:
        return 'shop';
      case ImpersonationType.attorneyFraud:
        return 'scale';
      case ImpersonationType.dataTheft:
        return 'folder';
      case ImpersonationType.w2Scam:
        return 'file';
      case ImpersonationType.giftCardScam:
        return 'card';
      case ImpersonationType.unknown:
        return 'question_circle';
    }
  }

  void _showAddExecutiveSheet(
    BuildContext context,
    ExecutiveProtectionProvider provider,
  ) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final titleController = TextEditingController();
    bool isHighValue = false;

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
                  'Add VIP Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add an executive to monitor for impersonation attacks',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: TextStyle(color: Colors.white54),
                    prefixIcon: const DuotoneIcon('user', color: Colors.white38, size: 24),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: GlassTheme.primaryAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: TextStyle(color: Colors.white54),
                    prefixIcon: const DuotoneIcon('letter', color: Colors.white38, size: 24),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: GlassTheme.primaryAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Title (Optional)',
                    labelStyle: TextStyle(color: Colors.white54),
                    prefixIcon: const DuotoneIcon('case', color: Colors.white38, size: 24),
                    hintText: 'e.g., CEO, CFO, VP of Finance',
                    hintStyle: TextStyle(color: Colors.white24),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: GlassTheme.primaryAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GlassContainer(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const DuotoneIcon(
                        'star',
                        color: GlassTheme.warningColor,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'High-Value Target',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'C-level executives, finance team',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isHighValue,
                        onChanged: (value) => setState(() => isHighValue = value),
                        activeColor: GlassTheme.warningColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: nameController.text.isNotEmpty &&
                            emailController.text.isNotEmpty
                        ? () {
                            final exec = ExecutiveProfile(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              name: nameController.text,
                              email: emailController.text,
                              title: titleController.text.isNotEmpty
                                  ? titleController.text
                                  : null,
                              isHighValue: isHighValue,
                            );
                            provider.addExecutive(exec);
                            Navigator.pop(context);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GlassTheme.primaryAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white12,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Add VIP'),
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

  void _showAnalyzeMessageSheet(
    BuildContext context,
    ExecutiveProtectionProvider provider,
  ) {
    final senderNameController = TextEditingController();
    final senderEmailController = TextEditingController();
    final subjectController = TextEditingController();
    final bodyController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
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
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Analyze Message',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const DuotoneIcon('close_circle', color: Colors.white54, size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Paste a suspicious email to check for impersonation',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: senderNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Sender Name',
                        labelStyle: TextStyle(color: Colors.white54),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: GlassTheme.primaryAccent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: senderEmailController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Sender Email',
                        labelStyle: TextStyle(color: Colors.white54),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: GlassTheme.primaryAccent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: subjectController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Subject',
                        labelStyle: TextStyle(color: Colors.white54),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: GlassTheme.primaryAccent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bodyController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Message Body',
                        labelStyle: TextStyle(color: Colors.white54),
                        alignLabelWithHint: true,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: GlassTheme.primaryAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  if (senderNameController.text.isNotEmpty &&
                      senderEmailController.text.isNotEmpty) {
                    final result = await provider.analyzeMessage(
                      senderName: senderNameController.text,
                      senderEmail: senderEmailController.text,
                      subject: subjectController.text,
                      body: bodyController.text,
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                      _showAnalysisResult(context, result);
                    }
                  }
                },
                icon: provider.isAnalyzing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const DuotoneIcon('magnifer', size: 18),
                label: Text(provider.isAnalyzing ? 'Analyzing...' : 'Analyze'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.primaryAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAnalysisResult(BuildContext context, ImpersonationResult result) {
    final riskColor =
        Color(ExecutiveProtectionProvider.getRiskLevelColor(result.riskLevel));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: Row(
          children: [
            DuotoneIcon(
              result.isImpersonation ? 'danger_triangle' : 'check_circle',
              color: result.isImpersonation ? riskColor : GlassTheme.successColor,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                result.isImpersonation
                    ? 'Impersonation Detected!'
                    : 'Message Appears Safe',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result.isImpersonation) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: riskColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${result.riskLevel.toUpperCase()} RISK - ${(result.confidenceScore * 100).toInt()}% confidence',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              result.recommendation,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 14,
              ),
            ),
          ],
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

  void _confirmRemoveExecutive(
    BuildContext context,
    ExecutiveProfile exec,
    ExecutiveProtectionProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text(
          'Remove VIP?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Stop monitoring ${exec.name} for impersonation attempts?',
          style: TextStyle(color: Colors.white.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.removeExecutive(exec.id);
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
