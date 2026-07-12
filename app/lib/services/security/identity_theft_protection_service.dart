// Identity Theft Protection Service
//
// Honest identity monitoring built on live backend capabilities:
// - Email exposure monitoring via the dark-web breach service
//   (POST /darkweb/check/email)
// - Data-broker / public-record exposure via the digital footprint
//   scanner (POST /footprint/scan)
// - Credit freeze guidance via the bureaus' OFFICIAL freeze pages
//   (OrbGuard cannot freeze credit on a user's behalf; freeze state is
//   recorded locally as user-declared / self-reported only)
// - Identity recovery checklists (local, user-managed)
//
// Asset types without a live monitoring source (SSN, credit cards, bank
// accounts, ...) are stored locally and explicitly surfaced with the
// `unavailable` status — they are never presented as "monitored".

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/api/sms_analysis.dart' show BreachCheckResult;
import '../api/orbguard_api_client.dart';

/// Identity monitoring status
enum MonitoringStatus {
  active('Active', 'Monitoring enabled'),
  paused('Paused', 'Monitoring temporarily paused'),
  inactive('Inactive', 'Monitoring not configured'),
  alertTriggered('Alert', 'Action required'),
  unavailable('Unavailable',
      'No live monitoring source exists for this asset type');

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
  publicRecords('Public Records', 'New public record in your name', AlertSeverity.medium),
  darkWebExposure('Dark Web', 'Personal info found on dark web', AlertSeverity.high),
  dataBrokerExposure('Data Broker', 'Personal info listed by a data broker', AlertSeverity.medium),
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

  /// The bureau's official self-service credit-freeze page. These are the
  /// well-known canonical URLs; freezing must be done by the user directly
  /// with the bureau.
  String get officialFreezeUrl {
    switch (this) {
      case CreditBureau.equifax:
        return 'https://www.equifax.com/personal/credit-report-services/credit-freeze/';
      case CreditBureau.experian:
        return 'https://www.experian.com/freeze/center.html';
      case CreditBureau.transunion:
        return 'https://www.transunion.com/credit-freeze';
    }
  }
}

/// Monitored identity asset
class MonitoredAsset {
  final String id;
  final AssetType type;
  final String maskedValue;
  final String hashedValue;

  /// Raw value retained ONLY for asset types with a live backend scan
  /// (currently email). For all other types only the hash + mask are kept.
  final String? scanValue;

  final DateTime addedDate;
  final DateTime? lastChecked;
  final MonitoringStatus status;
  final int alertCount;

  MonitoredAsset({
    required this.id,
    required this.type,
    required this.maskedValue,
    required this.hashedValue,
    this.scanValue,
    required this.addedDate,
    this.lastChecked,
    this.status = MonitoringStatus.active,
    this.alertCount = 0,
  });

  /// Whether a live backend data source exists for this asset type.
  bool get supportsLiveScan => type == AssetType.email;

  MonitoredAsset copyWith({
    DateTime? lastChecked,
    MonitoringStatus? status,
    int? alertCount,
  }) {
    return MonitoredAsset(
      id: id,
      type: type,
      maskedValue: maskedValue,
      hashedValue: hashedValue,
      scanValue: scanValue,
      addedDate: addedDate,
      lastChecked: lastChecked ?? this.lastChecked,
      status: status ?? this.status,
      alertCount: alertCount ?? this.alertCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'masked_value': maskedValue,
    'hashed_value': hashedValue,
    'scan_value': scanValue,
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
      scanValue: json['scan_value'] as String?,
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

  IdentityAlert copyWith({bool? isAcknowledged, bool? isResolved}) {
    return IdentityAlert(
      id: id,
      type: type,
      severity: severity,
      title: title,
      description: description,
      detectedDate: detectedDate,
      source: source,
      details: details,
      isAcknowledged: isAcknowledged ?? this.isAcknowledged,
      isResolved: isResolved ?? this.isResolved,
      recommendedActions: recommendedActions,
    );
  }

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
      details: (json['details'] as Map?)?.cast<String, dynamic>() ?? {},
      isAcknowledged: json['is_acknowledged'] as bool? ?? false,
      isResolved: json['is_resolved'] as bool? ?? false,
      recommendedActions: (json['recommended_actions'] as List<dynamic>?)
          ?.cast<String>() ?? [],
    );
  }
}

/// User-declared credit freeze record.
///
/// OrbGuard has no API integration with the bureaus, so this is an honest,
/// clearly-labeled self-reported record of what the user says they did on
/// the bureau's official freeze page — never an authoritative state.
class CreditFreezeStatus {
  final CreditBureau bureau;
  final bool isFrozen;

  /// When the user recorded this status in the app.
  final DateTime? reportedAt;

  /// Always true: this state is declared by the user, not verified.
  final bool selfReported;

  CreditFreezeStatus({
    required this.bureau,
    required this.isFrozen,
    this.reportedAt,
    this.selfReported = true,
  });

  Map<String, dynamic> toJson() => {
    'bureau': bureau.name,
    'is_frozen': isFrozen,
    'reported_at': reportedAt?.toIso8601String(),
    'self_reported': selfReported,
  };

  factory CreditFreezeStatus.fromJson(Map<String, dynamic> json) {
    return CreditFreezeStatus(
      bureau: CreditBureau.values.firstWhere(
        (b) => b.name == json['bureau'],
        orElse: () => CreditBureau.equifax,
      ),
      isFrozen: json['is_frozen'] as bool? ?? false,
      reportedAt: json['reported_at'] != null
          ? DateTime.tryParse(json['reported_at'] as String)
          : null,
      selfReported: json['self_reported'] as bool? ?? true,
    );
  }
}

/// Identity protection summary
class IdentityProtectionSummary {
  final MonitoringStatus overallStatus;
  final int totalAssets;
  final int activeAlerts;
  final int resolvedAlerts;
  final DateTime? lastScanDate;
  final Map<CreditBureau, CreditFreezeStatus> freezeStatus;
  final int protectionScore;
  final List<String> recommendations;

  IdentityProtectionSummary({
    required this.overallStatus,
    required this.totalAssets,
    required this.activeAlerts,
    required this.resolvedAlerts,
    this.lastScanDate,
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': status.name,
    'opened_date': openedDate.toIso8601String(),
    'resolved_date': resolvedDate?.toIso8601String(),
    'assigned_agent': assignedAgent,
    'steps': steps.map((s) => s.toJson()).toList(),
    'documents_required': documentsRequired,
    'estimated_loss': estimatedLoss,
    'recovered_amount': recoveredAmount,
  };

  factory RecoveryCase.fromJson(Map<String, dynamic> json) {
    return RecoveryCase(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      status: RecoveryCaseStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => RecoveryCaseStatus.open,
      ),
      openedDate: DateTime.parse(json['opened_date'] as String),
      resolvedDate: json['resolved_date'] != null
          ? DateTime.tryParse(json['resolved_date'] as String)
          : null,
      assignedAgent: json['assigned_agent'] as String?,
      steps: (json['steps'] as List<dynamic>?)
              ?.map((s) => RecoveryStep.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      documentsRequired:
          (json['documents_required'] as List<dynamic>?)?.cast<String>() ?? [],
      estimatedLoss: (json['estimated_loss'] as num?)?.toDouble() ?? 0,
      recoveredAmount: (json['recovered_amount'] as num?)?.toDouble() ?? 0,
    );
  }
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'is_completed': isCompleted,
    'completed_date': completedDate?.toIso8601String(),
    'notes': notes,
  };

  factory RecoveryStep.fromJson(Map<String, dynamic> json) {
    return RecoveryStep(
      id: json['id'] as String,
      description: json['description'] as String? ?? '',
      isCompleted: json['is_completed'] as bool? ?? false,
      completedDate: json['completed_date'] != null
          ? DateTime.tryParse(json['completed_date'] as String)
          : null,
      notes: json['notes'] as String?,
    );
  }
}

/// Identity Theft Protection Service
class IdentityTheftProtectionService {
  static const String _assetsPrefsKey = 'identity.assets';
  static const String _alertsPrefsKey = 'identity.alerts';
  static const String _freezePrefsKey = 'identity.freeze_status';
  static const String _recoveryPrefsKey = 'identity.recovery_cases';

  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  final List<MonitoredAsset> _monitoredAssets = [];
  final List<IdentityAlert> _alerts = [];
  final List<RecoveryCase> _recoveryCases = [];
  final Map<CreditBureau, CreditFreezeStatus> _freezeStatus = {};

  DateTime? _lastScanDate;

  /// Per-asset scan errors from the most recent scan, keyed by asset id.
  final Map<String, String> _lastScanErrors = {};

  Timer? _monitoringTimer;
  final _alertController = StreamController<IdentityAlert>.broadcast();

  Stream<IdentityAlert> get alertStream => _alertController.stream;

  /// Errors from the last scan (asset id -> message). Empty when the last
  /// scan completed cleanly.
  Map<String, String> get lastScanErrors => Map.unmodifiable(_lastScanErrors);

  /// Load persisted state. Must be called before use.
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final rawAssets = prefs.getString(_assetsPrefsKey);
      if (rawAssets != null && rawAssets.isNotEmpty) {
        final decoded = jsonDecode(rawAssets);
        if (decoded is List) {
          _monitoredAssets
            ..clear()
            ..addAll(decoded.whereType<Map>().map(
                (a) => MonitoredAsset.fromJson(a.cast<String, dynamic>())));
        }
      }

      final rawAlerts = prefs.getString(_alertsPrefsKey);
      if (rawAlerts != null && rawAlerts.isNotEmpty) {
        final decoded = jsonDecode(rawAlerts);
        if (decoded is List) {
          _alerts
            ..clear()
            ..addAll(decoded.whereType<Map>().map(
                (a) => IdentityAlert.fromJson(a.cast<String, dynamic>())));
        }
      }

      final rawFreeze = prefs.getString(_freezePrefsKey);
      if (rawFreeze != null && rawFreeze.isNotEmpty) {
        final decoded = jsonDecode(rawFreeze);
        if (decoded is List) {
          _freezeStatus.clear();
          for (final entry in decoded.whereType<Map>()) {
            final status =
                CreditFreezeStatus.fromJson(entry.cast<String, dynamic>());
            _freezeStatus[status.bureau] = status;
          }
        }
      }

      final rawRecovery = prefs.getString(_recoveryPrefsKey);
      if (rawRecovery != null && rawRecovery.isNotEmpty) {
        final decoded = jsonDecode(rawRecovery);
        if (decoded is List) {
          _recoveryCases
            ..clear()
            ..addAll(decoded.whereType<Map>().map(
                (c) => RecoveryCase.fromJson(c.cast<String, dynamic>())));
        }
      }
    } catch (e) {
      debugPrint('IdentityProtection: failed to load persisted state: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_assetsPrefsKey,
          jsonEncode(_monitoredAssets.map((a) => a.toJson()).toList()));
      await prefs.setString(_alertsPrefsKey,
          jsonEncode(_alerts.map((a) => a.toJson()).toList()));
      await prefs.setString(_freezePrefsKey,
          jsonEncode(_freezeStatus.values.map((f) => f.toJson()).toList()));
      await prefs.setString(_recoveryPrefsKey,
          jsonEncode(_recoveryCases.map((c) => c.toJson()).toList()));
    } catch (e) {
      debugPrint('IdentityProtection: failed to persist state: $e');
    }
  }

  /// Add asset for monitoring.
  ///
  /// Email assets are scanned against the live dark-web and digital
  /// footprint services. Other asset types have no live data source and
  /// are stored with [MonitoringStatus.unavailable] — explicitly NOT
  /// presented as monitored.
  Future<MonitoredAsset> addMonitoredAsset({
    required AssetType type,
    required String value,
  }) async {
    final normalized = type == AssetType.email ? value.trim().toLowerCase() : value.trim();

    // Hash the value for secure storage / dedupe.
    final hashedValue = sha256.convert(utf8.encode(normalized)).toString();

    // Mask the value for display.
    final maskedValue = _maskValue(type, normalized);

    final supportsLiveScan = type == AssetType.email;
    if (!supportsLiveScan) {
      debugPrint(
          'IdentityProtection: no live monitoring source for asset type '
          '"${type.name}" — stored with status=unavailable');
    }

    final asset = MonitoredAsset(
      id: 'asset_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      maskedValue: maskedValue,
      hashedValue: hashedValue,
      // Raw value retained only when a live scan needs it.
      scanValue: supportsLiveScan ? normalized : null,
      addedDate: DateTime.now(),
      status: supportsLiveScan
          ? MonitoringStatus.active
          : MonitoringStatus.unavailable,
    );

    _monitoredAssets.add(asset);
    await _persist();

    // Run initial scan for scannable assets.
    if (supportsLiveScan) {
      await _scanAsset(asset);
    }

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
    await _persist();
  }

  /// Get all monitored assets
  List<MonitoredAsset> getMonitoredAssets() => List.unmodifiable(_monitoredAssets);

  /// Scan all assets that have a live data source. Assets without one keep
  /// their explicit `unavailable` status. Throws if every scannable asset
  /// failed (so callers never mistake a total failure for a clean result).
  Future<List<IdentityAlert>> scanAllAssets() async {
    _lastScanErrors.clear();
    final newAlerts = <IdentityAlert>[];

    final scannable =
        _monitoredAssets.where((a) => a.supportsLiveScan).toList();

    for (final asset in scannable) {
      try {
        final alerts = await _scanAsset(asset);
        newAlerts.addAll(alerts);
      } catch (e) {
        _lastScanErrors[asset.id] = e.toString();
        debugPrint(
            'IdentityProtection: scan failed for ${asset.maskedValue}: $e');
      }
    }

    _lastScanDate = DateTime.now();
    await _persist();

    if (scannable.isNotEmpty && _lastScanErrors.length == scannable.length) {
      throw Exception(
          'All asset scans failed: ${_lastScanErrors.values.first}');
    }

    return newAlerts;
  }

  /// Scan a single asset against the live backend services.
  Future<List<IdentityAlert>> _scanAsset(MonitoredAsset asset) async {
    if (!asset.supportsLiveScan || asset.scanValue == null) {
      // No live source — never fabricate a result.
      _replaceAsset(asset.copyWith(status: MonitoringStatus.unavailable));
      return [];
    }

    final newAlerts = <IdentityAlert>[];
    final email = asset.scanValue!;

    // 1) Dark-web breach corpus (POST /darkweb/check/email).
    final BreachCheckResult breachResult =
        await _api.checkEmailBreaches(email);
    if (breachResult.isBreached) {
      for (final breach in breachResult.breaches) {
        final alertId = 'alert_breach_${asset.id}_'
            '${sha256.convert(utf8.encode(breach.name)).toString().substring(0, 12)}';
        if (_alerts.any((a) => a.id == alertId)) continue; // Already known.

        final alert = IdentityAlert(
          id: alertId,
          type: IdentityAlertType.darkWebExposure,
          severity: breach.isSensitive
              ? AlertSeverity.critical
              : AlertSeverity.high,
          title: 'Breach: ${breach.title.isNotEmpty ? breach.title : breach.name}',
          description:
              '${asset.maskedValue} appeared in the "${breach.title.isNotEmpty ? breach.title : breach.name}" '
              'breach${breach.breachDate != null ? ' (${breach.breachDate!.year})' : ''}. '
              'Exposed data: ${breach.dataClasses.isEmpty ? 'unknown' : breach.dataClasses.join(', ')}.',
          detectedDate: DateTime.now(),
          source: breach.domain.isNotEmpty ? breach.domain : 'dark web monitor',
          details: {
            'asset_id': asset.id,
            'breach_name': breach.name,
            'breach_date': breach.breachDate?.toIso8601String(),
            'data_classes': breach.dataClasses,
            'verified': breach.isVerified,
          },
          recommendedActions: [
            'Change the password for accounts using this email',
            'Enable two-factor authentication',
            if (breach.dataClasses
                .any((d) => d.toLowerCase().contains('password')))
              'This breach exposed passwords — change reused passwords everywhere',
          ],
        );
        _alerts.add(alert);
        _alertController.add(alert);
        newAlerts.add(alert);
      }
    }

    // 2) Data-broker / public-record footprint (POST /footprint/scan).
    final scanResult = await _api.scanDigitalFootprint({
      'email': email,
      'scan_type': 'data_broker_only',
    });
    final rawExposures = scanResult['exposures'];
    if (rawExposures is List) {
      for (final raw in rawExposures.whereType<Map>()) {
        final exposure = raw.cast<String, dynamic>();
        final sourceName =
            exposure['source_name']?.toString() ?? 'unknown source';
        final exposureType = exposure['type']?.toString() ?? 'unknown';
        final source = exposure['source']?.toString() ?? '';

        final alertId = 'alert_exposure_${asset.id}_'
            '${sha256.convert(utf8.encode('$sourceName|$exposureType')).toString().substring(0, 12)}';
        if (_alerts.any((a) => a.id == alertId)) continue;

        final alert = IdentityAlert(
          id: alertId,
          type: source == 'public_record'
              ? IdentityAlertType.publicRecords
              : source == 'dark_web'
                  ? IdentityAlertType.darkWebExposure
                  : IdentityAlertType.dataBrokerExposure,
          severity: _exposureSeverity(exposure['severity']?.toString()),
          title: 'Exposure on $sourceName',
          description:
              'Your $exposureType information was found on $sourceName '
              '(${exposure['exposed_value'] ?? asset.maskedValue}).',
          detectedDate: DateTime.now(),
          source: sourceName,
          details: {
            'asset_id': asset.id,
            ...exposure,
          },
          recommendedActions: [
            if (exposure['can_auto_remove'] == true)
              'Request automated removal from the Digital Footprint screen'
            else
              'Request removal directly from $sourceName',
            'Review what other data this source links to you',
          ],
        );
        _alerts.add(alert);
        _alertController.add(alert);
        newAlerts.add(alert);
      }
    }

    // Update asset bookkeeping with real results.
    final assetAlerts = _alerts
        .where((a) => a.details['asset_id'] == asset.id && !a.isResolved)
        .length;
    _replaceAsset(asset.copyWith(
      lastChecked: DateTime.now(),
      status: assetAlerts > 0
          ? MonitoringStatus.alertTriggered
          : MonitoringStatus.active,
      alertCount: assetAlerts,
    ));

    return newAlerts;
  }

  AlertSeverity _exposureSeverity(String? severity) {
    switch (severity) {
      case 'critical':
        return AlertSeverity.critical;
      case 'high':
        return AlertSeverity.high;
      case 'medium':
        return AlertSeverity.medium;
      case 'low':
        return AlertSeverity.low;
      default:
        return AlertSeverity.info;
    }
  }

  void _replaceAsset(MonitoredAsset updated) {
    final index = _monitoredAssets.indexWhere((a) => a.id == updated.id);
    if (index >= 0) {
      _monitoredAssets[index] = updated;
    }
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
      _alerts[index] = _alerts[index].copyWith(isAcknowledged: true);
      await _persist();
    }
  }

  /// Resolve alert
  Future<void> resolveAlert(String alertId) async {
    final index = _alerts.indexWhere((a) => a.id == alertId);
    if (index >= 0) {
      _alerts[index] =
          _alerts[index].copyWith(isAcknowledged: true, isResolved: true);
      await _persist();
    }
  }

  /// Record the user's self-declared freeze status for a bureau.
  ///
  /// OrbGuard cannot freeze or unfreeze credit — the user must do it on the
  /// bureau's official page ([CreditBureau.officialFreezeUrl]); this only
  /// stores what they tell us, clearly labeled self-reported.
  Future<CreditFreezeStatus> setSelfReportedFreezeStatus(
    CreditBureau bureau,
    bool isFrozen,
  ) async {
    final status = CreditFreezeStatus(
      bureau: bureau,
      isFrozen: isFrozen,
      reportedAt: DateTime.now(),
    );
    _freezeStatus[bureau] = status;
    await _persist();
    return status;
  }

  /// Get self-reported freeze status records
  Map<CreditBureau, CreditFreezeStatus> getFreezeStatus() =>
      Map.unmodifiable(_freezeStatus);

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
    await _persist();

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

    // Calculate protection score from what we can actually verify.
    var score = 100;

    // Live monitoring only exists for email; not having one monitored is
    // the biggest gap we can honestly assess.
    if (!_monitoredAssets.any((a) => a.type == AssetType.email)) score -= 20;

    // Deduct for active alerts.
    for (final alert in _alerts.where((a) => !a.isResolved)) {
      score -= alert.severity.weight * 3;
    }

    // Small credit for self-reported freezes (clearly labeled unverified).
    final frozenBureaus = _freezeStatus.values.where((s) => s.isFrozen).length;
    score += frozenBureaus * 5;

    score = score.clamp(0, 100);

    // Generate recommendations.
    final recommendations = <String>[];

    if (!_monitoredAssets.any((a) => a.type == AssetType.email)) {
      recommendations.add(
          'Add your email address — it is checked against live breach and '
          'data-broker sources');
    }

    if (frozenBureaus < 3) {
      recommendations.add(
          'Freeze credit at ${3 - frozenBureaus} more bureau(s) via their '
          'official pages, then record it here');
    }

    if (activeAlerts > 0) {
      recommendations.add('Review and resolve $activeAlerts active alert(s)');
    }

    final unavailableAssets = _monitoredAssets
        .where((a) => a.status == MonitoringStatus.unavailable)
        .length;
    if (unavailableAssets > 0) {
      recommendations.add(
          '$unavailableAssets stored asset(s) have no live monitoring '
          'source yet and are not being scanned');
    }

    return IdentityProtectionSummary(
      overallStatus: activeAlerts > 0
          ? MonitoringStatus.alertTriggered
          : MonitoringStatus.active,
      totalAssets: _monitoredAssets.length,
      activeAlerts: activeAlerts,
      resolvedAlerts: resolvedAlerts,
      lastScanDate: _lastScanDate,
      freezeStatus: Map.unmodifiable(_freezeStatus),
      protectionScore: score,
      recommendations: recommendations,
    );
  }

  /// Start continuous monitoring
  void startMonitoring({Duration interval = const Duration(hours: 24)}) {
    _monitoringTimer?.cancel();
    _monitoringTimer = Timer.periodic(interval, (_) async {
      try {
        await scanAllAssets();
      } catch (e) {
        debugPrint('IdentityProtection: periodic scan failed: $e');
      }
    });
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
