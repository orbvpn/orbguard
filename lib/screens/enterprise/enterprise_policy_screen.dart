/// Enterprise Policy Screen
/// Displays the organization's Zero Trust conditional access policies as
/// served by the backend (GET /api/v1/enterprise/policies). Policies are
/// authored and enforced server-side; this screen renders them.
library;

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

class _EnterprisePolicyScreenState extends State<EnterprisePolicyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnterprisePolicyProvider>().loadPolicies();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EnterprisePolicyProvider>(
      builder: (context, provider, _) {
        return GlassPage(
          title: 'Conditional Access',
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const DuotoneIcon('refresh', size: 22, color: Colors.white),
                      onPressed: provider.isLoading ? null : provider.loadPolicies,
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildBody(provider)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(EnterprisePolicyProvider provider) {
    if (provider.isLoading && !provider.hasLoaded) {
      return const Center(
        child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
      );
    }
    if (provider.error != null) {
      return _buildErrorState(provider);
    }
    if (provider.policies.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: provider.loadPolicies,
      color: GlassTheme.primaryAccent,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStats(provider),
          const SizedBox(height: 16),
          const GlassSectionHeader(title: 'Policies'),
          ...provider.policies.map((p) => _buildPolicyCard(p)),
        ],
      ),
    );
  }

  Widget _buildStats(EnterprisePolicyProvider provider) {
    return Row(
      children: [
        _buildStatItem('Total', provider.policies.length.toString(),
            GlassTheme.primaryAccent),
        _buildStatItem('Enabled', provider.enabledPolicies.length.toString(),
            GlassTheme.successColor),
        _buildStatItem('Disabled', provider.disabledPolicies.length.toString(),
            Colors.grey),
      ],
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
                color: Colors.white.withAlpha(153),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyCard(ConditionalAccessPolicy policy) {
    final statusColor =
        policy.enabled ? GlassTheme.successColor : Colors.grey;
    final requirementCount =
        policy.conditions.summary.length + policy.grantControls.summary.length;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => _showPolicyDetails(context, policy),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: 'clipboard_text',
                color: statusColor,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      policy.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (policy.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        policy.description,
                        style: TextStyle(
                          color: Colors.white.withAlpha(153),
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              GlassBadge(
                text: policy.enabled ? 'Enabled' : 'Disabled',
                color: statusColor,
                fontSize: 10,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (policy.priority != null)
                _buildBadge('Priority ${policy.priority}', Colors.white54),
              _buildBadge(
                requirementCount == 1
                    ? '1 requirement'
                    : '$requirementCount requirements',
                Colors.white54,
              ),
              if (policy.grantControls.requireMfa)
                _buildBadge('MFA', GlassTheme.primaryAccent),
              if (policy.conditions.requireCompliance)
                _buildBadge('Compliance', GlassTheme.warningColor),
              if (policy.conditions.requireManaged)
                _buildBadge('Managed device', GlassTheme.warningColor),
              if (policy.appliesToAll)
                _buildBadge('All users', Colors.white54)
              else
                _buildBadge('Scoped', Colors.white54),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(51),
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuotoneIcon('clipboard_text',
                size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
            const SizedBox(height: 16),
            const Text(
              'No Policies',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No conditional access policies are configured on the server.',
              style: TextStyle(color: Colors.white.withAlpha(153)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(EnterprisePolicyProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DuotoneIcon('danger_circle',
                size: 64, color: GlassTheme.errorColor),
            const SizedBox(height: 16),
            const Text(
              'Error Loading Policies',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              provider.error ?? 'An unknown error occurred',
              style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: provider.loadPolicies,
              icon: const DuotoneIcon('refresh', size: 18, color: Colors.white),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPolicyDetails(
      BuildContext context, ConditionalAccessPolicy policy) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [GlassTheme.gradientTop, GlassTheme.gradientBottom],
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
                  GlassBadge(
                    text: policy.enabled ? 'Enabled' : 'Disabled',
                    color: policy.enabled
                        ? GlassTheme.successColor
                        : Colors.grey,
                  ),
                ],
              ),
              if (policy.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  policy.description,
                  style: TextStyle(color: Colors.white.withAlpha(178)),
                ),
              ],
              const SizedBox(height: 16),
              GlassContainer(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _buildDetailRow(
                        'Priority',
                        policy.priority?.toString() ?? 'Not available'),
                    _buildDetailRow('Scope',
                        policy.appliesToAll ? 'All users' : 'Scoped'),
                    _buildDetailRow(
                        'Created',
                        policy.createdAt != null
                            ? _formatDate(policy.createdAt!)
                            : 'Not available'),
                    _buildDetailRow(
                        'Updated',
                        policy.updatedAt != null
                            ? _formatDate(policy.updatedAt!)
                            : 'Not available'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSummarySection(
                'Conditions',
                policy.conditions.summary,
                'No conditions configured — policy applies unconditionally.',
              ),
              const SizedBox(height: 24),
              _buildSummarySection(
                'Grant Controls',
                policy.grantControls.summary,
                'No grant controls configured.',
              ),
              if (!policy.appliesToAll) ...[
                const SizedBox(height: 24),
                _buildScopeSection(policy),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummarySection(
      String title, List<String> lines, String emptyText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (lines.isEmpty)
          Text(
            emptyText,
            style: TextStyle(color: Colors.white.withAlpha(128)),
          )
        else
          ...lines.map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DuotoneIcon('check_circle',
                        size: 18, color: GlassTheme.primaryAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _buildScopeSection(ConditionalAccessPolicy policy) {
    Widget chips(String label, List<String> values) {
      if (values.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                  color: Colors.white.withAlpha(153), fontSize: 12),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: values
                  .map((v) => Chip(
                        label: Text(v),
                        backgroundColor: Colors.white12,
                        labelStyle: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ))
                  .toList(),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Assignment',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        chips('Included users', policy.includeUsers),
        chips('Excluded users', policy.excludeUsers),
        chips('Included groups', policy.includeGroups),
        chips('Excluded groups', policy.excludeGroups),
        chips('Included apps', policy.includeApps),
        chips('Excluded apps', policy.excludeApps),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withAlpha(153))),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}
