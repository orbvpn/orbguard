/// QR Provider
/// State management for QR code scanning features
library qr_provider;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api/orbguard_api_client.dart';
import '../models/api/sms_analysis.dart';

/// QR scan history entry
class QrScanEntry {
  final String id;
  final String content;
  final String? contentType;
  final DateTime scannedAt;
  final QrScanResult? result;
  final bool isPending;

  QrScanEntry({
    required this.id,
    required this.content,
    this.contentType,
    required this.scannedAt,
    this.result,
    this.isPending = false,
  });

  QrScanEntry copyWith({
    String? id,
    String? content,
    String? contentType,
    DateTime? scannedAt,
    QrScanResult? result,
    bool? isPending,
  }) {
    return QrScanEntry(
      id: id ?? this.id,
      content: content ?? this.content,
      contentType: contentType ?? this.contentType,
      scannedAt: scannedAt ?? this.scannedAt,
      result: result ?? this.result,
      isPending: isPending ?? this.isPending,
    );
  }

  bool get isSafe => result?.threatLevel == SmsThreatLevel.safe;
  bool get hasThreats => result?.hasThreats ?? false;
}

/// QR protection stats
class QrStats {
  final int totalScanned;
  final int threatsFlagged;
  final int safeScans;
  final int urlsChecked;
  final int phishingBlocked;
  final int malwareBlocked;

  QrStats({
    this.totalScanned = 0,
    this.threatsFlagged = 0,
    this.safeScans = 0,
    this.urlsChecked = 0,
    this.phishingBlocked = 0,
    this.malwareBlocked = 0,
  });
}

/// QR Provider
class QrProvider extends ChangeNotifier {
  static const _prefsHistoryKey = 'qr_scan_history';
  static const _maxPersistedEntries = 100;

  /// Master QR-protection flag persisted by the Settings screen
  /// (ProtectionSettings → SettingsProvider, key `prot_qr`).
  static const _kMasterProtectionKey = 'prot_qr';

  final OrbGuardApiClient _api = OrbGuardApiClient.instance;
  SharedPreferences? _prefs;

  /// Restores persisted scan history as soon as the provider is created
  /// (the QR screen reads the provider without calling [init] itself).
  QrProvider() {
    unawaited(init());
  }

  // State
  final List<QrScanEntry> _history = [];
  QrStats _stats = QrStats();
  QrScanResult? _lastResult;

  bool _isScanning = false;
  bool _isReportingFalsePositive = false;
  String? _error;

  // Getters
  List<QrScanEntry> get history => List.unmodifiable(_history);
  QrStats get stats => _stats;
  QrScanResult? get lastResult => _lastResult;
  bool get isScanning => _isScanning;
  bool get isReportingFalsePositive => _isReportingFalsePositive;
  String? get error => _error;

  /// True when the user turned QR protection off in the app Settings
  /// (`prot_qr`). While set, QR analysis is skipped entirely.
  bool get protectionDisabledByUser => _protectionDisabledByUser;
  bool _protectionDisabledByUser = false;

  /// Reads the persisted Settings flag. Fails open (enabled) when
  /// preferences are unavailable — an unreadable setting is not a user
  /// opt-out.
  Future<bool> _isProtectionEnabledByUser() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('QrProvider: cannot read protection setting: $e');
    }
    final enabled = _prefs?.getBool(_kMasterProtectionKey) ?? true;
    _protectionDisabledByUser = !enabled;
    return enabled;
  }

  /// Recent threats from history
  List<QrScanEntry> get recentThreats => _history
      .where((e) => e.result != null && e.hasThreats)
      .take(10)
      .toList();

  /// Initialize provider
  Future<void> init() async {
    await loadHistory();
    _updateStats();
    notifyListeners();
  }

  /// Scan QR code content
  Future<QrScanResult?> scanQrCode(
    String content, {
    String? contentType,
    double? latitude,
    double? longitude,
  }) async {
    if (content.isEmpty) return null;

    if (!await _isProtectionEnabledByUser()) {
      _error = 'QR protection is disabled in Settings.';
      notifyListeners();
      return null;
    }

    // Create history entry
    final entryId = DateTime.now().millisecondsSinceEpoch.toString();
    final entry = QrScanEntry(
      id: entryId,
      content: content,
      contentType: contentType,
      scannedAt: DateTime.now(),
      isPending: true,
    );
    _history.insert(0, entry);
    _isScanning = true;
    notifyListeners();

    try {
      final request = QrScanRequest(
        content: content,
        contentType: contentType,
        latitude: latitude,
        longitude: longitude,
      );

      final result = await _api.scanQrCode(request);

      // Update history entry
      final index = _history.indexWhere((e) => e.id == entryId);
      if (index >= 0) {
        _history[index] = entry.copyWith(
          result: result,
          contentType: result.contentType,
          isPending: false,
        );
      }

      _lastResult = result;
      _updateStats();
      _isScanning = false;
      await _saveHistory();
      notifyListeners();
      return result;
    } catch (e) {
      // Remove pending entry on error
      _history.removeWhere((e) => e.id == entryId);
      _isScanning = false;
      _error = 'Failed to scan QR code: $e';
      notifyListeners();
      return null;
    }
  }

  /// Clear last result
  void clearLastResult() {
    _lastResult = null;
    notifyListeners();
  }

  /// Clear history
  void clearHistory() {
    _history.clear();
    _updateStats();
    _saveHistory();
    notifyListeners();
  }

  /// Remove single history entry
  void removeFromHistory(String id) {
    _history.removeWhere((e) => e.id == id);
    _updateStats();
    _saveHistory();
    notifyListeners();
  }

  /// Report the last scan (or any scanned content) as a false positive.
  ///
  /// Mediates the QR screen's report button via the live
  /// POST /qr/report-false-positive endpoint.
  Future<bool> reportFalsePositive(String content, {String? reason}) async {
    if (content.isEmpty) return false;

    _isReportingFalsePositive = true;
    _error = null;
    notifyListeners();

    try {
      await _api.reportQrFalsePositive(content, reason: reason);
      _isReportingFalsePositive = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isReportingFalsePositive = false;
      _error = 'Failed to report false positive: $e';
      notifyListeners();
      return false;
    }
  }

  /// Load history from persistent storage (shared_preferences, same pattern
  /// as SettingsProvider).
  Future<void> loadHistory() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('QrProvider: failed to open preferences: $e');
      return;
    }

    final raw = _prefs!.getString(_prefsHistoryKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final restored = <QrScanEntry>[];
      for (final item in decoded) {
        try {
          restored.add(_entryFromJson(Map<String, dynamic>.from(item as Map)));
        } catch (e) {
          // Skip individual corrupt entries rather than dropping everything.
          debugPrint('QrProvider: skipping corrupt history entry: $e');
        }
      }
      _history
        ..clear()
        ..addAll(restored);
    } catch (e) {
      debugPrint('QrProvider: failed to restore scan history: $e');
    }
  }

  /// Save history to persistent storage.
  Future<void> _saveHistory() async {
    final prefs = _prefs;
    if (prefs == null) return;

    try {
      final payload = _history
          .where((e) => !e.isPending)
          .take(_maxPersistedEntries)
          .map(_entryToJson)
          .toList();
      await prefs.setString(_prefsHistoryKey, jsonEncode(payload));
    } catch (e) {
      debugPrint('QrProvider: failed to persist scan history: $e');
    }
  }

  Map<String, dynamic> _entryToJson(QrScanEntry entry) => {
        'id': entry.id,
        'content': entry.content,
        'content_type': entry.contentType,
        'scanned_at': entry.scannedAt.toIso8601String(),
        if (entry.result != null) 'result': _resultToJson(entry.result!),
      };

  QrScanEntry _entryFromJson(Map<String, dynamic> json) {
    final resultJson = json['result'];
    return QrScanEntry(
      id: json['id'] as String,
      content: json['content'] as String,
      contentType: json['content_type'] as String?,
      scannedAt: DateTime.parse(json['scanned_at'] as String),
      result: resultJson != null
          ? QrScanResult.fromJson(Map<String, dynamic>.from(resultJson as Map))
          : null,
    );
  }

  /// Serialize a [QrScanResult] back into the exact backend wire shape so
  /// [QrScanResult.fromJson] can round-trip it on restore.
  Map<String, dynamic> _resultToJson(QrScanResult result) => {
        'id': result.id,
        'raw_content': result.rawContent,
        'content_type': result.contentType,
        'threat_level': result.qrThreatLevel.value,
        'threat_score': result.threatScore,
        'threats': result.threats
            .map((t) => {
                  'type': t.type,
                  'severity': t.severity.value,
                  'description': t.description,
                  if (t.evidence != null) 'evidence': t.evidence,
                  if (t.threatIntelMatch != null)
                    'threat_intel_match': {
                      'indicator_id': t.threatIntelMatch!.indicatorId,
                      'indicator_type': t.threatIntelMatch!.indicatorType,
                      'campaign': t.threatIntelMatch!.campaign,
                      'threat_actor': t.threatIntelMatch!.threatActor,
                      'confidence': t.threatIntelMatch!.confidence,
                    },
                })
            .toList(),
        if (result.parsedContent != null)
          'parsed_content': result.parsedContent,
        'is_safe': result.isSafe,
        'should_block': result.shouldBlock,
        'warnings': result.warnings,
        'recommendations': result.recommendations,
        'scanned_at': result.scannedAt.toIso8601String(),
        if (result.analysisDuration != null)
          'analysis_duration': result.analysisDuration!.inMicroseconds * 1000,
      };

  /// Update stats
  void _updateStats() {
    int threats = 0;
    int safe = 0;
    int urls = 0;
    int phishing = 0;
    int malware = 0;

    for (final entry in _history) {
      if (entry.result == null) continue;

      if (entry.result!.threatLevel == SmsThreatLevel.safe) {
        safe++;
      } else if (entry.hasThreats) {
        threats++;
        for (final threat in entry.result!.threats) {
          if (threat.type == 'phishing') phishing++;
          if (threat.type == 'malware') malware++;
        }
      }

      if (entry.result!.contentType == 'url') {
        urls++;
      }
    }

    _stats = QrStats(
      totalScanned: _history.where((e) => e.result != null).length,
      threatsFlagged: threats,
      safeScans: safe,
      urlsChecked: urls,
      phishingBlocked: phishing,
      malwareBlocked: malware,
    );
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Get content type display name
  static String getContentTypeDisplayName(String contentType) {
    switch (contentType.toLowerCase()) {
      case 'url':
        return 'URL';
      case 'text':
        return 'Plain Text';
      case 'email':
        return 'Email';
      case 'phone':
        return 'Phone Number';
      case 'sms':
        return 'SMS';
      case 'wifi':
        return 'Wi-Fi Network';
      case 'vcard':
        return 'Contact (vCard)';
      case 'geo':
        return 'Location';
      case 'event':
        return 'Calendar Event';
      case 'crypto':
        return 'Cryptocurrency';
      case 'app_link':
        return 'App Link';
      default:
        return 'Unknown';
    }
  }

  /// Get content type icon
  static String getContentTypeIcon(String contentType) {
    switch (contentType.toLowerCase()) {
      case 'url':
        return 'link';
      case 'text':
        return 'text_fields';
      case 'email':
        return 'email';
      case 'phone':
        return 'phone';
      case 'sms':
        return 'sms';
      case 'wifi':
        return 'wifi';
      case 'vcard':
        return 'contact_page';
      case 'geo':
        return 'location_on';
      case 'event':
        return 'event';
      case 'crypto':
        return 'currency_bitcoin';
      case 'app_link':
        return 'apps';
      default:
        return 'qr_code';
    }
  }
}
