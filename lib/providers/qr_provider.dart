/// QR Provider
/// State management for QR code scanning features
library qr_provider;

import 'package:flutter/foundation.dart';

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
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // State
  final List<QrScanEntry> _history = [];
  QrStats _stats = QrStats();
  QrScanResult? _lastResult;

  bool _isScanning = false;
  String? _error;

  // Getters
  List<QrScanEntry> get history => List.unmodifiable(_history);
  QrStats get stats => _stats;
  QrScanResult? get lastResult => _lastResult;
  bool get isScanning => _isScanning;
  String? get error => _error;

  /// Recent threats from history
  List<QrScanEntry> get recentThreats => _history
      .where((e) => e.result != null && e.hasThreats)
      .take(10)
      .toList();

  /// Initialize provider
  Future<void> init() async {
    await loadHistory();
    _updateStats();
  }

  /// Scan QR code content
  Future<QrScanResult?> scanQrCode(
    String content, {
    String? contentType,
    double? latitude,
    double? longitude,
  }) async {
    if (content.isEmpty) return null;

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

  /// Load history from storage
  Future<void> loadHistory() async {
    // TODO: Load from persistent storage
  }

  /// Save history to storage
  Future<void> _saveHistory() async {
    // TODO: Save to persistent storage
  }

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
