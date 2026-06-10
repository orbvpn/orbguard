/// Scam Detection Provider
/// State management for AI-powered scam analysis
///
/// Wire format (source of truth: orbguard.lab):
/// - POST /scam/analyze       -> models.ScamAnalysisResult (scam_analysis.go)
/// - GET  /scam/patterns      -> {version, last_updated, scam_types: [...], risk_indicators: [...]}
/// - POST /scam/report        -> {content, content_type, scam_type, phone_number?, url?, description?}
/// - GET  /scam/phone/{number} -> {phone_number, reputation_score, is_scam,
///                                 is_suspicious, risk_score, scam_type,
///                                 severity, explanation, indicators}

import 'package:flutter/foundation.dart';
import '../services/api/api_interceptors.dart' show ApiError;
import '../services/api/orbguard_api_client.dart';

/// Content type for analysis.
/// `name` matches the backend ContentType constants exactly
/// (text, url, image, voice, phone).
enum ScamContentType {
  text('Text', 'Plain text message or content'),
  url('URL', 'Web link or URL'),
  image('Image', 'Screenshot or image'),
  voice('Voice', 'Voice message or call'),
  phone('Phone', 'Phone number check');

  final String displayName;
  final String description;
  const ScamContentType(this.displayName, this.description);
}

/// Scam type. `apiValue` is the canonical backend ScamType string.
enum ScamType {
  phishing('Phishing', 'Attempt to steal credentials', 'phishing'),
  impersonation('Impersonation', 'Fake identity or brand', 'impersonation'),
  advanceFee('Advance Fee', 'Money requested upfront', 'advance_fee'),
  techSupport('Tech Support', 'Fake technical support', 'tech_support'),
  romance('Romance', 'Fake romantic interest', 'romance'),
  investment('Investment', 'Fraudulent investment scheme', 'investment'),
  lottery('Lottery/Prize', 'Fake winning notification', 'lottery'),
  jobOffer('Job Offer', 'Fraudulent employment', 'job_offer'),
  charity('Charity', 'Fake charitable cause', 'charity_fraud'),
  government('Government', 'Impersonating officials', 'impersonation'),
  unknown('Unknown', 'Unclassified scam type', 'other');

  final String displayName;
  final String description;
  final String apiValue;
  const ScamType(this.displayName, this.description, this.apiValue);
}

/// A single scam indicator as emitted by the backend
/// (models.ScamIndicator: {type, description, confidence, evidence?}).
class ScamIndicator {
  final String type;
  final String description;
  final double confidence;
  final String? evidence;

  const ScamIndicator({
    required this.type,
    required this.description,
    required this.confidence,
    this.evidence,
  });

  factory ScamIndicator.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    final description = json['description'];
    if (type is! String || description is! String) {
      throw const FormatException(
          'Malformed scam indicator: missing "type"/"description"');
    }
    return ScamIndicator(
      type: type,
      description: description,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      evidence: json['evidence'] as String?,
    );
  }

  /// Single-line display form used by list UIs.
  String get display =>
      (evidence != null && evidence!.isNotEmpty) ? '$description — $evidence' : description;
}

/// Analysis result
class ScamAnalysisResult {
  final String id;
  final ScamContentType contentType;
  final String content;
  final bool isScam;

  /// Verdict confidence (0-1) as computed by the backend, or by the local
  /// heuristic when [offline] is true.
  final double confidence;

  /// Risk score (0-1) — how risky the content is.
  final double riskScore;

  /// Backend severity: critical | high | medium | low | none.
  final String? severity;
  final ScamType? scamType;

  /// Typed indicators (backend `indicators` array of ScamIndicator objects).
  final List<ScamIndicator> indicatorDetails;
  final String? explanation;
  final List<String> recommendations;

  /// True when this result was produced by the on-device offline heuristic
  /// because the backend was unreachable.
  final bool offline;
  final DateTime analyzedAt;

  ScamAnalysisResult({
    required this.id,
    required this.contentType,
    required this.content,
    required this.isScam,
    required this.confidence,
    required this.riskScore,
    this.severity,
    this.scamType,
    this.indicatorDetails = const [],
    this.explanation,
    this.recommendations = const [],
    this.offline = false,
    DateTime? analyzedAt,
  }) : analyzedAt = analyzedAt ?? DateTime.now();

  /// Display strings for the indicators.
  List<String> get indicators =>
      indicatorDetails.map((i) => i.display).toList(growable: false);

  String get riskLevel {
    switch (severity) {
      case 'critical':
        return 'Critical';
      case 'high':
        return 'High';
      case 'medium':
        return 'Medium';
      case 'low':
        return 'Low';
      case 'none':
        return 'Safe';
    }
    // Fallback when severity was not provided: thresholds mirror the
    // backend's risk-score severity mapping.
    if (!isScam && riskScore < 0.3) return 'Safe';
    if (riskScore >= 0.9) return 'Critical';
    if (riskScore >= 0.7) return 'High';
    if (riskScore >= 0.5) return 'Medium';
    if (riskScore >= 0.3) return 'Low';
    return isScam ? 'Low' : 'Safe';
  }

  int get riskColor {
    switch (riskLevel) {
      case 'Critical':
        return 0xFFFF1744; // Red
      case 'High':
        return 0xFFFF5722; // Orange
      case 'Medium':
        return 0xFFFF9800; // Amber
      case 'Low':
        return 0xFFFFEB3B; // Yellow
      default:
        return 0xFF4CAF50; // Green
    }
  }
}

/// Phone reputation, matching GET /scam/phone/{number}.
class PhoneReputation {
  final String phoneNumber;

  /// 0-100, higher is better (backend: 100 - risk_score*100).
  final double reputationScore;
  final bool isScam;
  final bool isSuspicious;

  /// 0-1 risk score.
  final double riskScore;
  final ScamType? scamType;
  final String? severity;
  final String? explanation;
  final List<ScamIndicator> indicators;

  const PhoneReputation({
    required this.phoneNumber,
    required this.reputationScore,
    required this.isScam,
    required this.isSuspicious,
    required this.riskScore,
    this.scamType,
    this.severity,
    this.explanation,
    this.indicators = const [],
  });
}

/// Scam pattern, matching one entry of the `scam_types` array from
/// GET /scam/patterns: {type, description, indicators}.
class ScamPattern {
  /// Canonical backend scam type key (e.g. "tech_support").
  final String id;
  final ScamType type;
  final String description;

  /// Risk indicators associated with this scam type.
  final List<String> indicators;

  const ScamPattern({
    required this.id,
    required this.type,
    required this.description,
    this.indicators = const [],
  });

  /// Human-readable name derived from the canonical type key.
  String get name => id
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  /// Indicator chips shown in the UI.
  List<String> get keywords => indicators;

  /// The backend does not track per-pattern detection counts; always 0.
  int get detectionCount => 0;
}

/// Scam Detection Provider
class ScamDetectionProvider extends ChangeNotifier {
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // State
  final List<ScamAnalysisResult> _analysisHistory = [];
  final List<ScamPattern> _patterns = [];
  ScamAnalysisResult? _lastResult;

  bool _isAnalyzing = false;
  bool _isLoadingPatterns = false;
  String? _error;

  // Stats
  int _totalScanned = 0;
  int _scamsDetected = 0;

  // Getters
  List<ScamAnalysisResult> get analysisHistory =>
      List.unmodifiable(_analysisHistory);
  List<ScamPattern> get patterns => List.unmodifiable(_patterns);
  ScamAnalysisResult? get lastResult => _lastResult;
  bool get isAnalyzing => _isAnalyzing;
  bool get isLoadingPatterns => _isLoadingPatterns;
  String? get error => _error;
  int get totalScanned => _totalScanned;
  int get scamsDetected => _scamsDetected;

  /// Detection rate
  double get detectionRate =>
      _totalScanned > 0 ? _scamsDetected / _totalScanned : 0.0;

  /// Recent scams
  List<ScamAnalysisResult> get recentScams =>
      _analysisHistory.where((r) => r.isScam).take(10).toList();

  /// Initialize provider
  Future<void> init() async {
    await loadPatterns();
  }

  /// Load scam patterns.
  ///
  /// Canonical response entry shape (handlers/scam_detection.go GetPatterns,
  /// `scam_types` array): {type, description, indicators}.
  Future<void> loadPatterns() async {
    _isLoadingPatterns = true;
    notifyListeners();

    try {
      final data = await _api.getScamPatterns();
      final parsed = <ScamPattern>[];

      for (final pattern in data) {
        final typeKey = pattern['type'];
        final description = pattern['description'];
        if (typeKey is! String || description is! String) {
          throw const FormatException(
              'Malformed scam pattern entry: missing "type"/"description"');
        }
        final indicatorsRaw = pattern['indicators'];
        parsed.add(ScamPattern(
          id: typeKey,
          type: _parseScamType(typeKey) ?? ScamType.unknown,
          description: description,
          indicators: indicatorsRaw is List
              ? indicatorsRaw.whereType<String>().toList(growable: false)
              : const [],
        ));
      }

      _patterns
        ..clear()
        ..addAll(parsed);
      _error = null;
    } on FormatException catch (e) {
      _error = 'Failed to parse scam patterns: ${e.message}';
    } catch (e) {
      _error = 'Failed to load scam patterns: ${_describeError(e)}';
    }

    _isLoadingPatterns = false;
    notifyListeners();
  }

  /// Analyze content for scams.
  ///
  /// Request fields match the backend handler struct
  /// (content, content_type, url, phone_number, language).
  Future<ScamAnalysisResult?> analyzeContent({
    required ScamContentType type,
    required String content,
    String? language,
  }) async {
    _isAnalyzing = true;
    _error = null;
    notifyListeners();

    try {
      final payload = <String, dynamic>{
        'content': content,
        'content_type': type.name,
      };
      if (language != null && language.isNotEmpty) {
        payload['language'] = language;
      }
      if (type == ScamContentType.url) {
        payload['url'] = content;
      }
      if (type == ScamContentType.phone) {
        payload['phone_number'] = content;
      }

      final response = await _api.analyzeScam(payload);
      final result = _parseAnalysisResponse(type, content, response);
      _recordResult(result);
      return result;
    } on FormatException catch (e) {
      // A 200 response that doesn't parse is a contract violation —
      // surface it, never substitute fake results.
      _error = 'Failed to parse analysis response: ${e.message}';
      _isAnalyzing = false;
      notifyListeners();
      return null;
    } catch (e) {
      if (_isNetworkUnreachable(e)) {
        // Explicit OFFLINE fallback: backend unreachable, run the
        // on-device heuristic and mark the result as offline.
        final result = _localAnalysis(type, content);
        _recordResult(result);
        return result;
      }
      _error = 'Analysis failed: ${_describeError(e)}';
      _isAnalyzing = false;
      notifyListeners();
      return null;
    }
  }

  void _recordResult(ScamAnalysisResult result) {
    _lastResult = result;
    _analysisHistory.insert(0, result);
    _totalScanned++;
    if (result.isScam) _scamsDetected++;
    _isAnalyzing = false;
    notifyListeners();
  }

  /// Parses the live backend models.ScamAnalysisResult JSON.
  ScamAnalysisResult _parseAnalysisResponse(
    ScamContentType type,
    String content,
    Map<String, dynamic> response,
  ) {
    final isScam = response['is_scam'];
    if (isScam is! bool) {
      throw const FormatException(
          'Malformed scam analysis response: missing "is_scam"');
    }

    final riskScore = (response['risk_score'] as num?)?.toDouble();
    final confidence = (response['confidence'] as num?)?.toDouble();
    if (riskScore == null && confidence == null) {
      throw const FormatException(
          'Malformed scam analysis response: missing "risk_score"/"confidence"');
    }

    // indicators is an array of ScamIndicator objects (may be omitted).
    final indicatorsRaw = response['indicators'];
    final indicators = <ScamIndicator>[];
    if (indicatorsRaw != null) {
      if (indicatorsRaw is! List) {
        throw const FormatException(
            'Malformed scam analysis response: "indicators" is not a list');
      }
      for (final item in indicatorsRaw) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException(
              'Malformed scam analysis response: indicator is not an object');
        }
        indicators.add(ScamIndicator.fromJson(item));
      }
    }

    // safety_tips is the canonical list; recommendation is the same items
    // joined with newlines.
    final safetyTipsRaw = response['safety_tips'];
    List<String> recommendations;
    if (safetyTipsRaw is List) {
      recommendations =
          safetyTipsRaw.whereType<String>().toList(growable: false);
    } else {
      final recommendation = response['recommendation'];
      recommendations = (recommendation is String && recommendation.isNotEmpty)
          ? recommendation
              .split('\n')
              .where((line) => line.trim().isNotEmpty)
              .toList(growable: false)
          : const [];
    }

    final explanation = response['explanation'] as String?;

    return ScamAnalysisResult(
      id: (response['id'] as String?) ??
          (response['request_id'] as String?) ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      contentType: type,
      content: content,
      isScam: isScam,
      confidence: confidence ?? riskScore!,
      riskScore: riskScore ?? confidence!,
      severity: response['severity'] as String?,
      scamType: _parseScamType(response['scam_type'] as String?),
      indicatorDetails: indicators,
      explanation:
          (explanation != null && explanation.isNotEmpty) ? explanation : null,
      recommendations: recommendations,
      analyzedAt: DateTime.tryParse(response['analyzed_at']?.toString() ?? ''),
    );
  }

  /// Analyze text
  Future<ScamAnalysisResult?> analyzeText(String text) async {
    return analyzeContent(type: ScamContentType.text, content: text);
  }

  /// Analyze URL
  Future<ScamAnalysisResult?> analyzeUrl(String url) async {
    return analyzeContent(type: ScamContentType.url, content: url);
  }

  /// Check phone number reputation (GET /scam/phone/{number}).
  Future<PhoneReputation?> checkPhone(String phoneNumber) async {
    _isAnalyzing = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.getPhoneReputation(phoneNumber);

      final isScam = response['is_scam'];
      if (isScam is! bool) {
        throw const FormatException(
            'Malformed phone reputation response: missing "is_scam"');
      }
      final reputationScore =
          (response['reputation_score'] as num?)?.toDouble();
      final riskScore = (response['risk_score'] as num?)?.toDouble();
      if (reputationScore == null && riskScore == null) {
        throw const FormatException(
            'Malformed phone reputation response: missing "reputation_score"/"risk_score"');
      }

      final indicatorsRaw = response['indicators'];
      final indicators = <ScamIndicator>[];
      if (indicatorsRaw is List) {
        for (final item in indicatorsRaw) {
          if (item is Map<String, dynamic>) {
            indicators.add(ScamIndicator.fromJson(item));
          }
        }
      }

      final reputation = PhoneReputation(
        phoneNumber: (response['phone_number'] as String?) ?? phoneNumber,
        reputationScore: reputationScore ?? (100 - riskScore! * 100),
        isScam: isScam,
        isSuspicious: response['is_suspicious'] as bool? ?? false,
        riskScore: riskScore ?? (1 - reputationScore! / 100),
        scamType: _parseScamType(response['scam_type'] as String?),
        severity: response['severity'] as String?,
        explanation: response['explanation'] as String?,
        indicators: indicators,
      );

      _isAnalyzing = false;
      notifyListeners();
      return reputation;
    } on FormatException catch (e) {
      _error = 'Failed to parse phone reputation: ${e.message}';
      _isAnalyzing = false;
      notifyListeners();
      return null;
    } catch (e) {
      _error = 'Failed to check phone: ${_describeError(e)}';
      _isAnalyzing = false;
      notifyListeners();
      return null;
    }
  }

  /// Report scam (POST /scam/report).
  Future<bool> reportScam({
    required ScamContentType type,
    required String content,
    ScamType? scamType,
    String? notes,
  }) async {
    try {
      final payload = <String, dynamic>{
        'content': content,
        'content_type': type.name,
      };
      if (scamType != null) {
        payload['scam_type'] = scamType.apiValue;
      }
      if (notes != null && notes.isNotEmpty) {
        payload['description'] = notes;
      }
      if (type == ScamContentType.url) {
        payload['url'] = content;
      }
      if (type == ScamContentType.phone) {
        payload['phone_number'] = content;
      }
      await _api.reportScam(payload);
      return true;
    } catch (e) {
      _error = 'Failed to report: ${_describeError(e)}';
      notifyListeners();
      return false;
    }
  }

  /// Report phone number
  Future<bool> reportPhoneNumber(String phoneNumber, {String? reason}) async {
    try {
      await _api.reportPhoneNumber(phoneNumber, reason ?? 'User reported');
      return true;
    } catch (e) {
      _error = 'Failed to report: ${_describeError(e)}';
      notifyListeners();
      return false;
    }
  }

  /// True only for network-unreachable conditions (timeouts, no
  /// connectivity) — the only case where the offline heuristic is allowed.
  bool _isNetworkUnreachable(Object e) {
    return e is ApiError &&
        e.statusCode == null &&
        (e.code == 'TIMEOUT' || e.code == 'CONNECTION_ERROR');
  }

  String _describeError(Object e) => e is ApiError ? e.message : e.toString();

  /// On-device heuristic, used only as an explicit OFFLINE fallback when the
  /// backend is unreachable. Results are marked with `offline: true`.
  ScamAnalysisResult _localAnalysis(ScamContentType type, String content) {
    final lowerContent = content.toLowerCase();
    final indicators = <ScamIndicator>[];
    double riskScore = 0.0;
    ScamType? detectedType;

    // Urgency keywords
    final urgencyKeywords = [
      'urgent', 'immediately', 'act now', 'limited time',
      'expire', 'suspended', 'verify now', 'confirm immediately'
    ];
    for (final keyword in urgencyKeywords) {
      if (lowerContent.contains(keyword)) {
        indicators.add(ScamIndicator(
          type: 'urgency',
          description: 'Urgency keyword detected',
          confidence: 0.6,
          evidence: keyword,
        ));
        riskScore += 0.15;
      }
    }

    // Money-related
    final moneyKeywords = [
      'wire transfer', 'gift card', 'bitcoin', 'western union',
      'moneygram', 'cash app', 'venmo', 'bank account'
    ];
    for (final keyword in moneyKeywords) {
      if (lowerContent.contains(keyword)) {
        indicators.add(ScamIndicator(
          type: 'payment_method',
          description: 'High-risk payment method mentioned',
          confidence: 0.7,
          evidence: keyword,
        ));
        riskScore += 0.2;
        detectedType = ScamType.advanceFee;
      }
    }

    // Prize/lottery
    if (lowerContent.contains('winner') ||
        lowerContent.contains('prize') ||
        lowerContent.contains('lottery') ||
        lowerContent.contains('million dollars')) {
      indicators.add(const ScamIndicator(
        type: 'prize_lottery',
        description: 'Prize/lottery language detected',
        confidence: 0.7,
      ));
      riskScore += 0.3;
      detectedType = ScamType.lottery;
    }

    // Impersonation
    final impersonationKeywords = [
      'irs', 'social security', 'microsoft support', 'apple support',
      'amazon', 'bank of america', 'wells fargo', 'paypal'
    ];
    for (final keyword in impersonationKeywords) {
      if (lowerContent.contains(keyword)) {
        indicators.add(ScamIndicator(
          type: 'impersonation',
          description: 'Potential brand/authority impersonation',
          confidence: 0.6,
          evidence: keyword,
        ));
        riskScore += 0.2;
        detectedType = ScamType.impersonation;
      }
    }

    // URL checks
    if (type == ScamContentType.url) {
      if (content.contains('bit.ly') ||
          content.contains('tinyurl') ||
          content.contains('t.co')) {
        indicators.add(const ScamIndicator(
          type: 'url_shortener',
          description: 'URL shortener detected',
          confidence: 0.5,
        ));
        riskScore += 0.1;
      }

      // Suspicious TLDs
      final suspiciousTlds = ['.xyz', '.top', '.click', '.loan', '.work'];
      for (final tld in suspiciousTlds) {
        if (content.endsWith(tld)) {
          indicators.add(ScamIndicator(
            type: 'suspicious_tld',
            description: 'Suspicious top-level domain',
            confidence: 0.6,
            evidence: tld,
          ));
          riskScore += 0.15;
        }
      }
    }

    riskScore = riskScore.clamp(0.0, 1.0);
    final isScam = riskScore >= 0.4;
    final String severity;
    if (riskScore >= 0.9) {
      severity = 'critical';
    } else if (riskScore >= 0.7) {
      severity = 'high';
    } else if (riskScore >= 0.5) {
      severity = 'medium';
    } else if (riskScore >= 0.3) {
      severity = 'low';
    } else {
      severity = 'none';
    }

    return ScamAnalysisResult(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      contentType: type,
      content: content,
      isScam: isScam,
      confidence: riskScore,
      riskScore: riskScore,
      severity: severity,
      scamType: isScam ? (detectedType ?? ScamType.unknown) : null,
      indicatorDetails: indicators,
      explanation: isScam
          ? 'Offline analysis: this content matches ${indicators.length} scam indicators'
          : 'Offline analysis: no significant scam indicators detected',
      recommendations: isScam
          ? const [
              'Do not respond to this message',
              'Do not click any links',
              'Do not provide personal information',
              'Report to appropriate authorities',
            ]
          : const [],
      offline: true,
    );
  }

  /// Maps the canonical backend ScamType strings onto the client enum.
  /// Returns null for "none"/empty (not a scam).
  ScamType? _parseScamType(String? type) {
    if (type == null || type.isEmpty || type == 'none') return null;

    switch (type) {
      case 'phishing':
      case 'shipping':
      case 'banking':
      case 'social_media':
      case 'subscription':
        return ScamType.phishing;
      case 'impersonation':
        return ScamType.impersonation;
      case 'advance_fee':
        return ScamType.advanceFee;
      case 'tech_support':
        return ScamType.techSupport;
      case 'romance':
        return ScamType.romance;
      case 'investment':
      case 'crypto':
        return ScamType.investment;
      case 'lottery':
      case 'prize_winning':
        return ScamType.lottery;
      case 'job_offer':
      case 'job_scam':
        return ScamType.jobOffer;
      case 'charity_fraud':
        return ScamType.charity;
      case 'tax_refund':
        return ScamType.government;
      default:
        return ScamType.unknown;
    }
  }

  /// Clear history
  void clearHistory() {
    _analysisHistory.clear();
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
