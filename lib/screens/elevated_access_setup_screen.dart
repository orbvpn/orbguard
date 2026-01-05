// elevated_access_setup_screen.dart
// Location: lib/screens/elevated_access_setup_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ElevatedAccessSetupScreen extends StatefulWidget {
  const ElevatedAccessSetupScreen({super.key});

  @override
  State<ElevatedAccessSetupScreen> createState() =>
      _ElevatedAccessSetupScreenState();
}

class _ElevatedAccessSetupScreenState extends State<ElevatedAccessSetupScreen> {
  static const platform = MethodChannel('com.orb.guard/system');

  String _currentLevel = 'STANDARD';
  String _description = '';
  List<String> _capabilities = [];
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkCurrentAccess();
  }

  Future<void> _checkCurrentAccess() async {
    setState(() => _isChecking = true);

    try {
      final result = await platform.invokeMethod('checkAccessLevel');
      print('[AccessLevel] Result: $result');
      setState(() {
        _currentLevel = result['level'] ?? 'STANDARD';
        _description = result['description'] ?? '';
        _capabilities = List<String>.from(result['capabilities'] ?? []);
      });
      print('[AccessLevel] Set level to: $_currentLevel');
    } catch (e) {
      print('[AccessLevel] Error checking access: $e');
    } finally {
      setState(() => _isChecking = false);
    }
  }

  Future<void> _setupElevatedAccess() async {
    print('[AccessLevel] Tapped Enable Shell Access');
    try {
      final result = await platform.invokeMethod('getSetupInstructions');
      print('[AccessLevel] Got instructions: $result');
      final instructions = result as Map<dynamic, dynamic>;

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SetupInstructionsPage(
            instructions: instructions,
            onComplete: _checkCurrentAccess,
          ),
        ),
      );
    } catch (e) {
      _showError('Failed to get setup instructions: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Color _getLevelColor() {
    switch (_currentLevel) {
      case 'ROOT':
        return Colors.green;
      case 'SHELL':
        return Colors.cyan;
      default:
        return Colors.blue;
    }
  }

  IconData _getLevelIcon() {
    switch (_currentLevel) {
      case 'ROOT':
        return Icons.verified_user;
      case 'SHELL':
        return Icons.security;
      default:
        return Icons.shield;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Access Level Setup'),
      ),
      body: _isChecking
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Current Access Level Card
                  Card(
                    color: const Color(0xFF1D1E33),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(
                            _getLevelIcon(),
                            size: 64,
                            color: _getLevelColor(),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Current Access Level',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _currentLevel,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: _getLevelColor(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _description,
                            style: const TextStyle(fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Capabilities Card
                  Card(
                    color: const Color(0xFF1D1E33),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Capabilities',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._capabilities.map(
                            (cap) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                cap,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: cap.startsWith('✓')
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // What is Elevated Access?
                  _buildInfoSection(
                    'What is Elevated Access?',
                    'Elevated access allows OrbGuard to inspect system-level '
                        'components that are normally hidden from apps. This enables '
                        'detection of advanced spyware like Pegasus that operates at '
                        'the system level.\n\n'
                        'OrbGuard uses Android Debug Bridge (ADB) to gain shell '
                        'access, similar to how Shizuku works. This is completely '
                        'legitimate and safe.',
                    Icons.info_outline,
                  ),

                  const SizedBox(height: 16),

                  // Three Access Levels
                  _buildInfoSection(
                    'Three Access Levels',
                    '1. STANDARD - Uses normal Android APIs. Can detect many '
                        'threats but limited system access.\n\n'
                        '2. SHELL - Uses ADB shell access (uid 2000). Can read '
                        'system files, inspect processes, monitor network. Requires '
                        'one-time setup.\n\n'
                        '3. ROOT - Full system access (uid 0). Can modify system, '
                        'remove any threat. Only if device is rooted.',
                    Icons.layers,
                  ),

                  const SizedBox(height: 24),

                  // Action Buttons
                  if (_currentLevel == 'STANDARD') ...[
                    ElevatedButton.icon(
                      onPressed: _setupElevatedAccess,
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text('Enable Shell Access'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D9FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Recommended: Shell access enables deep scanning without '
                      'requiring root',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      onPressed: _checkCurrentAccess,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Re-check Access Level'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Safety Notice
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.verified, color: Colors.green),
                            const SizedBox(width: 8),
                            const Text(
                              'Safety & Privacy',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '✓ No data sent to external servers\n'
                          '✓ All scanning happens locally\n'
                          '✓ ADB access is temporary (until reboot)\n'
                          '✓ You can revoke access anytime\n'
                          '✓ Open source and transparent',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoSection(String title, String content, IconData icon) {
    return Card(
      color: const Color(0xFF1D1E33),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF00D9FF)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              content,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// Setup Instructions Page
class SetupInstructionsPage extends StatefulWidget {
  final Map<dynamic, dynamic> instructions;
  final VoidCallback onComplete;

  const SetupInstructionsPage({
    super.key,
    required this.instructions,
    required this.onComplete,
  });

  @override
  State<SetupInstructionsPage> createState() => _SetupInstructionsPageState();
}

class _SetupInstructionsPageState extends State<SetupInstructionsPage> {
  static const platform = MethodChannel('com.orb.guard/system');
  int _currentStep = 0;
  bool _isVerifying = false;

  List<String> get _steps =>
      List<String>.from(widget.instructions['steps'] ?? []);
  List<String> get _benefits =>
      List<String>.from(widget.instructions['benefits'] ?? []);
  String get _persistence => widget.instructions['persistence'] ?? '';
  String get _scriptPath => widget.instructions['scriptPath'] ?? '';

  Future<void> _verifyAccess() async {
    setState(() => _isVerifying = true);

    try {
      final result = await platform.invokeMethod('checkAccessLevel');
      final level = result['level'] ?? 'STANDARD';

      if (level == 'SHELL' || level == 'ROOT') {
        _showSuccess();
        await Future.delayed(const Duration(seconds: 2));
        widget.onComplete();
        if (mounted) Navigator.pop(context);
      } else {
        _showError('Shell access not detected. Please follow all steps.');
      }
    } catch (e) {
      _showError('Verification failed: $e');
    } finally {
      setState(() => _isVerifying = false);
    }
  }

  void _showSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Shell access enabled successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _copyCommand(String command) {
    Clipboard.setData(ClipboardData(text: command));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Command copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Shell Access'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Benefits Card
            Card(
              color: Colors.blue.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.star, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'What You\'ll Get',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._benefits.map(
                      (benefit) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child:
                            Text(benefit, style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Steps
            ..._steps.asMap().entries.map((entry) {
              final index = entry.key;
              final step = entry.value;
              final isActive = index == _currentStep;

              return Card(
                color: isActive
                    ? const Color(0xFF00D9FF).withOpacity(0.1)
                    : const Color(0xFF1D1E33),
                margin: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                  onTap: () => setState(() => _currentStep = index),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? const Color(0xFF00D9FF)
                                    : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color:
                                        isActive ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                step.split('\n').first,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isActive) ...[
                          const SizedBox(height: 12),
                          Text(
                            step,
                            style: const TextStyle(fontSize: 14, height: 1.5),
                          ),
                          if (step.contains('adb')) ...[
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () {
                                final command = step
                                    .split('\n')
                                    .where(
                                        (line) => line.trim().startsWith('adb'))
                                    .join('\n');
                                _copyCommand(command);
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy Command'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00D9FF),
                                foregroundColor: Colors.black,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 24),

            // Persistence Notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        'Important Note',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_persistence, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Verify Button
            ElevatedButton.icon(
              onPressed: _isVerifying ? null : _verifyAccess,
              icon: _isVerifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle),
              label: Text(_isVerifying ? 'Verifying...' : 'Verify Access'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 12),

            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Skip for Now'),
            ),
          ],
        ),
      ),
    );
  }
}
