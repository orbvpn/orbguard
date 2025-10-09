import 'package:flutter/material.dart';

class JailbreakInstructionsScreen extends StatelessWidget {
  const JailbreakInstructionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('iOS Jailbreak Guide')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            color: Color(0xFF1D1E33),
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
          const SizedBox(height: 16),

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
            color: const Color(0xFF1D1E33),
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
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('Test Jailbreak Status'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D9FF),
                      foregroundColor: Colors.black,
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
      color: const Color(0xFF1D1E33),
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
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '✅ $note',
                style: const TextStyle(fontSize: 12, color: Colors.green),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
