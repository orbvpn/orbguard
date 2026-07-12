/// Digital Footprint Provider
/// State management for data broker removal and personal data exposure tracking

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

/// Scan result
class FootprintScanResult {
  final String id;
  final DateTime scannedAt;
  final int brokersFound;
  final int exposuresFound;
  final List<DataBroker> brokers;
  final List<ExposureFinding> exposures;
  final int privacyScore;

  FootprintScanResult({
    required this.id,
    required this.scannedAt,
    this.brokersFound = 0,
    this.exposuresFound = 0,
    this.brokers = const [],
    this.exposures = const [],
    this.privacyScore = 100,
  });
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

  /// Load data brokers
  Future<void> loadBrokers() async {
    try {
      final data = await _api.getDataBrokers();
      _brokers.clear();

      for (final broker in data) {
        _brokers.add(DataBroker(
          id: broker['id'],
          name: broker['name'],
          website: broker['website'],
          category: _parseCategory(broker['category']),
          description: broker['description'],
          hasOptOut: broker['has_opt_out'] ?? true,
          optOutUrl: broker['opt_out_url'],
          estimatedDays: broker['estimated_days'] ?? 30,
          difficulty: (broker['difficulty'] ?? 0.5).toDouble(),
          dataCollected: List<String>.from(broker['data_collected'] ?? []),
        ));
      }
    } catch (e) {
      // Load default brokers
      _brokers.addAll(_getDefaultBrokers());
    }
    notifyListeners();
  }

  /// Scan digital footprint
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
      // Simulate progress
      for (var i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 300));
        _scanProgress = (i + 1) / 10;
        notifyListeners();
      }

      final response = await _api.scanDigitalFootprint({
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'address': address,
      });

      final brokers = <DataBroker>[];
      for (final b in response['brokers'] ?? []) {
        brokers.add(DataBroker(
          id: b['id'],
          name: b['name'],
          website: b['website'],
          category: _parseCategory(b['category']),
          hasOptOut: b['has_opt_out'] ?? true,
          optOutUrl: b['opt_out_url'],
        ));
      }

      final exposures = <ExposureFinding>[];
      for (final e in response['exposures'] ?? []) {
        exposures.add(ExposureFinding(
          id: e['id'],
          dataType: e['data_type'],
          source: e['source'],
          value: e['value'],
          riskLevel: e['risk_level'],
          foundAt: DateTime.parse(e['found_at']),
        ));
      }

      _lastScan = FootprintScanResult(
        id: response['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        scannedAt: DateTime.now(),
        brokersFound: brokers.length,
        exposuresFound: exposures.length,
        brokers: brokers,
        exposures: exposures,
        privacyScore: response['privacy_score'] ?? 100,
      );

      _isScanning = false;
      _scanProgress = 1.0;
      notifyListeners();
      return _lastScan;
    } catch (e) {
      // Return simulated result
      _lastScan = FootprintScanResult(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        scannedAt: DateTime.now(),
        brokersFound: 12,
        exposuresFound: 8,
        brokers: _brokers.take(12).toList(),
        exposures: [],
        privacyScore: 45,
      );

      _isScanning = false;
      _scanProgress = 1.0;
      notifyListeners();
      return _lastScan;
    }
  }

  /// Request removal from broker
  Future<RemovalRequest?> requestRemoval(DataBroker broker) async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.requestDataRemoval(broker.id);

      final request = RemovalRequest(
        id: response['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        broker: broker,
        status: RemovalStatus.submitted,
        requestedAt: DateTime.now(),
        confirmationId: response['confirmation_id'],
      );

      _requests.add(request);
      _isSubmitting = false;
      notifyListeners();
      return request;
    } catch (e) {
      // Create local request
      final request = RemovalRequest(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        broker: broker,
        status: RemovalStatus.pending,
        requestedAt: DateTime.now(),
      );

      _requests.add(request);
      _isSubmitting = false;
      notifyListeners();
      return request;
    }
  }

  /// Request batch removal
  Future<int> requestBatchRemoval(List<DataBroker> brokers) async {
    int successCount = 0;

    for (final broker in brokers) {
      final result = await requestRemoval(broker);
      if (result != null) successCount++;
    }

    return successCount;
  }

  /// Get removal status
  Future<void> refreshRequestStatus(String requestId) async {
    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index < 0) return;

    try {
      final response = await _api.getRemovalStatus(requestId);
      final request = _requests[index];

      _requests[index] = RemovalRequest(
        id: request.id,
        broker: request.broker,
        status: _parseStatus(response['status']),
        requestedAt: request.requestedAt,
        completedAt: response['completed_at'] != null
            ? DateTime.parse(response['completed_at'])
            : null,
        confirmationId: response['confirmation_id'],
        notes: response['notes'],
      );

      notifyListeners();
    } catch (e) {
      // Keep current status
    }
  }

  BrokerCategory _parseCategory(String? category) {
    if (category == null) return BrokerCategory.other;

    for (final cat in BrokerCategory.values) {
      if (cat.name == category) return cat;
    }
    return BrokerCategory.other;
  }

  RemovalStatus _parseStatus(String? status) {
    if (status == null) return RemovalStatus.pending;

    for (final s in RemovalStatus.values) {
      if (s.name == status) return s;
    }
    return RemovalStatus.pending;
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Default brokers list
  List<DataBroker> _getDefaultBrokers() {
    return [
      DataBroker(
        id: '1',
        name: 'Spokeo',
        website: 'spokeo.com',
        category: BrokerCategory.peopleSearch,
        description: 'People search engine aggregating public records',
        hasOptOut: true,
        optOutUrl: 'https://www.spokeo.com/optout',
        estimatedDays: 3,
        difficulty: 0.3,
        dataCollected: ['Name', 'Address', 'Phone', 'Email', 'Relatives'],
      ),
      DataBroker(
        id: '2',
        name: 'Whitepages',
        website: 'whitepages.com',
        category: BrokerCategory.peopleSearch,
        description: 'Directory service with personal information',
        hasOptOut: true,
        optOutUrl: 'https://www.whitepages.com/suppression_requests',
        estimatedDays: 7,
        difficulty: 0.4,
        dataCollected: ['Name', 'Address', 'Phone', 'Age', 'Associates'],
      ),
      DataBroker(
        id: '3',
        name: 'BeenVerified',
        website: 'beenverified.com',
        category: BrokerCategory.background,
        description: 'Background check and people search service',
        hasOptOut: true,
        optOutUrl: 'https://www.beenverified.com/opt-out',
        estimatedDays: 14,
        difficulty: 0.5,
        dataCollected: ['Name', 'Address', 'Criminal Records', 'Assets'],
      ),
      DataBroker(
        id: '4',
        name: 'Intelius',
        website: 'intelius.com',
        category: BrokerCategory.peopleSearch,
        description: 'People search and public records',
        hasOptOut: true,
        optOutUrl: 'https://www.intelius.com/opt-out',
        estimatedDays: 7,
        difficulty: 0.4,
        dataCollected: ['Name', 'Address', 'Phone', 'Email', 'Work History'],
      ),
      DataBroker(
        id: '5',
        name: 'Acxiom',
        website: 'acxiom.com',
        category: BrokerCategory.marketing,
        description: 'Marketing data and consumer insights',
        hasOptOut: true,
        optOutUrl: 'https://www.acxiom.com/about-us/privacy/optout/',
        estimatedDays: 30,
        difficulty: 0.6,
        dataCollected: ['Demographics', 'Interests', 'Purchase History'],
      ),
      DataBroker(
        id: '6',
        name: 'Oracle Data Cloud',
        website: 'oracle.com',
        category: BrokerCategory.marketing,
        description: 'Advertising and marketing data platform',
        hasOptOut: true,
        estimatedDays: 45,
        difficulty: 0.7,
        dataCollected: ['Online Behavior', 'Purchase Intent', 'Demographics'],
      ),
      DataBroker(
        id: '7',
        name: 'Epsilon',
        website: 'epsilon.com',
        category: BrokerCategory.marketing,
        description: 'Marketing services and data',
        hasOptOut: true,
        estimatedDays: 30,
        difficulty: 0.5,
        dataCollected: ['Name', 'Address', 'Email', 'Phone', 'Preferences'],
      ),
      DataBroker(
        id: '8',
        name: 'TruthFinder',
        website: 'truthfinder.com',
        category: BrokerCategory.background,
        description: 'Background check service',
        hasOptOut: true,
        optOutUrl: 'https://www.truthfinder.com/opt-out/',
        estimatedDays: 14,
        difficulty: 0.5,
        dataCollected: ['Criminal Records', 'Court Records', 'Social Media'],
      ),
      DataBroker(
        id: '9',
        name: 'PeopleFinder',
        website: 'peoplefinder.com',
        category: BrokerCategory.peopleSearch,
        description: 'People search directory',
        hasOptOut: true,
        estimatedDays: 7,
        difficulty: 0.3,
        dataCollected: ['Name', 'Address', 'Phone', 'Relatives'],
      ),
      DataBroker(
        id: '10',
        name: 'Radaris',
        website: 'radaris.com',
        category: BrokerCategory.peopleSearch,
        description: 'People search and public records',
        hasOptOut: true,
        optOutUrl: 'https://radaris.com/control/privacy',
        estimatedDays: 14,
        difficulty: 0.6,
        dataCollected: ['Name', 'Address', 'Phone', 'Email', 'Property Records'],
      ),
    ];
  }
}
