/// Playbooks Screen
/// Automated response playbooks interface

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';

class PlaybooksScreen extends StatefulWidget {
  const PlaybooksScreen({super.key});

  @override
  State<PlaybooksScreen> createState() => _PlaybooksScreenState();
}

class _PlaybooksScreenState extends State<PlaybooksScreen> {
  bool _isLoading = false;
  final List<Playbook> _playbooks = [];
  final List<PlaybookExecution> _executions = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _playbooks.addAll(_getSamplePlaybooks());
      _executions.addAll(_getSampleExecutions());
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Playbooks',
        actions: [
          GlassAppBarAction(
            svgIcon: AppIcons.addCircle,
            onTap: () => _showCreatePlaybookDialog(context),
            tooltip: 'Create Playbook',
          ),
          GlassAppBarAction(
            svgIcon: AppIcons.refresh,
            onTap: _isLoading ? null : _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    indicatorColor: GlassTheme.primaryAccent,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    tabs: const [
                      Tab(text: 'Playbooks'),
                      Tab(text: 'Executions'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildPlaybooksTab(),
                        _buildExecutionsTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
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
      padding: const EdgeInsets.all(16),
      children: [
        // Stats
        Row(
          children: [
            _buildStatCard('Active', _playbooks.where((p) => p.isEnabled).length.toString(), GlassTheme.successColor),
            const SizedBox(width: 12),
            _buildStatCard('Executions', _executions.length.toString(), GlassTheme.primaryAccent),
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
            Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaybookCard(Playbook playbook) {
    return GlassCard(
      onTap: () => _showPlaybookDetails(context, playbook),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: AppIcons.playCircle,
                color: playbook.isEnabled ? GlassTheme.primaryAccent : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(playbook.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('${playbook.steps.length} steps', style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11)),
                  ],
                ),
              ),
              Switch(
                value: playbook.isEnabled,
                onChanged: (v) => setState(() => playbook.isEnabled = v),
                activeColor: GlassTheme.successColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            playbook.description,
            style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12),
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
                style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11),
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
      padding: const EdgeInsets.all(16),
      itemCount: _executions.length,
      itemBuilder: (context, index) {
        return _buildExecutionCard(_executions[index]);
      },
    );
  }

  Widget _buildExecutionCard(PlaybookExecution execution) {
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
                    Text(execution.playbookName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(
                      execution.triggeredBy,
                      style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11),
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
                style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExecutionStat(String icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DuotoneIcon(icon, size: 14, color: Colors.white.withAlpha(128)),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
      ],
    );
  }

  Widget _buildEmptyState({
    required String icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(icon, size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(153))),
        ],
      ),
    );
  }

  void _showPlaybookDetails(BuildContext context, Playbook playbook) {
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
              colors: [GlassTheme.gradientTop, GlassTheme.gradientBottom],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Text(playbook.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(playbook.description, style: TextStyle(color: Colors.white.withAlpha(179))),
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
              const Text('Steps', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DuotoneIcon(AppIcons.play, size: 20, color: Colors.white),
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
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: GlassTheme.primaryAccent.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(color: GlassTheme.primaryAccent, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                Text(step.action, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11)),
              ],
            ),
          ),
          DuotoneIcon(_getActionIcon(step.action), size: 20, color: Colors.white54),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withAlpha(153))),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showCreatePlaybookDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Create Playbook', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Use the playbook builder to create custom automated responses.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Create', style: TextStyle(color: GlassTheme.primaryAccent)),
          ),
        ],
      ),
    );
  }

  void _executePlaybook(Playbook playbook) {
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

    // Simulate completion
    Future.delayed(const Duration(seconds: 3), () {
      setState(() {
        final exec = _executions.first;
        _executions[0] = PlaybookExecution(
          id: exec.id,
          playbookName: exec.playbookName,
          status: 'success',
          triggeredBy: exec.triggeredBy,
          startedAt: exec.startedAt,
          stepsCompleted: exec.totalSteps,
          totalSteps: exec.totalSteps,
          duration: 3,
        );
      });
    });
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

  List<Playbook> _getSamplePlaybooks() {
    return [
      Playbook(
        id: '1',
        name: 'Phishing Response',
        description: 'Automated response to detected phishing attempts.',
        trigger: 'phishing.detected',
        steps: [
          PlaybookStep(name: 'Block URL', action: 'block'),
          PlaybookStep(name: 'Notify Security Team', action: 'notify'),
          PlaybookStep(name: 'Log Incident', action: 'log'),
          PlaybookStep(name: 'Scan for Similar Threats', action: 'scan'),
        ],
        executionCount: 47,
      ),
      Playbook(
        id: '2',
        name: 'Malware Containment',
        description: 'Isolate and contain detected malware infections.',
        trigger: 'malware.detected',
        steps: [
          PlaybookStep(name: 'Isolate Device', action: 'isolate'),
          PlaybookStep(name: 'Alert SOC', action: 'notify'),
          PlaybookStep(name: 'Collect Forensics', action: 'scan'),
          PlaybookStep(name: 'Create Incident Ticket', action: 'log'),
        ],
        executionCount: 12,
      ),
      Playbook(
        id: '3',
        name: 'Suspicious Login Alert',
        description: 'Handle unusual login patterns and potential account compromise.',
        trigger: 'login.suspicious',
        steps: [
          PlaybookStep(name: 'Send User Alert', action: 'notify'),
          PlaybookStep(name: 'Log Event', action: 'log'),
        ],
        executionCount: 89,
      ),
    ];
  }

  List<PlaybookExecution> _getSampleExecutions() {
    return [
      PlaybookExecution(
        id: '1',
        playbookName: 'Phishing Response',
        status: 'success',
        triggeredBy: 'phishing.detected',
        startedAt: DateTime.now().subtract(const Duration(hours: 1)),
        stepsCompleted: 4,
        totalSteps: 4,
        duration: 8,
      ),
      PlaybookExecution(
        id: '2',
        playbookName: 'Suspicious Login Alert',
        status: 'success',
        triggeredBy: 'login.suspicious',
        startedAt: DateTime.now().subtract(const Duration(hours: 3)),
        stepsCompleted: 2,
        totalSteps: 2,
        duration: 2,
      ),
      PlaybookExecution(
        id: '3',
        playbookName: 'Malware Containment',
        status: 'failed',
        triggeredBy: 'malware.detected',
        startedAt: DateTime.now().subtract(const Duration(days: 1)),
        stepsCompleted: 2,
        totalSteps: 4,
        duration: 15,
      ),
    ];
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
}

class PlaybookStep {
  final String name;
  final String action;

  PlaybookStep({required this.name, required this.action});
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
}
