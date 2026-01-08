/// Scam Detection Provider
/// State management for AI-powered scam analysis

import 'package:flutter/foundation.dart';
import '../services/api/orbguard_api_client.dart';

/// Content type for analysis
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

/// Scam type
enum ScamType {
  phishing('Phishing', 'Attempt to steal credentials'),
  impersonation('Impersonation', 'Fake identity or brand'),
  advanceFee('Advance Fee', 'Money requested upfront'),
  techSupport('Tech Support', 'Fake technical support'),
  romance('Romance', 'Fake romantic interest'),
  investment('Investment', 'Fraudulent investment scheme'),
  lottery('Lottery/Prize', 'Fake winning notification'),
  jobOffer('Job Offer', 'Fraudulent employment'),
  charity('Charity', 'Fake charitable cause'),
  government('Government', 'Impersonating officials'),
  unknown('Unknown', 'Unclassified scam type');

  final String displayName;
  final String description;
  const ScamType(this.displayName, this.description);
}

/// Analysis result
class ScamAnalysisResult {
  final String id;
  final ScamContentType contentType;
  final String content;
  final bool isScam;
  final double confidence;
  final ScamType? scamType;
  final List<String> indicators;
  final String? explanation;
  final List<String> recommendations;
  final DateTime analyzedAt;

  ScamAnalysisResult({
    required this.id,
    required this.contentType,
    required this.content,
    required this.isScam,
    required this.confidence,
    this.scamType,
    this.indicators = const [],
    this.explanation,
    this.recommendations = const [],
    DateTime? analyzedAt,
  }) : analyzedAt = analyzedAt ?? DateTime.now();

  String get riskLevel {
    if (!isScam) return 'Safe';
    if (confidence >= 0.9) return 'Critical';
    if (confidence >= 0.7) return 'High';
    if (confidence >= 0.5) return 'Medium';
    return 'Low';
  }

  int get riskColor {
    if (!isScam) return 0xFF4CAF50; // Green
    if (confidence >= 0.9) return 0xFFFF1744; // Red
    if (confidence >= 0.7) return 0xFFFF5722; // Orange
    if (confidence >= 0.5) return 0xFFFF9800; // Amber
    return 0xFFFFEB3B; // Yellow
  }
}

/// Phone reputation
class PhoneReputation {
  final String phoneNumber;
  final bool isSpam;
  final bool isScam;
  final int reportCount;
  final String? carrier;
  final String? location;
  final List<String> tags;
  final double riskScore;

  PhoneReputation({
    required this.phoneNumber,
    this.isSpam = false,
    this.isScam = false,
    this.reportCount = 0,
    this.carrier,
    this.location,
    this.tags = const [],
    this.riskScore = 0.0,
  });
}

/// Scam pattern
class ScamPattern {
  final String id;
  final String name;
  final String description;
  final ScamType type;
  final List<String> keywords;
  final int detectionCount;

  ScamPattern({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    this.keywords = const [],
    this.detectionCount = 0,
  });
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

  /// Load scam patterns
  Future<void> loadPatterns() async {
    _isLoadingPatterns = true;
    notifyListeners();

    try {
      final data = await _api.getScamPatterns();
      _patterns.clear();

      for (final pattern in data) {
        _patterns.add(ScamPattern(
          id: pattern['id'],
          name: pattern['name'],
          description: pattern['description'],
          type: _parseScamType(pattern['type']),
          keywords: List<String>.from(pattern['keywords'] ?? []),
          detectionCount: pattern['detection_count'] ?? 0,
        ));
      }
    } catch (e) {
      // Load default patterns
      _patterns.addAll(_getDefaultPatterns());
    }

    _isLoadingPatterns = false;
    notifyListeners();
  }

  /// Analyze content for scams
  Future<ScamAnalysisResult?> analyzeContent({
    required ScamContentType type,
    required String content,
    String? language,
  }) async {
    _isAnalyzing = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.analyzeScam({
        'content_type': type.name,
        'content': content,
        'language': language,
      });

      final result = ScamAnalysisResult(
        id: response['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        contentType: type,
        content: content,
        isScam: response['is_scam'] ?? false,
        confidence: (response['confidence'] ?? 0.0).toDouble(),
        scamType: _parseScamType(response['scam_type']),
        indicators: List<String>.from(response['indicators'] ?? []),
        explanation: response['explanation'],
        recommendations: List<String>.from(response['recommendations'] ?? []),
      );

      _lastResult = result;
      _analysisHistory.insert(0, result);
      _totalScanned++;
      if (result.isScam) _scamsDetected++;

      _isAnalyzing = false;
      notifyListeners();
      return result;
    } catch (e) {
      // Run local analysis as fallback
      final result = _localAnalysis(type, content);
      _lastResult = result;
      _analysisHistory.insert(0, result);
      _totalScanned++;
      if (result.isScam) _scamsDetected++;

      _isAnalyzing = false;
      notifyListeners();
      return result;
    }
  }

  /// Analyze text
  Future<ScamAnalysisResult?> analyzeText(String text) async {
    return analyzeContent(type: ScamContentType.text, content: text);
  }

  /// Analyze URL
  Future<ScamAnalysisResult?> analyzeUrl(String url) async {
    return analyzeContent(type: ScamContentType.url, content: url);
  }

  /// Check phone number
  Future<PhoneReputation?> checkPhone(String phoneNumber) async {
    _isAnalyzing = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.getPhoneReputation(phoneNumber);

      final reputation = PhoneReputation(
        phoneNumber: phoneNumber,
        isSpam: response['is_spam'] ?? false,
        isScam: response['is_scam'] ?? false,
        reportCount: response['report_count'] ?? 0,
        carrier: response['carrier'],
        location: response['location'],
        tags: List<String>.from(response['tags'] ?? []),
        riskScore: (response['risk_score'] ?? 0.0).toDouble(),
      );

      _isAnalyzing = false;
      notifyListeners();
      return reputation;
    } catch (e) {
      _error = 'Failed to check phone: $e';
      _isAnalyzing = false;
      notifyListeners();
      return null;
    }
  }

  /// Report scam
  Future<bool> reportScam({
    required ScamContentType type,
    required String content,
    ScamType? scamType,
    String? notes,
  }) async {
    try {
      await _api.reportScam({
        'content_type': type.name,
        'content': content,
        'scam_type': scamType?.name,
        'notes': notes,
      });
      return true;
    } catch (e) {
      _error = 'Failed to report: $e';
      notifyListeners();
      return false;
    }
  }

  /// Report phone number
  Future<bool> reportPhoneNumber(String phoneNumber, {String? reason}) async {
    try {
      await _api.reportPhoneNumber(phoneNumber, reason: reason);
      return true;
    } catch (e) {
      _error = 'Failed to report: $e';
      notifyListeners();
      return false;
    }
  }

  /// Local analysis fallback
  ScamAnalysisResult _localAnalysis(ScamContentType type, String content) {
    final lowerContent = content.toLowerCase();
    final indicators = <String>[];
    double confidence = 0.0;
    ScamType? detectedType;

    // Urgency keywords
    final urgencyKeywords = [
      'urgent', 'immediately', 'act now', 'limited time',
      'expire', 'suspended', 'verify now', 'confirm immediately'
    ];
    for (final keyword in urgencyKeywords) {
      if (lowerContent.contains(keyword)) {
        indicators.add('Urgency: "$keyword"');
        confidence += 0.15;
      }
    }

    // Money-related
    final moneyKeywords = [
      'wire transfer', 'gift card', 'bitcoin', 'western union',
      'moneygram', 'cash app', 'venmo', 'bank account'
    ];
    for (final keyword in moneyKeywords) {
      if (lowerContent.contains(keyword)) {
        indicators.add('Payment method: "$keyword"');
        confidence += 0.2;
        detectedType = ScamType.advanceFee;
      }
    }

    // Prize/lottery
    if (lowerContent.contains('winner') ||
        lowerContent.contains('prize') ||
        lowerContent.contains('lottery') ||
        lowerContent.contains('million dollars')) {
      indicators.add('Prize/lottery language detected');
      confidence += 0.3;
      detectedType = ScamType.lottery;
    }

    // Impersonation
    final impersonationKeywords = [
      'irs', 'social security', 'microsoft support', 'apple support',
      'amazon', 'bank of america', 'wells fargo', 'paypal'
    ];
    for (final keyword in impersonationKeywords) {
      if (lowerContent.contains(keyword)) {
        indicators.add('Potential impersonation: "$keyword"');
        confidence += 0.2;
        detectedType = ScamType.impersonation;
      }
    }

    // URL checks
    if (type == ScamContentType.url) {
      if (content.contains('bit.ly') ||
          content.contains('tinyurl') ||
          content.contains('t.co')) {
        indicators.add('URL shortener detected');
        confidence += 0.1;
      }

      // Suspicious TLDs
      final suspiciousTlds = ['.xyz', '.top', '.click', '.loan', '.work'];
      for (final tld in suspiciousTlds) {
        if (content.endsWith(tld)) {
          indicators.add('Suspicious TLD: $tld');
          confidence += 0.15;
        }
      }
    }

    confidence = confidence.clamp(0.0, 1.0);
    final isScam = confidence >= 0.4;

    return ScamAnalysisResult(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      contentType: type,
      content: content,
      isScam: isScam,
      confidence: confidence,
      scamType: isScam ? (detectedType ?? ScamType.unknown) : null,
      indicators: indicators,
      explanation: isScam
          ? 'This content matches ${indicators.length} scam indicators'
          : 'No significant scam indicators detected',
      recommendations: isScam
          ? [
              'Do not respond to this message',
              'Do not click any links',
              'Do not provide personal information',
              'Report to appropriate authorities',
            ]
          : [],
    );
  }

  ScamType _parseScamType(String? type) {
    if (type == null) return ScamType.unknown;

    for (final scamType in ScamType.values) {
      if (scamType.name == type) return scamType;
    }
    return ScamType.unknown;
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

  /// Default patterns
  List<ScamPattern> _getDefaultPatterns() {
    return [
      ScamPattern(
        id: '1',
        name: 'IRS Impersonation',
        description: 'Scammers pretending to be IRS agents',
        type: ScamType.government,
        keywords: ['irs', 'tax', 'refund', 'audit', 'arrest warrant'],
        detectionCount: 15420,
      ),
      ScamPattern(
        id: '2',
        name: 'Tech Support Scam',
        description: 'Fake technical support calls',
        type: ScamType.techSupport,
        keywords: ['microsoft', 'apple', 'virus', 'infected', 'remote access'],
        detectionCount: 23150,
      ),
      ScamPattern(
        id: '3',
        name: 'Prize Winner',
        description: 'Fake lottery or prize notifications',
        type: ScamType.lottery,
        keywords: ['winner', 'prize', 'lottery', 'claim', 'million'],
        detectionCount: 18920,
      ),
      ScamPattern(
        id: '4',
        name: 'Package Delivery',
        description: 'Fake delivery notifications',
        type: ScamType.phishing,
        keywords: ['ups', 'fedex', 'usps', 'delivery', 'package', 'tracking'],
        detectionCount: 31240,
      ),
      ScamPattern(
        id: '5',
        name: 'Bank Alert',
        description: 'Fake bank security alerts',
        type: ScamType.phishing,
        keywords: ['suspended', 'verify', 'unusual activity', 'account locked'],
        detectionCount: 27830,
      ),
    ];
  }
}
