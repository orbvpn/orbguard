/// Threat Graph Screen
/// Threat correlation and relationship visualization interface

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';

class ThreatGraphScreen extends StatefulWidget {
  const ThreatGraphScreen({super.key});

  @override
  State<ThreatGraphScreen> createState() => _ThreatGraphScreenState();
}

class _ThreatGraphScreenState extends State<ThreatGraphScreen> {
  bool _isLoading = false;
  String _selectedEntity = '';
  final List<GraphNode> _nodes = [];
  final List<GraphRelation> _relations = [];

  @override
  void initState() {
    super.initState();
    _loadGraphData();
  }

  Future<void> _loadGraphData() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _nodes.addAll(_getSampleNodes());
      _relations.addAll(_getSampleRelations());
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Threat Graph',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : Column(
              children: [
                // Actions row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: DuotoneIcon(AppIcons.search, size: 22, color: Colors.white),
                        onPressed: () => _showSearchDialog(context),
                        tooltip: 'Search',
                      ),
                      IconButton(
                        icon: DuotoneIcon(AppIcons.refresh, size: 22, color: Colors.white),
                        onPressed: _isLoading ? null : _loadGraphData,
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                ),
                // Graph visualization placeholder
                Expanded(
                  flex: 2,
                  child: _buildGraphVisualization(),
                ),
                // Entity details
                Expanded(
                  flex: 3,
                  child: _buildEntityList(),
                ),
              ],
            ),
    );
  }

  Widget _buildGraphVisualization() {
    return GlassContainer(
      margin: const EdgeInsets.all(16),
      child: Stack(
        children: [
          // Graph placeholder
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DuotoneIcon(AppIcons.structure, size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
                const SizedBox(height: 12),
                const Text(
                  'Threat Relationship Graph',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_nodes.length} entities, ${_relations.length} relationships',
                  style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
                ),
              ],
            ),
          ),
          // Node indicators
          Positioned(
            top: 20,
            left: 20,
            child: _buildNodeIndicator('Indicators', _nodes.where((n) => n.type == 'indicator').length, GlassTheme.errorColor),
          ),
          Positioned(
            top: 20,
            right: 20,
            child: _buildNodeIndicator('Campaigns', _nodes.where((n) => n.type == 'campaign').length, GlassTheme.warningColor),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            child: _buildNodeIndicator('Actors', _nodes.where((n) => n.type == 'actor').length, const Color(0xFF9C27B0)),
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: _buildNodeIndicator('Malware', _nodes.where((n) => n.type == 'malware').length, const Color(0xFF2196F3)),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeIndicator(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(100), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('$label: $count', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildEntityList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const GlassSectionHeader(title: 'Related Entities'),
        ...(_selectedEntity.isEmpty ? _nodes.take(10) : _nodes).map(_buildEntityCard),
      ],
    );
  }

  Widget _buildEntityCard(GraphNode node) {
    final color = _getNodeColor(node.type);

    return GlassCard(
      onTap: () => _showEntityDetails(context, node),
      child: Row(
        children: [
          GlassSvgIconBox(
            icon: _getNodeIcon(node.type),
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
                Text(
                  node.type.toUpperCase(),
                  style: TextStyle(color: color, fontSize: 10),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${node.relationCount} relations',
                style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11),
              ),
              if (node.confidence != null)
                Text(
                  '${(node.confidence! * 100).toInt()}% conf',
                  style: TextStyle(color: GlassTheme.primaryAccent, fontSize: 10),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEntityDetails(BuildContext context, GraphNode node) {
    final color = _getNodeColor(node.type);
    final relatedNodes = _relations
        .where((r) => r.sourceId == node.id || r.targetId == node.id)
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
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
              // Header
              Row(
                children: [
                  GlassSvgIconBox(icon: _getNodeIcon(node.type), color: color, size: 56, iconSize: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        GlassBadge(text: node.type.toUpperCase(), color: color),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Details
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Type', node.type),
                    _buildDetailRow('Relations', '${node.relationCount}'),
                    if (node.confidence != null)
                      _buildDetailRow('Confidence', '${(node.confidence! * 100).toInt()}%'),
                    if (node.firstSeen != null)
                      _buildDetailRow('First Seen', _formatDate(node.firstSeen!)),
                  ],
                ),
              ),

              // Related entities
              if (relatedNodes.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Related Entities',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...relatedNodes.map((rel) => _buildRelationCard(rel, node.id)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRelationCard(GraphRelation relation, String currentNodeId) {
    final isSource = relation.sourceId == currentNodeId;
    final relatedNodeId = isSource ? relation.targetId : relation.sourceId;
    final relatedNode = _nodes.firstWhere((n) => n.id == relatedNodeId, orElse: () => _nodes.first);

    return GlassCard(
      child: Row(
        children: [
          GlassSvgIconBox(
            icon: _getNodeIcon(relatedNode.type),
            color: _getNodeColor(relatedNode.type),
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(relatedNode.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                Text(
                  '${isSource ? "→" : "←"} ${relation.relationType}',
                  style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11),
                ),
              ],
            ),
          ),
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

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Search Graph', style: TextStyle(color: Colors.white)),
        content: TextField(
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search indicators, actors, campaigns...',
            hintStyle: TextStyle(color: Colors.white.withAlpha(77)),
            prefixIcon: Padding(
              padding: const EdgeInsets.all(12),
              child: DuotoneIcon(AppIcons.search, size: 20, color: Colors.white54),
            ),
          ),
          onSubmitted: (value) {
            Navigator.pop(context);
            setState(() => _selectedEntity = value);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Color _getNodeColor(String type) {
    switch (type.toLowerCase()) {
      case 'indicator':
        return GlassTheme.errorColor;
      case 'campaign':
        return GlassTheme.warningColor;
      case 'actor':
        return const Color(0xFF9C27B0);
      case 'malware':
        return const Color(0xFF2196F3);
      case 'tool':
        return const Color(0xFF4CAF50);
      default:
        return GlassTheme.primaryAccent;
    }
  }

  String _getNodeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'indicator':
        return AppIcons.ioc;
      case 'campaign':
        return AppIcons.campaign;
      case 'actor':
        return AppIcons.threatActor;
      case 'malware':
        return AppIcons.malware;
      case 'tool':
        return AppIcons.settings;
      default:
        return AppIcons.target;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  List<GraphNode> _getSampleNodes() {
    return [
      GraphNode(id: '1', name: 'APT41', type: 'actor', relationCount: 15, confidence: 0.95, firstSeen: DateTime(2012, 1, 1)),
      GraphNode(id: '2', name: 'PhishHook Campaign', type: 'campaign', relationCount: 28, confidence: 0.88),
      GraphNode(id: '3', name: '185.192.69.x', type: 'indicator', relationCount: 8, confidence: 0.92),
      GraphNode(id: '4', name: 'Cobalt Strike', type: 'malware', relationCount: 42, confidence: 0.99),
      GraphNode(id: '5', name: 'fake-bank.com', type: 'indicator', relationCount: 5, confidence: 0.87),
      GraphNode(id: '6', name: 'Mimikatz', type: 'tool', relationCount: 35, confidence: 0.98),
      GraphNode(id: '7', name: 'FIN7', type: 'actor', relationCount: 22, confidence: 0.91),
      GraphNode(id: '8', name: 'RansomCloud', type: 'campaign', relationCount: 18, confidence: 0.85),
    ];
  }

  List<GraphRelation> _getSampleRelations() {
    return [
      GraphRelation(id: 'r1', sourceId: '1', targetId: '2', relationType: 'attributed-to'),
      GraphRelation(id: 'r2', sourceId: '2', targetId: '3', relationType: 'uses'),
      GraphRelation(id: 'r3', sourceId: '2', targetId: '5', relationType: 'uses'),
      GraphRelation(id: 'r4', sourceId: '1', targetId: '4', relationType: 'uses'),
      GraphRelation(id: 'r5', sourceId: '7', targetId: '4', relationType: 'uses'),
      GraphRelation(id: 'r6', sourceId: '7', targetId: '6', relationType: 'uses'),
      GraphRelation(id: 'r7', sourceId: '8', targetId: '4', relationType: 'uses'),
    ];
  }
}

class GraphNode {
  final String id;
  final String name;
  final String type;
  final int relationCount;
  final double? confidence;
  final DateTime? firstSeen;

  GraphNode({
    required this.id,
    required this.name,
    required this.type,
    required this.relationCount,
    this.confidence,
    this.firstSeen,
  });
}

class GraphRelation {
  final String id;
  final String sourceId;
  final String targetId;
  final String relationType;

  GraphRelation({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.relationType,
  });
}
