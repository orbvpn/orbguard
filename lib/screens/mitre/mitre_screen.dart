/// MITRE ATT&CK Screen
/// Displays MITRE ATT&CK matrix for mobile threats
library mitre_screen;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../providers/mitre_provider.dart';
import '../../widgets/mitre/mitre_widgets.dart';

/// Main MITRE ATT&CK screen
class MitreScreen extends StatefulWidget {
  const MitreScreen({super.key});

  @override
  State<MitreScreen> createState() => _MitreScreenState();
}

class _MitreScreenState extends State<MitreScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late MitreProvider _provider;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _provider = MitreProvider();
    _provider.init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: GlassScaffold(
        appBar: GlassAppBar(
          title: 'MITRE ATT&CK',
          showBackButton: true,
          actions: [
            GlassAppBarAction(
              svgIcon: 'info_circle',
              onTap: _showInfoDialog,
            ),
          ],
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
                    tabs: [
                      Tab(text: 'Matrix', icon: DuotoneIcon('widget_4', size: 24)),
                      Tab(text: 'Detections', icon: DuotoneIcon('danger_triangle', size: 24)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _MatrixTab(),
                  _DetectionsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text(
          'About MITRE ATT&CK',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'MITRE ATT&CK is a globally-accessible knowledge base of adversary tactics and techniques based on real-world observations.\n\n'
          'This view shows Mobile ATT&CK techniques that can be used to attack mobile devices. '
          'Red items indicate techniques that have been detected in threats found on your device.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

/// Matrix tab - horizontal scrollable MITRE matrix
class _MatrixTab extends StatelessWidget {
  const _MatrixTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<MitreProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00D9FF)),
          );
        }

        final detectedIds = provider.detectedTechniques
            .map((d) => d.technique.id)
            .toSet();

        return Column(
          children: [
            // Stats and legend
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  MitreStatsCard(
                    totalTechniques: provider.techniquesByTactic.values
                        .fold(0, (sum, list) => sum + list.length),
                    detectedTechniques: provider.detectedTechniques.length,
                    detectedByTactic: provider.detectedCountByTactic,
                  ),
                  const SizedBox(height: 8),
                  const MitreLegend(),
                ],
              ),
            ),

            // Matrix
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: provider.tactics.map((tactic) {
                    final techniques = provider.getTechniquesForTactic(tactic.id);
                    return SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: TacticColumn(
                        tactic: tactic,
                        techniques: techniques,
                        detectedTechniqueIds: detectedIds,
                        selectedTechniqueId: provider.selectedTechniqueId,
                        onTechniqueTap: (t) {
                          provider.selectTechnique(t.id);
                          _showTechniqueDetail(context, t, provider);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showTechniqueDetail(
    BuildContext context,
    MitreTechnique technique,
    MitreProvider provider,
  ) {
    final detection = provider.getDetectedTechnique(technique.id);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0A0E21),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                TechniqueDetailCard(
                  technique: technique,
                  detection: detection,
                  onClose: () {
                    provider.selectTechnique(null);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) => provider.selectTechnique(null));
  }
}

/// Detections tab - list of detected techniques
class _DetectionsTab extends StatelessWidget {
  const _DetectionsTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<MitreProvider>(
      builder: (context, provider, _) {
        final detections = provider.detectedTechniques;

        if (detections.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DuotoneIcon(
                  'shield_check',
                  size: 64,
                  color: Colors.green.withAlpha(128),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No Techniques Detected',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your device appears to be clean.\nNo MITRE ATT&CK techniques have been detected.',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        // Group by tactic
        final byTactic = <String, List<DetectedTechnique>>{};
        for (final detection in detections) {
          final tacticId = detection.technique.tacticId;
          byTactic.putIfAbsent(tacticId, () => []).add(detection);
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Warning banner
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(26),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withAlpha(77)),
              ),
              child: Row(
                children: [
                  const DuotoneIcon('danger_triangle', size: 24, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Threat Techniques Detected',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${detections.length} MITRE ATT&CK techniques found',
                          style: TextStyle(
                            color: Colors.red[200],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Detection list by tactic
            ...byTactic.entries.map((entry) {
              final tactic = MitreTactic.mobileTactics.firstWhere(
                (t) => t.id == entry.key,
                orElse: () => MitreTactic(
                  id: entry.key,
                  name: entry.key,
                  shortName: entry.key,
                  description: '',
                  order: 99,
                ),
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tactic header
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D9FF).withAlpha(26),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tactic.name,
                            style: const TextStyle(
                              color: Color(0xFF00D9FF),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${entry.value.length} technique(s)',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Techniques
                  ...entry.value.map((detection) => _DetectionCard(
                        detection: detection,
                        onTap: () => _showTechniqueDetail(context, detection),
                      )),

                  const SizedBox(height: 16),
                ],
              );
            }),
          ],
        );
      },
    );
  }

  void _showTechniqueDetail(BuildContext context, DetectedTechnique detection) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0A0E21),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                TechniqueDetailCard(
                  technique: detection.technique,
                  detection: detection,
                  onClose: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Detection card widget
class _DetectionCard extends StatelessWidget {
  final DetectedTechnique detection;
  final VoidCallback? onTap;

  const _DetectionCard({
    required this.detection,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      tintColor: Colors.red,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(51),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const DuotoneIcon(
              'danger_triangle',
              size: 20,
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(51),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        detection.technique.id,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        detection.technique.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Source: ${detection.source}',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 11,
                  ),
                ),
                Text(
                  'Confidence: ${(detection.confidence * 100).toInt()}%',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          DuotoneIcon(
            'alt_arrow_right',
            size: 24,
            color: Colors.grey[600],
          ),
        ],
      ),
    );
  }
}
