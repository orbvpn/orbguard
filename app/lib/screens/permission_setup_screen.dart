// lib/screens/permission_setup_screen.dart
// Interactive permission setup with explanations

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../permissions/permission_manager.dart';
import '../presentation/theme/brand.dart';
import '../presentation/theme/colors.dart';
import '../presentation/theme/glass_theme.dart';
import '../presentation/widgets/duotone_icon.dart';

class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({super.key});

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen>
    with WidgetsBindingObserver {
  final PermissionManager _permissionManager = PermissionManager();
  PermissionScanResult? _scanResult;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh permissions when app resumes (user returns from Settings)
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    setState(() => _isChecking = true);

    final result = await _permissionManager.checkAllPermissions();

    setState(() {
      _scanResult = result;
      _isChecking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permission Setup'),
        actions: [
          IconButton(
            icon: const DuotoneIcon(AppIcons.refresh),
            onPressed: _checkPermissions,
          ),
        ],
      ),
      body: _isChecking
          ? const Center(child: CircularProgressIndicator())
          : _scanResult == null
              ? const Center(child: Text('Loading...'))
              : _buildPermissionList(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildPermissionList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _buildDetectionCapabilityCard(),
        const SizedBox(height: 24),

        // Essential Permissions
        _buildGroupHeader('Essential Permissions', AppIcons.shieldCheck),
        Text(
          'Required for basic threat detection',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13),
        ),
        const SizedBox(height: 12),
        _buildStoragePermissionCard(),
        _buildPermissionCard(
          'Phone State',
          'Monitor device for suspicious modifications',
          Permission.phone,
          AppIcons.smartphone,
        ),

        const SizedBox(height: 24),

        // Advanced Permissions
        _buildGroupHeader('Advanced Detection', AppIcons.search),
        Text(
          'Enables deep threat analysis',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13),
        ),
        const SizedBox(height: 12),
        _buildPermissionCard(
          'SMS Access',
          'Detect SMS-based exploits (Pegasus)',
          Permission.sms,
          AppIcons.chatDots,
        ),
        _buildPermissionCard(
          'Location',
          'Detect location stalking behavior',
          Permission.location,
          AppIcons.mapPoint,
        ),

        const SizedBox(height: 24),

        // Special Permissions
        _buildGroupHeader('Special Permissions', AppIcons.settings),
        Text(
          'Requires manual activation in Settings',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13),
        ),
        const SizedBox(height: 12),
        _buildSpecialPermissionCard(
          'Usage Stats',
          'Monitor app behavior patterns',
          _scanResult!.granted.contains('Usage Stats'),
          () => _requestUsageStats(),
        ),
        _buildSpecialPermissionCard(
          'Accessibility',
          'Detect malicious accessibility services',
          _scanResult!.granted.contains('Accessibility'),
          () => _requestAccessibility(),
        ),

        const SizedBox(height: 80), // Space for bottom bar
      ],
    );
  }

  Widget _buildDetectionCapabilityCard() {
    final capability = _scanResult!.detectionCapability;
    Color color;
    String status;
    String icon;

    if (capability >= 80) {
      color = AppColors.accentInk;
      status = 'Excellent';
      icon = AppIcons.checkCircle;
    } else if (capability >= 50) {
      color = AppColors.amberInk;
      status = 'Good';
      icon = AppIcons.dangerTriangle;
    } else {
      color = AppColors.errorInk;
      status = 'Limited';
      icon = AppIcons.dangerCircle;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                DuotoneIcon(icon, color: color, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Detection Capability', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        status, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$capability%',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              child: LinearProgressIndicator(
                value: capability / 100,
                minHeight: 8,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${_scanResult!.granted.length} of ${_scanResult!.totalPermissions} permissions granted',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupHeader(String title, String icon) {
    return Row(
      children: [
        DuotoneIcon(icon, color: AppColors.secondaryInk),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStoragePermissionCard() {
    // Use scan result for storage status (handles Android 11+ MANAGE_EXTERNAL_STORAGE)
    final isGranted = _scanResult?.granted.contains('Storage Access') ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: DuotoneIcon(AppIcons.folder,
            color: isGranted
                ? AppColors.accentInk
                : Theme.of(context).colorScheme.onSurfaceVariant),
        title: const Text('Storage Access'),
        subtitle: const Text('Scan files for malware and threats',
            style: TextStyle(fontSize: 12)),
        trailing: isGranted
            ? DuotoneIcon(AppIcons.checkCircle, color: AppColors.accentInk)
            : ElevatedButton(
                onPressed: () => _requestPermission(Permission.storage, 'Storage Access'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.info,
                  foregroundColor: Brand.onPink,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('Grant'),
              ),
      ),
    );
  }

  Widget _buildPermissionCard(
    String name,
    String description,
    Permission permission,
    String icon,
  ) {
    return FutureBuilder<PermissionStatus>(
      future: permission.status,
      builder: (context, snapshot) {
        final isGranted = snapshot.data?.isGranted ?? false;
        final isDenied = snapshot.data?.isPermanentlyDenied ?? false;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: DuotoneIcon(icon,
                color: isGranted
                    ? AppColors.accentInk
                    : Theme.of(context).colorScheme.onSurfaceVariant),
            title: Text(name),
            subtitle: Text(description, style: const TextStyle(fontSize: 12)),
            trailing: isGranted
                ? DuotoneIcon(AppIcons.checkCircle, color: AppColors.accentInk)
                : isDenied
                    ? DuotoneIcon(AppIcons.forbidden, color: AppColors.errorInk)
                    : ElevatedButton(
                        onPressed: () => _requestPermission(permission, name),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.info,
                          foregroundColor: Brand.onPink,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: const Text('Grant'),
                      ),
          ),
        );
      },
    );
  }

  Widget _buildSpecialPermissionCard(
    String name,
    String description,
    bool isGranted,
    VoidCallback onRequest,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: DuotoneIcon(
          AppIcons.settings,
          color: isGranted ? AppColors.accentInk : AppColors.secondaryInk,
        ),
        title: Text(name),
        subtitle: Text(description, style: const TextStyle(fontSize: 12)),
        trailing: isGranted
            ? DuotoneIcon(AppIcons.checkCircle, color: AppColors.accentInk)
            : ElevatedButton(
                onPressed: onRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Brand.onPink,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('Enable'),
              ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final allEssential = _scanResult?.hasAllEssential ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          // Upward hairline shadow for the bottom bar (GlassTheme.shadow is
          // downward ambient) — color from the overlay token.
          BoxShadow(
            color: AppColors.overlayLight,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!allEssential)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              ),
              child: Row(
                children: [
                  DuotoneIcon(AppIcons.infoCircle, color: AppColors.secondaryInk),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Grant essential permissions to enable scanning',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      allEssential ? _grantAllRemaining : _grantEssential,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GlassTheme.primaryAccent,
                    foregroundColor: Brand.onLime,
                    padding: const EdgeInsets.all(16),
                  ),
                  child: Text(
                    allEssential ? 'Grant All Remaining' : 'Grant Essential',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              if (allEssential) ...[
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Brand.onLime,
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Text('Continue'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // PERMISSION REQUEST HANDLERS
  // ============================================================================

  Future<void> _grantEssential() async {
    final results = await _permissionManager.requestEssentialPermissions();

    // Show results
    final granted = results.values.where((s) => s.isGranted).length;
    final total = results.length;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Granted $granted of $total essential permissions'),
          backgroundColor: granted == total ? AppColors.success : AppColors.warning,
        ),
      );

      await _checkPermissions();
    }
  }

  Future<void> _grantAllRemaining() async {
    final results = await _permissionManager.requestAdvancedPermissions();

    final granted = results.values.where((s) => s.isGranted).length;
    final total = results.length;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Granted $granted of $total advanced permissions'),
          backgroundColor: granted == total ? AppColors.success : AppColors.warning,
        ),
      );

      await _checkPermissions();
    }
  }

  Future<void> _requestPermission(Permission permission, String name) async {
    // For storage permission on Android 11+, use native method
    if (permission == Permission.storage) {
      final success = await _permissionManager.requestStoragePermission();
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable "All files access" for OrbGuard'),
            backgroundColor: AppColors.warning,
          ),
        );
        // Wait for user to return from settings
        await Future.delayed(const Duration(seconds: 2));
        await _checkPermissions();
      }
      return;
    }

    final status = await _permissionManager.requestPermissionWithRationale(
      context: context,
      permission: permission,
      title: 'Grant $name',
      explanation: _getPermissionExplanation(permission),
      benefit: _getPermissionBenefit(permission),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status.isGranted ? '$name granted!' : '$name denied',
          ),
          backgroundColor: status.isGranted ? AppColors.success : AppColors.error,
        ),
      );

      await _checkPermissions();
    }
  }

  Future<void> _requestUsageStats() async {
    final success =
        await _permissionManager.requestUsageStatsPermission(context);
    if (success) {
      // Wait a bit for user to grant in Settings, then check again
      await Future.delayed(const Duration(seconds: 2));
      await _checkPermissions();
    }
  }

  Future<void> _requestAccessibility() async {
    final success =
        await _permissionManager.requestAccessibilityPermission(context);
    if (success) {
      await Future.delayed(const Duration(seconds: 2));
      await _checkPermissions();
    }
  }

  // ============================================================================
  // PERMISSION EXPLANATIONS
  // ============================================================================

  String _getPermissionExplanation(Permission permission) {
    final explanations = {
      Permission.storage:
          'OrbGuard needs to scan your files and installed apps to detect malware, suspicious modifications, and hidden threats.',
      Permission.phone:
          'This allows monitoring of device state to detect system-level compromises and root/jailbreak modifications.',
      Permission.sms:
          'Pegasus and similar spyware often use SMS-based zero-click exploits. This permission lets us scan SMS databases for exploit patterns.',
      Permission.location:
          'Location permission helps detect apps that excessively track your location, a common behavior of stalkerware.',
    };
    return explanations[permission] ??
        'This permission enhances threat detection capabilities.';
  }

  String _getPermissionBenefit(Permission permission) {
    final benefits = {
      // Honest: storage access only helps on older Android (≤12). The APK check
      // works on files you pick and needs no storage permission at all.
      Permission.storage:
          'Lets OrbGuard open files you choose to check (older Android only)',
      Permission.phone: 'Detects system compromises and security bypasses',
      Permission.sms:
          'Critical for detecting SMS-based zero-click exploits like those used by Pegasus',
      Permission.location:
          'Identifies location stalking and excessive tracking behavior',
    };
    return benefits[permission] ?? 'Enhances overall security monitoring';
  }
}
