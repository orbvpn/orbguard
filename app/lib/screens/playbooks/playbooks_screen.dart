// Playbooks Screen
// Automated response playbooks interface

import 'package:flutter/material.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../services/api/orbguard_api_client.dart';

class PlaybooksScreen extends StatefulWidget {
  const PlaybooksScreen({super.key});

  @override
  State<PlaybooksScreen> createState() => _PlaybooksScreenState();
}

class _PlaybooksScreenState extends State<PlaybooksScreen> {
  final OrbGuardApiClient _apiClient = OrbGuardApiClient.instance;
  bool _isLoading = false;
  final List<Playbook> _playbooks = [];
  final List<PlaybookExecution> _executions = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load playbooks from API
      final playbooksData = await _apiClient.getPlaybooks();
      final executionsData = await _apiClient.getPlaybookExecutions();

      setState(() {
        _playbooks.clear();
        _playbooks.addAll(playbooksData.map((json) => Playbook.fromJson(json)));

        _executions.clear();
        _executions.addAll(executionsData.map((json) => PlaybookExecution.fromJson(json)));

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassTabPage(
      title: 'Playbooks',
      hasSearch: true,
      searchHint: 'Search playbooks...',
      tabs: [
        GlassTab(
          label: 'Playbooks',
          iconPath: 'file',
          content: _buildPlaybooksContent(),
        ),
        GlassTab(
          label: 'Executions',
          iconPath: 'chart',
          content: _buildExecutionsContent(),
        ),
      ],
      actions: [
        IconButton(
          icon: DuotoneIcon(AppIcons.addCircle,
              size: 22, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => _showCreatePlaybookDialog(context),
          tooltip: 'Create Playbook',
        ),
        IconButton(
          icon: DuotoneIcon(AppIcons.refresh,
              size: 22, color: Theme.of(context).colorScheme.onSurface),
          onPressed: _isLoading ? null : _loadData,
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildPlaybooksContent() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accentInk),
      );
    }
    return _buildPlaybooksTab();
  }

  Widget _buildExecutionsContent() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accentInk),
      );
    }
    return _buildExecutionsTab();
  }

  Widget _buildPlaybooksTab() {
    if (_playbooks.isEmpty) {
      return _buildEmptyState(
        icon: AppIcons.playCircle,
        title: 'No Playbooks',
        subtitle: 'Create automated response playbooks',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Stats
        Row(
          children: [
            _buildStatCard('Active', _playbooks.where((p) => p.isEnabled).length.toString(), AppColors.accentInk),
            const SizedBox(width: 12),
            _buildStatCard('Executions', _executions.length.toString(), AppColors.accentInk),
          ],
        ),
        const SizedBox(height: 24),

        ..._playbooks.map((playbook) => _buildPlaybookCard(playbook)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: BrandText.heading(color: color, size: 28)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaybookCard(Playbook playbook) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      onTap: () => _showPlaybookDetails(context, playbook),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: AppIcons.playCircle,
                color: playbook.isEnabled
                    ? GlassTheme.primaryAccent
                    : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(playbook.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold)),
                    Text('${playbook.steps.length} steps', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
              Switch(
                value: playbook.isEnabled,
                onChanged: (v) => _setPlaybookEnabled(playbook, v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            playbook.description,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GlassBadge(text: 'Trigger: ${playbook.trigger}', color: GlassTheme.warningColor, fontSize: 10),
              const Spacer(),
              Text(
                '${playbook.executionCount} runs',
                style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExecutionsTab() {
    if (_executions.isEmpty) {
      return _buildEmptyState(
        icon: AppIcons.timer,
        title: 'No Executions',
        subtitle: 'Playbook executions will appear here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _executions.length,
      itemBuilder: (context, index) {
        return _buildExecutionCard(_executions[index]);
      },
    );
  }

  Widget _buildExecutionCard(PlaybookExecution execution) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = execution.status == 'success'
        ? GlassTheme.successColor
        : execution.status == 'running'
            ? GlassTheme.primaryAccent
            : GlassTheme.errorColor;

    return GlassCard(
      tintColor: execution.status == 'failed' ? GlassTheme.errorColor : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: execution.status == 'success'
                    ? AppIcons.checkCircle
                    : execution.status == 'running'
                        ? AppIcons.playCircle
                        : AppIcons.dangerCircle,
                color: statusColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(execution.playbookName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold)),
                    Text(
                      execution.triggeredBy, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                    ),
                  ],
                ),
              ),
              GlassBadge(text: execution.status.toUpperCase(), color: statusColor, fontSize: 10),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildExecutionStat(AppIcons.stopwatch, '${execution.duration}s'),
              const SizedBox(width: 16),
              _buildExecutionStat(AppIcons.structure, '${execution.stepsCompleted}/${execution.totalSteps} steps'),
              const Spacer(),
              Text(
                _formatTime(execution.startedAt),
                style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExecutionStat(String icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DuotoneIcon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ],
    );
  }

  Widget _buildEmptyState({
    required String icon,
    required String title,
    required String subtitle,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(icon, size: 64, color: AppColors.accentInk.withAlpha(128)),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  void _showPlaybookDetails(BuildContext context, Playbook playbook) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            gradient: GlassTheme.backgroundGradient(
                isDark: Theme.of(context).brightness == Brightness.dark),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(GlassTheme.radiusLarge)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Text(playbook.name, style: TextStyle(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(playbook.description, style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 20),

              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Trigger', playbook.trigger),
                    _buildDetailRow('Status', playbook.isEnabled ? 'Active' : 'Disabled'),
                    _buildDetailRow('Executions', '${playbook.executionCount}'),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              Text('Steps', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...playbook.steps.asMap().entries.map((entry) => _buildStepCard(entry.key + 1, entry.value)),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _executePlaybook(playbook);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GlassTheme.primaryAccent,
                    foregroundColor: Brand.onLime,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DuotoneIcon(AppIcons.play, size: 20, color: Brand.onLime),
                      const SizedBox(width: 8),
                      const Text('Run Now'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard(int number, PlaybookStep step) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.accentPill,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: TextStyle(color: AppColors.accentInk, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500)),
                Text(step.action, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
              ],
            ),
          ),
          DuotoneIcon(_getActionIcon(step.action), size: 20, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
          Text(value, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showCreatePlaybookDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create Playbook',
            style:
                TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'In-app playbook authoring is not available yet. Playbooks configured '
          'on the server appear here automatically.',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: AppColors.accentInk)),
          ),
        ],
      ),
    );
  }

  /// Persist the enable/disable toggle to the backend. Optimistically flips the
  /// switch, then reverts and surfaces an error if the API call fails.
  Future<void> _setPlaybookEnabled(Playbook playbook, bool enabled) async {
    final previous = playbook.isEnabled;
    setState(() => playbook.isEnabled = enabled);
    try {
      await _apiClient.setPlaybookEnabled(playbook.id, enabled);
    } catch (e) {
      if (!mounted) return;
      setState(() => playbook.isEnabled = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update playbook: $e'),
          backgroundColor: GlassTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _executePlaybook(Playbook playbook) async {
    // Optimistically add a running execution
    setState(() {
      _executions.insert(0, PlaybookExecution(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        playbookName: playbook.name,
        status: 'running',
        triggeredBy: 'Manual',
        startedAt: DateTime.now(),
        stepsCompleted: 0,
        totalSteps: playbook.steps.length,
        duration: 0,
      ));
    });

    try {
      // Execute playbook via API
      final result = await _apiClient.executePlaybook(playbook.id);

      setState(() {
        final exec = _executions.first;
        _executions[0] = PlaybookExecution(
          id: result['id'] as String? ?? exec.id,
          playbookName: exec.playbookName,
          status: result['status'] as String? ?? 'success',
          triggeredBy: exec.triggeredBy,
          startedAt: exec.startedAt,
          stepsCompleted: (result['steps_completed'] as num?)?.toInt() ?? exec.totalSteps,
          totalSteps: exec.totalSteps,
          duration: (result['duration'] as num?)?.toInt() ?? 0,
        );
      });
    } catch (e) {
      setState(() {
        final exec = _executions.first;
        _executions[0] = PlaybookExecution(
          id: exec.id,
          playbookName: exec.playbookName,
          status: 'failed',
          triggeredBy: exec.triggeredBy,
          startedAt: exec.startedAt,
          stepsCompleted: 0,
          totalSteps: exec.totalSteps,
          duration: 0,
        );
      });
    }
  }

  String _getActionIcon(String action) {
    switch (action.toLowerCase()) {
      case 'notify':
        return AppIcons.bell;
      case 'block':
        return AppIcons.forbidden;
      case 'isolate':
        return AppIcons.shield;
      case 'scan':
        return AppIcons.search;
      case 'log':
        return AppIcons.document;
      default:
        return AppIcons.play;
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

}

class Playbook {
  final String id;
  final String name;
  final String description;
  final String trigger;
  final List<PlaybookStep> steps;
  final int executionCount;
  bool isEnabled;

  Playbook({
    required this.id,
    required this.name,
    required this.description,
    required this.trigger,
    required this.steps,
    this.executionCount = 0,
    this.isEnabled = true,
  });

  factory Playbook.fromJson(Map<String, dynamic> json) {
    return Playbook(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Playbook',
      description: json['description'] as String? ?? '',
      trigger: json['trigger'] as String? ?? '',
      steps: (json['steps'] as List<dynamic>?)
              ?.map((s) => PlaybookStep.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      executionCount: (json['execution_count'] as num?)?.toInt() ?? 0,
      isEnabled: json['is_enabled'] as bool? ?? true,
    );
  }
}

class PlaybookStep {
  final String name;
  final String action;

  PlaybookStep({required this.name, required this.action});

  factory PlaybookStep.fromJson(Map<String, dynamic> json) {
    return PlaybookStep(
      name: json['name'] as String? ?? '',
      action: json['action'] as String? ?? '',
    );
  }
}

class PlaybookExecution {
  final String id;
  final String playbookName;
  final String status;
  final String triggeredBy;
  final DateTime startedAt;
  final int stepsCompleted;
  final int totalSteps;
  final int duration;

  PlaybookExecution({
    required this.id,
    required this.playbookName,
    required this.status,
    required this.triggeredBy,
    required this.startedAt,
    required this.stepsCompleted,
    required this.totalSteps,
    required this.duration,
  });

  factory PlaybookExecution.fromJson(Map<String, dynamic> json) {
    return PlaybookExecution(
      id: json['id'] as String? ?? '',
      playbookName: json['playbook_name'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      triggeredBy: json['triggered_by'] as String? ?? '',
      startedAt: json['started_at'] is String
          ? (DateTime.tryParse(json['started_at'] as String) ?? DateTime.now())
          : DateTime.now(),
      stepsCompleted: (json['steps_completed'] as num?)?.toInt() ?? 0,
      totalSteps: (json['total_steps'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
    );
  }
}
