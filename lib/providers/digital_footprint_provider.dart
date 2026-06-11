// Digital Footprint Provider
// State management for data broker removal and personal data exposure tracking
//
// Request/response shapes mirror the live backend in
// orbguard.lab/internal/api/handlers/footprint.go and the
// DigitalFootprint / DataBroker / RemovalRequest models.

import 'package:flutter/foundation.dart';
import '../services/api/orbguard_api_client.dart';

/// Data broker category
enum BrokerCategory {
  peopleSearch('People Search', 'Find personal info by name'),
  marketing('Marketing', 'Advertising and marketing data'),
  financial('Financial', 'Credit and financial data'),
  health('Health', 'Health and medical data'),
  background('Background Check', 'Criminal and background data'),
  other('Other', 'Other data collectors');

  final String displayName;
  final String description;
  const BrokerCategory(this.displayName, this.description);
}

/// Removal request status
enum RemovalStatus {
  pending('Pending', 0xFF9E9E9E),
  submitted('Submitted', 0xFF2196F3),
  inProgress('In Progress', 0xFFFF9800),
  completed('Completed', 0xFF4CAF50),
  failed('Failed', 0xFFFF1744),
  rejected('Rejected', 0xFFFF5722);

  final String displayName;
  final int color;
  const RemovalStatus(this.displayName, this.color);
}

/// Data broker info
class DataBroker {
  final String id;
  final String name;
  final String website;
  final BrokerCategory category;
  final String? description;
  final bool hasOptOut;
  final String? optOutUrl;
  final int estimatedDays;
  final double difficulty; // 0-1 scale
  final List<String> dataCollected;

  DataBroker({
    required this.id,
    required this.name,
    required this.website,
    required this.category,
    this.description,
    this.hasOptOut = true,
    this.optOutUrl,
    this.estimatedDays = 30,
    this.difficulty = 0.5,
    this.dataCollected = const [],
  });
}

/// Removal request
class RemovalRequest {
  final String id;
  final DataBroker broker;
  final RemovalStatus status;
  final DateTime requestedAt;
  final DateTime? completedAt;
  final String? confirmationId;
  final String? notes;

  RemovalRequest({
    required this.id,
    required this.broker,
    required this.status,
    required this.requestedAt,
    this.completedAt,
    this.confirmationId,
    this.notes,
  });

  int get daysPending => DateTime.now().difference(requestedAt).inDays;
}

/// Exposure finding
class ExposureFinding {
  final String id;
  final String dataType;
  final String source;
  final String? value;
  final String riskLevel;
  final DateTime foundAt;

  ExposureFinding({
    required this.id,
    required this.dataType,
    required this.source,
    this.value,
    required this.riskLevel,
    required this.foundAt,
  });
}

/// Scan result — built from the backend DigitalFootprint response of
/// POST /footprint/scan.
class FootprintScanResult {
  final String id;
  final DateTime scannedAt;
  final String status; // pending, running, completed, failed
  final int brokersFound;
  final int exposuresFound;
  final int breachesFound;
  final int darkWebExposures;
  final List<DataBroker> brokers;
  final List<ExposureFinding> exposures;

  /// Backend risk score (0-100, higher = more exposed).
  final double riskScore;
  final String riskLevel; // critical, high, medium, low

  FootprintScanResult({
    required this.id,
    required this.scannedAt,
    this.status = 'completed',
    this.brokersFound = 0,
    this.exposuresFound = 0,
    this.breachesFound = 0,
    this.darkWebExposures = 0,
    this.brokers = const [],
    this.exposures = const [],
    this.riskScore = 0,
    this.riskLevel = 'low',
  });

  /// Privacy score shown in the UI: inverse of the backend risk score.
  int get privacyScore => (100 - riskScore).round().clamp(0, 100);
}

/// Digital Footprint Provider
class DigitalFootprintProvider extends ChangeNotifier {
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // State
  final List<DataBroker> _brokers = [];
  final List<RemovalRequest> _requests = [];
  FootprintScanResult? _lastScan;

  bool _isLoading = false;
  bool _isScanning = false;
  bool _isSubmitting = false;
  String? _error;
  double _scanProgress = 0.0;

  // Getters
  List<DataBroker> get brokers => List.unmodifiable(_brokers);
  List<RemovalRequest> get requests => List.unmodifiable(_requests);
  FootprintScanResult? get lastScan => _lastScan;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;
  double get scanProgress => _scanProgress;

  /// Pending requests
  List<RemovalRequest> get pendingRequests => _requests
      .where((r) =>
          r.status == RemovalStatus.pending ||
          r.status == RemovalStatus.submitted ||
          r.status == RemovalStatus.inProgress)
      .toList();

  /// Completed requests
  List<RemovalRequest> get completedRequests =>
      _requests.where((r) => r.status == RemovalStatus.completed).toList();

  /// Stats
  int get totalBrokersFound => _lastScan?.brokersFound ?? 0;
  int get totalExposures => _lastScan?.exposuresFound ?? 0;
  int get requestsSubmitted => _requests.length;
  int get requestsCompleted => completedRequests.length;

  /// Initialize provider
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      await loadBrokers();
    } catch (e) {
      _error = 'Failed to initialize: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load data brokers from GET /footprint/brokers.
  ///
  /// Each entry is a backend DataBroker:
  /// {id, name, domain, category, description, data_types, site_url,
  ///  opt_out_url, opt_out_method, opt_out_difficulty, processing_days, ...}.
  /// On failure the error is surfaced — no fabricated broker list.
  Future<void> loadBrokers() async {
    try {
      final data = await _api.getDataBrokers();
      final parsed = <DataBroker>[];

      for (final raw in data) {
        if (raw is! Map) {
          throw const FormatException('Unexpected broker entry in response');
        }
        final broker = Map<String, dynamic>.from(raw);
        parsed.add(_parseBroker(broker));
      }

      _brokers
        ..clear()
        ..addAll(parsed);
      _error = null;
    } catch (e) {
      _error = 'Failed to load data brokers: $e';
    }
    notifyListeners();
  }

  /// Scan digital footprint via POST /footprint/scan.
  ///
  /// Sends the backend FootprintScanRequest shape: email, scan_type,
  /// first_name/last_name/phone, addresses[] as objects, and the
  /// include_dark_web/include_data_brokers/include_social_media/
  /// include_breaches options.
  Future<FootprintScanResult?> scan({
    required String email,
    String? firstName,
    String? lastName,
    String? phone,
    String? address,
  }) async {
    _isScanning = true;
    _scanProgress = 0.0;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.scanDigitalFootprint({
        'email': email,
        'scan_type': 'full',
        if (firstName != null && firstName.isNotEmpty) 'first_name': firstName,
        if (lastName != null && lastName.isNotEmpty) 'last_name': lastName,
        if (firstName != null &&
            firstName.isNotEmpty &&
            lastName != null &&
            lastName.isNotEmpty)
          'full_name': '$firstName $lastName',
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (address != null && address.isNotEmpty)
          'addresses': [
            {'street': address},
          ],
        'include_dark_web': true,
        'include_data_brokers': true,
        'include_social_media': true,
        'include_breaches': true,
      });

      _lastScan = _parseScanResult(response);
      if (_lastScan!.status == 'failed') {
        _error = 'Footprint scan failed on the server';
      }

      _isScanning = false;
      _scanProgress = 1.0;
      notifyListeners();
      return _lastScan;
    } catch (e) {
      _error = 'Footprint scan failed: $e';
      _isScanning = false;
      _scanProgress = 0.0;
      notifyListeners();
      return null;
    }
  }

  /// Request removal from broker via POST /footprint/removal.
  ///
  /// The backend persists the request, processes the opt-out asynchronously,
  /// and returns a RemovalRequest {id, status, broker_name, created_at,
  /// confirmation_id, ...}. Status transitions are visible through
  /// refreshRequestStatus(). On failure the error is surfaced — no fake
  /// local request is created.
  Future<RemovalRequest?> requestRemoval(DataBroker broker) async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.requestDataRemoval(broker.id);

      final id = response['id'] as String?;
      if (id == null || id.isEmpty) {
        throw const FormatException(
            'Unexpected removal response: missing "id"');
      }

      final request = RemovalRequest(
        id: id,
        broker: broker,
        status: _parseStatus(response['status'] as String?),
        requestedAt:
            DateTime.tryParse((response['created_at'] as String?) ?? '') ??
                DateTime.now(),
        completedAt:
            DateTime.tryParse((response['completed_at'] as String?) ?? ''),
        confirmationId: response['confirmation_id'] as String?,
        notes: response['notes'] as String?,
      );

      _requests.add(request);
      _isSubmitting = false;
      notifyListeners();
      return request;
    } catch (e) {
      _error = 'Removal request for ${broker.name} failed: $e';
      _isSubmitting = false;
      notifyListeners();
      return null;
    }
  }

  /// Request batch removal. Returns the number of successfully submitted
  /// requests; failures surface through [error].
  Future<int> requestBatchRemoval(List<DataBroker> brokers) async {
    int successCount = 0;

    for (final broker in brokers) {
      final result = await requestRemoval(broker);
      if (result != null) successCount++;
    }

    return successCount;
  }

  /// Refresh a removal request's status from GET /footprint/removal/{id}.
  /// Removal requests are processed asynchronously server-side, so polling
  /// this reflects real status transitions (pending → in_progress → ...).
  Future<void> refreshRequestStatus(String requestId) async {
    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index < 0) return;

    try {
      final response = await _api.getRemovalStatus(requestId);
      final request = _requests[index];

      _requests[index] = RemovalRequest(
        id: request.id,
        broker: request.broker,
        status: _parseStatus(response['status'] as String?),
        requestedAt:
            DateTime.tryParse((response['created_at'] as String?) ?? '') ??
                request.requestedAt,
        completedAt:
            DateTime.tryParse((response['completed_at'] as String?) ?? ''),
        confirmationId:
            (response['confirmation_id'] as String?) ?? request.confirmationId,
        notes: (response['notes'] as String?) ??
            (response['failure_reason'] as String?) ??
            request.notes,
      );

      notifyListeners();
    } catch (e) {
      _error = 'Failed to refresh removal status: $e';
      notifyListeners();
    }
  }

  /// Refresh all tracked removal requests that are not yet complete.
  Future<void> refreshAllRequestStatuses() async {
    final ids = pendingRequests.map((r) => r.id).toList();
    for (final id in ids) {
      await refreshRequestStatus(id);
    }
  }

  // ---------------------------------------------------------------------
  // Parsing helpers (live backend wire formats)
  // ---------------------------------------------------------------------

  DataBroker _parseBroker(Map<String, dynamic> broker) {
    final id = broker['id'] as String?;
    final name = broker['name'] as String?;
    if (id == null || name == null) {
      throw const FormatException('Broker entry missing "id" or "name"');
    }
    final optOutMethod = (broker['opt_out_method'] as String?) ?? '';
    return DataBroker(
      id: id,
      name: name,
      website: (broker['domain'] as String?) ??
          (broker['site_url'] as String?) ??
          '',
      category: _parseCategory(broker['category'] as String?),
      description: broker['description'] as String?,
      hasOptOut: optOutMethod.isNotEmpty && optOutMethod != 'none',
      optOutUrl: broker['opt_out_url'] as String?,
      estimatedDays: (broker['processing_days'] as num?)?.toInt() ?? 30,
      difficulty:
          _difficultyScore((broker['opt_out_difficulty'] as String?) ?? ''),
      dataCollected: (broker['data_types'] is List)
          ? List<String>.from(
              (broker['data_types'] as List).whereType<String>())
          : const [],
    );
  }

  FootprintScanResult _parseScanResult(Map<String, dynamic> response) {
    if (response['id'] == null || response['status'] == null) {
      throw const FormatException(
          'Unexpected footprint scan response: missing "id"/"status"');
    }

    // Brokers where the user's data was actually found (broker_findings[]).
    final brokers = <DataBroker>[];
    final brokerFindings = response['broker_findings'];
    if (brokerFindings is List) {
      for (final raw in brokerFindings) {
        if (raw is! Map) continue;
        final finding = Map<String, dynamic>.from(raw);
        if (finding['found'] != true) continue;
        final optOutUrl = finding['opt_out_url'] as String?;
        final optOutMethod = (finding['opt_out_method'] as String?) ?? '';
        brokers.add(DataBroker(
          id: (finding['broker_id'] as String?) ?? '',
          name: (finding['broker_name'] as String?) ?? 'Unknown broker',
          website: (finding['broker_url'] as String?) ?? '',
          category: _parseCategory(finding['category'] as String?),
          hasOptOut: (optOutUrl != null && optOutUrl.isNotEmpty) ||
              (optOutMethod.isNotEmpty && optOutMethod != 'none'),
          optOutUrl: optOutUrl,
          estimatedDays: (finding['estimated_days'] as num?)?.toInt() ?? 30,
          difficulty:
              _difficultyScore((finding['opt_out_difficulty'] as String?) ?? ''),
          dataCollected: (finding['data_types'] is List)
              ? List<String>.from(
                  (finding['data_types'] as List).whereType<String>())
              : const [],
        ));
      }
    }

    // Individual data exposures (exposures[]).
    final exposures = <ExposureFinding>[];
    final rawExposures = response['exposures'];
    if (rawExposures is List) {
      for (final raw in rawExposures) {
        if (raw is! Map) continue;
        final e = Map<String, dynamic>.from(raw);
        exposures.add(ExposureFinding(
          id: (e['id'] as String?) ?? '',
          dataType: (e['type'] as String?) ?? 'unknown',
          source: (e['source_name'] as String?) ??
              (e['source'] as String?) ??
              'unknown',
          value: e['exposed_value'] as String?,
          riskLevel: (e['severity'] as String?) ?? 'info',
          foundAt: DateTime.tryParse((e['first_seen'] as String?) ?? '') ??
              DateTime.tryParse((e['created_at'] as String?) ?? '') ??
              DateTime.now(),
        ));
      }
    }

    return FootprintScanResult(
      id: response['id'] as String,
      scannedAt:
          DateTime.tryParse((response['completed_at'] as String?) ?? '') ??
              DateTime.tryParse((response['started_at'] as String?) ?? '') ??
              DateTime.now(),
      status: response['status'] as String,
      brokersFound:
          (response['data_brokers_found'] as num?)?.toInt() ?? brokers.length,
      exposuresFound:
          (response['total_exposures'] as num?)?.toInt() ?? exposures.length,
      breachesFound: (response['breaches_found'] as num?)?.toInt() ?? 0,
      darkWebExposures:
          (response['dark_web_exposures'] as num?)?.toInt() ?? 0,
      brokers: brokers,
      exposures: exposures,
      riskScore: (response['risk_score'] as num?)?.toDouble() ?? 0,
      riskLevel: (response['risk_level'] as String?) ?? 'low',
    );
  }

  BrokerCategory _parseCategory(String? category) {
    switch (category) {
      case 'people_search':
        return BrokerCategory.peopleSearch;
      case 'marketing':
      case 'advertising':
        return BrokerCategory.marketing;
      case 'financial':
        return BrokerCategory.financial;
      case 'healthcare':
        return BrokerCategory.health;
      case 'background':
      case 'background_check':
        return BrokerCategory.background;
      default:
        return BrokerCategory.other;
    }
  }

  /// Maps backend RemovalStatus strings (pending, queued, in_progress,
  /// verifying, completed, failed, rejected, partial, reappeared) onto the
  /// UI status enum.
  RemovalStatus _parseStatus(String? status) {
    switch (status) {
      case 'pending':
      case 'queued':
        return RemovalStatus.pending;
      case 'in_progress':
      case 'verifying':
      case 'partial':
        return RemovalStatus.inProgress;
      case 'completed':
        return RemovalStatus.completed;
      case 'failed':
      case 'reappeared':
        return RemovalStatus.failed;
      case 'rejected':
        return RemovalStatus.rejected;
      default:
        return RemovalStatus.pending;
    }
  }

  /// Maps backend opt_out_difficulty (easy/medium/hard/very_hard) to the
  /// 0-1 scale used by the UI.
  double _difficultyScore(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return 0.25;
      case 'medium':
        return 0.5;
      case 'hard':
        return 0.75;
      case 'very_hard':
        return 1.0;
      default:
        return 0.5;
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
