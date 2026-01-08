/// Enterprise Policy Screen
/// Manage enterprise security policies and compliance

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/enterprise_policy_provider.dart';
import '../../services/security/enterprise/policy_management_service.dart';

class EnterprisePolicyScreen extends StatefulWidget {
  const EnterprisePolicyScreen({super.key});

  @override
  State<EnterprisePolicyScreen> createState() => _EnterprisePolicyScreenState();
}

class _EnterprisePolicyScreenState extends State<EnterprisePolicyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnterprisePolicyProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EnterprisePolicyProvider>(
      builder: (context, provider, _) {
        return GlassPage(
          title: 'Enterprise Policies',
          body: Column(
            children: [
              // Actions row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const DuotoneIcon('add_circle', size: 22, color: Colors.white),
                      onPressed: () => _showCreatePolicySheet(context, provider),
                      tooltip: 'Add Policy',
                    ),
                    IconButton(
                      icon: const DuotoneIcon('refresh', size: 22, color: Colors.white),
                      onPressed: () => provider.loadPolicies(),
                      tooltip: 'Refresh',
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
                      isScrollable: true,
                      tabs: const [
                        Tab(text: 'Policies'),
                        Tab(text: 'Violations'),
                        Tab(text: 'Templates'),
                        Tab(text: 'BYOD'),
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
                    : Column(
                        children: [
                          // Stats
                          _buildStats(provider),
                          // Tab content
                          Expanded(
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                _buildPoliciesTab(provider),
                                _buildViolationsTab(provider),
                                _buildTemplatesTab(provider),
                                _buildBYODTab(provider),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStats(EnterprisePolicyProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildStatItem(
            'Policies',
            provider.policies.length.toString(),
            GlassTheme.primaryAccent,
          ),
          _buildStatItem(
            'Enabled',
            provider.enabledPolicies.length.toString(),
            GlassTheme.successColor,
          ),
          _buildStatItem(
            'Violations',
            provider.unresolvedViolations.toString(),
            GlassTheme.warningColor,
          ),
          _buildStatItem(
            'Critical',
            provider.criticalViolations.toString(),
            GlassTheme.errorColor,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPoliciesTab(EnterprisePolicyProvider provider) {
    if (provider.policies.isEmpty) {
      return _buildEmptyState(
        icon: 'clipboard_text',
        title: 'No Policies',
        subtitle: 'Create a policy to get started',
        action: TextButton.icon(
          onPressed: () => _showCreatePolicySheet(context, provider),
          icon: const DuotoneIcon('add_circle', size: 18),
          label: const Text('Create Policy'),
        ),
      );
    }

    final groupedPolicies = <PolicyType, List<SecurityPolicy>>{};
    for (final policy in provider.policies) {
      groupedPolicies.putIfAbsent(policy.type, () => []).add(policy);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: groupedPolicies.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Row(
                children: [
                  DuotoneIcon(
                    _getPolicyTypeIcon(entry.key),
                    size: 18,
                    color: Color(EnterprisePolicyProvider.getPolicyTypeColor(entry.key)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entry.key.displayName,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ...entry.value.map((policy) => _buildPolicyCard(policy, provider)),
            const SizedBox(height: 16),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildPolicyCard(SecurityPolicy policy, EnterprisePolicyProvider provider) {
    final typeColor = Color(EnterprisePolicyProvider.getPolicyTypeColor(policy.type));

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showPolicyDetails(context, policy, provider),
        borderRadius: BorderRadius.circular(16),
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
                      color: typeColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: DuotoneIcon(
                        _getPolicyTypeIcon(policy.type),
                        color: typeColor,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                policy.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (policy.isDefault)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: GlassTheme.primaryAccent
                                      .withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'DEFAULT',
                                  style: TextStyle(
                                    color: GlassTheme.primaryAccent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          policy.description,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: policy.isEnabled,
                    onChanged: (value) =>
                        provider.togglePolicyEnabled(policy.id, value),
                    activeColor: GlassTheme.primaryAccent,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildPolicyBadge(
                    policy.enforcement.displayName,
                    Color(EnterprisePolicyProvider.getEnforcementColor(
                        policy.enforcement)),
                  ),
                  const SizedBox(width: 8),
                  _buildPolicyBadge(
                    '${policy.rules.length} rules',
                    Colors.white54,
                  ),
                  if (policy.assignedGroups.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _buildPolicyBadge(
                      '${policy.assignedGroups.length} groups',
                      Colors.white54,
                    ),
                  ],
                  if (policy.platforms.isNotEmpty) ...[
                    const Spacer(),
                    ...policy.platforms.map((p) => Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: DuotoneIcon(
                            p.toLowerCase() == 'ios'
                                ? 'apple'
                                : 'smartphone',
                            size: 16,
                            color: Colors.white54,
                          ),
                        )),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPolicyBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildViolationsTab(EnterprisePolicyProvider provider) {
    if (provider.violations.isEmpty) {
      return _buildEmptyState(
        icon: 'check_circle',
        title: 'No Violations',
        subtitle: 'All devices are compliant',
        color: GlassTheme.successColor,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.violations.length,
      itemBuilder: (context, index) {
        return _buildViolationCard(provider.violations[index], provider);
      },
    );
  }

  Widget _buildViolationCard(
    PolicyViolation violation,
    EnterprisePolicyProvider provider,
  ) {
    final severityColor =
        Color(EnterprisePolicyProvider.getSeverityColor(violation.severity));

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
                    color: severityColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: DuotoneIcon(
                      'danger_triangle',
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
                        violation.ruleName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        violation.deviceName,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
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
                    color: severityColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    violation.severity.toUpperCase(),
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
              violation.details,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                DuotoneIcon(
                  'clock_circle',
                  size: 14,
                  color: Colors.white.withOpacity(0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDate(violation.detectedAt),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      _showResolveDialog(context, violation, provider),
                  child: const Text('Resolve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplatesTab(EnterprisePolicyProvider provider) {
    final templates = provider.templates;

    if (templates.isEmpty) {
      return _buildEmptyState(
        icon: 'widget_5',
        title: 'No Templates',
        subtitle: 'Policy templates are loading...',
      );
    }

    final groupedTemplates = <String, List<PolicyTemplate>>{};
    for (final template in templates) {
      groupedTemplates.putIfAbsent(template.category, () => []).add(template);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: groupedTemplates.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
              child: Text(
                entry.key,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...entry.value.map((template) => _buildTemplateCard(template, provider)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildTemplateCard(
    PolicyTemplate template,
    EnterprisePolicyProvider provider,
  ) {
    final typeColor =
        Color(EnterprisePolicyProvider.getPolicyTypeColor(template.type));

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: typeColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: DuotoneIcon(
              _getPolicyTypeIcon(template.type),
              color: typeColor,
              size: 24,
            ),
          ),
        ),
        title: Text(
          template.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${template.rules.length} rules • ${template.type.displayName}',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
          ),
        ),
        trailing: IconButton(
          icon: const DuotoneIcon(
            'add_circle',
            color: GlassTheme.primaryAccent,
            size: 24,
          ),
          onPressed: () =>
              _showCreateFromTemplateDialog(context, template, provider),
        ),
      ),
    );
  }

  Widget _buildBYODTab(EnterprisePolicyProvider provider) {
    final byodTemplates = provider.getBYODTemplates();
    final byodPolicies = provider.byodPolicies;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Existing BYOD policies
        if (byodPolicies.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Active BYOD Policies',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...byodPolicies.map((policy) => _buildPolicyCard(policy, provider)),
          const SizedBox(height: 16),
        ],

        // BYOD Templates
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'BYOD Templates',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...byodTemplates.map((template) => _buildBYODTemplateCard(template, provider)),
      ],
    );
  }

  Widget _buildBYODTemplateCard(
    PolicyTemplate template,
    EnterprisePolicyProvider provider,
  ) {
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
                    color: GlassTheme.successColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: DuotoneIcon(
                      'smartphone',
                      color: GlassTheme.successColor,
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
                        template.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        template.description,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPolicyBadge(
                  '${template.rules.length} rules',
                  Colors.white54,
                ),
                _buildPolicyBadge(
                  template.category,
                  GlassTheme.primaryAccent,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    _showCreateFromTemplateDialog(context, template, provider),
                icon: const DuotoneIcon('add_circle', size: 18),
                label: const Text('Create Policy'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: GlassTheme.primaryAccent,
                  side: const BorderSide(
                    color: GlassTheme.primaryAccent,
                  ),
                ),
              ),
            ),
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

  String _getPolicyTypeIcon(PolicyType type) {
    switch (type) {
      case PolicyType.security:
        return 'shield';
      case PolicyType.compliance:
        return 'verified_check';
      case PolicyType.restriction:
        return 'forbidden';
      case PolicyType.configuration:
        return 'settings';
      case PolicyType.conditional:
        return 'clipboard_text';
      case PolicyType.byod:
        return 'smartphone';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _showCreatePolicySheet(
    BuildContext context,
    EnterprisePolicyProvider provider,
  ) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    PolicyType selectedType = PolicyType.security;
    EnforcementLevel selectedEnforcement = EnforcementLevel.warn;

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
                  'Create Policy',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Policy Name',
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
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description',
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
                const SizedBox(height: 16),
                const Text(
                  'Policy Type',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: PolicyType.values.map((type) {
                    final isSelected = type == selectedType;
                    final color = Color(
                      EnterprisePolicyProvider.getPolicyTypeColor(type),
                    );
                    return ChoiceChip(
                      label: Text(type.displayName),
                      selected: isSelected,
                      selectedColor: color,
                      backgroundColor: color.withOpacity(0.2),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : color,
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
                const Text(
                  'Enforcement Level',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: EnforcementLevel.values.map((level) {
                    final isSelected = level == selectedEnforcement;
                    final color = Color(
                      EnterprisePolicyProvider.getEnforcementColor(level),
                    );
                    return ChoiceChip(
                      label: Text(level.displayName),
                      selected: isSelected,
                      selectedColor: color,
                      backgroundColor: color.withOpacity(0.2),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : color,
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => selectedEnforcement = level);
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.isNotEmpty) {
                        await provider.createPolicy(
                          name: nameController.text,
                          description: descController.text,
                          type: selectedType,
                          enforcement: selectedEnforcement,
                        );
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GlassTheme.primaryAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Create Policy'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPolicyDetails(
    BuildContext context,
    SecurityPolicy policy,
    EnterprisePolicyProvider provider,
  ) {
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
              colors: [
                GlassTheme.gradientTop,
                GlassTheme.gradientBottom,
              ],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      policy.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const DuotoneIcon('trash_bin_minimalistic', color: Colors.red, size: 24),
                    onPressed: () {
                      Navigator.pop(context);
                      _confirmDelete(context, policy, provider);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                policy.description,
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildPolicyBadge(
                    policy.type.displayName,
                    Color(EnterprisePolicyProvider.getPolicyTypeColor(policy.type)),
                  ),
                  const SizedBox(width: 8),
                  _buildPolicyBadge(
                    policy.enforcement.displayName,
                    Color(EnterprisePolicyProvider.getEnforcementColor(
                        policy.enforcement)),
                  ),
                  const Spacer(),
                  Text(
                    policy.isEnabled ? 'Enabled' : 'Disabled',
                    style: TextStyle(
                      color: policy.isEnabled
                          ? GlassTheme.successColor
                          : Colors.white54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Rules',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (policy.rules.isEmpty)
                Text(
                  'No rules defined',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                )
              else
                ...policy.rules.map((rule) => GlassContainer(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          DuotoneIcon(
                            rule.isEnabled
                                ? 'check_circle'
                                : 'close_circle',
                            size: 20,
                            color: rule.isEnabled
                                ? GlassTheme.successColor
                                : Colors.white38,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rule.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  rule.description,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
              if (policy.assignedGroups.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  'Assigned Groups',
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
                  children: policy.assignedGroups
                      .map((g) => Chip(
                            label: Text(g),
                            backgroundColor: Colors.white12,
                            labelStyle: const TextStyle(color: Colors.white),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateFromTemplateDialog(
    BuildContext context,
    PolicyTemplate template,
    EnterprisePolicyProvider provider,
  ) {
    final nameController = TextEditingController(text: template.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text(
          'Create from Template',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Create a new policy based on "${template.name}"',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Policy Name',
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await provider.createFromTemplate(
                  template.id,
                  name: nameController.text,
                );
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showResolveDialog(
    BuildContext context,
    PolicyViolation violation,
    EnterprisePolicyProvider provider,
  ) {
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text(
          'Resolve Violation',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark this violation as resolved?',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await provider.resolveViolation(
                violation.id,
                notes: notesController.text.isNotEmpty
                    ? notesController.text
                    : null,
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    SecurityPolicy policy,
    EnterprisePolicyProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text(
          'Delete Policy?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "${policy.name}"? This action cannot be undone.',
          style: TextStyle(color: Colors.white.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await provider.deletePolicy(policy.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: GlassTheme.errorColor),
            ),
          ),
        ],
      ),
    );
  }
}
