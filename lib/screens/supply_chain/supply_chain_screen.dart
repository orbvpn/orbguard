/// Supply Chain Monitor Screen
/// Monitors app dependencies for vulnerabilities and trackers

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../providers/supply_chain_provider.dart';
import '../../services/security/supply_chain_monitor_service.dart';

class SupplyChainScreen extends StatefulWidget {
  const SupplyChainScreen({super.key});

  @override
  State<SupplyChainScreen> createState() => _SupplyChainScreenState();
}

class _SupplyChainScreenState extends State<SupplyChainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SupplyChainProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Supply Chain Monitor',
        showBackButton: true,
        actions: [
          GlassAppBarAction(
            icon: Icons.refresh,
            onTap: () => _startScan(),
          ),
        ],
      ),
      body: Consumer<SupplyChainProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
            );
          }

          return Column(
            children: [
              // Stats summary
              _buildStatsSummary(provider),
              const SizedBox(height: 16),
              // Tab bar
              _buildTabBar(),
              const SizedBox(height: 16),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildVulnerabilitiesTab(provider),
                    _buildTrackersTab(provider),
                    _buildLibrariesTab(provider),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startScan,
        backgroundColor: GlassTheme.primaryAccent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.search),
        label: const Text('Scan Apps'),
      ),
    );
  }

  void _startScan() {
    HapticFeedback.mediumImpact();
    final provider = context.read<SupplyChainProvider>();
    if (!provider.isScanning) {
      provider.scanAllApps();
    }
  }

  Widget _buildStatsSummary(SupplyChainProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Scan progress
          if (provider.isScanning)
            GlassCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: GlassTheme.primaryAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          provider.scanStatus,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: provider.scanProgress,
                      backgroundColor: Colors.white10,
                      color: GlassTheme.primaryAccent,
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            )
          else
            _buildSummaryCard(provider),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(SupplyChainProvider provider) {
    final hasIssues = provider.totalVulnerabilities > 0;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: (hasIssues ? GlassTheme.errorColor : GlassTheme.successColor)
                      .withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  hasIssues ? Icons.warning_rounded : Icons.verified_user,
                  color: hasIssues ? GlassTheme.errorColor : GlassTheme.successColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasIssues
                          ? '${provider.totalVulnerabilities} Vulnerabilities Found'
                          : 'No Vulnerabilities',
                      style: TextStyle(
                        color: hasIssues ? GlassTheme.errorColor : GlassTheme.successColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${provider.totalAppsScanned} apps scanned',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Stats row
          Row(
            children: [
              _buildStatItem(
                'Critical',
                provider.criticalVulnerabilities.toString(),
                GlassTheme.errorColor,
              ),
              _buildStatItem(
                'Trackers',
                provider.totalTrackers.toString(),
                GlassTheme.warningColor,
              ),
              _buildStatItem(
                'High Risk',
                provider.highRiskLibraries.length.toString(),
                const Color(0xFFFF5722),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
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
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: GlassTheme.glassDecoration(),
            child: TabBar(
              controller: _tabController,
              indicatorColor: GlassTheme.primaryAccent,
              labelColor: GlassTheme.primaryAccent,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(icon: Icon(Icons.bug_report), text: 'CVEs'),
                Tab(icon: Icon(Icons.track_changes), text: 'Trackers'),
                Tab(icon: Icon(Icons.library_books), text: 'Libraries'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVulnerabilitiesTab(SupplyChainProvider provider) {
    final vulns = provider.allVulnerabilities;

    if (vulns.isEmpty) {
      return _buildEmptyState(
        Icons.verified_user,
        'No Vulnerabilities',
        'No known vulnerabilities found in your apps',
        GlassTheme.successColor,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: vulns.length,
      itemBuilder: (context, index) => _buildVulnerabilityCard(vulns[index]),
    );
  }

  Widget _buildVulnerabilityCard(Vulnerability vuln) {
    final severityColor = _getSeverityColor(vuln.cvssScore);

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => _showVulnerabilityDetails(vuln),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: severityColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: severityColor.withOpacity(0.3)),
                ),
                child: Text(
                  vuln.cveId,
                  style: TextStyle(
                    color: severityColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: severityColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.speed, size: 14, color: severityColor),
                    const SizedBox(width: 4),
                    Text(
                      vuln.cvssScore.toStringAsFixed(1),
                      style: TextStyle(
                        color: severityColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            vuln.description,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.warning_amber, size: 14, color: Colors.white.withOpacity(0.5)),
              const SizedBox(width: 4),
              Text(
                vuln.severity,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.update, size: 14, color: Colors.white.withOpacity(0.5)),
              const SizedBox(width: 4),
              Text(
                'Affected: ${vuln.affectedVersions}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (vuln.fixedVersion != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: GlassTheme.successColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 14, color: GlassTheme.successColor),
                  const SizedBox(width: 4),
                  Text(
                    'Fixed in ${vuln.fixedVersion}',
                    style: const TextStyle(
                      color: GlassTheme.successColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrackersTab(SupplyChainProvider provider) {
    final trackers = <ThirdPartyLibrary>[];
    for (final result in provider.scanResults) {
      trackers.addAll(result.trackers);
    }

    if (trackers.isEmpty) {
      return _buildEmptyState(
        Icons.privacy_tip,
        'No Trackers Found',
        'No tracking libraries detected in your apps',
        GlassTheme.successColor,
      );
    }

    // Group by category
    final grouped = <LibraryCategory, List<ThirdPartyLibrary>>{};
    for (final tracker in trackers) {
      grouped[tracker.category] ??= [];
      grouped[tracker.category]!.add(tracker);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _getCategoryIcon(entry.key),
                    size: 18,
                    color: GlassTheme.warningColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entry.key.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: GlassTheme.warningColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${entry.value.length}',
                      style: const TextStyle(
                        color: GlassTheme.warningColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...entry.value.map((lib) => _buildTrackerCard(lib)),
            const SizedBox(height: 16),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildTrackerCard(ThirdPartyLibrary lib) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: GlassTheme.warningColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.track_changes,
              color: GlassTheme.warningColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lib.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (lib.vendor != null)
                  Text(
                    lib.vendor!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Color(SupplyChainProvider.getRiskColor(lib.riskLevel))
                  .withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              lib.riskLevel.displayName,
              style: TextStyle(
                color: Color(SupplyChainProvider.getRiskColor(lib.riskLevel)),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibrariesTab(SupplyChainProvider provider) {
    if (provider.librariesByCategory.isEmpty) {
      return _buildEmptyState(
        Icons.library_books,
        'No Libraries Found',
        'Scan your apps to see detected libraries',
        Colors.white54,
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: provider.librariesByCategory.entries.map((entry) {
        return ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: Icon(
            _getCategoryIcon(entry.value.first.category),
            color: GlassTheme.primaryAccent,
          ),
          title: Text(
            entry.key,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: GlassTheme.primaryAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${entry.value.length}',
              style: const TextStyle(
                color: GlassTheme.primaryAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          children: entry.value
              .map((lib) => ListTile(
                    contentPadding: const EdgeInsets.only(left: 16),
                    title: Text(
                      lib.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: lib.vendor != null
                        ? Text(
                            lib.vendor!,
                            style: TextStyle(color: Colors.white.withOpacity(0.5)),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (lib.isKnownTracker)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: GlassTheme.warningColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'TRACKER',
                              style: TextStyle(
                                color: GlassTheme.warningColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Color(SupplyChainProvider.getRiskColor(lib.riskLevel)),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState(
      IconData icon, String title, String subtitle, Color color) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: color.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showVulnerabilityDetails(Vulnerability vuln) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // CVE ID
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _getSeverityColor(vuln.cvssScore).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      vuln.cveId,
                      style: TextStyle(
                        color: _getSeverityColor(vuln.cvssScore),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'CVSS ${vuln.cvssScore.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: _getSeverityColor(vuln.cvssScore),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        vuln.severity,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Description
              const Text(
                'Description',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                vuln.description,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              // Affected versions
              _buildDetailRow('Affected Versions', vuln.affectedVersions),
              if (vuln.fixedVersion != null)
                _buildDetailRow('Fixed Version', vuln.fixedVersion!),
              _buildDetailRow(
                'Published',
                '${vuln.publishedDate.year}-${vuln.publishedDate.month.toString().padLeft(2, '0')}-${vuln.publishedDate.day.toString().padLeft(2, '0')}',
              ),
              if (vuln.exploitAvailable != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: GlassTheme.errorColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: GlassTheme.errorColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_rounded,
                        color: GlassTheme.errorColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          vuln.exploitAvailable!,
                          style: const TextStyle(
                            color: GlassTheme.errorColor,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // References
              if (vuln.references.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  'References',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...vuln.references.map((ref) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.link,
                            size: 14,
                            color: GlassTheme.primaryAccent.withOpacity(0.7),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ref,
                              style: TextStyle(
                                color: GlassTheme.primaryAccent.withOpacity(0.7),
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getSeverityColor(double cvss) {
    if (cvss >= 9.0) return GlassTheme.errorColor;
    if (cvss >= 7.0) return const Color(0xFFFF5722);
    if (cvss >= 4.0) return GlassTheme.warningColor;
    return const Color(0xFFFFEB3B);
  }

  IconData _getCategoryIcon(LibraryCategory category) {
    switch (category) {
      case LibraryCategory.analytics:
        return Icons.analytics;
      case LibraryCategory.advertising:
        return Icons.campaign;
      case LibraryCategory.crashReporting:
        return Icons.bug_report;
      case LibraryCategory.authentication:
        return Icons.fingerprint;
      case LibraryCategory.payment:
        return Icons.payment;
      case LibraryCategory.socialMedia:
        return Icons.share;
      case LibraryCategory.cloud:
        return Icons.cloud;
      case LibraryCategory.database:
        return Icons.storage;
      case LibraryCategory.networking:
        return Icons.wifi;
      case LibraryCategory.security:
        return Icons.security;
      case LibraryCategory.ui:
        return Icons.palette;
      case LibraryCategory.utility:
        return Icons.build;
      case LibraryCategory.malicious:
        return Icons.dangerous;
      case LibraryCategory.unknown:
        return Icons.help_outline;
    }
  }
}
