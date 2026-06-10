/// SMS Provider
/// State management for SMS protection features.
///
/// The provider OWNS the [SmsPlatformService] (constructor-injected); UI code
/// consumes only this provider. Blocked senders, protection settings and the
/// per-message analysis history are persisted with [SharedPreferences]
/// (the app-wide local persistence pattern, see settings_provider.dart).
library sms_provider;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api/orbguard_api_client.dart';
import '../services/platform/sms_platform_service.dart';
import '../models/api/sms_analysis.dart';

/// Local SMS message model
class SmsMessage {
  final String id;
  final String sender;
  final String content;
  final DateTime timestamp;
  final bool isRead;
  SmsAnalysisResult? analysisResult;
  bool isAnalyzing;

  SmsMessage({
    required this.id,
    required this.sender,
    required this.content,
    required this.timestamp,
    this.isRead = false,
    this.analysisResult,
    this.isAnalyzing = false,
  });

  SmsMessage copyWith({
    String? id,
    String? sender,
    String? content,
    DateTime? timestamp,
    bool? isRead,
    SmsAnalysisResult? analysisResult,
    bool? isAnalyzing,
  }) {
    return SmsMessage(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      analysisResult: analysisResult ?? this.analysisResult,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
    );
  }

  /// Check if this message has threats
  bool get hasThreats =>
      analysisResult != null && analysisResult!.hasThreats;

  /// Get threat level
  SmsThreatLevel get threatLevel =>
      analysisResult?.threatLevel ?? SmsThreatLevel.safe;
}

/// SMS statistics.
///
/// Threat counters are derived from the persisted analysis history (real
/// backend verdicts only), so they survive restarts; [totalMessages] and
/// [analyzedMessages] reflect the currently loaded inbox.
class SmsStats {
  final int totalMessages;
  final int analyzedMessages;
  final int threatsDetected;
  final int criticalThreats;
  final int highThreats;
  final int blockedSenders;
  final DateTime? lastScanAt;

  SmsStats({
    this.totalMessages = 0,
    this.analyzedMessages = 0,
    this.threatsDetected = 0,
    this.criticalThreats = 0,
    this.highThreats = 0,
    this.blockedSenders = 0,
    this.lastScanAt,
  });

  SmsStats copyWith({
    int? totalMessages,
    int? analyzedMessages,
    int? threatsDetected,
    int? criticalThreats,
    int? highThreats,
    int? blockedSenders,
    DateTime? lastScanAt,
  }) {
    return SmsStats(
      totalMessages: totalMessages ?? this.totalMessages,
      analyzedMessages: analyzedMessages ?? this.analyzedMessages,
      threatsDetected: threatsDetected ?? this.threatsDetected,
      criticalThreats: criticalThreats ?? this.criticalThreats,
      highThreats: highThreats ?? this.highThreats,
      blockedSenders: blockedSenders ?? this.blockedSenders,
      lastScanAt: lastScanAt ?? this.lastScanAt,
    );
  }
}

/// Filter options for SMS list
enum SmsFilter {
  all,
  safe,
  suspicious,
  dangerous,
  unanalyzed,
}

/// Sort options for SMS list
enum SmsSort {
  dateDesc,
  dateAsc,
  threatLevel,
  sender,
}

/// Honest state of the native SMS pipeline.
enum SmsPlatformStatus {
  /// Not checked yet (init/loadMessages has not completed).
  unknown,

  /// Inbox readable: platform supported and permission granted.
  ready,

  /// Platform supports SMS but the READ_SMS permission is missing.
  permissionRequired,

  /// This platform does not expose an SMS inbox (e.g. iOS, desktop, web).
  unsupported,

  /// The native channel exists but failed (real error, surfaced as-is).
  error,
}

/// SMS Provider for state management
class SmsProvider extends ChangeNotifier {
  SmsProvider({SmsPlatformService? platformService})
      : _platform = platformService ?? SmsPlatformService.instance;

  final OrbGuardApiClient _api = OrbGuardApiClient.instance;
  final SmsPlatformService _platform;

  // Persistence keys (SharedPreferences - app-wide pattern).
  static const _kBlockedSendersKey = 'sms_blocked_senders';
  static const _kAnalysisHistoryKey = 'sms_analysis_history';
  static const _kDeletedIdsKey = 'sms_deleted_message_ids';
  static const _kLastScanAtKey = 'sms_last_scan_at';
  static const _kProtectionEnabledKey = 'sms_protection_enabled';
  static const _kNotifyOnThreatKey = 'sms_notify_on_threat';
  static const _kAutoBlockDangerousKey = 'sms_auto_block_dangerous';

  /// Cap for the persisted analysis history (most recent kept).
  static const _maxPersistedAnalyses = 500;

  SharedPreferences? _prefs;
  bool _initialized = false;

  // State
  List<SmsMessage> _messages = [];
  List<String> _blockedSenders = [];
  Set<String> _deletedMessageIds = {};

  /// Persisted per-message analysis verdicts (message id -> result summary).
  /// Only real backend responses ever enter this map.
  final Map<String, SmsAnalysisResult> _analysisHistory = {};

  SmsStats _stats = SmsStats();
  SmsFilter _filter = SmsFilter.all;
  SmsSort _sort = SmsSort.dateDesc;

  bool _isLoading = false;
  bool _isAnalyzing = false;
  String? _error;

  // Honest pipeline state
  SmsPlatformStatus _platformStatus = SmsPlatformStatus.unknown;
  String? _platformStatusDetail;
  bool _hasSmsPermission = false;
  bool _hasLoadedOnce = false;

  // Backend health (real outcome of the last analyze call).
  bool? _lastAnalyzeSucceeded;
  String? _lastAnalyzeError;
  DateTime? _lastBackendSuccessAt;
  DateTime? _lastScanAt;

  // Protection settings (persisted, pushed to native).
  bool _protectionEnabled = true;
  bool _notifyOnThreat = true;
  bool _autoBlockDangerous = false;

  // Selected message for detail view
  SmsMessage? _selectedMessage;

  // Getters
  List<SmsMessage> get messages => _getFilteredMessages();
  List<SmsMessage> get allMessages => _messages;
  List<String> get blockedSenders => _blockedSenders;
  SmsStats get stats => _stats;
  SmsFilter get filter => _filter;
  SmsSort get sort => _sort;
  bool get isLoading => _isLoading;
  bool get isAnalyzing => _isAnalyzing;
  String? get error => _error;
  SmsMessage? get selectedMessage => _selectedMessage;

  SmsPlatformStatus get platformStatus => _platformStatus;
  String? get platformStatusDetail => _platformStatusDetail;
  bool get hasSmsPermission => _hasSmsPermission;
  bool get isPlatformSupported => _platform.isSupported;
  bool get hasLoadedOnce => _hasLoadedOnce;

  bool? get lastAnalyzeSucceeded => _lastAnalyzeSucceeded;
  String? get lastAnalyzeError => _lastAnalyzeError;
  DateTime? get lastBackendSuccessAt => _lastBackendSuccessAt;

  bool get protectionEnabled => _protectionEnabled;
  bool get notifyOnThreat => _notifyOnThreat;
  bool get autoBlockDangerous => _autoBlockDangerous;

  /// Get count of unanalyzed messages
  int get unanalyzedCount =>
      _messages.where((m) => m.analysisResult == null).length;

  /// Get count of threats
  int get threatCount =>
      _messages.where((m) => m.hasThreats).length;

  /// Initialize provider: load persisted state, take ownership of the
  /// platform service, then load the device inbox.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('SmsProvider: SharedPreferences unavailable: $e');
    }

    await loadBlockedSenders();
    _loadDeletedIds();
    _loadSettings();
    _loadAnalysisHistory();
    _loadLastScanAt();

    // The provider owns the platform service: register ourselves as the
    // sink for incoming SMS and push the persisted settings down to native.
    await _platform.init(smsProvider: this);
    await _platform.updateSettings(
      protectionEnabled: _protectionEnabled,
      notifyOnThreat: _notifyOnThreat,
      autoBlockDangerous: _autoBlockDangerous,
    );

    _updateStats();
    notifyListeners();

    await loadMessages();
  }

  /// Load SMS messages from the real device inbox via the platform channel.
  ///
  /// On unsupported platforms (iOS/desktop/web) this surfaces an explicit
  /// unavailable state instead of an empty "clean" inbox. New (never
  /// analyzed) messages are then analyzed through the backend batch endpoint.
  Future<void> loadMessages() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (!_platform.isSupported) {
        _platformStatus = SmsPlatformStatus.unsupported;
        _platformStatusDetail = _platform.unsupportedReason;
        _hasSmsPermission = false;
        return;
      }

      _hasSmsPermission = await _platform.checkSmsPermission();
      if (!_hasSmsPermission) {
        _platformStatus = SmsPlatformStatus.permissionRequired;
        _platformStatusDetail =
            'SMS permission has not been granted. Grant it to scan your inbox.';
        return;
      }

      final inbox = await _platform.readSmsInbox(limit: 200);
      _mergeInbox(inbox);
      _platformStatus = SmsPlatformStatus.ready;
      _platformStatusDetail = null;
      _hasLoadedOnce = true;
      _updateStats();
    } on SmsPlatformUnavailableException catch (e) {
      _platformStatus = SmsPlatformStatus.unsupported;
      _platformStatusDetail = e.message;
      _error = e.message;
      debugPrint('SmsProvider: SMS pipeline unavailable: $e');
    } catch (e) {
      _platformStatus = SmsPlatformStatus.error;
      _platformStatusDetail = '$e';
      _error = 'Failed to load messages: $e';
      debugPrint('SmsProvider: loadMessages failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    // Analyze messages that have never been analyzed (batch backend flow).
    if (_platformStatus == SmsPlatformStatus.ready && unanalyzedCount > 0) {
      await analyzeAllMessages();
    }
  }

  /// Merge a freshly read inbox into the current list, preserving in-memory
  /// analyses, re-attaching persisted analyses, and honoring local deletions.
  void _mergeInbox(List<SmsMessage> inbox) {
    final existingById = {for (final m in _messages) m.id: m};
    final merged = <SmsMessage>[];
    final seen = <String>{};

    for (final incoming in inbox) {
      if (incoming.id.isEmpty || _deletedMessageIds.contains(incoming.id)) {
        continue;
      }
      seen.add(incoming.id);
      final existing = existingById[incoming.id];
      merged.add(incoming.copyWith(
        analysisResult:
            existing?.analysisResult ?? _analysisHistory[incoming.id],
        isAnalyzing: existing?.isAnalyzing ?? false,
        isRead: (existing?.isRead ?? false) || incoming.isRead,
      ));
    }

    // Keep messages we already have that the inbox read did not return
    // (e.g. just received via the broadcast receiver, or beyond the limit).
    for (final m in _messages) {
      if (!seen.contains(m.id) && !_deletedMessageIds.contains(m.id)) {
        merged.add(m.copyWith(
          analysisResult: m.analysisResult ?? _analysisHistory[m.id],
        ));
      }
    }

    _messages = merged;
  }

  /// Trigger the Android runtime permission dialog. The grant result arrives
  /// asynchronously; callers should invoke [loadMessages] again (e.g. on app
  /// resume) to re-check.
  Future<void> requestSmsPermission() async {
    try {
      await _platform.requestSmsPermission();
    } on SmsPlatformUnavailableException catch (e) {
      _platformStatus = SmsPlatformStatus.unsupported;
      _platformStatusDetail = e.message;
      notifyListeners();
    } catch (e) {
      _error = 'Permission request failed: $e';
      notifyListeners();
    }
  }

  /// Add a message (from platform channel or manual input)
  void addMessage(SmsMessage message) {
    if (message.id.isNotEmpty && _deletedMessageIds.contains(message.id)) {
      // User deleted this message in-app; honor that.
      return;
    }
    // Check if already exists
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index >= 0) {
      _messages[index] = message;
    } else {
      _messages.insert(
        0,
        message.copyWith(
          analysisResult:
              message.analysisResult ?? _analysisHistory[message.id],
        ),
      );
    }
    _updateStats();
    notifyListeners();
  }

  /// Analyze a single message
  Future<SmsAnalysisResult?> analyzeMessage(String messageId) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return null;

    _messages[index] = _messages[index].copyWith(isAnalyzing: true);
    notifyListeners();

    try {
      final message = _messages[index];
      final request = SmsAnalysisRequest(
        content: message.content,
        sender: message.sender,
        timestamp: message.timestamp,
      );

      final result = await _api.analyzeSms(request);
      _recordBackendSuccess();

      _messages[index] = _messages[index].copyWith(
        analysisResult: result,
        isAnalyzing: false,
      );
      _storeAnalysis(message.id, result);
      await _markScanCompleted();

      _updateStats();
      notifyListeners();
      return result;
    } catch (e) {
      _recordBackendFailure(e);
      _messages[index] = _messages[index].copyWith(isAnalyzing: false);
      _error = 'Analysis failed: $e';
      notifyListeners();
      return null;
    }
  }

  /// Analyze all unanalyzed messages via the backend batch endpoint.
  Future<void> analyzeAllMessages() async {
    if (_isAnalyzing) return;

    _isAnalyzing = true;
    _error = null;
    notifyListeners();

    var failedBatches = 0;
    var succeededBatches = 0;
    Object? lastBatchError;

    try {
      final unanalyzed = _messages
          .where((m) => m.analysisResult == null)
          .toList();

      if (unanalyzed.isEmpty) {
        return;
      }

      // Analyze in batches of 10
      const batchSize = 10;
      for (var i = 0; i < unanalyzed.length; i += batchSize) {
        final batch = unanalyzed.skip(i).take(batchSize).toList();
        final requests = batch
            .map((m) => SmsAnalysisRequest(
                  content: m.content,
                  sender: m.sender,
                  timestamp: m.timestamp,
                ))
            .toList();

        try {
          final results = await _api.analyzeSmssBatch(requests);
          succeededBatches++;
          _recordBackendSuccess();

          for (var j = 0; j < batch.length && j < results.length; j++) {
            final msgIndex = _messages.indexWhere((m) => m.id == batch[j].id);
            if (msgIndex >= 0) {
              _messages[msgIndex] = _messages[msgIndex].copyWith(
                analysisResult: results[j],
                isAnalyzing: false,
              );
            }
            _storeAnalysis(batch[j].id, results[j], persist: false);
          }
          notifyListeners();
        } catch (e) {
          // Continue with the next batch, but never hide the failure.
          failedBatches++;
          lastBatchError = e;
          _recordBackendFailure(e);
          debugPrint('SmsProvider: batch analyze failed: $e');
        }
      }

      if (succeededBatches > 0) {
        _persistAnalysisHistory();
        await _markScanCompleted();
      }
      if (failedBatches > 0) {
        _error = succeededBatches == 0
            ? 'Analysis failed: $lastBatchError'
            : 'Some messages could not be analyzed '
                '($failedBatches of ${failedBatches + succeededBatches} '
                'batches failed): $lastBatchError';
      }

      _updateStats();
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  /// Analyze content without saving
  Future<SmsAnalysisResult?> analyzeContent(String content,
      {String? sender}) async {
    try {
      final request = SmsAnalysisRequest(
        content: content,
        sender: sender,
      );
      final result = await _api.analyzeSms(request);
      _recordBackendSuccess();
      notifyListeners();
      return result;
    } catch (e) {
      _recordBackendFailure(e);
      _error = 'Analysis failed: $e';
      notifyListeners();
      return null;
    }
  }

  /// Block a sender
  Future<void> blockSender(String sender) async {
    if (!_blockedSenders.contains(sender)) {
      _blockedSenders.add(sender);
      await _saveBlockedSenders();
      _updateStats();
      notifyListeners();
    }
  }

  /// Unblock a sender
  Future<void> unblockSender(String sender) async {
    if (_blockedSenders.remove(sender)) {
      await _saveBlockedSenders();
      _updateStats();
      notifyListeners();
    }
  }

  /// Check if sender is blocked
  bool isSenderBlocked(String sender) {
    return _blockedSenders.contains(sender);
  }

  /// Update protection settings; persisted and pushed to the native side.
  Future<void> updateProtectionSettings({
    bool? protectionEnabled,
    bool? notifyOnThreat,
    bool? autoBlockDangerous,
  }) async {
    _protectionEnabled = protectionEnabled ?? _protectionEnabled;
    _notifyOnThreat = notifyOnThreat ?? _notifyOnThreat;
    _autoBlockDangerous = autoBlockDangerous ?? _autoBlockDangerous;

    final prefs = _prefs;
    if (prefs != null) {
      await prefs.setBool(_kProtectionEnabledKey, _protectionEnabled);
      await prefs.setBool(_kNotifyOnThreatKey, _notifyOnThreat);
      await prefs.setBool(_kAutoBlockDangerousKey, _autoBlockDangerous);
    }

    await _platform.updateSettings(
      protectionEnabled: _protectionEnabled,
      notifyOnThreat: _notifyOnThreat,
      autoBlockDangerous: _autoBlockDangerous,
    );
    notifyListeners();
  }

  /// Set filter
  void setFilter(SmsFilter newFilter) {
    if (_filter != newFilter) {
      _filter = newFilter;
      notifyListeners();
    }
  }

  /// Set sort
  void setSort(SmsSort newSort) {
    if (_sort != newSort) {
      _sort = newSort;
      notifyListeners();
    }
  }

  /// Select a message for detail view
  void selectMessage(String? messageId) {
    if (messageId == null) {
      _selectedMessage = null;
    } else {
      _selectedMessage = _messages.firstWhere(
        (m) => m.id == messageId,
        orElse: () => _messages.first,
      );
    }
    notifyListeners();
  }

  /// Mark message as read
  void markAsRead(String messageId) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index >= 0) {
      _messages[index] = _messages[index].copyWith(isRead: true);
      notifyListeners();
    }
  }

  /// Report false positive
  Future<void> reportFalsePositive(String messageId) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index >= 0) {
      final message = _messages[index];

      // Report to API
      try {
        await _api.reportSmsFalsePositive(messageId, message.content);
      } catch (e) {
        debugPrint('Failed to report false positive: $e');
      }

      // Clear the analysis result locally (including persisted history so
      // the reported verdict does not keep counting toward stats).
      _messages[index] = SmsMessage(
        id: message.id,
        sender: message.sender,
        content: message.content,
        timestamp: message.timestamp,
        isRead: message.isRead,
      );
      _analysisHistory.remove(messageId);
      _persistAnalysisHistory();
      _updateStats();
      notifyListeners();
    }
  }

  /// Delete a message (from the app's view; persisted so it stays deleted
  /// across inbox reloads).
  void deleteMessage(String messageId) {
    _messages.removeWhere((m) => m.id == messageId);
    if (_selectedMessage?.id == messageId) {
      _selectedMessage = null;
    }
    if (messageId.isNotEmpty) {
      _deletedMessageIds.add(messageId);
      _persistDeletedIds();
    }
    _updateStats();
    notifyListeners();
  }

  /// Clear all messages
  void clearMessages() {
    for (final m in _messages) {
      if (m.id.isNotEmpty) _deletedMessageIds.add(m.id);
    }
    _persistDeletedIds();
    _messages.clear();
    _selectedMessage = null;
    _updateStats();
    notifyListeners();
  }

  /// Get filtered and sorted messages
  List<SmsMessage> _getFilteredMessages() {
    var filtered = _messages.where((m) {
      switch (_filter) {
        case SmsFilter.all:
          return true;
        case SmsFilter.safe:
          return m.analysisResult?.threatLevel == SmsThreatLevel.safe;
        case SmsFilter.suspicious:
          return m.analysisResult?.threatLevel == SmsThreatLevel.suspicious;
        case SmsFilter.dangerous:
          return m.analysisResult?.threatLevel == SmsThreatLevel.dangerous ||
              m.analysisResult?.threatLevel == SmsThreatLevel.critical;
        case SmsFilter.unanalyzed:
          return m.analysisResult == null;
      }
    }).toList();

    // Sort
    switch (_sort) {
      case SmsSort.dateDesc:
        filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        break;
      case SmsSort.dateAsc:
        filtered.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        break;
      case SmsSort.threatLevel:
        filtered.sort((a, b) =>
            (b.analysisResult?.threatLevel.score ?? -1)
                .compareTo(a.analysisResult?.threatLevel.score ?? -1));
        break;
      case SmsSort.sender:
        filtered.sort((a, b) => a.sender.compareTo(b.sender));
        break;
    }

    return filtered;
  }

  /// Update stats. Threat counters come from the persisted analysis history
  /// (every entry is a real backend verdict), so they survive restarts even
  /// when an analyzed message scrolls out of the inbox read window.
  void _updateStats() {
    int critical = 0;
    int high = 0;
    int threats = 0;

    for (final result in _analysisHistory.values) {
      switch (result.threatLevel) {
        case SmsThreatLevel.critical:
          critical++;
          threats++;
          break;
        case SmsThreatLevel.dangerous:
          high++;
          threats++;
          break;
        case SmsThreatLevel.suspicious:
          threats++;
          break;
        case SmsThreatLevel.safe:
          break;
      }
    }

    _stats = SmsStats(
      totalMessages: _messages.length,
      analyzedMessages:
          _messages.where((m) => m.analysisResult != null).length,
      threatsDetected: threats,
      criticalThreats: critical,
      highThreats: high,
      blockedSenders: _blockedSenders.length,
      lastScanAt: _lastScanAt,
    );
  }

  // ==========================================================================
  // Persistence (SharedPreferences - same pattern as settings_provider.dart)
  // ==========================================================================

  /// Load blocked senders from storage, merging additively with anything
  /// already blocked in memory (e.g. blocked from the native side before
  /// persistence loaded).
  Future<void> loadBlockedSenders() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final stored = prefs.getStringList(_kBlockedSendersKey) ?? [];
    final merged = {...stored, ..._blockedSenders};
    _blockedSenders = merged.toList()..sort();
    if (merged.length != stored.length) {
      await _saveBlockedSenders();
    }
  }

  /// Save blocked senders to storage
  Future<void> _saveBlockedSenders() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setStringList(_kBlockedSendersKey, _blockedSenders);
    } catch (e) {
      debugPrint('SmsProvider: failed to persist blocked senders: $e');
    }
  }

  void _loadDeletedIds() {
    final prefs = _prefs;
    if (prefs == null) return;
    _deletedMessageIds =
        (prefs.getStringList(_kDeletedIdsKey) ?? []).toSet();
  }

  void _persistDeletedIds() {
    final prefs = _prefs;
    if (prefs == null) return;
    // Cap the list so it cannot grow unbounded.
    var ids = _deletedMessageIds.toList();
    if (ids.length > 2000) {
      ids = ids.sublist(ids.length - 2000);
      _deletedMessageIds = ids.toSet();
    }
    prefs.setStringList(_kDeletedIdsKey, ids).catchError((Object e) {
      debugPrint('SmsProvider: failed to persist deleted ids: $e');
      return false;
    });
  }

  void _loadSettings() {
    final prefs = _prefs;
    if (prefs == null) return;
    _protectionEnabled = prefs.getBool(_kProtectionEnabledKey) ?? true;
    _notifyOnThreat = prefs.getBool(_kNotifyOnThreatKey) ?? true;
    _autoBlockDangerous = prefs.getBool(_kAutoBlockDangerousKey) ?? false;
  }

  void _loadLastScanAt() {
    final prefs = _prefs;
    if (prefs == null) return;
    final raw = prefs.getString(_kLastScanAtKey);
    if (raw != null) {
      _lastScanAt = DateTime.tryParse(raw);
    }
  }

  Future<void> _markScanCompleted() async {
    _lastScanAt = DateTime.now();
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setString(
          _kLastScanAtKey, _lastScanAt!.toUtc().toIso8601String());
    } catch (e) {
      debugPrint('SmsProvider: failed to persist last scan time: $e');
    }
  }

  /// Load the persisted analysis history (real backend verdicts only).
  void _loadAnalysisHistory() {
    final prefs = _prefs;
    if (prefs == null) return;
    final raw = prefs.getString(_kAnalysisHistoryKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((messageId, entry) {
        try {
          _analysisHistory[messageId] =
              SmsAnalysisResult.fromJson(entry as Map<String, dynamic>);
        } catch (e) {
          debugPrint(
              'SmsProvider: dropping unreadable analysis for $messageId: $e');
        }
      });
    } catch (e) {
      debugPrint('SmsProvider: failed to load analysis history: $e');
    }
  }

  /// Record a backend analysis verdict for a message and (optionally)
  /// persist the history immediately.
  void _storeAnalysis(String messageId, SmsAnalysisResult result,
      {bool persist = true}) {
    if (messageId.isEmpty) return;
    _analysisHistory[messageId] = result;
    if (persist) {
      _persistAnalysisHistory();
    }
  }

  void _persistAnalysisHistory() {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      var entries = _analysisHistory.entries.toList()
        ..sort((a, b) => a.value.analyzedAt.compareTo(b.value.analyzedAt));
      if (entries.length > _maxPersistedAnalyses) {
        final removed =
            entries.sublist(0, entries.length - _maxPersistedAnalyses);
        for (final e in removed) {
          _analysisHistory.remove(e.key);
        }
        entries = entries.sublist(entries.length - _maxPersistedAnalyses);
      }
      final encoded = jsonEncode({
        for (final e in entries) e.key: _analysisSummaryJson(e.value),
      });
      prefs.setString(_kAnalysisHistoryKey, encoded).catchError((Object e) {
        debugPrint('SmsProvider: failed to persist analysis history: $e');
        return false;
      });
    } catch (e) {
      debugPrint('SmsProvider: failed to encode analysis history: $e');
    }
  }

  /// Serialize a result summary in the exact wire shape that
  /// [SmsAnalysisResult.fromJson] consumes, so the persisted history
  /// round-trips through the contract-aligned model. Heavyweight detail
  /// (URLs, pattern matches, sender analysis) is intentionally not persisted;
  /// the detail screen offers re-analysis for that.
  Map<String, dynamic> _analysisSummaryJson(SmsAnalysisResult r) {
    return {
      'id': r.id,
      'message_id': r.messageId,
      'is_threat': r.isThreat,
      'threat_level': r.rawThreatLevel,
      if (r.threatType != null) 'threat_type': r.threatType!.value,
      'confidence': r.riskScore,
      'description': r.description,
      'recommendations': r.recommendations,
      'analyzed_at': r.analyzedAt.toUtc().toIso8601String(),
    };
  }

  /// Load stats from storage and recompute from the persisted history.
  Future<void> loadStats() async {
    _loadLastScanAt();
    _updateStats();
    notifyListeners();
  }

  // ==========================================================================
  // Backend health tracking
  // ==========================================================================

  void _recordBackendSuccess() {
    _lastAnalyzeSucceeded = true;
    _lastAnalyzeError = null;
    _lastBackendSuccessAt = DateTime.now();
  }

  void _recordBackendFailure(Object e) {
    _lastAnalyzeSucceeded = false;
    _lastAnalyzeError = '$e';
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
