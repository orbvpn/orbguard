/// Threat Hunting Service
///
/// Proactive threat detection and investigation:
/// - Hypothesis-driven hunting
/// - IOC sweeping across device
/// - MITRE ATT&CK-based detection rules
/// - Automated hunt queries
/// - Threat investigation workflows
/// - Evidence collection and correlation

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/api/threat_indicator.dart';
import '../../models/api/url_reputation.dart';
import '../api/orbguard_api_client.dart';

/// Threat hunt definition
class ThreatHunt {
  final String id;
  final String name;
  final String description;
  final HuntType type;
  final String hypothesis;
  final List<HuntRule> rules;
  final List<String> mitreAttackIds;
  final HuntPriority priority;
  final DateTime createdAt;
  final String? author;

  ThreatHunt({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.hypothesis,
    required this.rules,
    required this.mitreAttackIds,
    this.priority = HuntPriority.medium,
    DateTime? createdAt,
    this.author,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// Hunt types
enum HuntType {
  iocSweep('IOC Sweep', 'Search for known indicators'),
  behaviorAnalysis('Behavior Analysis', 'Detect suspicious behaviors'),
  anomalyDetection('Anomaly Detection', 'Find statistical anomalies'),
  attackPattern('Attack Pattern', 'Match MITRE ATT&CK patterns'),
  dataExfiltration('Data Exfiltration', 'Detect data theft attempts'),
  persistenceMechanism('Persistence', 'Find persistence mechanisms'),
  lateralMovement('Lateral Movement', 'Detect spreading behavior'),
  privilegeEscalation('Privilege Escalation', 'Find escalation attempts');

  final String displayName;
  final String description;
  const HuntType(this.displayName, this.description);
}

/// Hunt priority
enum HuntPriority {
  critical,
  high,
  medium,
  low,
}

/// Hunt rule for detection
class HuntRule {
  final String id;
  final String name;
  final RuleType type;
  final String query;
  final double severity;
  final Map<String, dynamic>? parameters;

  HuntRule({
    required this.id,
    required this.name,
    required this.type,
    required this.query,
    this.severity = 0.5,
    this.parameters,
  });
}

/// Rule types
enum RuleType {
  regex,
  hash,
  domain,
  ip,
  path,
  permission,
  behavior,
  network,
  process,
}

/// Hunt result
class HuntResult {
  final String huntId;
  final DateTime startTime;
  final DateTime endTime;
  final HuntStatus status;
  final List<HuntFinding> findings;
  final int itemsScanned;
  final int rulesMatched;
  final String summary;

  /// Rules that could not be evaluated on this platform/build, keyed by
  /// rule id with a human-readable reason. These are explicitly surfaced
  /// instead of being silently reported as "clean".
  final Map<String, String> unavailableRules;

  HuntResult({
    required this.huntId,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.findings,
    required this.itemsScanned,
    required this.rulesMatched,
    required this.summary,
    this.unavailableRules = const {},
  });

  Duration get duration => endTime.difference(startTime);
  bool get hasCriticalFindings => findings.any((f) => f.severity >= 0.9);
  int get criticalCount => findings.where((f) => f.severity >= 0.9).length;
  int get highCount => findings.where((f) => f.severity >= 0.7 && f.severity < 0.9).length;
}

/// Hunt status
enum HuntStatus {
  pending,
  running,
  completed,
  failed,
  cancelled,
}

/// Individual finding from a hunt
class HuntFinding {
  final String id;
  final String ruleId;
  final String ruleName;
  final FindingType type;
  final String description;
  final double severity;
  final String evidence;
  final Map<String, dynamic> context;
  final List<String> mitreAttackIds;
  final DateTime timestamp;
  final List<String> recommendations;

  HuntFinding({
    required this.id,
    required this.ruleId,
    required this.ruleName,
    required this.type,
    required this.description,
    required this.severity,
    required this.evidence,
    required this.context,
    this.mitreAttackIds = const [],
    DateTime? timestamp,
    this.recommendations = const [],
  }) : timestamp = timestamp ?? DateTime.now();

  String get severityLevel {
    if (severity >= 0.9) return 'Critical';
    if (severity >= 0.7) return 'High';
    if (severity >= 0.5) return 'Medium';
    if (severity >= 0.3) return 'Low';
    return 'Informational';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'rule_id': ruleId,
        'rule_name': ruleName,
        'type': type.name,
        'description': description,
        'severity': severity,
        'evidence': evidence,
        'context': context,
        'mitre_attack_ids': mitreAttackIds,
        'timestamp': timestamp.toIso8601String(),
        'recommendations': recommendations,
      };

  factory HuntFinding.fromJson(Map<String, dynamic> json) {
    return HuntFinding(
      id: json['id'] as String,
      ruleId: json['rule_id'] as String? ?? '',
      ruleName: json['rule_name'] as String? ?? '',
      type: FindingType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => FindingType.suspiciousApp,
      ),
      description: json['description'] as String? ?? '',
      severity: (json['severity'] as num?)?.toDouble() ?? 0.5,
      evidence: json['evidence'] as String? ?? '',
      context: (json['context'] as Map?)?.cast<String, dynamic>() ?? {},
      mitreAttackIds:
          (json['mitre_attack_ids'] as List<dynamic>?)?.cast<String>() ?? [],
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? ''),
      recommendations:
          (json['recommendations'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}

/// Finding types
enum FindingType {
  malwareIndicator,
  suspiciousApp,
  networkAnomaly,
  dataExfiltration,
  persistenceMechanism,
  privilegeAbuse,
  configurationRisk,
  vulnerableComponent,
}

/// Investigation case
class InvestigationCase {
  final String id;
  final String title;
  final String description;
  final CaseStatus status;
  final CasePriority priority;
  final List<HuntFinding> relatedFindings;
  final List<String> notes;
  final List<TimelineEvent> timeline;
  final DateTime createdAt;
  final DateTime? closedAt;
  final String? conclusion;

  InvestigationCase({
    required this.id,
    required this.title,
    required this.description,
    this.status = CaseStatus.open,
    this.priority = CasePriority.medium,
    this.relatedFindings = const [],
    this.notes = const [],
    this.timeline = const [],
    DateTime? createdAt,
    this.closedAt,
    this.conclusion,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status.name,
        'priority': priority.name,
        'related_findings': relatedFindings.map((f) => f.toJson()).toList(),
        'notes': notes,
        'timeline': timeline.map((t) => t.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'closed_at': closedAt?.toIso8601String(),
        'conclusion': conclusion,
      };

  factory InvestigationCase.fromJson(Map<String, dynamic> json) {
    return InvestigationCase(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: CaseStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => CaseStatus.open,
      ),
      priority: CasePriority.values.firstWhere(
        (p) => p.name == json['priority'],
        orElse: () => CasePriority.medium,
      ),
      relatedFindings: (json['related_findings'] as List<dynamic>?)
              ?.map((f) => HuntFinding.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
      notes: (json['notes'] as List<dynamic>?)?.cast<String>() ?? [],
      timeline: (json['timeline'] as List<dynamic>?)
              ?.map((t) => TimelineEvent.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      closedAt: json['closed_at'] != null
          ? DateTime.tryParse(json['closed_at'] as String)
          : null,
      conclusion: json['conclusion'] as String?,
    );
  }
}

/// Case status
enum CaseStatus {
  open('Open', 'Case is open'),
  investigating('Investigating', 'Under investigation'),
  pendingAction('Pending Action', 'Awaiting action'),
  resolved('Resolved', 'Case resolved'),
  falsePositive('False Positive', 'Marked as false positive'),
  closed('Closed', 'Case closed');

  final String displayName;
  final String description;
  const CaseStatus(this.displayName, this.description);
}

/// Case priority
enum CasePriority {
  critical,
  high,
  medium,
  low,
}

/// Timeline event
class TimelineEvent {
  final DateTime timestamp;
  final String event;
  final String? actor;
  final Map<String, dynamic>? data;

  TimelineEvent({
    DateTime? timestamp,
    required this.event,
    this.actor,
    this.data,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'event': event,
        'actor': actor,
        'data': data,
      };

  factory TimelineEvent.fromJson(Map<String, dynamic> json) {
    return TimelineEvent(
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? ''),
      event: json['event'] as String? ?? '',
      actor: json['actor'] as String?,
      data: (json['data'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

/// Outcome of executing a single hunt rule.
class _RuleOutcome {
  final List<HuntFinding> findings;
  final int itemsScanned;

  /// Non-null when the rule could not be evaluated on this platform/build.
  final String? unavailableReason;

  const _RuleOutcome({
    this.findings = const [],
    this.itemsScanned = 0,
    this.unavailableReason,
  });
}

/// Thrown internally when a native capability is not present.
class _CapabilityUnavailable implements Exception {
  final String reason;
  _CapabilityUnavailable(this.reason);

  @override
  String toString() => reason;
}

/// Threat Hunting Service
class ThreatHuntingService {
  // Real native channels implemented by the device agent
  // (android/app/src/main/kotlin/com/orb/guard/MainActivity.kt).
  static const MethodChannel _systemChannel =
      MethodChannel('com.orb.guard/system');
  static const MethodChannel _wifiChannel =
      MethodChannel('com.orb.guard/wifi');
  static const MethodChannel _browserChannel =
      MethodChannel('com.orb.guard/browser');

  static const String _casesPrefsKey = 'threat_hunting.cases';

  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // Available hunts
  final List<ThreatHunt> _availableHunts = [];

  // Per-hunt-execution caches (cleared at the start of each hunt)
  List<Map<String, dynamic>>? _installedAppsCache;
  bool _wifiPostureEvaluated = false;

  // Hunt results
  final Map<String, HuntResult> _huntResults = {};

  // Investigation cases
  final Map<String, InvestigationCase> _cases = {};

  // Active hunts
  final Set<String> _activeHunts = {};

  // Stream controllers
  final _huntProgressController = StreamController<HuntProgress>.broadcast();
  final _findingController = StreamController<HuntFinding>.broadcast();
  final _caseUpdateController = StreamController<InvestigationCase>.broadcast();

  /// Stream of hunt progress
  Stream<HuntProgress> get onHuntProgress => _huntProgressController.stream;

  /// Stream of findings
  Stream<HuntFinding> get onFinding => _findingController.stream;

  /// Stream of case updates
  Stream<InvestigationCase> get onCaseUpdate => _caseUpdateController.stream;

  /// Initialize the service
  Future<void> initialize() async {
    _loadBuiltInHunts();
    await _loadPersistedCases();
  }

  /// Load investigation cases persisted on-device.
  /// The backend has no investigation-case endpoint, so cases live in
  /// SharedPreferences (same on-device persistence pattern as the rest of
  /// the app).
  Future<void> _loadPersistedCases() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_casesPrefsKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      _cases.clear();
      for (final entry in decoded) {
        if (entry is! Map) continue;
        try {
          final investigation =
              InvestigationCase.fromJson(entry.cast<String, dynamic>());
          _cases[investigation.id] = investigation;
        } catch (e) {
          debugPrint('ThreatHunting: skipping corrupt persisted case: $e');
        }
      }
    } catch (e) {
      debugPrint('ThreatHunting: failed to load persisted cases: $e');
    }
  }

  Future<void> _persistCases() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload =
          jsonEncode(_cases.values.map((c) => c.toJson()).toList());
      await prefs.setString(_casesPrefsKey, payload);
    } catch (e) {
      debugPrint('ThreatHunting: failed to persist cases: $e');
    }
  }

  /// Load built-in threat hunts
  void _loadBuiltInHunts() {
    _availableHunts.addAll([
      // Malware IOC Sweep
      ThreatHunt(
        id: 'hunt_malware_ioc',
        name: 'Malware IOC Sweep',
        description: 'Search for known malware indicators across installed apps and files',
        type: HuntType.iocSweep,
        hypothesis: 'Device may contain known malware based on threat intelligence',
        rules: [
          HuntRule(
            id: 'rule_malware_hash',
            name: 'Known Malware Hash',
            type: RuleType.hash,
            query: 'SHA256_HASH_LIST',
            severity: 1.0,
          ),
          HuntRule(
            id: 'rule_malware_domain',
            name: 'Known C2 Domain',
            type: RuleType.domain,
            query: r'(malware|c2|evil)\.(xyz|tk|ml|ga)',
            severity: 0.9,
          ),
          HuntRule(
            id: 'rule_malware_package',
            name: 'Known Malware Package',
            type: RuleType.path,
            query: 'KNOWN_MALWARE_PACKAGES',
            severity: 1.0,
          ),
        ],
        mitreAttackIds: ['T1204', 'T1566'],
        priority: HuntPriority.high,
      ),

      // Spyware Detection
      ThreatHunt(
        id: 'hunt_spyware',
        name: 'Spyware Detection',
        description: 'Detect stalkerware and commercial spyware',
        type: HuntType.behaviorAnalysis,
        hypothesis: 'Device may have surveillance software installed',
        rules: [
          HuntRule(
            id: 'rule_spy_accessibility',
            name: 'Accessibility Service Abuse',
            type: RuleType.permission,
            query: 'BIND_ACCESSIBILITY_SERVICE',
            severity: 0.7,
          ),
          HuntRule(
            id: 'rule_spy_device_admin',
            name: 'Device Admin Abuse',
            type: RuleType.permission,
            query: 'BIND_DEVICE_ADMIN',
            severity: 0.8,
          ),
          HuntRule(
            id: 'rule_spy_hidden_app',
            name: 'Hidden App Detection',
            type: RuleType.behavior,
            query: 'NO_LAUNCHER_ICON && BACKGROUND_SERVICE',
            severity: 0.9,
          ),
        ],
        mitreAttackIds: ['T1417', 'T1429', 'T1512'],
        priority: HuntPriority.high,
      ),

      // Data Exfiltration
      ThreatHunt(
        id: 'hunt_exfil',
        name: 'Data Exfiltration Detection',
        description: 'Detect potential data theft activities',
        type: HuntType.dataExfiltration,
        hypothesis: 'App may be stealing sensitive data',
        rules: [
          HuntRule(
            id: 'rule_exfil_contacts',
            name: 'Contact Exfiltration',
            type: RuleType.behavior,
            query: 'READ_CONTACTS && INTERNET && HIGH_NETWORK_TX',
            severity: 0.8,
          ),
          HuntRule(
            id: 'rule_exfil_sms',
            name: 'SMS Exfiltration',
            type: RuleType.behavior,
            query: 'READ_SMS && INTERNET',
            severity: 0.9,
          ),
          HuntRule(
            id: 'rule_exfil_files',
            name: 'File Exfiltration',
            type: RuleType.behavior,
            query: 'READ_EXTERNAL_STORAGE && HIGH_NETWORK_TX',
            severity: 0.7,
          ),
        ],
        mitreAttackIds: ['T1533', 'T1636', 'T1537'],
        priority: HuntPriority.critical,
      ),

      // Persistence Mechanisms
      ThreatHunt(
        id: 'hunt_persistence',
        name: 'Persistence Mechanism Detection',
        description: 'Find apps establishing persistence',
        type: HuntType.persistenceMechanism,
        hypothesis: 'Malware may have established persistence',
        rules: [
          HuntRule(
            id: 'rule_persist_boot',
            name: 'Boot Persistence',
            type: RuleType.permission,
            query: 'RECEIVE_BOOT_COMPLETED',
            severity: 0.5,
          ),
          HuntRule(
            id: 'rule_persist_alarm',
            name: 'Alarm-based Persistence',
            type: RuleType.behavior,
            query: 'SCHEDULE_EXACT_ALARM && BACKGROUND_SERVICE',
            severity: 0.6,
          ),
          HuntRule(
            id: 'rule_persist_foreground',
            name: 'Foreground Service Persistence',
            type: RuleType.behavior,
            query: 'FOREGROUND_SERVICE && NO_USER_INTERACTION',
            severity: 0.7,
          ),
        ],
        mitreAttackIds: ['T1398', 'T1624'],
        priority: HuntPriority.medium,
      ),

      // Network Anomalies
      ThreatHunt(
        id: 'hunt_network',
        name: 'Network Anomaly Detection',
        description: 'Detect suspicious network activity',
        type: HuntType.anomalyDetection,
        hypothesis: 'App may be communicating with malicious servers',
        rules: [
          HuntRule(
            id: 'rule_net_unusual_port',
            name: 'Unusual Port Communication',
            type: RuleType.network,
            query: 'PORT NOT IN (80, 443, 8080, 8443)',
            severity: 0.6,
          ),
          HuntRule(
            id: 'rule_net_dns_tunnel',
            name: 'DNS Tunneling',
            type: RuleType.network,
            query: 'HIGH_DNS_QUERY_LENGTH || UNUSUAL_DNS_PATTERN',
            severity: 0.8,
          ),
          HuntRule(
            id: 'rule_net_beaconing',
            name: 'C2 Beaconing',
            type: RuleType.network,
            query: 'PERIODIC_CONNECTIONS && FIXED_INTERVAL',
            severity: 0.9,
          ),
        ],
        mitreAttackIds: ['T1571', 'T1573', 'T1071'],
        priority: HuntPriority.high,
      ),

      // Privilege Escalation
      ThreatHunt(
        id: 'hunt_privesc',
        name: 'Privilege Escalation Detection',
        description: 'Detect attempts to gain elevated privileges',
        type: HuntType.privilegeEscalation,
        hypothesis: 'App may be attempting to escalate privileges',
        rules: [
          HuntRule(
            id: 'rule_privesc_root',
            name: 'Root Access Attempt',
            type: RuleType.behavior,
            query: 'SU_BINARY_ACCESS || ROOT_CHECK',
            severity: 0.9,
          ),
          HuntRule(
            id: 'rule_privesc_exploit',
            name: 'Exploit Attempt',
            type: RuleType.behavior,
            query: 'NATIVE_CODE && SYSTEM_CALL_ANOMALY',
            severity: 1.0,
          ),
        ],
        mitreAttackIds: ['T1404', 'T1428'],
        priority: HuntPriority.critical,
      ),
    ]);
  }

  /// Get available hunts
  List<ThreatHunt> getAvailableHunts({HuntType? type, HuntPriority? minPriority}) {
    var hunts = _availableHunts.toList();

    if (type != null) {
      hunts = hunts.where((h) => h.type == type).toList();
    }

    if (minPriority != null) {
      hunts = hunts.where((h) => h.priority.index <= minPriority.index).toList();
    }

    return hunts;
  }

  /// Execute a threat hunt
  Future<HuntResult> executeHunt(String huntId) async {
    final hunt = _availableHunts.firstWhere(
      (h) => h.id == huntId,
      orElse: () => throw ArgumentError('Hunt not found: $huntId'),
    );

    if (_activeHunts.contains(huntId)) {
      throw StateError('Hunt already running: $huntId');
    }

    _activeHunts.add(huntId);
    final startTime = DateTime.now();
    final findings = <HuntFinding>[];
    final unavailableRules = <String, String>{};
    int itemsScanned = 0;
    int rulesMatched = 0;

    // Reset per-execution caches so each hunt sees fresh device state.
    _installedAppsCache = null;
    _wifiPostureEvaluated = false;

    try {
      _huntProgressController.add(HuntProgress(
        huntId: huntId,
        phase: 'Initializing',
        progress: 0.0,
      ));

      // Execute each rule
      for (int i = 0; i < hunt.rules.length; i++) {
        final rule = hunt.rules[i];

        _huntProgressController.add(HuntProgress(
          huntId: huntId,
          phase: 'Executing: ${rule.name}',
          progress: (i + 1) / hunt.rules.length,
        ));

        final outcome = await _executeRule(rule, hunt);
        findings.addAll(outcome.findings);
        itemsScanned += outcome.itemsScanned;

        if (outcome.unavailableReason != null) {
          unavailableRules[rule.id] = outcome.unavailableReason!;
          debugPrint(
              'ThreatHunting: rule ${rule.id} unavailable: ${outcome.unavailableReason}');
        }

        if (outcome.findings.isNotEmpty) {
          rulesMatched++;
          for (final finding in outcome.findings) {
            _findingController.add(finding);
          }
        }
      }

      final result = HuntResult(
        huntId: huntId,
        startTime: startTime,
        endTime: DateTime.now(),
        status: HuntStatus.completed,
        findings: findings,
        itemsScanned: itemsScanned,
        rulesMatched: rulesMatched,
        summary: _generateHuntSummary(hunt, findings,
            unavailableRules: unavailableRules),
        unavailableRules: unavailableRules,
      );

      _huntResults[huntId] = result;

      _huntProgressController.add(HuntProgress(
        huntId: huntId,
        phase: 'Completed',
        progress: 1.0,
      ));

      return result;
    } catch (e) {
      final result = HuntResult(
        huntId: huntId,
        startTime: startTime,
        endTime: DateTime.now(),
        status: HuntStatus.failed,
        findings: findings,
        itemsScanned: itemsScanned,
        rulesMatched: rulesMatched,
        summary: 'Hunt failed: $e',
        unavailableRules: unavailableRules,
      );

      _huntResults[huntId] = result;
      return result;
    } finally {
      _activeHunts.remove(huntId);
    }
  }

  /// Execute a single rule
  Future<_RuleOutcome> _executeRule(HuntRule rule, ThreatHunt hunt) async {
    switch (rule.type) {
      case RuleType.permission:
        return _checkPermissions(rule, hunt);
      case RuleType.behavior:
        return _checkBehaviors(rule, hunt);
      case RuleType.network:
        return _checkNetwork(rule, hunt);
      case RuleType.hash:
        return _checkHashes(rule, hunt);
      case RuleType.domain:
        return _checkDomains(rule, hunt);
      case RuleType.path:
        return _checkPaths(rule, hunt);
      default:
        return _RuleOutcome(
          unavailableReason:
              'No rule engine implemented for type "${rule.type.name}"',
        );
    }
  }

  /// Fetch the installed-app inventory from the device agent
  /// (com.orb.guard/system -> getInstalledApps). Cached per hunt execution.
  Future<List<Map<String, dynamic>>> _getInstalledApps() async {
    if (_installedAppsCache != null) return _installedAppsCache!;

    if (!Platform.isAndroid) {
      throw _CapabilityUnavailable(
          'Installed-app inventory is only available on Android');
    }

    try {
      final result = await _systemChannel
          .invokeMethod<Map<dynamic, dynamic>>('getInstalledApps');
      final rawApps = result?['apps'];
      if (rawApps is! List) {
        throw _CapabilityUnavailable(
            'Device agent returned no app inventory');
      }
      _installedAppsCache = rawApps
          .whereType<Map>()
          .map((a) => a.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      return _installedAppsCache!;
    } on MissingPluginException {
      throw _CapabilityUnavailable(
          'Device agent app-inventory channel (com.orb.guard/system) '
          'is not implemented on this platform');
    } on PlatformException catch (e) {
      throw _CapabilityUnavailable(
          'Device agent app-inventory call failed: ${e.message}');
    }
  }

  /// Check permission-based rules against the real installed-app inventory.
  Future<_RuleOutcome> _checkPermissions(HuntRule rule, ThreatHunt hunt) async {
    final List<Map<String, dynamic>> apps;
    try {
      apps = await _getInstalledApps();
    } on _CapabilityUnavailable catch (e) {
      return _RuleOutcome(unavailableReason: e.reason);
    }

    final findings = <HuntFinding>[];
    final query = rule.query.toLowerCase();

    for (final app in apps) {
      final isSystemApp = app['isSystemApp'] == true;
      if (isSystemApp) continue; // System apps legitimately hold these.

      final permissions = (app['permissions'] as List<dynamic>? ?? [])
          .map((p) => p.toString().toLowerCase());
      final matched = permissions.any((p) => p.contains(query));
      if (!matched) continue;

      final packageName = app['packageName']?.toString() ?? 'unknown';
      final appName = app['appName']?.toString() ?? packageName;
      findings.add(HuntFinding(
        id: 'finding_perm_${packageName}_${rule.id}',
        ruleId: rule.id,
        ruleName: rule.name,
        type: FindingType.suspiciousApp,
        description: 'App "$appName" requests ${rule.query}',
        severity: rule.severity,
        evidence: 'Package: $packageName, Permission: ${rule.query}, '
            'Installer: ${app['installerPackage'] ?? 'unknown'}',
        context: app,
        mitreAttackIds: hunt.mitreAttackIds,
        recommendations: [
          'Review app permissions',
          'Consider uninstalling if unnecessary',
        ],
      ));
    }

    return _RuleOutcome(findings: findings, itemsScanned: apps.length);
  }

  /// Check behavior-based rules. The device agent does not currently expose
  /// runtime behavior telemetry (launcher visibility, background services,
  /// network volume per app), so behavior queries are reported as
  /// unavailable rather than silently returning a clean result.
  Future<_RuleOutcome> _checkBehaviors(HuntRule rule, ThreatHunt hunt) async {
    // Permission-combination behavior queries can be partially evaluated
    // from the static app inventory (requested permissions).
    final permissionTokens = <String>[
      'READ_CONTACTS',
      'READ_SMS',
      'READ_EXTERNAL_STORAGE',
      'SCHEDULE_EXACT_ALARM',
      'FOREGROUND_SERVICE',
      'INTERNET',
    ].where((t) => rule.query.contains(t)).toList();

    final runtimeTokens = <String>[
      'NO_LAUNCHER_ICON',
      'BACKGROUND_SERVICE',
      'HIGH_NETWORK_TX',
      'NO_USER_INTERACTION',
      'SU_BINARY_ACCESS',
      'ROOT_CHECK',
      'NATIVE_CODE',
      'SYSTEM_CALL_ANOMALY',
    ].where((t) => rule.query.contains(t)).toList();

    if (permissionTokens.isEmpty) {
      return _RuleOutcome(
        unavailableReason: 'Behavior query "${rule.query}" requires runtime '
            'telemetry (${runtimeTokens.join(', ')}) that the device agent '
            'does not expose yet',
      );
    }

    final List<Map<String, dynamic>> apps;
    try {
      apps = await _getInstalledApps();
    } on _CapabilityUnavailable catch (e) {
      return _RuleOutcome(unavailableReason: e.reason);
    }

    final findings = <HuntFinding>[];
    for (final app in apps) {
      if (app['isSystemApp'] == true) continue;

      final permissions = (app['permissions'] as List<dynamic>? ?? [])
          .map((p) => p.toString())
          .toList();
      final hasAll = permissionTokens.every(
          (token) => permissions.any((p) => p.contains(token)));
      if (!hasAll) continue;

      final packageName = app['packageName']?.toString() ?? 'unknown';
      final appName = app['appName']?.toString() ?? packageName;
      findings.add(HuntFinding(
        id: 'finding_behavior_${packageName}_${rule.id}',
        ruleId: rule.id,
        ruleName: rule.name,
        type: FindingType.suspiciousApp,
        description:
            'App "$appName" holds the permission combination '
            '${permissionTokens.join(' + ')}',
        severity: rule.severity *
            (runtimeTokens.isEmpty ? 1.0 : 0.8), // static-only evidence
        evidence: 'Package: $packageName, Permissions: '
            '${permissionTokens.join(', ')}'
            '${runtimeTokens.isEmpty ? '' : ' (runtime signals '
                '${runtimeTokens.join(', ')} not evaluated — '
                'no runtime telemetry available)'}',
        context: app,
        mitreAttackIds: hunt.mitreAttackIds,
        recommendations: [
          'Review whether this app needs these permissions',
          'Revoke permissions or uninstall if unexpected',
        ],
      ));
    }

    return _RuleOutcome(findings: findings, itemsScanned: apps.length);
  }

  /// Check network-based rules using the device agent's Wi-Fi channel
  /// (com.orb.guard/wifi -> getCurrentNetwork). Per-flow traffic analytics
  /// (ports, DNS patterns, beaconing intervals) require packet capture that
  /// is not available on-device, so those query semantics are explicitly
  /// reported as unavailable; the current network's security posture IS
  /// evaluated from real data.
  Future<_RuleOutcome> _checkNetwork(HuntRule rule, ThreatHunt hunt) async {
    Map<dynamic, dynamic>? network;
    try {
      network =
          await _wifiChannel.invokeMethod<Map<dynamic, dynamic>>('getCurrentNetwork');
    } on MissingPluginException {
      return const _RuleOutcome(
        unavailableReason:
            'Wi-Fi telemetry channel (com.orb.guard/wifi) is not implemented '
            'on this platform',
      );
    } on PlatformException catch (e) {
      return _RuleOutcome(
        unavailableReason: 'getCurrentNetwork failed: ${e.message}',
      );
    }

    final findings = <HuntFinding>[];
    var itemsScanned = 0;

    // Evaluate the connected network's security posture once per hunt run
    // (the posture is a property of the network, not of each rule).
    if (!_wifiPostureEvaluated && network != null) {
      _wifiPostureEvaluated = true;
      itemsScanned = 1;

      final ssid = network['ssid']?.toString() ?? 'Unknown';
      final bssid = network['bssid']?.toString() ?? '';
      final security = (network['security']?.toString() ?? '').toLowerCase();

      double? postureSeverity;
      String? postureIssue;
      if (security.isEmpty || security == 'unknown') {
        postureSeverity = null; // No claim without data.
      } else if (security.contains('open') || security == 'none') {
        postureSeverity = 0.8;
        postureIssue = 'unencrypted (open) network';
      } else if (security.contains('wep')) {
        postureSeverity = 0.9;
        postureIssue = 'WEP encryption (broken, trivially crackable)';
      } else if (security.contains('wpa') &&
          !security.contains('wpa2') &&
          !security.contains('wpa3')) {
        postureSeverity = 0.6;
        postureIssue = 'legacy WPA(1) encryption';
      }

      if (postureSeverity != null) {
        findings.add(HuntFinding(
          id: 'finding_wifi_${bssid.isEmpty ? ssid : bssid}_${hunt.id}',
          ruleId: rule.id,
          ruleName: rule.name,
          type: FindingType.networkAnomaly,
          description:
              'Connected Wi-Fi network "$ssid" uses $postureIssue',
          severity: postureSeverity,
          evidence: 'SSID: $ssid, BSSID: $bssid, Security: $security '
              '(reported by device Wi-Fi agent)',
          context: network.map((k, v) => MapEntry(k.toString(), v)),
          mitreAttackIds: hunt.mitreAttackIds,
          recommendations: [
            'Avoid sensitive activity on this network',
            'Use a VPN while connected',
            'Switch to a WPA2/WPA3 protected network',
          ],
        ));
      }
    }

    if (findings.isEmpty) {
      return _RuleOutcome(
        itemsScanned: itemsScanned,
        unavailableReason:
            'Rule query "${rule.query}" requires on-device traffic capture '
            'which is not available; current Wi-Fi posture was evaluated '
            'via getCurrentNetwork and raised no findings',
      );
    }

    return _RuleOutcome(findings: findings, itemsScanned: itemsScanned);
  }

  /// Check hash/IOC rules. The device agent does not expose APK file bytes
  /// for SHA-256 computation, so this sweeps the real installed-app
  /// inventory (package names from getInstalledApps) against the live
  /// threat-intelligence service via POST /indicators/check.
  Future<_RuleOutcome> _checkHashes(HuntRule rule, ThreatHunt hunt) async {
    final List<Map<String, dynamic>> apps;
    try {
      apps = await _getInstalledApps();
    } on _CapabilityUnavailable catch (e) {
      return _RuleOutcome(unavailableReason: e.reason);
    }

    // Sweep non-system packages (sideloaded/user-installed apps are the
    // realistic malware delivery channel on Android).
    final candidates = apps
        .where((a) => a['isSystemApp'] != true)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return const _RuleOutcome(itemsScanned: 0);
    }

    final byPackage = <String, Map<String, dynamic>>{
      for (final app in candidates)
        if (app['packageName'] != null) app['packageName'].toString(): app,
    };

    final findings = <HuntFinding>[];
    try {
      final packageNames = byPackage.keys.toList();
      const chunkSize = 100;
      for (var i = 0; i < packageNames.length; i += chunkSize) {
        final chunk = packageNames.sublist(
            i,
            (i + chunkSize) > packageNames.length
                ? packageNames.length
                : i + chunkSize);
        final results = await _api.checkIndicators(
          chunk.map((p) => IndicatorCheckRequest(value: p)).toList(),
        );

        for (final result in results.where((r) => r.isThreat)) {
          final app = byPackage[result.value];
          final appName =
              app?['appName']?.toString() ?? result.value;
          findings.add(HuntFinding(
            id: 'finding_ioc_${result.value}_${rule.id}',
            ruleId: rule.id,
            ruleName: rule.name,
            type: FindingType.malwareIndicator,
            description:
                'Installed app "$appName" matches a known threat indicator',
            severity: _severityToDouble(result.severity, rule.severity),
            evidence: 'Package: ${result.value} flagged by threat '
                'intelligence (confidence: '
                '${result.confidence?.toStringAsFixed(2) ?? 'n/a'}'
                '${result.campaignName != null ? ', campaign: ${result.campaignName}' : ''}). '
                'Note: matched on package identity; APK hash computation is '
                'not available from the device agent.',
            context: {
              if (app != null) ...app,
              'indicator_type': result.type?.value,
              'tags': result.tags,
              'intel_description': result.description,
            },
            mitreAttackIds: result.mitreTechniques?.isNotEmpty == true
                ? result.mitreTechniques!
                : hunt.mitreAttackIds,
            recommendations: [
              'Uninstall this app immediately',
              'Run a full device scan',
              'Change credentials used on this device',
            ],
          ));
        }
      }
    } catch (e) {
      return _RuleOutcome(
        itemsScanned: candidates.length,
        unavailableReason:
            'Threat-intelligence indicator check (/indicators/check) '
            'failed: $e',
      );
    }

    return _RuleOutcome(findings: findings, itemsScanned: candidates.length);
  }

  /// Check domain rules against the URLs the browser-protection agent has
  /// actually observed on this device (com.orb.guard/browser ->
  /// getAnalyzedUrls), via the live POST /url/check[/batch] endpoint plus
  /// the rule's own domain regex.
  Future<_RuleOutcome> _checkDomains(HuntRule rule, ThreatHunt hunt) async {
    List<dynamic> rawUrls;
    try {
      final result = await _browserChannel
          .invokeMethod<Map<dynamic, dynamic>>('getAnalyzedUrls');
      rawUrls = result?['urls'] as List<dynamic>? ?? const [];
    } on MissingPluginException {
      return const _RuleOutcome(
        unavailableReason:
            'Browser URL-history channel (com.orb.guard/browser) is not '
            'implemented on this platform',
      );
    } on PlatformException catch (e) {
      return _RuleOutcome(
        unavailableReason: 'getAnalyzedUrls failed: ${e.message}',
      );
    }

    // Deduplicate observed URLs and extract domains.
    final urls = <String>{};
    final domainsByUrl = <String, String>{};
    for (final entry in rawUrls) {
      if (entry is! Map) continue;
      final url = entry['url']?.toString();
      if (url == null || url.isEmpty) continue;
      urls.add(url);
      final domain = entry['domain']?.toString() ??
          Uri.tryParse(url)?.host ??
          '';
      if (domain.isNotEmpty) domainsByUrl[url] = domain;
    }

    if (urls.isEmpty) {
      // Honest empty: the browser agent has not observed any URLs yet.
      return const _RuleOutcome(itemsScanned: 0);
    }

    final findings = <HuntFinding>[];

    // 1) Local rule regex against observed domains.
    RegExp? pattern;
    try {
      pattern = RegExp(rule.query, caseSensitive: false);
    } on FormatException {
      pattern = null; // Query is an IOC-set placeholder, not a regex.
    }
    if (pattern != null) {
      for (final entry in domainsByUrl.entries) {
        if (!pattern.hasMatch(entry.value)) continue;
        findings.add(HuntFinding(
          id: 'finding_domain_rx_${entry.value}_${rule.id}',
          ruleId: rule.id,
          ruleName: rule.name,
          type: FindingType.malwareIndicator,
          description:
              'Visited domain "${entry.value}" matches hunt pattern',
          severity: rule.severity,
          evidence: 'URL: ${entry.key} matched pattern ${rule.query} '
              '(observed by browser protection agent)',
          context: {'url': entry.key, 'domain': entry.value},
          mitreAttackIds: hunt.mitreAttackIds,
          recommendations: [
            'Do not revisit this site',
            'Clear browser data and saved credentials for this site',
          ],
        ));
      }
    }

    // 2) Live reputation check via the backend URL service.
    try {
      final urlList = urls.toList();
      const chunkSize = 50;
      for (var i = 0; i < urlList.length; i += chunkSize) {
        final chunk = urlList.sublist(
            i,
            (i + chunkSize) > urlList.length ? urlList.length : i + chunkSize);
        final List<UrlReputationResult> results = chunk.length == 1
            ? [await _api.checkUrl(chunk.first)]
            : await _api.checkUrlsBatch(chunk);

        for (final result in results) {
          if (result.isSafe && !result.shouldBlock) continue;
          findings.add(HuntFinding(
            id: 'finding_domain_intel_${result.domain}_${rule.id}',
            ruleId: rule.id,
            ruleName: rule.name,
            type: FindingType.malwareIndicator,
            description:
                'Visited domain "${result.domain}" is flagged as '
                '${result.category.name} by threat intelligence',
            severity: _severityToDouble(result.threatLevel, rule.severity),
            evidence: 'URL: ${result.url}, category: ${result.category.name}, '
                'threat level: ${result.threatLevel.value}, confidence: '
                '${result.confidence.toStringAsFixed(2)}'
                '${result.campaignName != null ? ', campaign: ${result.campaignName}' : ''}',
            context: {
              'url': result.url,
              'domain': result.domain,
              'category': result.category.name,
              'warnings': result.warnings,
              'block_reason': result.blockReason,
            },
            mitreAttackIds: hunt.mitreAttackIds,
            recommendations: [
              if (result.recommendation != null) result.recommendation!,
              'Avoid this site and check for credential reuse',
            ],
          ));
        }
      }
    } catch (e) {
      return _RuleOutcome(
        findings: findings,
        itemsScanned: urls.length,
        unavailableReason:
            'URL reputation check (/url/check) failed: $e — only the local '
            'pattern match was evaluated',
      );
    }

    return _RuleOutcome(findings: findings, itemsScanned: urls.length);
  }

  /// Check path-based rules. Like the hash rule, the package inventory is
  /// the available evidence surface; known-malware package identifiers are
  /// already swept by the hash/IOC rule against /indicators/check, and raw
  /// file-system path scanning is not exposed by the device agent.
  Future<_RuleOutcome> _checkPaths(HuntRule rule, ThreatHunt hunt) async {
    if (rule.query == 'KNOWN_MALWARE_PACKAGES') {
      final hasHashRule = hunt.rules.any((r) => r.type == RuleType.hash);
      if (hasHashRule) {
        // The hash/IOC rule in this hunt already sweeps the package
        // inventory against /indicators/check; re-running it here would
        // double-report the same evidence under a second rule id.
        return const _RuleOutcome(
          unavailableReason:
              'Package-identity sweep is covered by the IOC hash rule in '
              'this hunt; raw file-system path scanning is not exposed by '
              'the device agent',
        );
      }
      // Same evidence surface and intelligence source as the hash rule.
      return _checkHashes(rule, hunt);
    }
    return _RuleOutcome(
      unavailableReason:
          'File-system path scanning for "${rule.query}" requires native '
          'file access the device agent does not expose',
    );
  }

  /// Map backend severity levels onto the 0..1 finding scale, falling back
  /// to the rule's static severity when the backend gives no signal.
  double _severityToDouble(SeverityLevel? level, double fallback) {
    if (level == null || level == SeverityLevel.unknown) return fallback;
    return (level.score / 10.0).clamp(0.0, 1.0);
  }

  /// Generate hunt summary
  String _generateHuntSummary(
    ThreatHunt hunt,
    List<HuntFinding> findings, {
    Map<String, String> unavailableRules = const {},
  }) {
    final unavailableNote = unavailableRules.isEmpty
        ? ''
        : ' ${unavailableRules.length} rule(s) could not be evaluated on '
            'this device (see rule details).';

    if (findings.isEmpty) {
      if (unavailableRules.length == hunt.rules.length) {
        return '${hunt.name}: no rules could be evaluated on this device — '
            'result is inconclusive, not clean.$unavailableNote';
      }
      return 'No threats detected during ${hunt.name}.$unavailableNote';
    }

    final critical = findings.where((f) => f.severity >= 0.9).length;
    final high = findings.where((f) => f.severity >= 0.7 && f.severity < 0.9).length;

    return '${hunt.name} completed: ${findings.length} findings '
        '($critical critical, $high high risk). '
        'Immediate attention ${critical > 0 ? "required" : "recommended"}.'
        '$unavailableNote';
  }

  /// Execute all critical hunts
  Future<List<HuntResult>> executeAllCriticalHunts() async {
    final criticalHunts = _availableHunts.where(
      (h) => h.priority == HuntPriority.critical || h.priority == HuntPriority.high
    );

    final results = <HuntResult>[];
    for (final hunt in criticalHunts) {
      final result = await executeHunt(hunt.id);
      results.add(result);
    }

    return results;
  }

  /// Create investigation case from findings
  InvestigationCase createCase(
    String title,
    String description,
    List<HuntFinding> findings, {
    CasePriority priority = CasePriority.medium,
  }) {
    final caseId = 'case_${DateTime.now().millisecondsSinceEpoch}';

    final investigation = InvestigationCase(
      id: caseId,
      title: title,
      description: description,
      priority: priority,
      relatedFindings: findings,
      timeline: [
        TimelineEvent(event: 'Case created'),
        ...findings.map((f) => TimelineEvent(
          event: 'Finding added: ${f.description}',
          data: {'finding_id': f.id},
        )),
      ],
    );

    _cases[caseId] = investigation;
    _caseUpdateController.add(investigation);

    // Persist on-device (no backend investigation-case endpoint exists).
    unawaited(_persistCases());

    return investigation;
  }

  /// Get all investigation cases
  List<InvestigationCase> getCases({CaseStatus? status}) {
    var cases = _cases.values.toList();

    if (status != null) {
      cases = cases.where((c) => c.status == status).toList();
    }

    return cases..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Get hunt results
  HuntResult? getHuntResult(String huntId) => _huntResults[huntId];

  /// Get service statistics
  Map<String, dynamic> getStatistics() {
    return {
      'available_hunts': _availableHunts.length,
      'completed_hunts': _huntResults.length,
      'active_hunts': _activeHunts.length,
      'open_cases': _cases.values.where((c) => c.status == CaseStatus.open).length,
      'total_findings': _huntResults.values.fold<int>(
        0, (sum, r) => sum + r.findings.length
      ),
    };
  }

  /// Dispose resources
  void dispose() {
    _huntProgressController.close();
    _findingController.close();
    _caseUpdateController.close();
  }
}

/// Hunt progress update
class HuntProgress {
  final String huntId;
  final String phase;
  final double progress;

  HuntProgress({
    required this.huntId,
    required this.phase,
    required this.progress,
  });
}
