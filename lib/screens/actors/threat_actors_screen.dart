/// Threat Actors Screen
/// Threat actor profiles and intelligence interface

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/api/orbguard_api_client.dart';
import '../../models/api/campaign.dart';

class ThreatActorsScreen extends StatefulWidget {
  const ThreatActorsScreen({super.key});

  @override
  State<ThreatActorsScreen> createState() => _ThreatActorsScreenState();
}

class _ThreatActorsScreenState extends State<ThreatActorsScreen> {
  bool _isLoading = true;
  List<ThreatActor> _actors = [];
  String _selectedCategory = 'All';

  final List<String> _categories = ['All', 'APT', 'Cybercrime', 'Hacktivism', 'Nation-State'];

  @override
  void initState() {
    super.initState();
    _loadActors();
  }

  Future<void> _loadActors() async {
    setState(() => _isLoading = true);

    try {
      final response = await OrbGuardApiClient.instance.listActors();
      setState(() {
        _actors = response.items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _actors = _getSampleActors();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredActors = _selectedCategory == 'All'
        ? _actors
        : _actors.where((a) => a.category == _selectedCategory).toList();

    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Threat Actors',
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadActors,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : Column(
              children: [
                // Category filter
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: _categories.map((cat) {
                      final isSelected = cat == _selectedCategory;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _selectedCategory = cat),
                          backgroundColor: GlassTheme.glassColorDark,
                          selectedColor: GlassTheme.primaryAccent.withAlpha(77),
                          labelStyle: TextStyle(
                            color: isSelected ? GlassTheme.primaryAccent : Colors.white70,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                // Actor list
                Expanded(
                  child: filteredActors.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filteredActors.length,
                          itemBuilder: (context, index) {
                            return _buildActorCard(filteredActors[index]);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildActorCard(ThreatActor actor) {
    final sophisticationColor = _getSophisticationColor(actor.sophistication);

    return GlassCard(
      onTap: () => _showActorDetails(context, actor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassIconBox(
                icon: _getCategoryIcon(actor.category),
                color: _getCategoryColor(actor.category),
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      actor.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getCategoryColor(actor.category).withAlpha(40),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            actor.category,
                            style: TextStyle(
                              color: _getCategoryColor(actor.category),
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (actor.countryCode != null)
                          Text(
                            actor.countryCode!,
                            style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GlassBadge(text: actor.sophistication, color: sophisticationColor, fontSize: 10),
                  const SizedBox(height: 4),
                  Text(
                    '${actor.campaignCount} campaigns',
                    style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          if (actor.description != null) ...[
            const SizedBox(height: 12),
            Text(
              actor.description!,
              style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (actor.aliases.isNotEmpty) ...[
                Icon(Icons.label, size: 14, color: Colors.white.withAlpha(102)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    actor.aliases.take(3).join(', '),
                    style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const Spacer(),
              if (actor.isActive)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: GlassTheme.successColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Active',
                      style: TextStyle(color: GlassTheme.successColor, fontSize: 10),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_search, size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
          const SizedBox(height: 16),
          const Text(
            'No Threat Actors',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Threat actor profiles will appear here',
            style: TextStyle(color: Colors.white.withAlpha(153)),
          ),
        ],
      ),
    );
  }

  void _showActorDetails(BuildContext context, ThreatActor actor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
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
              // Header
              Row(
                children: [
                  GlassIconBox(
                    icon: _getCategoryIcon(actor.category),
                    color: _getCategoryColor(actor.category),
                    size: 64,
                    iconSize: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          actor.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            GlassBadge(
                              text: actor.category,
                              color: _getCategoryColor(actor.category),
                            ),
                            const SizedBox(width: 8),
                            if (actor.isActive)
                              const GlassBadge(text: 'Active', color: GlassTheme.successColor),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Description
              if (actor.description != null) ...[
                Text(
                  actor.description!,
                  style: TextStyle(color: Colors.white.withAlpha(204), fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 20),
              ],

              // Details
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Sophistication', actor.sophistication),
                    _buildDetailRow('Campaigns', '${actor.campaignCount} known'),
                    if (actor.countryCode != null)
                      _buildDetailRow('Origin', actor.countryCode!),
                    _buildDetailRow('First Seen', _formatDate(actor.firstSeen)),
                    if (actor.lastSeen != null)
                      _buildDetailRow('Last Seen', _formatDate(actor.lastSeen!)),
                  ],
                ),
              ),

              // Aliases
              if (actor.aliases.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Also Known As',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actor.aliases.map((alias) => GlassBadge(
                        text: alias,
                        color: Colors.white54,
                      )).toList(),
                ),
              ],

              // Motivations
              if (actor.motivations.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Motivations',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actor.motivations.map((m) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9C27B0).withAlpha(40),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(m, style: const TextStyle(color: Color(0xFF9C27B0), fontSize: 12)),
                      )).toList(),
                ),
              ],

              // Targeted Sectors
              if (actor.targetedSectors.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Targeted Sectors',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actor.targetedSectors.map((s) => GlassBadge(
                        text: s,
                        color: GlassTheme.warningColor,
                      )).toList(),
                ),
              ],

              // TTPs
              if (actor.ttps.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'MITRE ATT&CK TTPs',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actor.ttps.map((ttp) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: GlassTheme.primaryAccent.withAlpha(40),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          ttp,
                          style: const TextStyle(
                            color: GlassTheme.primaryAccent,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      )).toList(),
                ),
              ],
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
        title: const Text('Search Actors', style: TextStyle(color: Colors.white)),
        content: TextField(
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter actor name or alias...',
            hintStyle: TextStyle(color: Colors.white.withAlpha(77)),
            prefixIcon: const Icon(Icons.search, color: Colors.white54),
          ),
          onSubmitted: (value) {
            Navigator.pop(context);
            // Implement search
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'apt':
        return GlassTheme.errorColor;
      case 'cybercrime':
        return const Color(0xFFFF9800);
      case 'hacktivism':
        return const Color(0xFF4CAF50);
      case 'nation-state':
        return const Color(0xFF9C27B0);
      default:
        return GlassTheme.primaryAccent;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'apt':
        return Icons.security;
      case 'cybercrime':
        return Icons.attach_money;
      case 'hacktivism':
        return Icons.public;
      case 'nation-state':
        return Icons.flag;
      default:
        return Icons.person;
    }
  }

  Color _getSophisticationColor(String level) {
    switch (level.toLowerCase()) {
      case 'expert':
        return GlassTheme.errorColor;
      case 'advanced':
        return const Color(0xFFFF5722);
      case 'intermediate':
        return GlassTheme.warningColor;
      case 'basic':
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.year}';
  }

  List<ThreatActor> _getSampleActors() {
    return [
      ThreatActor(
        id: '1',
        name: 'APT41',
        category: 'APT',
        description: 'Chinese state-sponsored threat group known for espionage and financially motivated operations.',
        sophistication: 'Expert',
        isActive: true,
        countryCode: 'CN',
        firstSeen: DateTime(2012, 1, 1),
        lastSeen: DateTime.now(),
        campaignCount: 28,
        aliases: ['Double Dragon', 'Winnti', 'Barium'],
        motivations: ['Espionage', 'Financial Gain'],
        targetedSectors: ['Technology', 'Healthcare', 'Gaming'],
        ttps: ['T1566', 'T1195', 'T1027', 'T1059'],
      ),
      ThreatActor(
        id: '2',
        name: 'FIN7',
        category: 'Cybercrime',
        description: 'Financially motivated threat group targeting retail and hospitality sectors.',
        sophistication: 'Advanced',
        isActive: true,
        firstSeen: DateTime(2015, 1, 1),
        lastSeen: DateTime.now(),
        campaignCount: 42,
        aliases: ['Carbanak', 'Navigator Group'],
        motivations: ['Financial Gain'],
        targetedSectors: ['Retail', 'Hospitality', 'Financial'],
        ttps: ['T1566.001', 'T1204', 'T1059.001'],
      ),
      ThreatActor(
        id: '3',
        name: 'Lazarus Group',
        category: 'Nation-State',
        description: 'North Korean state-sponsored group responsible for high-profile attacks.',
        sophistication: 'Expert',
        isActive: true,
        countryCode: 'KP',
        firstSeen: DateTime(2009, 1, 1),
        lastSeen: DateTime.now(),
        campaignCount: 35,
        aliases: ['Hidden Cobra', 'Guardians of Peace', 'ZINC'],
        motivations: ['Financial Gain', 'Espionage', 'Sabotage'],
        targetedSectors: ['Financial', 'Cryptocurrency', 'Defense'],
        ttps: ['T1566', 'T1486', 'T1059', 'T1071'],
      ),
      ThreatActor(
        id: '4',
        name: 'Anonymous',
        category: 'Hacktivism',
        description: 'Decentralized hacktivist collective known for DDoS attacks and data leaks.',
        sophistication: 'Intermediate',
        isActive: true,
        firstSeen: DateTime(2003, 1, 1),
        campaignCount: 100,
        aliases: ['Anon', 'Legion'],
        motivations: ['Ideology', 'Political'],
        targetedSectors: ['Government', 'Corporate'],
        ttps: ['T1498', 'T1499', 'T1491'],
      ),
    ];
  }
}
