/// Digital Footprint Screen
/// Data broker removal and personal data exposure tracking interface

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/digital_footprint_provider.dart';

class DigitalFootprintScreen extends StatefulWidget {
  const DigitalFootprintScreen({super.key});

  @override
  State<DigitalFootprintScreen> createState() => _DigitalFootprintScreenState();
}

class _DigitalFootprintScreenState extends State<DigitalFootprintScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DigitalFootprintProvider>().init();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DigitalFootprintProvider>(
      builder: (context, provider, _) {
        return GlassScaffold(
          appBar: GlassAppBar(
            title: 'Digital Footprint',
            actions: [
              GlassAppBarAction(
                svgIcon: AppIcons.refresh,
                onTap: provider.isLoading ? null : () => provider.loadBrokers(),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: GlassTheme.primaryAccent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(text: 'Scan'),
                Tab(text: 'Brokers'),
                Tab(text: 'Requests'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildScanTab(provider),
              _buildBrokersTab(provider),
              _buildRequestsTab(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScanTab(DigitalFootprintProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Privacy Score
          if (provider.lastScan != null) ...[
            _buildPrivacyScoreCard(provider.lastScan!.privacyScore),
            const SizedBox(height: 16),
            // Stats row
            Row(
              children: [
                _buildStatCard('Brokers', provider.totalBrokersFound.toString(), GlassTheme.warningColor),
                const SizedBox(width: 12),
                _buildStatCard('Exposures', provider.totalExposures.toString(), GlassTheme.errorColor),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Scan form
          const Text(
            'Scan Your Digital Footprint',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your information to find where your data is being sold',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Email field
          _buildInputField(
            controller: _emailController,
            label: 'Email Address',
            hint: 'Enter your email',
            svgIcon: AppIcons.letter,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),

          // Name field
          _buildInputField(
            controller: _nameController,
            label: 'Full Name (Optional)',
            hint: 'Enter your name',
            svgIcon: AppIcons.user,
          ),
          const SizedBox(height: 12),

          // Phone field
          _buildInputField(
            controller: _phoneController,
            label: 'Phone Number (Optional)',
            hint: 'Enter your phone',
            svgIcon: AppIcons.smartphone,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 20),

          // Scan button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: provider.isScanning ? null : () => _startScan(provider),
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (provider.isScanning)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  else
                    DuotoneIcon(AppIcons.search, size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(provider.isScanning ? 'Scanning...' : 'Start Scan'),
                ],
              ),
            ),
          ),

          // Progress
          if (provider.isScanning) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: provider.scanProgress,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(GlassTheme.primaryAccent),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scanning ${(provider.scanProgress * 100).toInt()}%...',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],

          // Results
          if (provider.lastScan != null && provider.lastScan!.brokers.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Found on These Sites',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () => _requestBatchRemoval(provider, provider.lastScan!.brokers),
                  child: const Text('Remove All'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...provider.lastScan!.brokers.take(5).map((broker) => _buildBrokerCard(broker, provider)),
          ],
        ],
      ),
    );
  }

  Widget _buildPrivacyScoreCard(int score) {
    final color = score >= 80
        ? GlassTheme.successColor
        : score >= 50
            ? GlassTheme.warningColor
            : GlassTheme.errorColor;

    return GlassCard(
      tintColor: color,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 8,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Text(
                  '$score',
                  style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Privacy Score',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  score >= 80
                      ? 'Your data exposure is minimal'
                      : score >= 50
                          ? 'Your data is moderately exposed'
                          : 'Your data is highly exposed',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String svgIcon,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
        ),
        const SizedBox(height: 6),
        GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: DuotoneIcon(svgIcon, size: 20, color: Colors.white54),
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBrokersTab(DigitalFootprintProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent));
    }

    if (provider.brokers.isEmpty) {
      return _buildEmptyState(
        svgIcon: AppIcons.enterprise,
        title: 'No Data Brokers',
        subtitle: 'Data broker information will appear here',
      );
    }

    final groupedBrokers = <BrokerCategory, List<DataBroker>>{};
    for (final broker in provider.brokers) {
      groupedBrokers.putIfAbsent(broker.category, () => []).add(broker);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: groupedBrokers.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassSectionHeader(title: entry.key.displayName),
            ...entry.value.map((broker) => _buildBrokerCard(broker, provider)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildBrokerCard(DataBroker broker, DigitalFootprintProvider provider) {
    final difficultyColor = broker.difficulty >= 0.7
        ? GlassTheme.errorColor
        : broker.difficulty >= 0.4
            ? GlassTheme.warningColor
            : GlassTheme.successColor;

    return GlassCard(
      onTap: () => _showBrokerDetails(context, broker, provider),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(icon: AppIcons.enterprise, color: _getCategoryColor(broker.category)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      broker.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      broker.website,
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (broker.hasOptOut)
                TextButton(
                  onPressed: provider.isSubmitting
                      ? null
                      : () => provider.requestRemoval(broker),
                  child: const Text('Remove'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildBrokerInfoChip(
                AppIcons.clock,
                '~${broker.estimatedDays} days',
                Colors.white54,
              ),
              const SizedBox(width: 8),
              _buildBrokerInfoChip(
                AppIcons.chartSquare,
                'Difficulty: ${(broker.difficulty * 100).toInt()}%',
                difficultyColor,
              ),
            ],
          ),
          if (broker.dataCollected.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: broker.dataCollected.take(4).map((data) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: GlassTheme.errorColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    data,
                    style: const TextStyle(color: GlassTheme.errorColor, fontSize: 10),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBrokerInfoChip(String svgIcon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(svgIcon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildRequestsTab(DigitalFootprintProvider provider) {
    if (provider.requests.isEmpty) {
      return _buildEmptyState(
        svgIcon: AppIcons.clipboardText,
        title: 'No Removal Requests',
        subtitle: 'Your data removal requests will appear here',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats
        Row(
          children: [
            _buildStatCard('Submitted', provider.requestsSubmitted.toString(), GlassTheme.primaryAccent),
            const SizedBox(width: 12),
            _buildStatCard('Completed', provider.requestsCompleted.toString(), GlassTheme.successColor),
          ],
        ),
        const SizedBox(height: 24),

        // Pending requests
        if (provider.pendingRequests.isNotEmpty) ...[
          const GlassSectionHeader(title: 'Pending'),
          ...provider.pendingRequests.map((request) => _buildRequestCard(request)),
        ],

        // Completed requests
        if (provider.completedRequests.isNotEmpty) ...[
          const GlassSectionHeader(title: 'Completed'),
          ...provider.completedRequests.map((request) => _buildRequestCard(request)),
        ],
      ],
    );
  }

  Widget _buildRequestCard(RemovalRequest request) {
    final statusColor = Color(request.status.color);

    return GlassCard(
      child: Row(
        children: [
          GlassSvgIconBox(
            icon: _getStatusIcon(request.status),
            color: statusColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.broker.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
                Text(
                  '${request.daysPending} days pending',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
              ],
            ),
          ),
          GlassBadge(text: request.status.displayName, color: statusColor),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required String svgIcon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(svgIcon, size: 64, color: GlassTheme.primaryAccent.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _startScan(DigitalFootprintProvider provider) {
    if (_emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an email address')),
      );
      return;
    }

    final nameParts = _nameController.text.split(' ');
    provider.scan(
      email: _emailController.text,
      firstName: nameParts.isNotEmpty ? nameParts.first : null,
      lastName: nameParts.length > 1 ? nameParts.last : null,
      phone: _phoneController.text.isNotEmpty ? _phoneController.text : null,
    );
  }

  void _requestBatchRemoval(DigitalFootprintProvider provider, List<DataBroker> brokers) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Remove from All', style: TextStyle(color: Colors.white)),
        content: Text(
          'Request removal from ${brokers.length} data brokers?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.requestBatchRemoval(brokers);
              _tabController.animateTo(2); // Go to requests tab
            },
            child: const Text('Request Removal'),
          ),
        ],
      ),
    );
  }

  void _showBrokerDetails(BuildContext context, DataBroker broker, DigitalFootprintProvider provider) {
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
              Row(
                children: [
                  GlassSvgIconBox(
                    icon: AppIcons.enterprise,
                    color: _getCategoryColor(broker.category),
                    size: 56,
                    iconSize: 28,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          broker.name,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(broker.website, style: const TextStyle(color: GlassTheme.primaryAccent)),
                      ],
                    ),
                  ),
                ],
              ),
              if (broker.description != null) ...[
                const SizedBox(height: 20),
                Text(
                  broker.description!,
                  style: TextStyle(color: Colors.white.withOpacity(0.7)),
                ),
              ],
              const SizedBox(height: 20),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Category', broker.category.displayName),
                    _buildDetailRow('Estimated Removal Time', '~${broker.estimatedDays} days'),
                    _buildDetailRow('Difficulty', '${(broker.difficulty * 100).toInt()}%'),
                    _buildDetailRow('Has Opt-Out', broker.hasOptOut ? 'Yes' : 'No'),
                  ],
                ),
              ),
              if (broker.dataCollected.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Data They Collect',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: broker.dataCollected.map((data) {
                    return GlassBadge(text: data, color: GlassTheme.errorColor);
                  }).toList(),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: provider.isSubmitting
                      ? null
                      : () {
                          Navigator.pop(context);
                          provider.requestRemoval(broker);
                          _tabController.animateTo(2);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GlassTheme.errorColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DuotoneIcon(AppIcons.trash, size: 20, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text('Request Data Removal'),
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6))),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Color _getCategoryColor(BrokerCategory category) {
    switch (category) {
      case BrokerCategory.peopleSearch:
        return const Color(0xFF2196F3);
      case BrokerCategory.marketing:
        return const Color(0xFF9C27B0);
      case BrokerCategory.financial:
        return const Color(0xFF4CAF50);
      case BrokerCategory.health:
        return const Color(0xFFFF5722);
      case BrokerCategory.background:
        return const Color(0xFFFF9800);
      default:
        return Colors.grey;
    }
  }

  String _getStatusIcon(RemovalStatus status) {
    switch (status) {
      case RemovalStatus.pending:
        return AppIcons.clock;
      case RemovalStatus.submitted:
        return AppIcons.forward;
      case RemovalStatus.inProgress:
        return AppIcons.refresh;
      case RemovalStatus.completed:
        return AppIcons.checkCircle;
      case RemovalStatus.failed:
        return AppIcons.dangerCircle;
      case RemovalStatus.rejected:
        return AppIcons.closeCircle;
    }
  }
}
