// Executive Protection Screen
// BEC and CEO fraud detection and prevention

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/app_sheet.dart';
import '../../presentation/widgets/sheet_panel.dart';
import '../../providers/executive_protection_provider.dart';
import '../../services/security/executive_protection_service.dart';

class ExecutiveProtectionScreen extends StatefulWidget {
  const ExecutiveProtectionScreen({super.key});

  @override
  State<ExecutiveProtectionScreen> createState() =>
      _ExecutiveProtectionScreenState();
}

class _ExecutiveProtectionScreenState extends State<ExecutiveProtectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExecutiveProtectionProvider>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ExecutiveProtectionProvider>(
      builder: (context, provider, _) {
        return GlassTabPage(
          title: 'Executive Protection',
          actions: [
            GestureDetector(
              onTap: () => _showAnalyzeMessageSheet(context, provider),
              child: DuotoneIcon('letter',
                  size: 22, color: context.colors.onSurface),
            ),
          ],
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddExecutiveSheet(context, provider),
            backgroundColor: GlassTheme.primaryAccent,
            foregroundColor: Brand.onLime,
            tooltip: 'Add VIP',
            child: DuotoneIcon('user_plus', size: 26, color: Brand.onLime),
          ),
          tabs: [
            GlassTab(
              label: 'Dashboard',
              iconPath: 'chart',
              content: provider.isLoading
                  ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
                  : _buildDashboardTab(provider),
            ),
            GlassTab(
              label: 'Alerts',
              iconPath: 'shield',
              content: provider.isLoading
                  ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
                  : _buildAlertsTab(provider),
            ),
            GlassTab(
              label: 'VIPs',
              iconPath: 'lock',
              content: provider.isLoading
                  ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
                  : _buildVIPsTab(provider),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDashboardTab(ExecutiveProtectionProvider provider) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Protection Status Card
        _buildStatusCard(provider),
        const SizedBox(height: 24),

        // Quick Stats
        _buildQuickStats(provider),
        const SizedBox(height: 24),

        // Attack Types Overview
        _buildAttackTypesCard(),
        const SizedBox(height: 24),

        // Recent Alerts Preview
        if (provider.alerts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Recent Threats',
              style: TextStyle(
                color: context.colors.onSurfaceVariant,
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
      margin: EdgeInsets.zero,
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
                    ? GlassTheme.errorColor.withValues(alpha: 0.2)
                    : GlassTheme.successColor.withValues(alpha: 0.2),
              ),
              child: DuotoneIcon(
                hasAlerts ? 'danger_triangle' : 'verified_check',
                size: 40,
                color: hasAlerts
                    ? GlassTheme.errorColor
                    : AppColors.accentInk,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasAlerts ? 'Threats Detected' : 'Protected',
                    style: TextStyle(
                      color: context.colors.onSurface,
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
                      color: context.colors.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildStatusBadge(
                        '${provider.executives.length} VIPs',
                        GlassTheme.primaryAccent,
                        ink: AppColors.accentInk,
                      ),
                      const SizedBox(width: 8),
                      _buildStatusBadge(
                        '${provider.stats['corporate_domains'] ?? 0} Domains',
                        context.colors.onSurfaceVariant,
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

  Widget _buildStatusBadge(String text, Color color, {Color? ink}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: ink ?? color,
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
          AppColors.accentInk,
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
          AppColors.accentInk,
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, String icon, Color color) {
    return Expanded(
      child: GlassCard(
        margin: EdgeInsets.zero,
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
                  color: context.colors.onSurfaceVariant,
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
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BEC Attack Types We Detect',
              style: TextStyle(
                color: context.colors.onSurface,
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
      decoration: GlassTheme.tintedGlassDecoration(
        tintColor: GlassTheme.primaryAccent,
        radius: GlassTheme.radiusLarge,
        opacity: 0.1,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(icon, size: 16, color: AppColors.accentInk),
          const SizedBox(width: 6),
          Text(
            type.displayName,
            style: TextStyle(
              color: AppColors.accentInk,
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
        color: AppColors.accentInk,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                    color: riskColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (alert.impersonatedExecutive != null)
                        Text(
                          'Impersonating: ${alert.impersonatedExecutive!.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.onSurfaceVariant,
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
                      decoration: GlassTheme.badgeGlassDecoration(
                        isDark: context.isDark,
                        tintColor: riskColor,
                      ),
                      child: Text(
                        alert.riskLevel.toUpperCase(),
                        style: TextStyle(
                          color: riskColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(alert.confidenceScore * 100).toInt()}% confidence',
                      style: TextStyle(
                        color: context.colors.onSurfaceVariant,
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
              Text(
                'Threat Indicators',
                style: TextStyle(
                  color: context.colors.onSurfaceVariant,
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
                                style: TextStyle(
                                  color: context.colors.onSurface,
                                  fontSize: 12,
                                ),
                              ),
                              if (indicator.evidence != null)
                                Text(
                                  indicator.evidence!,
                                  style: TextStyle(
                                    color: context.colors.onSurfaceVariant,
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
                    color: AppColors.accentInk,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alert.recommendation,
                      style: TextStyle(
                        color: context.colors.onSurface,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                ? GlassTheme.warningColor.withValues(alpha: 0.2)
                : GlassTheme.primaryAccent.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
          ),
          child: Center(
            child: Text(
              exec.name.isNotEmpty ? exec.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: exec.isHighValue
                    ? GlassTheme.warningColor
                    : AppColors.accentInk,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                exec.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (exec.isHighValue) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: GlassTheme.warningColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            if (exec.title != null)
              Text(
                exec.title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        trailing: IconButton(
          icon: DuotoneIcon('trash_bin_minimalistic',
              color: context.colors.onSurfaceVariant.withValues(alpha: 0.7),
              size: 24),
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
            DuotoneIcon(icon, size: 64, color: color.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: context.colors.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: context.colors.onSurfaceVariant),
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
    final cs = context.colors;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Container(
          decoration: BoxDecoration(
            gradient: GlassTheme.backgroundGradient(isDark: context.isDark),
            borderRadius:
                const BorderRadius.vertical(
                top: Radius.circular(GlassTheme.radiusLarge)),
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
                Text(
                  'Add VIP Profile',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add an executive to monitor for impersonation attacks',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  style: TextStyle(color: cs.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: TextStyle(color: cs.onSurfaceVariant),
                    prefixIcon: DuotoneIcon('user',
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        size: 24),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: cs.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppColors.accentInk,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  style: TextStyle(color: cs.onSurface),
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: TextStyle(color: cs.onSurfaceVariant),
                    prefixIcon: DuotoneIcon('letter',
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        size: 24),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: cs.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppColors.accentInk,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  style: TextStyle(color: cs.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Title (Optional)',
                    labelStyle: TextStyle(color: cs.onSurfaceVariant),
                    prefixIcon: DuotoneIcon('case',
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        size: 24),
                    hintText: 'e.g., CEO, CFO, VP of Finance',
                    hintStyle: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: cs.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppColors.accentInk,
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
                            Text(
                              'High-Value Target',
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'C-level executives, finance team',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isHighValue,
                        onChanged: (value) => setState(() => isHighValue = value),
                        activeThumbColor: GlassTheme.warningColor,
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
                      foregroundColor: Brand.onLime,
                      disabledBackgroundColor:
                          cs.onSurface.withValues(alpha: 0.06),
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
    final cs = context.colors;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          gradient: GlassTheme.backgroundGradient(isDark: context.isDark),
          borderRadius: const BorderRadius.vertical(
                top: Radius.circular(GlassTheme.radiusLarge)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Analyze Message',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: DuotoneIcon('close_circle',
                      color: cs.onSurfaceVariant, size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Paste a suspicious email to check for impersonation',
              style: TextStyle(
                color: cs.onSurfaceVariant,
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
                      style: TextStyle(color: cs.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Sender Name',
                        labelStyle: TextStyle(color: cs.onSurfaceVariant),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: cs.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: AppColors.accentInk,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: senderEmailController,
                      style: TextStyle(color: cs.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Sender Email',
                        labelStyle: TextStyle(color: cs.onSurfaceVariant),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: cs.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: AppColors.accentInk,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: subjectController,
                      style: TextStyle(color: cs.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Subject',
                        labelStyle: TextStyle(color: cs.onSurfaceVariant),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: cs.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: AppColors.accentInk,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bodyController,
                      style: TextStyle(color: cs.onSurface),
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: 'Message Body',
                        labelStyle: TextStyle(color: cs.onSurfaceVariant),
                        alignLabelWithHint: true,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: cs.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: AppColors.accentInk,
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
                          color: Brand.onLime,
                        ),
                      )
                    : const DuotoneIcon('magnifer', size: 18),
                label: Text(provider.isAnalyzing ? 'Analyzing...' : 'Analyze'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.primaryAccent,
                  foregroundColor: Brand.onLime,
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
    final cs = context.colors;

    showAppSheet(
      context,
      child: SheetPanel(
        title: result.isImpersonation
            ? 'Impersonation Detected!'
            : 'Message Appears Safe',
        titleIcon: DuotoneIcon(
          result.isImpersonation ? 'danger_triangle' : 'check_circle',
          color: result.isImpersonation ? riskColor : AppColors.accentInk,
          size: 24,
        ),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result.isImpersonation) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: GlassTheme.badgeGlassDecoration(
                  isDark: context.isDark,
                  tintColor: riskColor,
                ),
                child: Text(
                  '${result.riskLevel.toUpperCase()} RISK - ${(result.confidenceScore * 100).toInt()}% confidence',
                  style: TextStyle(
                    color: riskColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              result.recommendation,
              style: TextStyle(color: cs.onSurface, fontSize: 14, height: 1.45),
            ),
          ],
        ),
        primaryLabel: 'Close',
      ),
    );
  }

  void _confirmRemoveExecutive(
    BuildContext context,
    ExecutiveProfile exec,
    ExecutiveProtectionProvider provider,
  ) {
    final cs = context.colors;
    showAppSheet(
      context,
      child: SheetPanel(
        title: 'Remove VIP?',
        body: Text(
          'Stop monitoring ${exec.name} for impersonation attempts?',
          style: TextStyle(color: cs.onSurface, fontSize: 14.5, height: 1.45),
        ),
        secondaryLabel: 'Cancel',
        primaryLabel: 'Remove',
        danger: true,
        onPrimary: () => provider.removeExecutive(exec.id),
      ),
    );
  }
}
