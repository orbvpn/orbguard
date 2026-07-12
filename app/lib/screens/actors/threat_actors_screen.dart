/// Threat Actors Screen
/// Threat actor profiles and intelligence interface
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/api/orbguard_api_client.dart';
import '../../models/api/campaign.dart';
import '../../models/api/threat_indicator.dart';

class ThreatActorsScreen extends StatefulWidget {
  const ThreatActorsScreen({super.key});

  @override
  State<ThreatActorsScreen> createState() => _ThreatActorsScreenState();
}

class _ThreatActorsScreenState extends State<ThreatActorsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<ThreatActor> _actors = [];
  String _selectedCategory = 'All';

  final List<String> _categories = ['All', 'APT', 'Cybercrime', 'Hacktivism', 'Nation-State'];

  @override
  void initState() {
    super.initState();
    _loadActors();
  }

  Future<void> _loadActors() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await OrbGuardApiClient.instance.listActors();
      setState(() {
        _actors = response.items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load threat actors. Please try again.';
      });
    }
  }

  String _getActorCategory(ThreatActor actor) {
    switch (actor.type) {
      case ActorType.nationState:
        return 'Nation-State';
      case ActorType.criminalGroup:
        return 'Cybercrime';
      case ActorType.hacktivist:
        return 'Hacktivism';
      case ActorType.insider:
        return 'APT';
      case ActorType.unknown:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredActors = _selectedCategory == 'All'
        ? _actors
        : _actors.where((a) => _getActorCategory(a) == _selectedCategory).toList();

    return GlassPage(
      title: 'Threat Actors',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : _errorMessage != null
              ? _buildErrorState()
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
                        onPressed: _isLoading ? null : _loadActors,
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                ),
                // Category filter
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
    final category = _getActorCategory(actor);
    final sophisticationColor = _getSophisticationColor(actor.sophisticationLevel);

    return GlassCard(
      onTap: () => _showActorDetails(context, actor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: _getCategoryIcon(category),
                color: _getCategoryColor(category),
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
                            color: _getCategoryColor(category).withAlpha(40),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              color: _getCategoryColor(category),
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (actor.country != null)
                          Text(
                            actor.country!,
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
                  GlassBadge(text: actor.sophisticationLevel.value.toUpperCase(), color: sophisticationColor, fontSize: 10),
                  const SizedBox(height: 4),
                  Text(
                    '${actor.associatedCampaigns.length} campaigns',
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
                DuotoneIcon(AppIcons.tag, size: 14, color: Colors.white.withAlpha(102)),
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
          DuotoneIcon(AppIcons.threatActor, size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
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

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuotoneIcon(AppIcons.warning, size: 64, color: GlassTheme.errorColor.withAlpha(179)),
            const SizedBox(height: 16),
            const Text(
              'Error Loading Data',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'An unexpected error occurred',
              style: TextStyle(color: Colors.white.withAlpha(153)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadActors,
              icon: DuotoneIcon(AppIcons.refresh, size: 18, color: Colors.white),
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

  void _showActorDetails(BuildContext context, ThreatActor actor) {
    final category = _getActorCategory(actor);

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
                  GlassSvgIconBox(
                    icon: _getCategoryIcon(category),
                    color: _getCategoryColor(category),
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
                              text: category,
                              color: _getCategoryColor(category),
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
                    _buildDetailRow('Sophistication', actor.sophisticationLevel.value.toUpperCase()),
                    _buildDetailRow('Campaigns', '${actor.associatedCampaigns.length} known'),
                    if (actor.country != null)
                      _buildDetailRow('Origin', actor.country!),
                    if (actor.firstSeen != null)
                      _buildDetailRow('First Seen', _formatDate(actor.firstSeen!)),
                    if (actor.lastSeen != null)
                      _buildDetailRow('Last Seen', _formatDate(actor.lastSeen!)),
                    _buildDetailRow('Indicators', '${actor.indicatorCount}'),
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
                        child: Text(m.value, style: const TextStyle(color: Color(0xFF9C27B0), fontSize: 12)),
                      )).toList(),
                ),
              ],

              // Targeted Industries
              if (actor.targetedIndustries.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Targeted Industries',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actor.targetedIndustries.map((s) => GlassBadge(
                        text: s,
                        color: GlassTheme.warningColor,
                      )).toList(),
                ),
              ],

              // MITRE Techniques
              if (actor.mitreTechniques.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'MITRE ATT&CK TTPs',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actor.mitreTechniques.map((ttp) => Container(
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

              // Tools
              if (actor.tools.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Known Tools',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actor.tools.map((tool) => GlassBadge(
                        text: tool,
                        color: const Color(0xFFFF5722),
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
            prefixIcon: Padding(
              padding: const EdgeInsets.all(12),
              child: DuotoneIcon(AppIcons.search, size: 20, color: Colors.white54),
            ),
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

  String _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'apt':
        return AppIcons.shieldCheck;
      case 'cybercrime':
        return AppIcons.dollar;
      case 'hacktivism':
        return AppIcons.global;
      case 'nation-state':
        return AppIcons.flag;
      default:
        return AppIcons.user;
    }
  }

  Color _getSophisticationColor(SeverityLevel level) {
    switch (level) {
      case SeverityLevel.critical:
        return GlassTheme.errorColor;
      case SeverityLevel.high:
        return const Color(0xFFFF5722);
      case SeverityLevel.medium:
        return GlassTheme.warningColor;
      case SeverityLevel.low:
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.year}';
  }
}
