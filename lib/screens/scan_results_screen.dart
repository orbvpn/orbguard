import 'package:flutter/material.dart';
import '../main.dart'; // Import ThreatDetection from main.dart

class ScanResultsScreen extends StatelessWidget {
  final List<ThreatDetection> threats;

  const ScanResultsScreen({super.key, required this.threats});

  @override
  Widget build(BuildContext context) {
    final critical = threats.where((t) => t.severity == 'CRITICAL').toList();
    final high = threats.where((t) => t.severity == 'HIGH').toList();
    final medium = threats.where((t) => t.severity == 'MEDIUM').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Results'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _exportReport(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary Card
          Card(
            color: const Color(0xFF1D1E33),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Threats Detected',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatColumn('Critical', critical.length, Colors.red),
                      _buildStatColumn('High', high.length, Colors.orange),
                      _buildStatColumn('Medium', medium.length, Colors.yellow),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Critical Threats
          if (critical.isNotEmpty) ...[
            const Text(
              '🔴 Critical Threats',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...critical.map((threat) => _buildThreatCard(threat, context)),
            const SizedBox(height: 16),
          ],

          // High Priority Threats
          if (high.isNotEmpty) ...[
            const Text(
              '🟠 High Priority Threats',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...high.map((threat) => _buildThreatCard(threat, context)),
            const SizedBox(height: 16),
          ],

          // Medium Priority Threats
          if (medium.isNotEmpty) ...[
            const Text(
              '🟡 Medium Priority Threats',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...medium.map((threat) => _buildThreatCard(threat, context)),
          ],

          // Action Buttons
          const SizedBox(height: 24),
          if (critical.isNotEmpty || high.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () => _removeAllThreats(context),
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Remove All Threats'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.all(16),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label),
      ],
    );
  }

  Widget _buildThreatCard(ThreatDetection threat, BuildContext context) {
    return Card(
      color: const Color(0xFF1D1E33),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(
          Icons.error,
          color: threat.severity == 'CRITICAL'
              ? Colors.red
              : threat.severity == 'HIGH'
              ? Colors.orange
              : Colors.yellow,
        ),
        title: Text(
          threat.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(threat.description),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Type', threat.type),
                _buildInfoRow('Path', threat.path),
                _buildInfoRow(
                  'Requires Root',
                  threat.requiresRoot ? 'Yes' : 'No',
                ),
                if (threat.metadata.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Additional Details:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...threat.metadata.entries.map(
                    (e) => _buildInfoRow(e.key, e.value.toString()),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _quarantineThreat(threat),
                      child: const Text('Quarantine'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _removeThreat(threat, context),
                      icon: const Icon(Icons.delete),
                      label: const Text('Remove'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text('$label:', style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _exportReport(BuildContext context) {
    // Export report as JSON or PDF
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Report exported')));
  }

  void _removeThreat(ThreatDetection threat, BuildContext context) {
    // Call removal function
  }

  void _quarantineThreat(ThreatDetection threat) {
    // Move to quarantine instead of deleting
  }

  void _removeAllThreats(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove All Threats'),
        content: const Text(
          'Are you sure you want to remove ALL detected threats?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Remove all threats
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove All'),
          ),
        ],
      ),
    );
  }
}
