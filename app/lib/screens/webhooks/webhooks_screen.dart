// Webhooks Screen
// Webhook configuration and management interface

import 'package:flutter/material.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../services/api/orbguard_api_client.dart';

class WebhooksScreen extends StatefulWidget {
  const WebhooksScreen({super.key});

  @override
  State<WebhooksScreen> createState() => _WebhooksScreenState();
}

class _WebhooksScreenState extends State<WebhooksScreen> {
  bool _isLoading = false;
  String? _error;
  final List<Webhook> _webhooks = [];
  final _api = OrbGuardApiClient.instance;

  @override
  void initState() {
    super.initState();
    _loadWebhooks();
  }

  Future<void> _loadWebhooks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final webhooksData = await _api.getWebhooks();
      final webhooks = webhooksData.map((data) => Webhook.fromJson(data)).toList();
      setState(() {
        _webhooks.clear();
        _webhooks.addAll(webhooks);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Webhooks',
      actions: [
        GestureDetector(
          onTap: () { if (!_isLoading) _loadWebhooks(); },
          child: DuotoneIcon('refresh', size: 22, color: context.colors.onSurface),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddWebhookDialog(context),
        backgroundColor: GlassTheme.primaryAccent,
        foregroundColor: Brand.onLime,
        tooltip: 'Add Webhook',
        child: DuotoneIcon('add_circle', size: 26, color: Brand.onLime),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
          : _error != null
              ? _buildErrorState()
              : Column(
              children: [
                Expanded(
                  child: _webhooks.isEmpty
                      ? _buildEmptyState()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          children: [
                            // Stats
                            Row(
                              children: [
                                _buildStatCard('Active', _webhooks.where((w) => w.isEnabled).length.toString(), AppColors.accentInk),
                                const SizedBox(width: 12),
                                _buildStatCard('Total Sent', _formatSentCount(_webhooks.fold(0, (sum, w) => sum + w.sentCount)), AppColors.accentInk),
                              ],
                            ),
                            const SizedBox(height: 24),

                            const GlassSectionHeader(title: 'Configured Webhooks'),
                            ..._webhooks.map((webhook) => _buildWebhookCard(webhook)),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  String _formatSentCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return (count / 1000).toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return count.toString();
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: BrandText.heading(color: color, size: 28)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildWebhookCard(Webhook webhook) {
    return GlassCard(
      onTap: () => _showWebhookDetails(context, webhook),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassDuotoneIconBox(
                icon: _getWebhookSvgIcon(webhook.type),
                color: webhook.isEnabled ? GlassTheme.primaryAccent : context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(webhook.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold)),
                    Text(webhook.type, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
              Switch(
                value: webhook.isEnabled,
                onChanged: (v) => _setWebhookEnabled(webhook, v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            webhook.url,
            style: BrandText.mono(color: context.colors.onSurfaceVariant, size: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildWebhookStat('forward', '${webhook.sentCount} sent'),
              const SizedBox(width: 16),
              _buildWebhookHealth(webhook),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: webhook.events.take(3).map((event) => GlassBadge(
                  text: event,
                  color: GlassTheme.primaryAccent,
                  fontSize: 10,
                )).toList(),
          ),
        ],
      ),
    );
  }

  /// Health chip for a webhook. One that has never delivered (no status
  /// reported by the backend) reads as a neutral "Unknown" — not a green
  /// "Healthy" it hasn't earned.
  Widget _buildWebhookHealth(Webhook webhook) {
    if (!webhook.hasDelivered) {
      return _buildWebhookStat('question_circle', 'Unknown');
    }
    final healthy = webhook.lastStatus == 'success';
    return _buildWebhookStat(
      healthy ? 'check_circle' : 'danger_circle',
      healthy ? 'Healthy' : 'Failed',
      color: healthy ? AppColors.accentInk : AppColors.errorInk,
    );
  }

  Widget _buildWebhookStat(String icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DuotoneIcon(icon, size: 14, color: color ?? context.colors.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color ?? context.colors.onSurfaceVariant, fontSize: 12)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon('link', size: 64, color: AppColors.accentInk.withAlpha(128)),
          const SizedBox(height: 16),
          Text(
            'No Webhooks',
            style: TextStyle(color: context.colors.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Configure webhooks to receive threat notifications',
            style: TextStyle(color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showAddWebhookDialog(context),
            icon: const DuotoneIcon('add_circle', size: 18, color: Brand.onLime),
            label: const Text('Add Webhook'),
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.primaryAccent,
              foregroundColor: Brand.onLime,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuotoneIcon('danger_circle', size: 64, color: AppColors.errorInk.withAlpha(128)),
            const SizedBox(height: 16),
            Text(
              'Failed to Load Webhooks',
              style: TextStyle(color: context.colors.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'An unknown error occurred',
              style: TextStyle(color: context.colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadWebhooks,
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

  Future<void> _createWebhook(String name, String url) async {
    try {
      final data = {
        'name': name,
        'url': url,
        'type': 'Custom',
        'events': ['threat.detected'],
        'is_enabled': true,
      };
      await _api.createWebhook(data);
      await _loadWebhooks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create webhook: $e'),
            backgroundColor: GlassTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _deleteWebhook(Webhook webhook) async {
    try {
      await _api.deleteWebhook(webhook.id);
      await _loadWebhooks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete webhook: $e'),
            backgroundColor: GlassTheme.errorColor,
          ),
        );
      }
    }
  }

  /// Persist the enable/disable toggle to the backend. Optimistically flips the
  /// switch, then reverts and surfaces an error if the API call fails.
  Future<void> _setWebhookEnabled(Webhook webhook, bool enabled) async {
    final previous = webhook.isEnabled;
    setState(() => webhook.isEnabled = enabled);
    try {
      await _api.setWebhookEnabled(webhook.id, enabled);
    } catch (e) {
      if (!mounted) return;
      setState(() => webhook.isEnabled = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update webhook: $e'),
          backgroundColor: GlassTheme.errorColor,
        ),
      );
    }
  }

  /// Trigger a real test delivery via the backend and report the outcome.
  Future<void> _testWebhook(Webhook webhook) async {
    try {
      await _api.testWebhook(webhook.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test delivery sent to ${webhook.name}'),
          backgroundColor: GlassTheme.successColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to test ${webhook.name}: $e'),
          backgroundColor: GlassTheme.errorColor,
        ),
      );
    }
  }

  void _showAddWebhookDialog(BuildContext context) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.isDark
            ? GlassTheme.gradientTop
            : GlassTheme.gradientTopLight,
        title: Text('Add Webhook', style: TextStyle(color: context.colors.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: TextStyle(color: context.colors.onSurface),
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: context.colors.onSurfaceVariant),
                hintText: 'e.g., Slack Notifications',
                hintStyle: TextStyle(color: context.colors.onSurfaceVariant.withValues(alpha: 0.7)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              style: TextStyle(color: context.colors.onSurface),
              decoration: InputDecoration(
                labelText: 'Webhook URL',
                labelStyle: TextStyle(color: context.colors.onSurfaceVariant),
                hintText: 'https://...',
                hintStyle: TextStyle(color: context.colors.onSurfaceVariant.withValues(alpha: 0.7)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && urlController.text.isNotEmpty) {
                Navigator.pop(context);
                _createWebhook(nameController.text, urlController.text);
              }
            },
            child: Text('Add', style: TextStyle(color: AppColors.accentInk)),
          ),
        ],
      ),
    );
  }

  void _showWebhookDetails(BuildContext context, Webhook webhook) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: context.isDark
                  ? const [GlassTheme.gradientTop, GlassTheme.gradientBottom]
                  : const [GlassTheme.gradientTopLight, GlassTheme.gradientBottomLight],
            ),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(GlassTheme.radiusLarge)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Text(webhook.name, style: TextStyle(color: context.colors.onSurface, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              GlassBadge(text: webhook.type, color: GlassTheme.primaryAccent),
              const SizedBox(height: 16),
              GlassContainer(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  webhook.url,
                  style: BrandText.mono(color: context.colors.onSurface.withValues(alpha: 0.8), size: 12),
                ),
              ),
              const SizedBox(height: 20),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Status', webhook.isEnabled ? 'Active' : 'Disabled'),
                    _buildDetailRow('Last Status',
                        webhook.hasDelivered ? webhook.lastStatus.toUpperCase() : 'Unknown'),
                    _buildDetailRow('Total Sent', '${webhook.sentCount}'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('Events', style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: webhook.events.map((event) => GlassBadge(text: event, color: GlassTheme.primaryAccent)).toList(),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _testWebhook(webhook);
                      },
                      icon: DuotoneIcon('forward', size: 18, color: AppColors.accentInk),
                      label: const Text('Test'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accentInk,
                        side: BorderSide(color: AppColors.accentInk),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteWebhook(webhook);
                      },
                      icon: DuotoneIcon('trash_bin_minimalistic', size: 18, color: AppColors.errorInk),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.errorInk,
                        side: BorderSide(color: AppColors.errorInk),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.colors.onSurfaceVariant)),
          Text(value, style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _getWebhookSvgIcon(String type) {
    switch (type.toLowerCase()) {
      case 'slack':
        return 'hashtag';
      case 'teams':
        return 'users_group_rounded';
      case 'discord':
        return 'chat_dots';
      case 'pagerduty':
        return 'bell_bing';
      default:
        return 'link';
    }
  }
}

class Webhook {
  final String id;
  final String name;
  final String url;
  final String type;
  final List<String> events;
  final int sentCount;
  final String lastStatus;
  bool isEnabled;

  Webhook({
    required this.id,
    required this.name,
    required this.url,
    required this.type,
    required this.events,
    this.sentCount = 0,
    this.lastStatus = '',
    this.isEnabled = true,
  });

  /// Whether the backend has reported a delivery outcome yet. A webhook that
  /// has never delivered has no status, so it must not read as "Healthy".
  bool get hasDelivered => lastStatus.isNotEmpty;

  factory Webhook.fromJson(Map<String, dynamic> json) {
    return Webhook(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      type: json['type'] as String? ?? 'Custom',
      events: (json['events'] as List<dynamic>?)?.cast<String>() ?? [],
      sentCount: json['sent_count'] as int? ?? json['sentCount'] as int? ?? 0,
      lastStatus: json['last_status'] as String? ?? json['lastStatus'] as String? ?? '',
      isEnabled: json['is_enabled'] as bool? ?? json['isEnabled'] as bool? ?? true,
    );
  }
}
