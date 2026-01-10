/// App Security Screen
/// Main screen for app security analysis and privacy audit

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/app_security_provider.dart';
import '../../widgets/app_security/app_security_widgets.dart';

class AppSecurityScreen extends StatelessWidget {
  const AppSecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSecurityProvider>(
      builder: (context, provider, child) {
        return GlassTabPage(
          title: 'App Security',
          hasSearch: true,
          searchHint: 'Search apps...',
          headerContent: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PopupMenuButton<AppSortOption>(
                  icon: const DuotoneIcon('sort_vertical', size: 24, color: Colors.white),
                  color: GlassTheme.gradientTop,
                  onSelected: (option) {
                    context.read<AppSecurityProvider>().setSortOption(option);
                  },
                  itemBuilder: (context) {
                    final currentSort =
                        context.read<AppSecurityProvider>().sortOption;
                    return AppSortOption.values.map((option) {
                      return PopupMenuItem(
                        value: option,
                        child: Row(
                          children: [
                            if (option == currentSort)
                              DuotoneIcon('check_circle', size: 18, color: GlassTheme.primaryAccent)
                            else
                              const SizedBox(width: 18),
                            const SizedBox(width: 8),
                            Text(option.displayName),
                          ],
                        ),
                      );
                    }).toList();
                  },
                ),
              ],
            ),
          ),
          tabs: [
            GlassTab(
              label: 'Apps',
              iconPath: 'widget',
              content: _AppsTab(provider: provider),
            ),
            GlassTab(
              label: 'Risks',
              iconPath: 'danger_triangle',
              content: _RisksTab(provider: provider),
            ),
            GlassTab(
              label: 'Stats',
              iconPath: 'chart',
              content: _StatsTab(provider: provider),
            ),
          ],
        );
      },
    );
  }
}

class _AppsTab extends StatelessWidget {
  final AppSecurityProvider provider;

  const _AppsTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Scan progress / start button
        Padding(
          padding: const EdgeInsets.all(16),
          child: ScanProgressIndicator(
            progress: provider.scanProgress,
            isScanning: provider.isScanning,
            onStart: () => provider.scanAllApps(),
          ),
        ),
        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: AppFilterOption.values.map((option) {
              final isSelected = provider.filterOption == option;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(option.displayName),
                  selected: isSelected,
                  onSelected: (selected) {
                    provider.setFilterOption(option);
                  },
                  backgroundColor: const Color(0xFF2A2B40),
                  selectedColor: const Color(0xFF00D9FF).withAlpha(40),
                  checkmarkColor: const Color(0xFF00D9FF),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? const Color(0xFF00D9FF)
                        : Colors.white70,
                    fontSize: 12,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        // App list
        Expanded(
          child: provider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : provider.apps.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: provider.apps.length,
                      itemBuilder: (context, index) {
                        final app = provider.apps[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppListCard(
                            app: app,
                            onTap: () {
                              provider.selectApp(app.app.packageName);
                              _showAppDetails(context, provider);
                            },
                            onAnalyze: () =>
                                provider.analyzeApp(app.app.packageName),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DuotoneIcon(
            'smartphone',
            size: 64,
            color: Colors.white.withAlpha(31),
          ),
          const SizedBox(height: 16),
          Text(
            'No apps found',
            style: TextStyle(
              color: Colors.white.withAlpha(128),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pull down to refresh',
            style: TextStyle(
              color: Colors.white.withAlpha(77),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  void _showAppDetails(BuildContext context, AppSecurityProvider provider) {
    final app = provider.selectedApp;
    if (app == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
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
              // App header
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2B40),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        app.app.appName.isNotEmpty
                            ? app.app.appName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.app.appName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'v${app.app.version}',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (app.result != null)
                    PrivacyGradeBadge(grade: app.privacyGrade, large: true),
                ],
              ),
              const SizedBox(height: 24),
              // Risk score
              if (app.result != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    RiskScoreGauge(score: app.riskScore),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RiskLevelBadge(level: app.riskLevel),
                        const SizedBox(height: 12),
                        if (app.result!.isKnownMalware)
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withAlpha(40),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DuotoneIcon('bug',
                                    size: 16, color: Colors.red),
                                SizedBox(width: 6),
                                Text(
                                  'Malware Detected',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (app.app.isSideloaded)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withAlpha(40),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DuotoneIcon('download_minimalistic',
                                    size: 16, color: Colors.orange),
                                SizedBox(width: 6),
                                Text(
                                  'Sideloaded',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Warnings
                if (app.result!.warnings.isNotEmpty) ...[
                  const Text(
                    'Warnings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...app.result!.warnings.map((warning) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const DuotoneIcon('danger_triangle',
                                size: 18, color: Colors.orange),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                warning,
                                style: TextStyle(
                                  color: Colors.orange[300],
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 24),
                ],
                // Permissions
                if (app.result!.permissionRisks.isNotEmpty) ...[
                  const Text(
                    'Permissions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...app.result!.permissionRisks.map((perm) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: PermissionChip(
                            permission: perm, showDescription: true),
                      )),
                  const SizedBox(height: 24),
                ],
                // Trackers
                if (app.result!.detectedTrackers.isNotEmpty) ...[
                  Text(
                    'Trackers (${app.result!.detectedTrackers.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...app.result!.detectedTrackers.map((tracker) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TrackerCard(tracker: tracker),
                      )),
                  const SizedBox(height: 24),
                ],
                // Recommendation
                if (app.result!.recommendation != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const DuotoneIcon('lightbulb_bolt', size: 24, color: Colors.blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            app.result!.recommendation!,
                            style: TextStyle(
                              color: Colors.blue[200],
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else ...[
                // Not analyzed yet
                Center(
                  child: Column(
                    children: [
                      DuotoneIcon(
                        'magnifer',
                        size: 48,
                        color: Colors.grey.withAlpha(128),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'App not analyzed yet',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          provider.analyzeApp(app.app.packageName);
                          Navigator.pop(context);
                        },
                        icon: const DuotoneIcon('magnifer', size: 20, color: Colors.black),
                        label: const Text('Analyze Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00D9FF),
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ).whenComplete(() => provider.clearSelectedApp());
  }
}

class _RisksTab extends StatelessWidget {
  final AppSecurityProvider provider;

  const _RisksTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    final highRiskApps = provider.highRiskApps;
    final sideloadedApps = provider.sideloadedApps;
    final appsWithTrackers = provider.appsWithTrackers;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // High risk apps
          if (highRiskApps.isNotEmpty) ...[
            _buildSectionHeader(
              'High Risk Apps',
              'danger_triangle',
              Colors.red,
              highRiskApps.length,
            ),
            const SizedBox(height: 12),
            ...highRiskApps.take(5).map((app) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppListCard(
                    app: app,
                    onTap: () {
                      provider.selectApp(app.app.packageName);
                      _showAppDetails(context, provider);
                    },
                  ),
                )),
            const SizedBox(height: 24),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  DuotoneIcon('check_circle', size: 24, color: Colors.green.withAlpha(178)),
                  const SizedBox(width: 12),
                  const Text(
                    'No high risk apps detected',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          // Sideloaded apps
          if (sideloadedApps.isNotEmpty) ...[
            _buildSectionHeader(
              'Sideloaded Apps',
              'download_minimalistic',
              Colors.orange,
              sideloadedApps.length,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const DuotoneIcon('info_circle', size: 18, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'These apps were installed outside official app stores',
                      style: TextStyle(
                        color: Colors.orange[300],
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ...sideloadedApps.take(5).map((app) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppListCard(
                    app: app,
                    onTap: () {
                      provider.selectApp(app.app.packageName);
                      _showAppDetails(context, provider);
                    },
                  ),
                )),
            const SizedBox(height: 24),
          ],
          // Apps with trackers
          if (appsWithTrackers.isNotEmpty) ...[
            _buildSectionHeader(
              'Apps with Trackers',
              'eye',
              Colors.purple,
              appsWithTrackers.length,
            ),
            const SizedBox(height: 12),
            ...appsWithTrackers.take(5).map((app) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppListCard(
                    app: app,
                    onTap: () {
                      provider.selectApp(app.app.packageName);
                      _showAppDetails(context, provider);
                    },
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
      String title, String svgIcon, Color color, int count) {
    return Row(
      children: [
        DuotoneIcon(svgIcon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withAlpha(40),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  void _showAppDetails(BuildContext context, AppSecurityProvider provider) {
    final app = provider.selectedApp;
    if (app == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
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
              // App header
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2B40),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        app.app.appName.isNotEmpty
                            ? app.app.appName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.app.appName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'v${app.app.version}',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (app.result != null)
                    PrivacyGradeBadge(grade: app.privacyGrade, large: true),
                ],
              ),
              const SizedBox(height: 24),
              // Risk score
              if (app.result != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    RiskScoreGauge(score: app.riskScore),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RiskLevelBadge(level: app.riskLevel),
                        const SizedBox(height: 12),
                        if (app.result!.isKnownMalware)
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withAlpha(40),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DuotoneIcon('bug',
                                    size: 16, color: Colors.red),
                                SizedBox(width: 6),
                                Text(
                                  'Malware Detected',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (app.app.isSideloaded)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withAlpha(40),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DuotoneIcon('download_minimalistic',
                                    size: 16, color: Colors.orange),
                                SizedBox(width: 6),
                                Text(
                                  'Sideloaded',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Warnings
                if (app.result!.warnings.isNotEmpty) ...[
                  const Text(
                    'Warnings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...app.result!.warnings.map((warning) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const DuotoneIcon('danger_triangle',
                                size: 18, color: Colors.orange),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                warning,
                                style: TextStyle(
                                  color: Colors.orange[300],
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 24),
                ],
                // Permissions
                if (app.result!.permissionRisks.isNotEmpty) ...[
                  const Text(
                    'Permissions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...app.result!.permissionRisks.map((perm) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: PermissionChip(
                            permission: perm, showDescription: true),
                      )),
                  const SizedBox(height: 24),
                ],
                // Trackers
                if (app.result!.detectedTrackers.isNotEmpty) ...[
                  Text(
                    'Trackers (${app.result!.detectedTrackers.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...app.result!.detectedTrackers.map((tracker) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TrackerCard(tracker: tracker),
                      )),
                  const SizedBox(height: 24),
                ],
                // Recommendation
                if (app.result!.recommendation != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const DuotoneIcon('lightbulb_bolt', size: 24, color: Colors.blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            app.result!.recommendation!,
                            style: TextStyle(
                              color: Colors.blue[200],
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else ...[
                // Not analyzed yet
                Center(
                  child: Column(
                    children: [
                      DuotoneIcon(
                        'magnifer',
                        size: 48,
                        color: Colors.grey.withAlpha(128),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'App not analyzed yet',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          provider.analyzeApp(app.app.packageName);
                          Navigator.pop(context);
                        },
                        icon: const DuotoneIcon('magnifer', size: 20, color: Colors.black),
                        label: const Text('Analyze Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00D9FF),
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ).whenComplete(() => provider.clearSelectedApp());
  }
}

class _StatsTab extends StatelessWidget {
  final AppSecurityProvider provider;

  const _StatsTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          AppSecurityStatsCard(stats: provider.stats),
          const SizedBox(height: 24),
          // Privacy grade distribution
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Privacy Grade Distribution',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildGradeBar(provider),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Risk breakdown
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Risk Breakdown',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildRiskBreakdown(provider.stats),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeBar(AppSecurityProvider provider) {
    final apps = provider.allApps.where((a) => a.result != null).toList();
    if (apps.isEmpty) {
      return Text(
        'Scan apps to see grade distribution',
        style: TextStyle(color: Colors.grey[500]),
      );
    }

    final gradeCounts = <String, int>{};
    for (final app in apps) {
      final grade = app.privacyGrade;
      gradeCounts[grade] = (gradeCounts[grade] ?? 0) + 1;
    }

    return Row(
      children: ['A', 'B', 'C', 'D', 'F'].map((grade) {
        final count = gradeCounts[grade] ?? 0;
        final percentage = count / apps.length;
        final color = Color(AppSecurityProvider.getPrivacyGradeColor(grade));

        return Expanded(
          child: Column(
            children: [
              Container(
                height: 60,
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: percentage * 60,
                  width: 30,
                  decoration: BoxDecoration(
                    color: color.withAlpha(178),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                grade,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                count.toString(),
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRiskBreakdown(AppSecurityStats stats) {
    final total = stats.highRiskApps + stats.mediumRiskApps + stats.lowRiskApps;
    if (total == 0) {
      return Text(
        'Scan apps to see risk breakdown',
        style: TextStyle(color: Colors.grey[500]),
      );
    }

    return Column(
      children: [
        _buildRiskRow('High Risk', stats.highRiskApps, total, Colors.red),
        const SizedBox(height: 12),
        _buildRiskRow('Medium Risk', stats.mediumRiskApps, total, Colors.orange),
        const SizedBox(height: 12),
        _buildRiskRow('Low Risk', stats.lowRiskApps, total, Colors.green),
      ],
    );
  }

  Widget _buildRiskRow(String label, int count, int total, Color color) {
    final percentage = total > 0 ? count / total : 0.0;

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 30,
          child: Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
