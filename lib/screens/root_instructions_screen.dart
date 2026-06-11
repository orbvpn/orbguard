import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../presentation/widgets/duotone_icon.dart';

class RootInstructionsScreen extends StatefulWidget {
  const RootInstructionsScreen({super.key});

  @override
  State<RootInstructionsScreen> createState() => _RootInstructionsScreenState();
}

class _RootInstructionsScreenState extends State<RootInstructionsScreen> {
  /// Same native channel used by DeviceSecurityProvider/_checkRootedAndroid —
  /// MainActivity handles "checkRootAccess" and returns
  /// {hasRoot, accessLevel, method}.
  static const _systemChannel = MethodChannel('com.orb.guard/system');
  static final Uri _xdaUrl = Uri.parse('https://forum.xda-developers.com/');

  bool _isTesting = false;

  Future<void> _openXdaForum() async {
    final launched =
        await launchUrl(_xdaUrl, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${_xdaUrl.host}')),
      );
    }
  }

  Future<void> _testRootAccess() async {
    setState(() => _isTesting = true);
    String title;
    String message;
    try {
      final result = await _systemChannel.invokeMethod('checkRootAccess');
      final map = result is Map ? result : const {};
      final hasRoot = map['hasRoot'] == true;
      final method = map['method']?.toString();
      final accessLevel = map['accessLevel']?.toString();
      title = hasRoot ? 'Root Access Detected' : 'No Root Access';
      message = hasRoot
          ? 'This device has root access'
              '${method != null && method.isNotEmpty ? ' via $method' : ''}. '
              'Access level: ${accessLevel ?? 'Full'}. '
              'Deep spyware scans can use elevated privileges.'
          : 'No root access was detected on this device. Scans will run '
              'with standard (non-root) privileges.';
    } on PlatformException catch (e) {
      title = 'Root Check Failed';
      message = 'The native root check could not run: '
          '${e.message ?? e.code}';
    } on MissingPluginException {
      title = 'Root Check Unavailable';
      message = 'The native root check is not available on this platform.';
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Android Root Guide')),
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
                    '• Rooting YOUR device is LEGAL\n'
                    '• Voids manufacturer warranty\n'
                    '• Enables full system access\n'
                    '• Required for deep spyware removal\n'
                    '• Proceed at your own risk',
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _buildMethodCard(
            'Method 1: Magisk (Recommended)',
            [
              '1. Unlock bootloader (varies by manufacturer)',
              '2. Install TWRP custom recovery',
              '3. Download latest Magisk APK',
              '4. Flash Magisk through TWRP',
              '5. Reboot and verify root with this app',
            ],
            'Most popular and maintained root solution',
          ),

          _buildMethodCard('Method 2: KingoRoot', [
            '1. Enable USB Debugging',
            '2. Download KingoRoot for PC',
            '3. Connect device to PC',
            '4. Run KingoRoot and follow prompts',
            '5. Wait for root process to complete',
          ], 'One-click root solution for many devices'),

          _buildMethodCard(
            'Method 3: Device-Specific ROMs',
            [
              '1. Check XDA Forums for your device',
              '2. Download custom ROM (LineageOS, etc.)',
              '3. Install via custom recovery',
              '4. Custom ROMs often include root',
            ],
            'Best for older devices or specific models',
          ),

          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openXdaForum,
            icon: const DuotoneIcon(AppIcons.share, color: Colors.white),
            label: const Text('Visit XDA Developers Forum'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isTesting ? null : _testRootAccess,
            icon: _isTesting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const DuotoneIcon(AppIcons.checkCircle, color: Colors.black),
            label: Text(_isTesting ? 'Testing...' : 'Test Root Access'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D9FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildMethodCard(
    String title,
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
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '💡 $note',
                style: const TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
