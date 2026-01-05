/// SMS Provider
/// State management for SMS protection features
library sms_provider;

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/api/orbguard_api_client.dart';
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

/// SMS statistics
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

/// SMS Provider for state management
class SmsProvider extends ChangeNotifier {
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // State
  List<SmsMessage> _messages = [];
  List<String> _blockedSenders = [];
  SmsStats _stats = SmsStats();
  SmsFilter _filter = SmsFilter.all;
  SmsSort _sort = SmsSort.dateDesc;

  bool _isLoading = false;
  bool _isAnalyzing = false;
  String? _error;

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

  /// Get count of unanalyzed messages
  int get unanalyzedCount =>
      _messages.where((m) => m.analysisResult == null).length;

  /// Get count of threats
  int get threatCount =>
      _messages.where((m) => m.hasThreats).length;

  /// Initialize provider
  Future<void> init() async {
    await loadBlockedSenders();
    await loadStats();
  }

  /// Load SMS messages from native code
  Future<void> loadMessages() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // TODO: Load messages from native platform channel
      // For now, we'll work with manually added messages
      _updateStats();
    } catch (e) {
      _error = 'Failed to load messages: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add a message (from platform channel or manual input)
  void addMessage(SmsMessage message) {
    // Check if already exists
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index >= 0) {
      _messages[index] = message;
    } else {
      _messages.insert(0, message);
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

      _messages[index] = _messages[index].copyWith(
        analysisResult: result,
        isAnalyzing: false,
      );

      _updateStats();
      notifyListeners();
      return result;
    } catch (e) {
      _messages[index] = _messages[index].copyWith(isAnalyzing: false);
      notifyListeners();
      _error = 'Analysis failed: $e';
      return null;
    }
  }

  /// Analyze all unanalyzed messages
  Future<void> analyzeAllMessages() async {
    if (_isAnalyzing) return;

    _isAnalyzing = true;
    _error = null;
    notifyListeners();

    try {
      final unanalyzed = _messages
          .where((m) => m.analysisResult == null)
          .toList();

      if (unanalyzed.isEmpty) {
        _isAnalyzing = false;
        notifyListeners();
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

          for (var j = 0; j < batch.length && j < results.length; j++) {
            final msgIndex = _messages.indexWhere((m) => m.id == batch[j].id);
            if (msgIndex >= 0) {
              _messages[msgIndex] = _messages[msgIndex].copyWith(
                analysisResult: results[j],
                isAnalyzing: false,
              );
            }
          }
          notifyListeners();
        } catch (e) {
          // Continue with next batch even if this one fails
        }
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
      return await _api.analyzeSms(request);
    } catch (e) {
      _error = 'Analysis failed: $e';
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
    // TODO: Implement API call to report false positive
    // For now, just clear the analysis result
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index >= 0) {
      _messages[index] = _messages[index].copyWith(
        analysisResult: null,
      );
      _updateStats();
      notifyListeners();
    }
  }

  /// Delete a message
  void deleteMessage(String messageId) {
    _messages.removeWhere((m) => m.id == messageId);
    if (_selectedMessage?.id == messageId) {
      _selectedMessage = null;
    }
    _updateStats();
    notifyListeners();
  }

  /// Clear all messages
  void clearMessages() {
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

  /// Update stats
  void _updateStats() {
    int critical = 0;
    int high = 0;
    int threats = 0;

    for (final msg in _messages) {
      if (msg.analysisResult != null) {
        if (msg.analysisResult!.threatLevel == SmsThreatLevel.critical) {
          critical++;
          threats++;
        } else if (msg.analysisResult!.threatLevel == SmsThreatLevel.dangerous) {
          high++;
          threats++;
        } else if (msg.analysisResult!.threatLevel == SmsThreatLevel.suspicious) {
          threats++;
        }
      }
    }

    _stats = SmsStats(
      totalMessages: _messages.length,
      analyzedMessages: _messages.where((m) => m.analysisResult != null).length,
      threatsDetected: threats,
      criticalThreats: critical,
      highThreats: high,
      blockedSenders: _blockedSenders.length,
      lastScanAt: DateTime.now(),
    );
  }

  /// Load blocked senders from storage
  Future<void> loadBlockedSenders() async {
    // TODO: Load from persistent storage
    _blockedSenders = [];
  }

  /// Save blocked senders to storage
  Future<void> _saveBlockedSenders() async {
    // TODO: Save to persistent storage
  }

  /// Load stats from storage
  Future<void> loadStats() async {
    // TODO: Load from persistent storage
    _updateStats();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

}
