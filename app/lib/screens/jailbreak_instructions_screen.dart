import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../presentation/theme/brand.dart';
import '../presentation/theme/colors.dart';
import '../presentation/theme/glass_theme.dart';
import '../presentation/widgets/duotone_icon.dart';
import '../presentation/widgets/app_sheet.dart';
import '../presentation/widgets/sheet_panel.dart';

class JailbreakInstructionsScreen extends StatefulWidget {
  const JailbreakInstructionsScreen({super.key});

  @override
  State<JailbreakInstructionsScreen> createState() =>
      _JailbreakInstructionsScreenState();
}

class _JailbreakInstructionsScreenState
    extends State<JailbreakInstructionsScreen> {
  /// Same native channel used elsewhere for root/jailbreak detection —
  /// AppDelegate handles "checkRootAccess" on iOS and returns
  /// {hasRoot: isJailbroken, accessLevel, method}.
  static const _systemChannel = MethodChannel('com.orb.guard/system');

  bool _isTesting = false;

  Future<void> _testJailbreakStatus() async {
    setState(() => _isTesting = true);
    String title;
    String message;
    try {
      final result = await _systemChannel.invokeMethod('checkRootAccess');
      final map = result is Map ? result : const {};
      final isJailbroken = map['hasRoot'] == true;
      title = isJailbroken ? 'Jailbreak Detected' : 'No Jailbreak Detected';
      message = isJailbroken
          ? 'This device is jailbroken. Deep scans can access the full '
              'filesystem for spyware detection.'
          : 'No jailbreak was detected on this device. Scans will run with '
              'standard (sandboxed) access.';
    } on PlatformException catch (e) {
      title = 'Jailbreak Check Failed';
      message = 'The native jailbreak check could not run: '
          '${e.message ?? e.code}';
    } on MissingPluginException {
      title = 'Jailbreak Check Unavailable';
      message =
          'The native jailbreak check is not available on this platform.';
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
    if (!mounted) return;
    showAppSheet(
      context,
      child: SheetPanel(
        title: title,
        body: Text(
          message,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.45,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        primaryLabel: 'OK',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('iOS Jailbreak Guide')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ Important Information',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  Text(
                    '• Jailbreaking YOUR device is LEGAL\n'
                    '• Voids Apple warranty\n'
                    '• Enables full filesystem access\n'
                    '• Required for deep spyware detection\n'
                    '• Proceed at your own risk',
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _buildJailbreakCard(
            'checkra1n',
            'iOS 12.0 - 14.8.1',
            'A5-A11 devices',
            [
              '1. Download checkra1n for Mac/Linux',
              '2. Connect iPhone via USB',
              '3. Put device in DFU mode',
              '4. Run checkra1n and follow prompts',
              '5. Install Cydia from checkra1n app',
            ],
            'Semi-tethered, very stable',
          ),

          _buildJailbreakCard(
            'unc0ver',
            'iOS 11.0 - 14.8',
            'All devices',
            [
              '1. Download unc0ver IPA',
              '2. Sign with AltStore or similar',
              '3. Install on device',
              '4. Trust developer certificate',
              '5. Run unc0ver and jailbreak',
            ],
            'Semi-untethered, popular choice',
          ),

          _buildJailbreakCard(
            'Taurine',
            'iOS 14.0 - 14.8.1',
            'All devices',
            [
              '1. Download Taurine IPA',
              '2. Install via AltStore',
              '3. Run Taurine app',
              '4. Tap "Jailbreak"',
              '5. Install Sileo package manager',
            ],
            'Modern UI, Sileo integration',
          ),

          _buildJailbreakCard('Dopamine', 'iOS 15.0 - 16.6', 'All devices', [
            '1. Download Dopamine',
            '2. Install via TrollStore',
            '3. Open Dopamine',
            '4. Tap jailbreak button',
            '5. Respring when prompted',
          ], 'Latest iOS versions'),

          const SizedBox(height: 24),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'After Jailbreaking:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '1. Open Cydia/Sileo\n'
                    '2. Install OpenSSH (optional)\n'
                    '3. Install mobile terminal\n'
                    '4. Return to this app\n'
                    '5. Run deep scan',
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isTesting ? null : _testJailbreakStatus,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Brand.onLime,
                            ),
                          )
                        : const DuotoneIcon(AppIcons.checkCircle,
                            color: Brand.onLime),
                    label: Text(
                        _isTesting ? 'Testing...' : 'Test Jailbreak Status'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GlassTheme.primaryAccent,
                      foregroundColor: Brand.onLime,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildJailbreakCard(
    String name,
    String iOSVersion,
    String devices,
    List<String> steps,
    String note,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Chip(
                  label: Text(iOSVersion, style: const TextStyle(fontSize: 11)),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(devices, style: const TextStyle(fontSize: 11)),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...steps.map(
              (step) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(step),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              ),
              child: Text(
                '✅ $note',
                style: TextStyle(fontSize: 12, color: AppColors.accentInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
