/// MITRE ATT&CK Provider
/// State management for MITRE ATT&CK technique display
library mitre_provider;

import 'package:flutter/foundation.dart';

import '../services/api/orbguard_api_client.dart';

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

  /// Standard MITRE ATT&CK Mobile tactics
  static const List<MitreTactic> mobileTactics = [
    MitreTactic(id: 'TA0027', name: 'Initial Access', shortName: 'Initial Access', description: 'Techniques for gaining an initial foothold on a mobile device.', order: 1),
    MitreTactic(id: 'TA0041', name: 'Execution', shortName: 'Execution', description: 'Techniques for running malicious code on a mobile device.', order: 2),
    MitreTactic(id: 'TA0028', name: 'Persistence', shortName: 'Persistence', description: 'Techniques for maintaining presence on a mobile device.', order: 3),
    MitreTactic(id: 'TA0029', name: 'Privilege Escalation', shortName: 'Privilege Escalation', description: 'Techniques for gaining higher-level permissions.', order: 4),
    MitreTactic(id: 'TA0030', name: 'Defense Evasion', shortName: 'Defense Evasion', description: 'Techniques for avoiding detection.', order: 5),
    MitreTactic(id: 'TA0031', name: 'Credential Access', shortName: 'Credential Access', description: 'Techniques for stealing credentials.', order: 6),
    MitreTactic(id: 'TA0032', name: 'Discovery', shortName: 'Discovery', description: 'Techniques for learning about the device environment.', order: 7),
    MitreTactic(id: 'TA0033', name: 'Lateral Movement', shortName: 'Lateral Movement', description: 'Techniques for moving through the environment.', order: 8),
    MitreTactic(id: 'TA0034', name: 'Collection', shortName: 'Collection', description: 'Techniques for gathering data of interest.', order: 9),
    MitreTactic(id: 'TA0035', name: 'Command and Control', shortName: 'C2', description: 'Techniques for communicating with compromised devices.', order: 10),
    MitreTactic(id: 'TA0036', name: 'Exfiltration', shortName: 'Exfiltration', description: 'Techniques for stealing data.', order: 11),
    MitreTactic(id: 'TA0037', name: 'Impact', shortName: 'Impact', description: 'Techniques for disrupting availability or integrity.', order: 12),
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
  // All known tactics
  List<MitreTactic> _tactics = [];

  // All known techniques (subset for mobile)
  final Map<String, List<MitreTechnique>> _techniquesByTactic = {};

  // Detected techniques from scans
  final List<DetectedTechnique> _detectedTechniques = [];

  // State
  bool _isLoading = false;
  String? _error;
  String? _selectedTacticId;
  String? _selectedTechniqueId;

  // Getters
  List<MitreTactic> get tactics => _tactics;

  String? get error => _error;

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
    _error = null;
    notifyListeners();

    try {
      final apiClient = OrbGuardApiClient.instance;

      // Load tactics from API
      final apiTactics = await apiClient.getMitreTactics();
      _tactics = apiTactics.asMap().entries.map((entry) {
        final t = entry.value;
        return MitreTactic(
          id: t.id,
          name: t.name,
          shortName: t.shortName ?? _generateShortName(t.name),
          description: t.description ?? '',
          order: entry.key + 1,
        );
      }).toList();

      // Load techniques from API
      _techniquesByTactic.clear();
      final apiTechniques = await apiClient.getMitreTechniques();
      for (final t in apiTechniques) {
        final technique = MitreTechnique(
          id: t.id,
          name: t.name,
          tacticId: t.tacticId,
          description: t.description ?? '',
          platforms: t.platforms,
          mitigations: t.mitigations,
          url: t.url,
        );
        _techniquesByTactic.putIfAbsent(t.tacticId, () => []).add(technique);
      }
    } catch (e) {
      _error = 'Failed to load MITRE data: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Generate short name from tactic name
  String _generateShortName(String name) {
    if (name.contains(' ')) {
      final words = name.split(' ');
      if (words.length == 2) {
        return words[0].substring(0, words[0].length.clamp(0, 4)) +
            words[1].substring(0, words[1].length.clamp(0, 3));
      }
      return words.first.substring(0, words.first.length.clamp(0, 7));
    }
    return name.substring(0, name.length.clamp(0, 8));
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
