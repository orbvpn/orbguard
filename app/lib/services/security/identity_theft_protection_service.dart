/// Identity Theft Protection Service
///
/// Comprehensive identity monitoring and protection:
/// - SSN exposure monitoring
/// - Credit monitoring alerts
/// - Bank account monitoring
/// - Address change detection
/// - Identity fraud alerts
/// - Credit freeze recommendations
/// - Identity recovery assistance

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Identity monitoring status
enum MonitoringStatus {
  active('Active', 'Monitoring enabled'),
  paused('Paused', 'Monitoring temporarily paused'),
  inactive('Inactive', 'Monitoring not configured'),
  alertTriggered('Alert', 'Action required');

  final String displayName;
  final String description;

  const MonitoringStatus(this.displayName, this.description);
}

/// Type of identity alert
enum IdentityAlertType {
  ssnExposure('SSN Exposure', 'Your Social Security Number was found', AlertSeverity.critical),
  creditInquiry('Credit Inquiry', 'New credit inquiry detected', AlertSeverity.high),
  newAccount('New Account', 'New account opened in your name', AlertSeverity.critical),
  addressChange('Address Change', 'Address change detected', AlertSeverity.high),
  bankAccountExposure('Bank Exposure', 'Bank account information exposed', AlertSeverity.critical),
  creditScoreChange('Score Change', 'Significant credit score change', AlertSeverity.medium),
  publicRecords('Public Records', 'New public record in your name', AlertSeverity.medium),
  darkWebExposure('Dark Web', 'Personal info found on dark web', AlertSeverity.high),
  paydayLoan('Payday Loan', 'Payday loan application detected', AlertSeverity.high),
  sexOffenderRegistry('Registry Alert', 'Name appeared in registry', AlertSeverity.critical),
  courtRecords('Court Records', 'New court record filed', AlertSeverity.medium),
  utilityAccount('Utility Account', 'New utility account opened', AlertSeverity.medium);

  final String displayName;
  final String description;
  final AlertSeverity defaultSeverity;

  const IdentityAlertType(this.displayName, this.description, this.defaultSeverity);
}

/// Alert severity level
enum AlertSeverity {
  critical('Critical', 5),
  high('High', 4),
  medium('Medium', 3),
  low('Low', 2),
  info('Info', 1);

  final String displayName;
  final int weight;

  const AlertSeverity(this.displayName, this.weight);
}

/// Credit bureau
enum CreditBureau {
  equifax('Equifax'),
  experian('Experian'),
  transunion('TransUnion');

  final String displayName;

  const CreditBureau(this.displayName);
}

/// Monitored identity asset
class MonitoredAsset {
  final String id;
  final AssetType type;
  final String maskedValue;
  final String hashedValue;
  final DateTime addedDate;
  final DateTime? lastChecked;
  final MonitoringStatus status;
  final int alertCount;

  MonitoredAsset({
    required this.id,
    required this.type,
    required this.maskedValue,
    required this.hashedValue,
    required this.addedDate,
    this.lastChecked,
    this.status = MonitoringStatus.active,
    this.alertCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'masked_value': maskedValue,
    'hashed_value': hashedValue,
    'added_date': addedDate.toIso8601String(),
    'last_checked': lastChecked?.toIso8601String(),
    'status': status.name,
    'alert_count': alertCount,
  };

  factory MonitoredAsset.fromJson(Map<String, dynamic> json) {
    return MonitoredAsset(
      id: json['id'] as String,
      type: AssetType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AssetType.other,
      ),
      maskedValue: json['masked_value'] as String,
      hashedValue: json['hashed_value'] as String,
      addedDate: DateTime.parse(json['added_date'] as String),
      lastChecked: json['last_checked'] != null
          ? DateTime.parse(json['last_checked'] as String)
          : null,
      status: MonitoringStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => MonitoringStatus.inactive,
      ),
      alertCount: json['alert_count'] as int? ?? 0,
    );
  }
}

/// Type of monitored asset
enum AssetType {
  ssn('Social Security Number'),
  creditCard('Credit Card'),
  bankAccount('Bank Account'),
  email('Email Address'),
  phone('Phone Number'),
  driversLicense('Driver\'s License'),
  passport('Passport'),
  address('Physical Address'),
  dateOfBirth('Date of Birth'),
  mothersMaidenName('Mother\'s Maiden Name'),
  medicalId('Medical ID'),
  other('Other');

  final String displayName;

  const AssetType(this.displayName);
}

/// Identity alert
class IdentityAlert {
  final String id;
  final IdentityAlertType type;
  final AlertSeverity severity;
  final String title;
  final String description;
  final DateTime detectedDate;
  final String? source;
  final Map<String, dynamic> details;
  final bool isAcknowledged;
  final bool isResolved;
  final List<String> recommendedActions;

  IdentityAlert({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.description,
    required this.detectedDate,
    this.source,
    this.details = const {},
    this.isAcknowledged = false,
    this.isResolved = false,
    this.recommendedActions = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'severity': severity.name,
    'title': title,
    'description': description,
    'detected_date': detectedDate.toIso8601String(),
    'source': source,
    'details': details,
    'is_acknowledged': isAcknowledged,
    'is_resolved': isResolved,
    'recommended_actions': recommendedActions,
  };

  factory IdentityAlert.fromJson(Map<String, dynamic> json) {
    return IdentityAlert(
      id: json['id'] as String,
      type: IdentityAlertType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => IdentityAlertType.darkWebExposure,
      ),
      severity: AlertSeverity.values.firstWhere(
        (s) => s.name == json['severity'],
        orElse: () => AlertSeverity.medium,
      ),
      title: json['title'] as String,
      description: json['description'] as String,
      detectedDate: DateTime.parse(json['detected_date'] as String),
      source: json['source'] as String?,
      details: json['details'] as Map<String, dynamic>? ?? {},
      isAcknowledged: json['is_acknowledged'] as bool? ?? false,
      isResolved: json['is_resolved'] as bool? ?? false,
      recommendedActions: (json['recommended_actions'] as List<dynamic>?)
          ?.cast<String>() ?? [],
    );
  }
}

/// Credit score update
class CreditScoreUpdate {
  final CreditBureau bureau;
  final int score;
  final int? previousScore;
  final int change;
  final DateTime date;
  final String? factors;

  CreditScoreUpdate({
    required this.bureau,
    required this.score,
    this.previousScore,
    required this.change,
    required this.date,
    this.factors,
  });

  String get changeDescription {
    if (change > 0) return '+$change points';
    if (change < 0) return '$change points';
    return 'No change';
  }

  String get scoreRating {
    if (score >= 800) return 'Excellent';
    if (score >= 740) return 'Very Good';
    if (score >= 670) return 'Good';
    if (score >= 580) return 'Fair';
    return 'Poor';
  }
}

/// Credit freeze status
class CreditFreezeStatus {
  final CreditBureau bureau;
  final bool isFrozen;
  final DateTime? frozenDate;
  final DateTime? unfreezeDate;
  final String? pin;

  CreditFreezeStatus({
    required this.bureau,
    required this.isFrozen,
    this.frozenDate,
    this.unfreezeDate,
    this.pin,
  });
}

/// Identity protection summary
class IdentityProtectionSummary {
  final MonitoringStatus overallStatus;
  final int totalAssets;
  final int activeAlerts;
  final int resolvedAlerts;
  final DateTime? lastScanDate;
  final Map<CreditBureau, CreditScoreUpdate?> creditScores;
  final Map<CreditBureau, CreditFreezeStatus> freezeStatus;
  final int protectionScore;
  final List<String> recommendations;

  IdentityProtectionSummary({
    required this.overallStatus,
    required this.totalAssets,
    required this.activeAlerts,
    required this.resolvedAlerts,
    this.lastScanDate,
    this.creditScores = const {},
    this.freezeStatus = const {},
    required this.protectionScore,
    this.recommendations = const [],
  });

  String get protectionGrade {
    if (protectionScore >= 90) return 'A';
    if (protectionScore >= 80) return 'B';
    if (protectionScore >= 70) return 'C';
    if (protectionScore >= 60) return 'D';
    return 'F';
  }
}

/// Identity recovery case
class RecoveryCase {
  final String id;
  final String title;
  final RecoveryCaseStatus status;
  final DateTime openedDate;
  final DateTime? resolvedDate;
  final String? assignedAgent;
  final List<RecoveryStep> steps;
  final List<String> documentsRequired;
  final double estimatedLoss;
  final double recoveredAmount;

  RecoveryCase({
    required this.id,
    required this.title,
    required this.status,
    required this.openedDate,
    this.resolvedDate,
    this.assignedAgent,
    this.steps = const [],
    this.documentsRequired = const [],
    this.estimatedLoss = 0,
    this.recoveredAmount = 0,
  });
}

enum RecoveryCaseStatus {
  open('Open'),
  inProgress('In Progress'),
  pendingDocuments('Pending Documents'),
  underReview('Under Review'),
  resolved('Resolved'),
  closed('Closed');

  final String displayName;

  const RecoveryCaseStatus(this.displayName);
}

class RecoveryStep {
  final String id;
  final String description;
  final bool isCompleted;
  final DateTime? completedDate;
  final String? notes;

  RecoveryStep({
    required this.id,
    required this.description,
    this.isCompleted = false,
    this.completedDate,
    this.notes,
  });
}

/// Identity Theft Protection Service
class IdentityTheftProtectionService {
  final List<MonitoredAsset> _monitoredAssets = [];
  final List<IdentityAlert> _alerts = [];
  final List<RecoveryCase> _recoveryCases = [];
  final Map<CreditBureau, CreditScoreUpdate> _creditScores = {};
  final Map<CreditBureau, CreditFreezeStatus> _freezeStatus = {};

  Timer? _monitoringTimer;
  final _alertController = StreamController<IdentityAlert>.broadcast();

  Stream<IdentityAlert> get alertStream => _alertController.stream;

  /// Add asset for monitoring
  Future<MonitoredAsset> addMonitoredAsset({
    required AssetType type,
    required String value,
  }) async {
    // Hash the value for secure storage
    final hashedValue = sha256.convert(utf8.encode(value)).toString();

    // Mask the value for display
    final maskedValue = _maskValue(type, value);

    final asset = MonitoredAsset(
      id: 'asset_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      maskedValue: maskedValue,
      hashedValue: hashedValue,
      addedDate: DateTime.now(),
      status: MonitoringStatus.active,
    );

    _monitoredAssets.add(asset);

    // Run initial scan
    await _scanAsset(asset);

    return asset;
  }

  /// Mask sensitive values for display
  String _maskValue(AssetType type, String value) {
    switch (type) {
      case AssetType.ssn:
        if (value.length >= 4) {
          return '***-**-${value.substring(value.length - 4)}';
        }
        return '***-**-****';
      case AssetType.creditCard:
        if (value.length >= 4) {
          return '**** **** **** ${value.substring(value.length - 4)}';
        }
        return '**** **** **** ****';
      case AssetType.bankAccount:
        if (value.length >= 4) {
          return '****${value.substring(value.length - 4)}';
        }
        return '********';
      case AssetType.email:
        final parts = value.split('@');
        if (parts.length == 2 && parts[0].length > 2) {
          return '${parts[0].substring(0, 2)}***@${parts[1]}';
        }
        return '***@***';
      case AssetType.phone:
        if (value.length >= 4) {
          return '(***) ***-${value.substring(value.length - 4)}';
        }
        return '(***) ***-****';
      case AssetType.driversLicense:
        if (value.length >= 3) {
          return '***${value.substring(value.length - 3)}';
        }
        return '******';
      case AssetType.passport:
        if (value.length >= 3) {
          return '******${value.substring(value.length - 3)}';
        }
        return '*********';
      default:
        if (value.length > 4) {
          return '${value.substring(0, 2)}${'*' * (value.length - 4)}${value.substring(value.length - 2)}';
        }
        return '****';
    }
  }

  /// Remove asset from monitoring
  Future<void> removeMonitoredAsset(String assetId) async {
    _monitoredAssets.removeWhere((a) => a.id == assetId);
  }

  /// Get all monitored assets
  List<MonitoredAsset> getMonitoredAssets() => List.unmodifiable(_monitoredAssets);

  /// Scan all assets for exposure
  Future<List<IdentityAlert>> scanAllAssets() async {
    final newAlerts = <IdentityAlert>[];

    for (final asset in _monitoredAssets) {
      final alerts = await _scanAsset(asset);
      newAlerts.addAll(alerts);
    }

    return newAlerts;
  }

  /// Scan specific asset
  Future<List<IdentityAlert>> _scanAsset(MonitoredAsset asset) async {
    final alerts = <IdentityAlert>[];

    // Simulate scanning various sources
    await Future.delayed(const Duration(milliseconds: 500));

    // Check dark web databases
    final darkWebAlerts = await _checkDarkWeb(asset);
    alerts.addAll(darkWebAlerts);

    // Check data broker sites
    final dataBrokerAlerts = await _checkDataBrokers(asset);
    alerts.addAll(dataBrokerAlerts);

    // Check public records
    final publicRecordAlerts = await _checkPublicRecords(asset);
    alerts.addAll(publicRecordAlerts);

    for (final alert in alerts) {
      _alerts.add(alert);
      _alertController.add(alert);
    }

    return alerts;
  }

  /// Check dark web for asset exposure
  Future<List<IdentityAlert>> _checkDarkWeb(MonitoredAsset asset) async {
    // Simulate dark web scanning
    // In production, this would call a dark web monitoring API
    return [];
  }

  /// Check data broker sites
  Future<List<IdentityAlert>> _checkDataBrokers(MonitoredAsset asset) async {
    // Known data broker sites to check
    final dataBrokers = [
      'Spokeo', 'WhitePages', 'BeenVerified', 'Intelius',
      'PeopleFinder', 'TruePeopleSearch', 'FastPeopleSearch',
      'Radaris', 'USSearch', 'Pipl', 'ZabaSearch',
    ];

    // Simulate checking data brokers
    // In production, this would scrape or API-call each broker
    return [];
  }

  /// Check public records
  Future<List<IdentityAlert>> _checkPublicRecords(MonitoredAsset asset) async {
    // Check various public record databases
    // Court records, property records, voter registration, etc.
    return [];
  }

  /// Get all alerts
  List<IdentityAlert> getAlerts({
    bool includeResolved = false,
    IdentityAlertType? type,
    AlertSeverity? minSeverity,
  }) {
    return _alerts.where((alert) {
      if (!includeResolved && alert.isResolved) return false;
      if (type != null && alert.type != type) return false;
      if (minSeverity != null && alert.severity.weight < minSeverity.weight) return false;
      return true;
    }).toList();
  }

  /// Acknowledge alert
  Future<void> acknowledgeAlert(String alertId) async {
    final index = _alerts.indexWhere((a) => a.id == alertId);
    if (index >= 0) {
      final alert = _alerts[index];
      _alerts[index] = IdentityAlert(
        id: alert.id,
        type: alert.type,
        severity: alert.severity,
        title: alert.title,
        description: alert.description,
        detectedDate: alert.detectedDate,
        source: alert.source,
        details: alert.details,
        isAcknowledged: true,
        isResolved: alert.isResolved,
        recommendedActions: alert.recommendedActions,
      );
    }
  }

  /// Resolve alert
  Future<void> resolveAlert(String alertId) async {
    final index = _alerts.indexWhere((a) => a.id == alertId);
    if (index >= 0) {
      final alert = _alerts[index];
      _alerts[index] = IdentityAlert(
        id: alert.id,
        type: alert.type,
        severity: alert.severity,
        title: alert.title,
        description: alert.description,
        detectedDate: alert.detectedDate,
        source: alert.source,
        details: alert.details,
        isAcknowledged: true,
        isResolved: true,
        recommendedActions: alert.recommendedActions,
      );
    }
  }

  /// Get credit scores
  Map<CreditBureau, CreditScoreUpdate> getCreditScores() =>
      Map.unmodifiable(_creditScores);

  /// Update credit score
  Future<void> updateCreditScore(CreditBureau bureau, int score) async {
    final previous = _creditScores[bureau];
    final change = previous != null ? score - previous.score : 0;

    _creditScores[bureau] = CreditScoreUpdate(
      bureau: bureau,
      score: score,
      previousScore: previous?.score,
      change: change,
      date: DateTime.now(),
    );

    // Alert on significant changes
    if (change.abs() >= 50) {
      final alert = IdentityAlert(
        id: 'alert_credit_${DateTime.now().millisecondsSinceEpoch}',
        type: IdentityAlertType.creditScoreChange,
        severity: change < -50 ? AlertSeverity.high : AlertSeverity.medium,
        title: 'Credit Score Change',
        description: 'Your ${bureau.displayName} credit score changed by $change points',
        detectedDate: DateTime.now(),
        source: bureau.displayName,
        details: {
          'bureau': bureau.name,
          'previous_score': previous?.score,
          'new_score': score,
          'change': change,
        },
        recommendedActions: [
          'Review recent credit inquiries',
          'Check for new accounts',
          'Verify account balances',
        ],
      );

      _alerts.add(alert);
      _alertController.add(alert);
    }
  }

  /// Freeze credit at bureau
  Future<CreditFreezeStatus> freezeCredit(CreditBureau bureau) async {
    // Generate a secure PIN
    final pin = _generateSecurePin();

    final status = CreditFreezeStatus(
      bureau: bureau,
      isFrozen: true,
      frozenDate: DateTime.now(),
      pin: pin,
    );

    _freezeStatus[bureau] = status;

    return status;
  }

  /// Unfreeze credit at bureau
  Future<CreditFreezeStatus> unfreezeCredit(
    CreditBureau bureau, {
    Duration? temporaryDuration,
  }) async {
    final status = CreditFreezeStatus(
      bureau: bureau,
      isFrozen: false,
      unfreezeDate: temporaryDuration != null
          ? DateTime.now().add(temporaryDuration)
          : null,
    );

    _freezeStatus[bureau] = status;

    return status;
  }

  /// Get freeze status
  Map<CreditBureau, CreditFreezeStatus> getFreezeStatus() =>
      Map.unmodifiable(_freezeStatus);

  String _generateSecurePin() {
    // Generate 10-digit PIN
    final random = DateTime.now().millisecondsSinceEpoch;
    return (random % 10000000000).toString().padLeft(10, '0');
  }

  /// Open identity recovery case
  Future<RecoveryCase> openRecoveryCase({
    required String title,
    required double estimatedLoss,
    required List<String> documentsRequired,
  }) async {
    final recoveryCase = RecoveryCase(
      id: 'case_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      status: RecoveryCaseStatus.open,
      openedDate: DateTime.now(),
      documentsRequired: documentsRequired,
      estimatedLoss: estimatedLoss,
      steps: _generateRecoverySteps(),
    );

    _recoveryCases.add(recoveryCase);

    return recoveryCase;
  }

  List<RecoveryStep> _generateRecoverySteps() {
    return [
      RecoveryStep(
        id: 'step_1',
        description: 'File FTC Identity Theft Report at IdentityTheft.gov',
      ),
      RecoveryStep(
        id: 'step_2',
        description: 'File police report with local law enforcement',
      ),
      RecoveryStep(
        id: 'step_3',
        description: 'Place fraud alerts with all three credit bureaus',
      ),
      RecoveryStep(
        id: 'step_4',
        description: 'Review credit reports for fraudulent accounts',
      ),
      RecoveryStep(
        id: 'step_5',
        description: 'Contact affected financial institutions',
      ),
      RecoveryStep(
        id: 'step_6',
        description: 'Dispute fraudulent transactions',
      ),
      RecoveryStep(
        id: 'step_7',
        description: 'Replace compromised documents (SSN card, driver\'s license)',
      ),
      RecoveryStep(
        id: 'step_8',
        description: 'Set up ongoing credit monitoring',
      ),
    ];
  }

  /// Get recovery cases
  List<RecoveryCase> getRecoveryCases({RecoveryCaseStatus? status}) {
    if (status == null) return List.unmodifiable(_recoveryCases);
    return _recoveryCases.where((c) => c.status == status).toList();
  }

  /// Get protection summary
  IdentityProtectionSummary getSummary() {
    final activeAlerts = _alerts.where((a) => !a.isResolved).length;
    final resolvedAlerts = _alerts.where((a) => a.isResolved).length;

    // Calculate protection score
    var score = 100;

    // Deduct for unmonitored asset types
    if (!_monitoredAssets.any((a) => a.type == AssetType.ssn)) score -= 15;
    if (!_monitoredAssets.any((a) => a.type == AssetType.email)) score -= 10;
    if (!_monitoredAssets.any((a) => a.type == AssetType.phone)) score -= 5;

    // Deduct for active alerts
    for (final alert in _alerts.where((a) => !a.isResolved)) {
      score -= alert.severity.weight * 3;
    }

    // Bonus for credit freezes
    final frozenBureaus = _freezeStatus.values.where((s) => s.isFrozen).length;
    score += frozenBureaus * 5;

    score = score.clamp(0, 100);

    // Generate recommendations
    final recommendations = <String>[];

    if (!_monitoredAssets.any((a) => a.type == AssetType.ssn)) {
      recommendations.add('Add your SSN for monitoring');
    }

    if (frozenBureaus < 3) {
      recommendations.add('Freeze credit at ${3 - frozenBureaus} more bureau(s)');
    }

    if (activeAlerts > 0) {
      recommendations.add('Review and resolve $activeAlerts active alert(s)');
    }

    if (_monitoredAssets.length < 3) {
      recommendations.add('Add more assets for comprehensive monitoring');
    }

    return IdentityProtectionSummary(
      overallStatus: activeAlerts > 0
          ? MonitoringStatus.alertTriggered
          : MonitoringStatus.active,
      totalAssets: _monitoredAssets.length,
      activeAlerts: activeAlerts,
      resolvedAlerts: resolvedAlerts,
      lastScanDate: DateTime.now(),
      creditScores: Map.unmodifiable(_creditScores),
      freezeStatus: Map.unmodifiable(_freezeStatus),
      protectionScore: score,
      recommendations: recommendations,
    );
  }

  /// Start continuous monitoring
  void startMonitoring({Duration interval = const Duration(hours: 24)}) {
    _monitoringTimer?.cancel();
    _monitoringTimer = Timer.periodic(interval, (_) => scanAllAssets());
  }

  /// Stop monitoring
  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  /// Dispose resources
  void dispose() {
    _monitoringTimer?.cancel();
    _alertController.close();
  }
}
