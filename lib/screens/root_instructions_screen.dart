class RootInstructionsScreen extends StatelessWidget {
  const RootInstructionsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Android Root Guide')),
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
          const SizedBox(height: 16),

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
            onPressed: () {
              // Open XDA Developers
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Visit XDA Developers Forum'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              // Test root access
              Navigator.pop(context);
            },
            icon: const Icon(Icons.check),
            label: const Text('Test Root Access'),
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
      color: const Color(0xFF1D1E33),
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
                color: Colors.blue.withOpacity(0.1),
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
