/// Threat Graph Screen
/// Threat correlation and relationship visualization interface.
///
/// Wire format: GET /graph/nodes returns {nodes: [{id, label, type,
/// properties}], count} and GET /graph/relations returns {relations:
/// [{id, from, to, type, properties}], count} (orbguard.lab
/// internal/infrastructure/graph/explore.go NodeView/RelationView). Both
/// answer 503 when the deployment has no Neo4j — surfaced as an explicit
/// error state, never an empty fake graph.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/threat_hunting_provider.dart';

/// Maximum number of nodes rendered in the visualization. The highest-degree
/// nodes are preferred; a "showing N of M" note is displayed when capped.
const int kGraphRenderCap = 60;

class ThreatGraphScreen extends StatefulWidget {
  const ThreatGraphScreen({super.key});

  @override
  State<ThreatGraphScreen> createState() => _ThreatGraphScreenState();
}

class _ThreatGraphScreenState extends State<ThreatGraphScreen> {
  List<GraphNode> _nodes = [];
  List<GraphRelation> _relations = [];
  _GraphLayout? _layout;
  String _dataSignature = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ThreatHuntingProvider>().loadGraphData();
    });
  }

  /// Re-parse provider data and recompute the layout only when the
  /// underlying node/relation sets actually changed.
  void _syncFromProvider(ThreatHuntingProvider provider) {
    final signature =
        '${provider.graphNodes.length}:${provider.graphRelations.length}:'
        '${provider.graphNodes.isNotEmpty ? provider.graphNodes.first['id'] : ''}:'
        '${provider.graphRelations.isNotEmpty ? provider.graphRelations.first['id'] : ''}';
    if (signature == _dataSignature) return;
    _dataSignature = signature;

    final relations = provider.graphRelations
        .map(GraphRelation.fromJson)
        .where((r) => r.sourceId.isNotEmpty && r.targetId.isNotEmpty)
        .toList();

    // Degree per node id, used for relation counts and render priority.
    final degree = <String, int>{};
    for (final rel in relations) {
      degree[rel.sourceId] = (degree[rel.sourceId] ?? 0) + 1;
      degree[rel.targetId] = (degree[rel.targetId] ?? 0) + 1;
    }

    final nodes = provider.graphNodes
        .map((json) => GraphNode.fromJson(json, degree))
        .where((n) => n.id.isNotEmpty)
        .toList()
      ..sort((a, b) => b.relationCount.compareTo(a.relationCount));

    _nodes = nodes;
    _relations = relations;
    _layout = nodes.isEmpty
        ? null
        : _GraphLayout.compute(
            nodes.take(kGraphRenderCap).toList(),
            relations,
          );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThreatHuntingProvider>(
      builder: (context, provider, child) {
        _syncFromProvider(provider);

        return GlassPage(
          title: 'Threat Graph',
          body: provider.isLoadingGraph
              ? const Center(
                  child: CircularProgressIndicator(
                      color: GlassTheme.primaryAccent))
              : Column(
                  children: [
                    // Actions row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: DuotoneIcon(AppIcons.search,
                                size: 22, color: Colors.white),
                            onPressed: () =>
                                _showSearchDialog(context, provider),
                            tooltip: 'Search',
                          ),
                          IconButton(
                            icon: DuotoneIcon(AppIcons.refresh,
                                size: 22, color: Colors.white),
                            onPressed: provider.isLoadingGraph
                                ? null
                                : () => provider.loadGraphData(),
                            tooltip: 'Refresh',
                          ),
                        ],
                      ),
                    ),
                    if (provider.graphError != null)
                      Expanded(child: _buildErrorState(provider))
                    else if (_nodes.isEmpty)
                      Expanded(child: _buildEmptyState())
                    else ...[
                      // Graph visualization
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
                  ],
                ),
        );
      },
    );
  }

  Widget _buildErrorState(ThreatHuntingProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuotoneIcon(AppIcons.dangerTriangle,
                size: 56, color: GlassTheme.errorColor),
            const SizedBox(height: 16),
            const Text(
              'Graph Unavailable',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              provider.graphError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => provider.loadGraphData(),
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(AppIcons.structure,
              size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
          const SizedBox(height: 16),
          const Text(
            'No Graph Data',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'The threat graph has no nodes yet — indicators, campaigns and '
            'actors appear here once they are synced to the graph database.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildGraphVisualization() {
    final layout = _layout;
    if (layout == null) return const SizedBox.shrink();

    final renderedCount = layout.nodes.length;
    final totalCount = _nodes.length;

    return GlassContainer(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size =
                    Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  onTapUp: (details) =>
                      _onGraphTap(details.localPosition, size, layout),
                  child: CustomPaint(
                    size: size,
                    painter: _ThreatGraphPainter(
                      layout: layout,
                      nodeColor: _getNodeColor,
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  renderedCount < totalCount
                      ? 'Showing $renderedCount of $totalCount entities '
                          '(${_relations.length} relationships)'
                      : '$totalCount entities, ${_relations.length} relationships',
                  style:
                      TextStyle(color: Colors.white.withAlpha(128), fontSize: 11),
                ),
                Text(
                  'Tap a node for details',
                  style:
                      TextStyle(color: Colors.white.withAlpha(102), fontSize: 11),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: _legendEntries()
                  .map((e) => _buildLegendDot(e.$1, e.$2))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Legend entries for node types actually present in the rendered graph.
  List<(String, Color)> _legendEntries() {
    final types = <String>{};
    for (final node in _layout?.nodes ?? const <GraphNode>[]) {
      types.add(node.type.toLowerCase());
    }
    return types.map((t) => (_displayType(t), _getNodeColor(t))).toList();
  }

  Widget _buildLegendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 10)),
      ],
    );
  }

  void _onGraphTap(Offset position, Size size, _GraphLayout layout) {
    GraphNode? hit;
    double bestDistance = 24; // touch slop in px
    for (var i = 0; i < layout.nodes.length; i++) {
      final p = layout.scaledPosition(i, size);
      final d = (p - position).distance;
      if (d < bestDistance) {
        bestDistance = d;
        hit = layout.nodes[i];
      }
    }
    if (hit != null) {
      _showEntityDetails(context, hit);
    }
  }

  Widget _buildEntityList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const GlassSectionHeader(title: 'Entities'),
        ..._nodes.take(50).map(_buildEntityCard),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500),
                ),
                Text(
                  _displayType(node.type).toUpperCase(),
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
                style:
                    TextStyle(color: Colors.white.withAlpha(128), fontSize: 11),
              ),
              if (node.confidence != null)
                Text(
                  '${(node.confidence! * 100).toInt()}% conf',
                  style: TextStyle(
                      color: GlassTheme.primaryAccent, fontSize: 10),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEntityDetails(BuildContext context, GraphNode node) {
    final color = _getNodeColor(node.type);
    final relatedRelations = _relations
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
                  GlassSvgIconBox(
                      icon: _getNodeIcon(node.type),
                      color: color,
                      size: 56,
                      iconSize: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        GlassBadge(
                            text: _displayType(node.type).toUpperCase(),
                            color: color),
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
                    _buildDetailRow('Type', _displayType(node.type)),
                    _buildDetailRow('Relations', '${node.relationCount}'),
                    if (node.confidence != null)
                      _buildDetailRow('Confidence',
                          '${(node.confidence! * 100).toInt()}%'),
                    if (node.firstSeen != null)
                      _buildDetailRow('First Seen', _formatDate(node.firstSeen!)),
                  ],
                ),
              ),

              // Raw graph properties (real data from Neo4j)
              if (node.properties.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Properties',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                GlassContainer(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: node.properties.entries
                        .take(12)
                        .map((e) =>
                            _buildDetailRow(e.key, '${e.value}'))
                        .toList(),
                  ),
                ),
              ],

              // Related entities
              if (relatedRelations.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Related Entities',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...relatedRelations.map((rel) => _buildRelationCard(rel, node.id)),
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
    final relatedNode = _nodes
        .where((n) => n.id == relatedNodeId)
        .firstOrNull;

    return GlassCard(
      onTap: relatedNode == null
          ? null
          : () {
              Navigator.pop(context);
              _showEntityDetails(context, relatedNode);
            },
      child: Row(
        children: [
          GlassSvgIconBox(
            icon: _getNodeIcon(relatedNode?.type ?? 'unknown'),
            color: _getNodeColor(relatedNode?.type ?? 'unknown'),
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  relatedNode?.name ?? relatedNodeId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500),
                ),
                Text(
                  '${isSource ? "→" : "←"} ${relation.relationType}',
                  style: TextStyle(
                      color: Colors.white.withAlpha(128), fontSize: 11),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withAlpha(153))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showSearchDialog(
      BuildContext context, ThreatHuntingProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title:
            const Text('Search Graph', style: TextStyle(color: Colors.white)),
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
            // Server-side search over value/name/id.
            provider.loadGraphData(
                query: value.trim().isEmpty ? null : value.trim());
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
        ],
      ),
    );
  }

  /// Maps the Neo4j node label (e.g. "Indicator", "ThreatActor") to a
  /// human-friendly display name.
  String _displayType(String type) {
    switch (type.toLowerCase()) {
      case 'threatactor':
        return 'Actor';
      case 'indicator':
        return 'Indicator';
      case 'campaign':
        return 'Campaign';
      case 'malware':
        return 'Malware';
      case 'tool':
        return 'Tool';
      default:
        return type;
    }
  }

  Color _getNodeColor(String type) {
    switch (type.toLowerCase()) {
      case 'indicator':
        return GlassTheme.errorColor;
      case 'campaign':
        return GlassTheme.warningColor;
      case 'actor':
      case 'threatactor':
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
      case 'threatactor':
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
}

/// Parsed view of a backend NodeView ({id, label, type, properties}).
class GraphNode {
  final String id;
  final String name;
  final String type;
  final int relationCount;
  final double? confidence;
  final DateTime? firstSeen;
  final Map<String, dynamic> properties;

  GraphNode({
    required this.id,
    required this.name,
    required this.type,
    required this.relationCount,
    this.confidence,
    this.firstSeen,
    this.properties = const {},
  });

  factory GraphNode.fromJson(
      Map<String, dynamic> json, Map<String, int> degreeById) {
    final id = json['id'] as String? ?? '';
    final properties = (json['properties'] is Map)
        ? Map<String, dynamic>.from(json['properties'] as Map)
        : <String, dynamic>{};

    final name = (properties['value'] as String?) ??
        (properties['name'] as String?) ??
        (json['label'] as String?) ??
        id;

    return GraphNode(
      id: id,
      name: name,
      type: json['type'] as String? ?? json['label'] as String? ?? 'unknown',
      relationCount: degreeById[id] ?? 0,
      confidence: (properties['confidence'] as num?)?.toDouble(),
      firstSeen: _parseGraphTime(
          properties['first_seen'] ?? properties['created_at']),
      properties: properties,
    );
  }

  /// Neo4j properties may carry timestamps as ISO strings or epoch numbers
  /// (seconds or milliseconds).
  static DateTime? _parseGraphTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is num) {
      final v = raw.toInt();
      if (v <= 0) return null;
      // Heuristic: ms timestamps are > 10^12 for any modern date.
      return DateTime.fromMillisecondsSinceEpoch(v > 1000000000000 ? v : v * 1000);
    }
    return null;
  }
}

/// Parsed view of a backend RelationView ({id, from, to, type, properties}).
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

  factory GraphRelation.fromJson(Map<String, dynamic> json) {
    return GraphRelation(
      id: json['id'] as String? ?? '',
      sourceId:
          json['from'] as String? ?? json['source_id'] as String? ?? '',
      targetId: json['to'] as String? ?? json['target_id'] as String? ?? '',
      relationType: json['type'] as String? ??
          json['relation_type'] as String? ??
          'related',
    );
  }
}

/// Deterministic force-directed layout for the rendered subset of the graph.
/// Positions are computed once per data change in normalized [0,1]² space and
/// scaled to the canvas at paint time.
class _GraphLayout {
  final List<GraphNode> nodes;
  final List<Offset> positions; // normalized 0..1
  final List<(int, int, String)> edges; // index pairs + relation type
  final Map<String, int> indexById;

  _GraphLayout._(this.nodes, this.positions, this.edges, this.indexById);

  static _GraphLayout compute(
      List<GraphNode> nodes, List<GraphRelation> relations) {
    final indexById = <String, int>{
      for (var i = 0; i < nodes.length; i++) nodes[i].id: i,
    };

    final edges = <(int, int, String)>[];
    for (final rel in relations) {
      final a = indexById[rel.sourceId];
      final b = indexById[rel.targetId];
      if (a != null && b != null && a != b) {
        edges.add((a, b, rel.relationType));
      }
    }

    final n = nodes.length;
    // Deterministic initial positions on a circle, jittered by id hash.
    final positions = List<Offset>.generate(n, (i) {
      final angle = 2 * math.pi * i / n;
      final jitter = (nodes[i].id.hashCode % 1000) / 1000 * 0.1;
      final r = 0.35 + jitter;
      return Offset(0.5 + r * math.cos(angle), 0.5 + r * math.sin(angle));
    });

    if (n > 1) {
      // Fruchterman–Reingold style iterations in unit space.
      final k = math.sqrt(1.0 / n); // ideal edge length
      var temperature = 0.10;
      const iterations = 150;

      for (var iter = 0; iter < iterations; iter++) {
        final disp = List<Offset>.filled(n, Offset.zero);

        // Repulsive forces between all pairs.
        for (var i = 0; i < n; i++) {
          for (var j = i + 1; j < n; j++) {
            var delta = positions[i] - positions[j];
            var dist = delta.distance;
            if (dist < 1e-6) {
              // Deterministic tiny separation for coincident points.
              delta = Offset((i - j) * 1e-4, (j - i) * 1e-4);
              dist = delta.distance;
            }
            final force = (k * k) / dist;
            final push = delta / dist * force;
            disp[i] += push;
            disp[j] -= push;
          }
        }

        // Attractive forces along edges.
        for (final (a, b, _) in edges) {
          var delta = positions[a] - positions[b];
          final dist = math.max(delta.distance, 1e-6);
          final force = (dist * dist) / k;
          final pull = delta / dist * force;
          disp[a] -= pull;
          disp[b] += pull;
        }

        // Apply displacement limited by temperature; keep inside bounds.
        for (var i = 0; i < n; i++) {
          final d = disp[i];
          final len = d.distance;
          if (len < 1e-9) continue;
          final limited = d / len * math.min(len, temperature);
          positions[i] = Offset(
            (positions[i].dx + limited.dx).clamp(0.05, 0.95),
            (positions[i].dy + limited.dy).clamp(0.05, 0.95),
          );
        }

        temperature *= 0.96; // cool down
      }
    } else if (n == 1) {
      positions[0] = const Offset(0.5, 0.5);
    }

    return _GraphLayout._(nodes, positions, edges, indexById);
  }

  Offset scaledPosition(int index, Size size) {
    final p = positions[index];
    return Offset(p.dx * size.width, p.dy * size.height);
  }
}

/// Paints the force-directed threat graph: edges first, then nodes sized by
/// degree and colored by entity type, with labels when the graph is small.
class _ThreatGraphPainter extends CustomPainter {
  final _GraphLayout layout;
  final Color Function(String type) nodeColor;

  _ThreatGraphPainter({required this.layout, required this.nodeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final edgePaint = Paint()
      ..color = Colors.white.withAlpha(46)
      ..strokeWidth = 1;

    for (final (a, b, _) in layout.edges) {
      canvas.drawLine(
        layout.scaledPosition(a, size),
        layout.scaledPosition(b, size),
        edgePaint,
      );
    }

    final showLabels = layout.nodes.length <= 25;
    for (var i = 0; i < layout.nodes.length; i++) {
      final node = layout.nodes[i];
      final center = layout.scaledPosition(i, size);
      final color = nodeColor(node.type);
      final radius =
          (4.0 + math.min(node.relationCount, 12) * 0.8).clamp(4.0, 14.0);

      canvas.drawCircle(
        center,
        radius + 3,
        Paint()..color = color.withAlpha(46),
      );
      canvas.drawCircle(center, radius, Paint()..color = color);

      if (showLabels) {
        final label = node.name.length > 18
            ? '${node.name.substring(0, 16)}…'
            : node.name;
        final textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: Colors.white.withAlpha(179),
              fontSize: 9,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 120);
        textPainter.paint(
          canvas,
          center + Offset(-textPainter.width / 2, radius + 4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ThreatGraphPainter oldDelegate) =>
      oldDelegate.layout != layout;
}
