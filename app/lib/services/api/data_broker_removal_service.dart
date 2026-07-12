/// Data Broker Removal Service
///
/// DIY automated data broker opt-out system.
/// Handles scanning and removal requests for major data brokers.
///
/// Supported brokers:
/// - Spokeo, WhitePages, BeenVerified, Intelius
/// - PeopleFinder, TruePeopleSearch, FastPeopleSearch
/// - Radaris, USSearch, ThatsThem, and more

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Data broker information
enum DataBroker {
  spokeo(
    'Spokeo',
    'https://www.spokeo.com/optout',
    OptOutDifficulty.medium,
    'Email verification required',
  ),
  whitepages(
    'WhitePages',
    'https://www.whitepages.com/suppression-requests',
    OptOutDifficulty.medium,
    'Identity verification required',
  ),
  beenVerified(
    'BeenVerified',
    'https://www.beenverified.com/app/optout/search',
    OptOutDifficulty.hard,
    'Account creation required',
  ),
  intelius(
    'Intelius',
    'https://www.intelius.com/opt-out',
    OptOutDifficulty.medium,
    'Form submission with verification',
  ),
  peopleFinder(
    'PeopleFinder',
    'https://www.peoplefinder.com/optout',
    OptOutDifficulty.easy,
    'Simple form submission',
  ),
  truePeopleSearch(
    'TruePeopleSearch',
    'https://www.truepeoplesearch.com/removal',
    OptOutDifficulty.easy,
    'Simple form submission',
  ),
  fastPeopleSearch(
    'FastPeopleSearch',
    'https://www.fastpeoplesearch.com/removal',
    OptOutDifficulty.easy,
    'Simple form submission',
  ),
  radaris(
    'Radaris',
    'https://radaris.com/control/privacy',
    OptOutDifficulty.hard,
    'Account and verification required',
  ),
  usSearch(
    'USSearch',
    'https://www.ussearch.com/opt-out',
    OptOutDifficulty.medium,
    'Form submission required',
  ),
  thatsThem(
    'ThatsThem',
    'https://thatsthem.com/optout',
    OptOutDifficulty.medium,
    'Email verification required',
  ),
  myLife(
    'MyLife',
    'https://www.mylife.com/privacy-policy',
    OptOutDifficulty.hard,
    'Phone verification required',
  ),
  instantCheckmate(
    'InstantCheckmate',
    'https://www.instantcheckmate.com/opt-out',
    OptOutDifficulty.medium,
    'Form submission required',
  ),
  piplSearch(
    'Pipl',
    'https://pipl.com/personal-information-removal-request',
    OptOutDifficulty.hard,
    'Business email only',
  ),
  zabaSearch(
    'ZabaSearch',
    'https://www.zabasearch.com/block_records',
    OptOutDifficulty.easy,
    'Fax required for removal',
  ),
  familyTreeNow(
    'FamilyTreeNow',
    'https://www.familytreenow.com/optout',
    OptOutDifficulty.easy,
    'Simple form submission',
  ),
  cyberBackgroundChecks(
    'CyberBackgroundChecks',
    'https://www.cyberbackgroundchecks.com/removal',
    OptOutDifficulty.easy,
    'Simple form submission',
  ),
  publicRecordsNow(
    'PublicRecordsNow',
    'https://www.publicrecordsnow.com/optout',
    OptOutDifficulty.medium,
    'Email verification required',
  ),
  advancedBackgroundChecks(
    'AdvancedBackgroundChecks',
    'https://www.advancedbackgroundchecks.com/removal',
    OptOutDifficulty.easy,
    'Simple form submission',
  ),
  nuwber(
    'Nuwber',
    'https://nuwber.com/removal/link',
    OptOutDifficulty.medium,
    'Profile URL required',
  ),
  clustrMaps(
    'ClustrMaps',
    'https://clustrmaps.com/bl/opt-out',
    OptOutDifficulty.easy,
    'Simple form submission',
  );

  final String displayName;
  final String optOutUrl;
  final OptOutDifficulty difficulty;
  final String notes;

  const DataBroker(this.displayName, this.optOutUrl, this.difficulty, this.notes);
}

/// Opt-out difficulty level
enum OptOutDifficulty {
  easy('Easy', 'Simple form submission'),
  medium('Medium', 'Email or identity verification'),
  hard('Hard', 'Account creation or phone verification');

  final String displayName;
  final String description;

  const OptOutDifficulty(this.displayName, this.description);
}

/// Status of a data broker record
enum RecordStatus {
  found('Found', 'Record found on broker site'),
  removalRequested('Requested', 'Removal request submitted'),
  pendingVerification('Pending', 'Awaiting verification'),
  removed('Removed', 'Successfully removed'),
  reappeared('Reappeared', 'Record reappeared after removal'),
  failed('Failed', 'Removal request failed'),
  notFound('Not Found', 'No record found');

  final String displayName;
  final String description;

  const RecordStatus(this.displayName, this.description);
}

/// User profile for data broker searches
class UserProfile {
  final String firstName;
  final String lastName;
  final String? middleName;
  final String? city;
  final String? state;
  final String? zipCode;
  final String? email;
  final String? phone;
  final int? age;
  final List<String> previousAddresses;
  final List<String> previousNames;

  UserProfile({
    required this.firstName,
    required this.lastName,
    this.middleName,
    this.city,
    this.state,
    this.zipCode,
    this.email,
    this.phone,
    this.age,
    this.previousAddresses = const [],
    this.previousNames = const [],
  });

  String get fullName => middleName != null
      ? '$firstName $middleName $lastName'
      : '$firstName $lastName';

  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'middle_name': middleName,
        'city': city,
        'state': state,
        'zip_code': zipCode,
        'email': email,
        'phone': phone,
        'age': age,
        'previous_addresses': previousAddresses,
        'previous_names': previousNames,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      middleName: json['middle_name'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      zipCode: json['zip_code'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      age: json['age'] as int?,
      previousAddresses: (json['previous_addresses'] as List<dynamic>?)
              ?.cast<String>() ??
          [],
      previousNames:
          (json['previous_names'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}

/// Record found on a data broker
class DataBrokerRecord {
  final String id;
  final DataBroker broker;
  final String? profileUrl;
  final String name;
  final String? city;
  final String? state;
  final int? age;
  final List<String> associatedNames;
  final List<String> associatedAddresses;
  final List<String> associatedPhones;
  final List<String> associatedEmails;
  final RecordStatus status;
  final DateTime foundDate;
  final DateTime? removalRequestDate;
  final DateTime? removalConfirmDate;
  final String? verificationCode;
  final List<String> optOutSteps;

  DataBrokerRecord({
    required this.id,
    required this.broker,
    this.profileUrl,
    required this.name,
    this.city,
    this.state,
    this.age,
    this.associatedNames = const [],
    this.associatedAddresses = const [],
    this.associatedPhones = const [],
    this.associatedEmails = const [],
    required this.status,
    required this.foundDate,
    this.removalRequestDate,
    this.removalConfirmDate,
    this.verificationCode,
    this.optOutSteps = const [],
  });

  DataBrokerRecord copyWith({
    RecordStatus? status,
    DateTime? removalRequestDate,
    DateTime? removalConfirmDate,
    String? verificationCode,
  }) {
    return DataBrokerRecord(
      id: id,
      broker: broker,
      profileUrl: profileUrl,
      name: name,
      city: city,
      state: state,
      age: age,
      associatedNames: associatedNames,
      associatedAddresses: associatedAddresses,
      associatedPhones: associatedPhones,
      associatedEmails: associatedEmails,
      status: status ?? this.status,
      foundDate: foundDate,
      removalRequestDate: removalRequestDate ?? this.removalRequestDate,
      removalConfirmDate: removalConfirmDate ?? this.removalConfirmDate,
      verificationCode: verificationCode ?? this.verificationCode,
      optOutSteps: optOutSteps,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'broker': broker.name,
        'profile_url': profileUrl,
        'name': name,
        'city': city,
        'state': state,
        'age': age,
        'associated_names': associatedNames,
        'associated_addresses': associatedAddresses,
        'associated_phones': associatedPhones,
        'associated_emails': associatedEmails,
        'status': status.name,
        'found_date': foundDate.toIso8601String(),
        'removal_request_date': removalRequestDate?.toIso8601String(),
        'removal_confirm_date': removalConfirmDate?.toIso8601String(),
        'verification_code': verificationCode,
        'opt_out_steps': optOutSteps,
      };

  factory DataBrokerRecord.fromJson(Map<String, dynamic> json) {
    return DataBrokerRecord(
      id: json['id'] as String,
      broker: DataBroker.values.firstWhere(
        (b) => b.name == json['broker'],
        orElse: () => DataBroker.spokeo,
      ),
      profileUrl: json['profile_url'] as String?,
      name: json['name'] as String,
      city: json['city'] as String?,
      state: json['state'] as String?,
      age: json['age'] as int?,
      associatedNames:
          (json['associated_names'] as List<dynamic>?)?.cast<String>() ?? [],
      associatedAddresses:
          (json['associated_addresses'] as List<dynamic>?)?.cast<String>() ??
              [],
      associatedPhones:
          (json['associated_phones'] as List<dynamic>?)?.cast<String>() ?? [],
      associatedEmails:
          (json['associated_emails'] as List<dynamic>?)?.cast<String>() ?? [],
      status: RecordStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => RecordStatus.found,
      ),
      foundDate: DateTime.parse(json['found_date'] as String),
      removalRequestDate: json['removal_request_date'] != null
          ? DateTime.parse(json['removal_request_date'] as String)
          : null,
      removalConfirmDate: json['removal_confirm_date'] != null
          ? DateTime.parse(json['removal_confirm_date'] as String)
          : null,
      verificationCode: json['verification_code'] as String?,
      optOutSteps:
          (json['opt_out_steps'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}

/// Removal request
class RemovalRequest {
  final String id;
  final DataBrokerRecord record;
  final DateTime requestedAt;
  final RemovalMethod method;
  final RemovalStatus status;
  final String? errorMessage;
  final List<RemovalStep> steps;

  RemovalRequest({
    required this.id,
    required this.record,
    required this.requestedAt,
    required this.method,
    required this.status,
    this.errorMessage,
    this.steps = const [],
  });
}

enum RemovalMethod {
  automated('Automated', 'Automatic form submission'),
  semiAutomated('Semi-Automated', 'Guided with manual verification'),
  manual('Manual', 'Step-by-step instructions');

  final String displayName;
  final String description;

  const RemovalMethod(this.displayName, this.description);
}

enum RemovalStatus {
  pending('Pending', 'Request not yet submitted'),
  submitted('Submitted', 'Request submitted to broker'),
  verificationNeeded('Verification Needed', 'Requires user action'),
  processing('Processing', 'Being processed by broker'),
  completed('Completed', 'Successfully removed'),
  failed('Failed', 'Removal request failed'),
  recheck('Recheck', 'Needs verification');

  final String displayName;
  final String description;

  const RemovalStatus(this.displayName, this.description);
}

class RemovalStep {
  final int stepNumber;
  final String instruction;
  final bool isCompleted;
  final String? url;
  final String? inputRequired;

  RemovalStep({
    required this.stepNumber,
    required this.instruction,
    this.isCompleted = false,
    this.url,
    this.inputRequired,
  });
}

/// Scan result
class BrokerScanResult {
  final UserProfile profile;
  final List<DataBrokerRecord> records;
  final DateTime scannedAt;
  final int brokersScanned;
  final int recordsFound;
  final Duration scanDuration;

  BrokerScanResult({
    required this.profile,
    required this.records,
    required this.scannedAt,
    required this.brokersScanned,
    required this.recordsFound,
    required this.scanDuration,
  });

  int get easyRemovals =>
      records.where((r) => r.broker.difficulty == OptOutDifficulty.easy).length;

  int get mediumRemovals =>
      records.where((r) => r.broker.difficulty == OptOutDifficulty.medium).length;

  int get hardRemovals =>
      records.where((r) => r.broker.difficulty == OptOutDifficulty.hard).length;
}

/// Data Broker Removal Service
class DataBrokerRemovalService {
  final http.Client _client;
  final List<DataBrokerRecord> _records = [];
  final List<RemovalRequest> _removalRequests = [];
  UserProfile? _userProfile;

  final _scanProgressController = StreamController<ScanProgress>.broadcast();
  final _removalProgressController = StreamController<RemovalProgress>.broadcast();

  Stream<ScanProgress> get scanProgress => _scanProgressController.stream;
  Stream<RemovalProgress> get removalProgress => _removalProgressController.stream;

  DataBrokerRemovalService({http.Client? client})
      : _client = client ?? http.Client();

  /// Set user profile for searches
  void setUserProfile(UserProfile profile) {
    _userProfile = profile;
  }

  /// Get current user profile
  UserProfile? get userProfile => _userProfile;

  /// Scan all data brokers for user's information
  Future<BrokerScanResult> scanAllBrokers(UserProfile profile) async {
    _userProfile = profile;
    final startTime = DateTime.now();
    final foundRecords = <DataBrokerRecord>[];

    int scannedCount = 0;
    final totalBrokers = DataBroker.values.length;

    for (final broker in DataBroker.values) {
      _scanProgressController.add(ScanProgress(
        broker: broker,
        current: scannedCount,
        total: totalBrokers,
        status: 'Scanning ${broker.displayName}...',
      ));

      try {
        final records = await _scanBroker(broker, profile);
        foundRecords.addAll(records);
      } catch (e) {
        print('Failed to scan ${broker.displayName}: $e');
      }

      scannedCount++;

      // Rate limiting to avoid blocks
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _records.clear();
    _records.addAll(foundRecords);

    final scanDuration = DateTime.now().difference(startTime);

    _scanProgressController.add(ScanProgress(
      broker: null,
      current: totalBrokers,
      total: totalBrokers,
      status: 'Scan complete',
      isComplete: true,
    ));

    return BrokerScanResult(
      profile: profile,
      records: foundRecords,
      scannedAt: DateTime.now(),
      brokersScanned: totalBrokers,
      recordsFound: foundRecords.length,
      scanDuration: scanDuration,
    );
  }

  /// Scan individual broker
  Future<List<DataBrokerRecord>> _scanBroker(
    DataBroker broker,
    UserProfile profile,
  ) async {
    // This would need actual scraping implementation
    // For now, we simulate the scan with heuristics

    // In production, this would:
    // 1. Use headless browser (Puppeteer/Selenium via platform channel)
    // 2. Or call a backend API that handles scraping
    // 3. Or use official APIs where available

    final records = <DataBrokerRecord>[];

    // Simulated scan - in production, replace with actual scraping
    final searchUrl = _buildSearchUrl(broker, profile);

    try {
      // Attempt to fetch search results page
      final response = await _client.get(
        Uri.parse(searchUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Parse response to find matching records
        final foundRecords = _parseSearchResults(broker, response.body, profile);
        records.addAll(foundRecords);
      }
    } catch (e) {
      // Log error but don't fail the entire scan
      print('Error scanning ${broker.displayName}: $e');
    }

    return records;
  }

  /// Build search URL for broker
  String _buildSearchUrl(DataBroker broker, UserProfile profile) {
    final firstName = Uri.encodeComponent(profile.firstName);
    final lastName = Uri.encodeComponent(profile.lastName);
    final city = profile.city != null ? Uri.encodeComponent(profile.city!) : '';
    final state = profile.state != null ? Uri.encodeComponent(profile.state!) : '';

    switch (broker) {
      case DataBroker.spokeo:
        return 'https://www.spokeo.com/$firstName-$lastName${city.isNotEmpty ? '/$city-$state' : ''}';
      case DataBroker.whitepages:
        return 'https://www.whitepages.com/name/$firstName-$lastName${city.isNotEmpty ? '/$city-$state' : ''}';
      case DataBroker.truePeopleSearch:
        return 'https://www.truepeoplesearch.com/results?name=$firstName%20$lastName${city.isNotEmpty ? '&citystatezip=$city%20$state' : ''}';
      case DataBroker.fastPeopleSearch:
        return 'https://www.fastpeoplesearch.com/name/$firstName-$lastName${city.isNotEmpty ? '_$city-$state' : ''}';
      case DataBroker.thatsThem:
        return 'https://thatsthem.com/name/$firstName-$lastName${city.isNotEmpty ? '/$city-$state' : ''}';
      case DataBroker.nuwber:
        return 'https://nuwber.com/search?name=$firstName%20$lastName${city.isNotEmpty ? '&city=$city&state=$state' : ''}';
      default:
        return broker.optOutUrl;
    }
  }

  /// Parse search results from broker response
  List<DataBrokerRecord> _parseSearchResults(
    DataBroker broker,
    String html,
    UserProfile profile,
  ) {
    final records = <DataBrokerRecord>[];

    // Basic detection - check if name appears in response
    final nameVariations = [
      profile.fullName.toLowerCase(),
      '${profile.firstName} ${profile.lastName}'.toLowerCase(),
    ];

    final htmlLower = html.toLowerCase();

    for (final name in nameVariations) {
      if (htmlLower.contains(name)) {
        // Found a potential match
        records.add(DataBrokerRecord(
          id: '${broker.name}_${DateTime.now().millisecondsSinceEpoch}',
          broker: broker,
          name: profile.fullName,
          city: profile.city,
          state: profile.state,
          age: profile.age,
          status: RecordStatus.found,
          foundDate: DateTime.now(),
          optOutSteps: _getOptOutSteps(broker),
        ));
        break;
      }
    }

    return records;
  }

  /// Get opt-out steps for a broker
  List<String> _getOptOutSteps(DataBroker broker) {
    switch (broker) {
      case DataBroker.spokeo:
        return [
          'Go to ${broker.optOutUrl}',
          'Search for your name and find your listing',
          'Click on your profile to get the profile URL',
          'Enter the profile URL in the opt-out form',
          'Enter your email address for verification',
          'Click the verification link sent to your email',
          'Your listing will be removed within 24-48 hours',
        ];
      case DataBroker.whitepages:
        return [
          'Go to ${broker.optOutUrl}',
          'Search for and find your listing',
          'Copy the URL of your profile',
          'Enter the URL in the removal request form',
          'Select a reason for removal',
          'Verify your phone number via call or text',
          'Removal takes 24-48 hours',
        ];
      case DataBroker.truePeopleSearch:
        return [
          'Go to ${broker.optOutUrl}',
          'Find your listing by searching your name',
          'Click on your listing',
          'Click "Remove This Record" button',
          'Complete the CAPTCHA verification',
          'Record will be removed immediately',
        ];
      case DataBroker.fastPeopleSearch:
        return [
          'Go to ${broker.optOutUrl}',
          'Find your listing',
          'Click the "Remove This Record" button',
          'Record will be removed within minutes',
        ];
      case DataBroker.beenVerified:
        return [
          'Go to ${broker.optOutUrl}',
          'Create a free account (required)',
          'Search for your record',
          'Click on your listing',
          'Submit opt-out request through your account',
          'Removal takes 1-2 weeks',
        ];
      case DataBroker.radaris:
        return [
          'Go to ${broker.optOutUrl}',
          'Create an account (required)',
          'Find your profile',
          'Click "Control Information"',
          'Select "Make Private" or "Remove"',
          'Verify via email',
          'Removal takes up to 48 hours',
        ];
      case DataBroker.intelius:
        return [
          'Go to ${broker.optOutUrl}',
          'Search for your listing',
          'Select the record(s) to remove',
          'Provide verification information',
          'Submit the opt-out form',
          'Removal takes 7-14 days',
        ];
      default:
        return [
          'Go to ${broker.optOutUrl}',
          'Find your listing',
          'Follow the opt-out instructions',
          'Complete any required verification',
          'Wait for removal confirmation',
        ];
    }
  }

  /// Request removal from a specific broker
  Future<RemovalRequest> requestRemoval(DataBrokerRecord record) async {
    final request = RemovalRequest(
      id: 'removal_${DateTime.now().millisecondsSinceEpoch}',
      record: record,
      requestedAt: DateTime.now(),
      method: _getRemovalMethod(record.broker),
      status: RemovalStatus.pending,
      steps: _buildRemovalSteps(record),
    );

    _removalRequests.add(request);

    // Update record status
    final index = _records.indexWhere((r) => r.id == record.id);
    if (index >= 0) {
      _records[index] = record.copyWith(
        status: RecordStatus.removalRequested,
        removalRequestDate: DateTime.now(),
      );
    }

    _removalProgressController.add(RemovalProgress(
      request: request,
      status: 'Removal request initiated',
    ));

    return request;
  }

  RemovalMethod _getRemovalMethod(DataBroker broker) {
    switch (broker.difficulty) {
      case OptOutDifficulty.easy:
        return RemovalMethod.automated;
      case OptOutDifficulty.medium:
        return RemovalMethod.semiAutomated;
      case OptOutDifficulty.hard:
        return RemovalMethod.manual;
    }
  }

  List<RemovalStep> _buildRemovalSteps(DataBrokerRecord record) {
    final steps = <RemovalStep>[];
    final optOutSteps = record.optOutSteps.isNotEmpty
        ? record.optOutSteps
        : _getOptOutSteps(record.broker);

    for (int i = 0; i < optOutSteps.length; i++) {
      steps.add(RemovalStep(
        stepNumber: i + 1,
        instruction: optOutSteps[i],
        url: i == 0 ? record.broker.optOutUrl : null,
      ));
    }

    return steps;
  }

  /// Request removal from all found brokers
  Future<List<RemovalRequest>> requestRemovalAll() async {
    final requests = <RemovalRequest>[];

    for (final record in _records.where((r) => r.status == RecordStatus.found)) {
      final request = await requestRemoval(record);
      requests.add(request);

      // Rate limiting
      await Future.delayed(const Duration(milliseconds: 500));
    }

    return requests;
  }

  /// Mark removal step as completed
  void completeRemovalStep(String requestId, int stepNumber) {
    final index = _removalRequests.indexWhere((r) => r.id == requestId);
    if (index >= 0) {
      // In a full implementation, this would update the step status
      _removalProgressController.add(RemovalProgress(
        request: _removalRequests[index],
        status: 'Step $stepNumber completed',
      ));
    }
  }

  /// Verify removal was successful
  Future<bool> verifyRemoval(DataBrokerRecord record) async {
    // Re-scan the specific broker to verify removal
    if (_userProfile == null) return false;

    try {
      final results = await _scanBroker(record.broker, _userProfile!);
      final stillExists = results.any((r) =>
          r.name.toLowerCase() == record.name.toLowerCase() &&
          r.city?.toLowerCase() == record.city?.toLowerCase());

      if (!stillExists) {
        // Update record status
        final index = _records.indexWhere((r) => r.id == record.id);
        if (index >= 0) {
          _records[index] = record.copyWith(
            status: RecordStatus.removed,
            removalConfirmDate: DateTime.now(),
          );
        }
        return true;
      } else {
        // Record reappeared or never removed
        final index = _records.indexWhere((r) => r.id == record.id);
        if (index >= 0) {
          _records[index] = record.copyWith(
            status: RecordStatus.reappeared,
          );
        }
        return false;
      }
    } catch (e) {
      print('Verification failed: $e');
      return false;
    }
  }

  /// Get all found records
  List<DataBrokerRecord> getRecords({RecordStatus? status}) {
    if (status == null) return List.unmodifiable(_records);
    return _records.where((r) => r.status == status).toList();
  }

  /// Get all removal requests
  List<RemovalRequest> getRemovalRequests({RemovalStatus? status}) {
    if (status == null) return List.unmodifiable(_removalRequests);
    return _removalRequests.where((r) => r.status == status).toList();
  }

  /// Get statistics
  DataBrokerStats getStats() {
    return DataBrokerStats(
      totalBrokers: DataBroker.values.length,
      recordsFound: _records.where((r) => r.status == RecordStatus.found).length,
      removalRequested: _records.where((r) => r.status == RecordStatus.removalRequested).length,
      removedSuccessfully: _records.where((r) => r.status == RecordStatus.removed).length,
      pendingVerification: _records.where((r) => r.status == RecordStatus.pendingVerification).length,
      failed: _records.where((r) => r.status == RecordStatus.failed).length,
      reappeared: _records.where((r) => r.status == RecordStatus.reappeared).length,
    );
  }

  /// Dispose resources
  void dispose() {
    _client.close();
    _scanProgressController.close();
    _removalProgressController.close();
  }
}

/// Scan progress update
class ScanProgress {
  final DataBroker? broker;
  final int current;
  final int total;
  final String status;
  final bool isComplete;

  ScanProgress({
    this.broker,
    required this.current,
    required this.total,
    required this.status,
    this.isComplete = false,
  });

  double get progress => total > 0 ? current / total : 0;
}

/// Removal progress update
class RemovalProgress {
  final RemovalRequest request;
  final String status;

  RemovalProgress({
    required this.request,
    required this.status,
  });
}

/// Data broker statistics
class DataBrokerStats {
  final int totalBrokers;
  final int recordsFound;
  final int removalRequested;
  final int removedSuccessfully;
  final int pendingVerification;
  final int failed;
  final int reappeared;

  DataBrokerStats({
    required this.totalBrokers,
    required this.recordsFound,
    required this.removalRequested,
    required this.removedSuccessfully,
    required this.pendingVerification,
    required this.failed,
    required this.reappeared,
  });

  int get totalActive => recordsFound + removalRequested + pendingVerification;

  double get removalSuccessRate {
    final total = removedSuccessfully + failed;
    return total > 0 ? removedSuccessfully / total : 0;
  }
}
