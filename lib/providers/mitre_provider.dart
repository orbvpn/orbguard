/// MITRE ATT&CK Provider
/// State management for MITRE ATT&CK technique display
library mitre_provider;

import 'package:flutter/foundation.dart';

/// MITRE ATT&CK Tactic
class MitreTactic {
  final String id;
  final String name;
  final String shortName;
  final String description;
  final int order;

  const MitreTactic({
    required this.id,
    required this.name,
    required this.shortName,
    required this.description,
    required this.order,
  });

  /// Mobile ATT&CK tactics
  static const List<MitreTactic> mobileTactics = [
    MitreTactic(
      id: 'TA0027',
      name: 'Initial Access',
      shortName: 'Initial',
      description: 'Techniques to gain initial access to a mobile device',
      order: 1,
    ),
    MitreTactic(
      id: 'TA0041',
      name: 'Execution',
      shortName: 'Execution',
      description: 'Techniques for running malicious code on mobile',
      order: 2,
    ),
    MitreTactic(
      id: 'TA0028',
      name: 'Persistence',
      shortName: 'Persist',
      description: 'Techniques to maintain access across reboots',
      order: 3,
    ),
    MitreTactic(
      id: 'TA0029',
      name: 'Privilege Escalation',
      shortName: 'PrivEsc',
      description: 'Techniques to gain higher permissions',
      order: 4,
    ),
    MitreTactic(
      id: 'TA0030',
      name: 'Defense Evasion',
      shortName: 'Evasion',
      description: 'Techniques to avoid detection',
      order: 5,
    ),
    MitreTactic(
      id: 'TA0031',
      name: 'Credential Access',
      shortName: 'Creds',
      description: 'Techniques to steal credentials',
      order: 6,
    ),
    MitreTactic(
      id: 'TA0032',
      name: 'Discovery',
      shortName: 'Discovery',
      description: 'Techniques to explore the device',
      order: 7,
    ),
    MitreTactic(
      id: 'TA0033',
      name: 'Lateral Movement',
      shortName: 'Lateral',
      description: 'Techniques to move to other devices',
      order: 8,
    ),
    MitreTactic(
      id: 'TA0035',
      name: 'Collection',
      shortName: 'Collect',
      description: 'Techniques to gather data',
      order: 9,
    ),
    MitreTactic(
      id: 'TA0037',
      name: 'Command and Control',
      shortName: 'C2',
      description: 'Techniques for remote communication',
      order: 10,
    ),
    MitreTactic(
      id: 'TA0036',
      name: 'Exfiltration',
      shortName: 'Exfil',
      description: 'Techniques to steal data',
      order: 11,
    ),
    MitreTactic(
      id: 'TA0034',
      name: 'Impact',
      shortName: 'Impact',
      description: 'Techniques to disrupt or destroy',
      order: 12,
    ),
  ];
}

/// MITRE ATT&CK Technique
class MitreTechnique {
  final String id;
  final String name;
  final String tacticId;
  final String description;
  final List<String> platforms;
  final List<String>? subTechniques;
  final List<String>? mitigations;
  final String? url;

  const MitreTechnique({
    required this.id,
    required this.name,
    required this.tacticId,
    required this.description,
    this.platforms = const ['Android', 'iOS'],
    this.subTechniques,
    this.mitigations,
    this.url,
  });

  String get displayId => id.replaceAll('T', 'T').replaceAll('.', '.');

  bool get isSubTechnique => id.contains('.');

  String get parentId => id.split('.').first;
}

/// Detected technique in a threat
class DetectedTechnique {
  final MitreTechnique technique;
  final String source;
  final String evidence;
  final DateTime detectedAt;
  final double confidence;

  DetectedTechnique({
    required this.technique,
    required this.source,
    required this.evidence,
    required this.detectedAt,
    this.confidence = 1.0,
  });
}

/// MITRE ATT&CK Provider
class MitreProvider extends ChangeNotifier {
  // All known techniques (subset for mobile)
  final Map<String, List<MitreTechnique>> _techniquesByTactic = {};

  // Detected techniques from scans
  final List<DetectedTechnique> _detectedTechniques = [];

  // State
  bool _isLoading = false;
  String? _selectedTacticId;
  String? _selectedTechniqueId;

  // Getters
  List<MitreTactic> get tactics => MitreTactic.mobileTactics;

  Map<String, List<MitreTechnique>> get techniquesByTactic => _techniquesByTactic;

  List<DetectedTechnique> get detectedTechniques => _detectedTechniques;

  bool get isLoading => _isLoading;

  String? get selectedTacticId => _selectedTacticId;

  String? get selectedTechniqueId => _selectedTechniqueId;

  MitreTechnique? get selectedTechnique {
    if (_selectedTechniqueId == null) return null;
    for (final techniques in _techniquesByTactic.values) {
      for (final t in techniques) {
        if (t.id == _selectedTechniqueId) return t;
      }
    }
    return null;
  }

  /// Get techniques for a specific tactic
  List<MitreTechnique> getTechniquesForTactic(String tacticId) {
    return _techniquesByTactic[tacticId] ?? [];
  }

  /// Get count of detected techniques per tactic
  Map<String, int> get detectedCountByTactic {
    final counts = <String, int>{};
    for (final detected in _detectedTechniques) {
      final tacticId = detected.technique.tacticId;
      counts[tacticId] = (counts[tacticId] ?? 0) + 1;
    }
    return counts;
  }

  /// Total detected techniques
  int get totalDetectedCount => _detectedTechniques.length;

  /// Initialize provider with techniques
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Load techniques (in production, fetch from API or local database)
      _loadMobileTechniques();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load mobile ATT&CK techniques
  void _loadMobileTechniques() {
    _techniquesByTactic.clear();

    // Initial Access techniques
    _addTechniques('TA0027', [
      const MitreTechnique(
        id: 'T1474',
        name: 'Supply Chain Compromise',
        tacticId: 'TA0027',
        description: 'Adversaries may manipulate products or mechanisms prior to receipt by the end user.',
        mitigations: ['M1001', 'M1006'],
      ),
      const MitreTechnique(
        id: 'T1476',
        name: 'Deliver Malicious App via Other Means',
        tacticId: 'TA0027',
        description: 'Adversaries may deliver malicious apps via means other than app stores.',
        mitigations: ['M1011', 'M1012'],
      ),
      const MitreTechnique(
        id: 'T1456',
        name: 'Drive-by Compromise',
        tacticId: 'TA0027',
        description: 'Adversaries may gain access by visiting a website during normal browsing.',
      ),
      const MitreTechnique(
        id: 'T1458',
        name: 'Replication Through Removable Media',
        tacticId: 'TA0027',
        description: 'Adversaries may move onto devices by copying malware to removable media.',
      ),
      const MitreTechnique(
        id: 'T1660',
        name: 'Phishing',
        tacticId: 'TA0027',
        description: 'Adversaries may send messages to trick users into installing malware.',
      ),
    ]);

    // Execution techniques
    _addTechniques('TA0041', [
      const MitreTechnique(
        id: 'T1623',
        name: 'Command and Scripting Interpreter',
        tacticId: 'TA0041',
        description: 'Adversaries may abuse command and script interpreters.',
      ),
      const MitreTechnique(
        id: 'T1575',
        name: 'Native Code',
        tacticId: 'TA0041',
        description: 'Adversaries may use native code to execute functionality.',
      ),
    ]);

    // Persistence techniques
    _addTechniques('TA0028', [
      const MitreTechnique(
        id: 'T1398',
        name: 'Boot or Logon Initialization Scripts',
        tacticId: 'TA0028',
        description: 'Adversaries may run scripts at device boot or logon.',
      ),
      const MitreTechnique(
        id: 'T1624',
        name: 'Event Triggered Execution',
        tacticId: 'TA0028',
        description: 'Adversaries may establish persistence using event triggers.',
      ),
      const MitreTechnique(
        id: 'T1541',
        name: 'Foreground Persistence',
        tacticId: 'TA0028',
        description: 'Adversaries may abuse foreground services for persistence.',
        platforms: ['Android'],
      ),
    ]);

    // Privilege Escalation techniques
    _addTechniques('TA0029', [
      const MitreTechnique(
        id: 'T1404',
        name: 'Exploitation for Privilege Escalation',
        tacticId: 'TA0029',
        description: 'Adversaries may exploit vulnerabilities to gain privileges.',
      ),
      const MitreTechnique(
        id: 'T1626',
        name: 'Abuse Elevation Control Mechanism',
        tacticId: 'TA0029',
        description: 'Adversaries may abuse elevation control mechanisms.',
      ),
    ]);

    // Defense Evasion techniques
    _addTechniques('TA0030', [
      const MitreTechnique(
        id: 'T1628',
        name: 'Hide Artifacts',
        tacticId: 'TA0030',
        description: 'Adversaries may hide artifacts to evade detection.',
      ),
      const MitreTechnique(
        id: 'T1629',
        name: 'Impair Defenses',
        tacticId: 'TA0030',
        description: 'Adversaries may disable security features.',
      ),
      const MitreTechnique(
        id: 'T1630',
        name: 'Indicator Removal on Host',
        tacticId: 'TA0030',
        description: 'Adversaries may remove indicators of their presence.',
      ),
      const MitreTechnique(
        id: 'T1406',
        name: 'Obfuscated Files or Information',
        tacticId: 'TA0030',
        description: 'Adversaries may obfuscate files or information.',
      ),
    ]);

    // Credential Access techniques
    _addTechniques('TA0031', [
      const MitreTechnique(
        id: 'T1634',
        name: 'Credentials from Password Store',
        tacticId: 'TA0031',
        description: 'Adversaries may steal credentials from password stores.',
      ),
      const MitreTechnique(
        id: 'T1417',
        name: 'Input Capture',
        tacticId: 'TA0031',
        description: 'Adversaries may capture user input including keystrokes.',
      ),
      const MitreTechnique(
        id: 'T1411',
        name: 'Input Prompt',
        tacticId: 'TA0031',
        description: 'Adversaries may display fake dialogs to capture credentials.',
      ),
    ]);

    // Discovery techniques
    _addTechniques('TA0032', [
      const MitreTechnique(
        id: 'T1420',
        name: 'File and Directory Discovery',
        tacticId: 'TA0032',
        description: 'Adversaries may enumerate files and directories.',
      ),
      const MitreTechnique(
        id: 'T1418',
        name: 'Software Discovery',
        tacticId: 'TA0032',
        description: 'Adversaries may enumerate installed applications.',
      ),
      const MitreTechnique(
        id: 'T1422',
        name: 'System Network Configuration Discovery',
        tacticId: 'TA0032',
        description: 'Adversaries may look for network configuration details.',
      ),
      const MitreTechnique(
        id: 'T1426',
        name: 'System Information Discovery',
        tacticId: 'TA0032',
        description: 'Adversaries may gather system information.',
      ),
    ]);

    // Collection techniques
    _addTechniques('TA0035', [
      const MitreTechnique(
        id: 'T1432',
        name: 'Access Contact List',
        tacticId: 'TA0035',
        description: 'Adversaries may access contact list to identify targets.',
      ),
      const MitreTechnique(
        id: 'T1429',
        name: 'Audio Capture',
        tacticId: 'TA0035',
        description: 'Adversaries may capture audio using the microphone.',
      ),
      const MitreTechnique(
        id: 'T1512',
        name: 'Video Capture',
        tacticId: 'TA0035',
        description: 'Adversaries may capture video using the camera.',
      ),
      const MitreTechnique(
        id: 'T1430',
        name: 'Location Tracking',
        tacticId: 'TA0035',
        description: 'Adversaries may track the device\'s location.',
      ),
      const MitreTechnique(
        id: 'T1636',
        name: 'Protected User Data',
        tacticId: 'TA0035',
        description: 'Adversaries may access protected user data.',
      ),
      const MitreTechnique(
        id: 'T1513',
        name: 'Screen Capture',
        tacticId: 'TA0035',
        description: 'Adversaries may capture screenshots.',
      ),
      const MitreTechnique(
        id: 'T1409',
        name: 'Stored Application Data',
        tacticId: 'TA0035',
        description: 'Adversaries may access stored application data.',
      ),
    ]);

    // Command and Control techniques
    _addTechniques('TA0037', [
      const MitreTechnique(
        id: 'T1437',
        name: 'Application Layer Protocol',
        tacticId: 'TA0037',
        description: 'Adversaries may use application layer protocols for C2.',
      ),
      const MitreTechnique(
        id: 'T1521',
        name: 'Encrypted Channel',
        tacticId: 'TA0037',
        description: 'Adversaries may use encrypted channels for C2.',
      ),
      const MitreTechnique(
        id: 'T1544',
        name: 'Ingress Tool Transfer',
        tacticId: 'TA0037',
        description: 'Adversaries may transfer tools from external systems.',
      ),
    ]);

    // Exfiltration techniques
    _addTechniques('TA0036', [
      const MitreTechnique(
        id: 'T1646',
        name: 'Exfiltration Over C2 Channel',
        tacticId: 'TA0036',
        description: 'Adversaries may steal data over the C2 channel.',
      ),
      const MitreTechnique(
        id: 'T1639',
        name: 'Exfiltration Over Alternative Protocol',
        tacticId: 'TA0036',
        description: 'Adversaries may exfiltrate data using alternative protocols.',
      ),
    ]);

    // Impact techniques
    _addTechniques('TA0034', [
      const MitreTechnique(
        id: 'T1471',
        name: 'Data Encrypted for Impact',
        tacticId: 'TA0034',
        description: 'Adversaries may encrypt data to impact availability (ransomware).',
      ),
      const MitreTechnique(
        id: 'T1447',
        name: 'Delete Device Data',
        tacticId: 'TA0034',
        description: 'Adversaries may delete device data.',
      ),
      const MitreTechnique(
        id: 'T1448',
        name: 'Carrier Billing Fraud',
        tacticId: 'TA0034',
        description: 'Adversaries may use premium SMS for billing fraud.',
        platforms: ['Android'],
      ),
    ]);
  }

  void _addTechniques(String tacticId, List<MitreTechnique> techniques) {
    _techniquesByTactic[tacticId] = techniques;
  }

  /// Add a detected technique
  void addDetectedTechnique(DetectedTechnique detected) {
    _detectedTechniques.add(detected);
    notifyListeners();
  }

  /// Clear detected techniques
  void clearDetectedTechniques() {
    _detectedTechniques.clear();
    notifyListeners();
  }

  /// Select a tactic
  void selectTactic(String? tacticId) {
    _selectedTacticId = tacticId;
    _selectedTechniqueId = null;
    notifyListeners();
  }

  /// Select a technique
  void selectTechnique(String? techniqueId) {
    _selectedTechniqueId = techniqueId;
    notifyListeners();
  }

  /// Check if a technique has been detected
  bool isTechniqueDetected(String techniqueId) {
    return _detectedTechniques.any((d) => d.technique.id == techniqueId);
  }

  /// Get detected technique info
  DetectedTechnique? getDetectedTechnique(String techniqueId) {
    try {
      return _detectedTechniques.firstWhere((d) => d.technique.id == techniqueId);
    } catch (e) {
      return null;
    }
  }
}
