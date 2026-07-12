// SMS Analysis Models
// Models for SMS/smishing analysis from OrbGuard Lab API.
//
// Wire formats in this file mirror the live backend handlers:
// - orbguard.lab/internal/api/handlers/sms.go (+ models/sms.go)
// - orbguard.lab/internal/api/handlers/qr_security.go (+ models/qr_security.go)
// - orbguard.lab/internal/api/handlers/darkweb.go (+ models/darkweb.go)

import 'threat_indicator.dart';

/// Threat level for SMS messages.
///
/// The backend emits `threat_level` as one of:
/// `safe`, `low`, `medium`, `high`, `critical`.
/// These are mapped onto the UI levels below (low/medium -> suspicious,
/// high -> dangerous). Unknown values throw a [FormatException] instead of
/// silently defaulting to safe.
enum SmsThreatLevel {
  safe('safe', 0),
  suspicious('suspicious', 1),
  dangerous('dangerous', 2),
  critical('critical', 3);

  final String value;
  final int score;
  const SmsThreatLevel(this.value, this.score);

  static SmsThreatLevel fromString(String value) {
    switch (value) {
      case 'safe':
        return SmsThreatLevel.safe;
      case 'low':
      case 'medium':
      case 'suspicious':
        return SmsThreatLevel.suspicious;
      case 'high':
      case 'dangerous':
        return SmsThreatLevel.dangerous;
      case 'critical':
        return SmsThreatLevel.critical;
      default:
        throw FormatException('Unknown SMS threat level: "$value"');
    }
  }

  /// Get color for UI display
  int get color {
    switch (this) {
      case SmsThreatLevel.safe:
        return 0xFF4CAF50; // Green
      case SmsThreatLevel.suspicious:
        return 0xFFFFC107; // Amber
      case SmsThreatLevel.dangerous:
        return 0xFFFF9800; // Orange
      case SmsThreatLevel.critical:
        return 0xFFF44336; // Red
    }
  }

  String get displayName {
    switch (this) {
      case SmsThreatLevel.safe:
        return 'Safe';
      case SmsThreatLevel.suspicious:
        return 'Suspicious';
      case SmsThreatLevel.dangerous:
        return 'Dangerous';
      case SmsThreatLevel.critical:
        return 'Critical';
    }
  }
}

/// Types of SMS threats detected.
///
/// The backend emits `threat_type` as one of: `phishing`, `smishing`,
/// `malware`, `scam`, `spam`, `impersonation`, `executive_impersonation`,
/// `bank_fraud`, `delivery_scam`, `tech_support_scam`, `premium_rate`,
/// `suspicious_link` (or empty when not a threat). [fromString] maps each
/// of those onto the closest UI category.
enum SmsThreatType {
  phishing('phishing'),
  smishing('smishing'),
  malwareLink('malware'),
  scam('scam'),
  spam('spam'),
  executiveImpersonation('executive_impersonation'),
  bankingFraud('bank_fraud'),
  packageDeliveryScam('delivery_scam'),
  otpFraud('otp_fraud'),
  premiumRate('premium_rate'),
  unknown('unknown');

  final String value;
  const SmsThreatType(this.value);

  static SmsThreatType fromString(String value) {
    switch (value) {
      case 'phishing':
        return SmsThreatType.phishing;
      case 'smishing':
      case 'suspicious_link':
        return SmsThreatType.smishing;
      case 'malware':
      case 'malware_link':
        return SmsThreatType.malwareLink;
      case 'scam':
      case 'tech_support_scam':
        return SmsThreatType.scam;
      case 'spam':
        return SmsThreatType.spam;
      case 'impersonation':
      case 'executive_impersonation':
        return SmsThreatType.executiveImpersonation;
      case 'bank_fraud':
      case 'banking_fraud':
        return SmsThreatType.bankingFraud;
      case 'delivery_scam':
      case 'package_delivery_scam':
        return SmsThreatType.packageDeliveryScam;
      case 'otp_fraud':
        return SmsThreatType.otpFraud;
      case 'premium_rate':
        return SmsThreatType.premiumRate;
      default:
        return SmsThreatType.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case SmsThreatType.phishing:
        return 'Phishing';
      case SmsThreatType.smishing:
        return 'SMS Phishing';
      case SmsThreatType.malwareLink:
        return 'Malware Link';
      case SmsThreatType.scam:
        return 'Scam';
      case SmsThreatType.spam:
        return 'Spam';
      case SmsThreatType.executiveImpersonation:
        return 'Executive Impersonation';
      case SmsThreatType.bankingFraud:
        return 'Banking Fraud';
      case SmsThreatType.packageDeliveryScam:
        return 'Package Delivery Scam';
      case SmsThreatType.otpFraud:
        return 'OTP Fraud';
      case SmsThreatType.premiumRate:
        return 'Premium Rate';
      case SmsThreatType.unknown:
        return 'Unknown';
    }
  }
}

/// Suspicious intent types
enum SuspiciousIntent {
  urgency('urgency'),
  fear('fear'),
  reward('reward'),
  curiosity('curiosity'),
  authority('authority'),
  social('social'),
  greed('greed'),
  none('none');

  final String value;
  const SuspiciousIntent(this.value);

  static SuspiciousIntent fromString(String value) {
    return SuspiciousIntent.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SuspiciousIntent.none,
    );
  }
}

/// Request to analyze SMS.
///
/// The backend (`POST /sms/analyze`) reads `body`, `sender`, `timestamp`
/// and `device_id`.
class SmsAnalysisRequest {
  final String content;
  final String? sender;
  final DateTime? timestamp;
  final String? deviceId;

  SmsAnalysisRequest({
    required this.content,
    this.sender,
    this.timestamp,
    this.deviceId,
  });

  Map<String, dynamic> toJson() {
    return {
      // Backend field is `body` (handlers/sms.go AnalyzeRequest).
      'body': content,
      if (sender != null) 'sender': sender,
      if (timestamp != null) 'timestamp': timestamp!.toUtc().toIso8601String(),
      if (deviceId != null) 'device_id': deviceId,
    };
  }
}

/// NLP intent analysis of an SMS message
/// (backend `intent_analysis` object).
class SmsIntentAnalysis {
  final String primaryIntent;
  final double urgency;
  final double fearFactor;
  final double rewardPromise;
  final bool actionRequired;
  final bool personalData;
  final bool financialData;
  final List<String> suspiciousFlags;

  SmsIntentAnalysis({
    required this.primaryIntent,
    required this.urgency,
    required this.fearFactor,
    required this.rewardPromise,
    required this.actionRequired,
    required this.personalData,
    required this.financialData,
    required this.suspiciousFlags,
  });

  factory SmsIntentAnalysis.fromJson(Map<String, dynamic> json) {
    return SmsIntentAnalysis(
      primaryIntent: json['primary_intent'] as String? ?? '',
      urgency: (json['urgency'] as num?)?.toDouble() ?? 0.0,
      fearFactor: (json['fear_factor'] as num?)?.toDouble() ?? 0.0,
      rewardPromise: (json['reward_promise'] as num?)?.toDouble() ?? 0.0,
      actionRequired: json['action_required'] as bool? ?? false,
      personalData: json['personal_data'] as bool? ?? false,
      financialData: json['financial_data'] as bool? ?? false,
      suspiciousFlags:
          (json['suspicious_flags'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  /// Intents detected by the backend, derived from the scored factors.
  List<SuspiciousIntent> get detectedIntents {
    final intents = <SuspiciousIntent>[];
    if (urgency > 0) intents.add(SuspiciousIntent.urgency);
    if (fearFactor > 0) intents.add(SuspiciousIntent.fear);
    if (rewardPromise > 0) intents.add(SuspiciousIntent.reward);
    if (personalData || financialData) intents.add(SuspiciousIntent.greed);
    return intents;
  }
}

/// A matched suspicious pattern in an SMS
/// (backend `pattern_matches[]` entry).
class SmsPatternMatch {
  final String patternName;
  final String patternType;
  final String matchedText;
  final double confidence;
  final String description;

  SmsPatternMatch({
    required this.patternName,
    required this.patternType,
    required this.matchedText,
    required this.confidence,
    required this.description,
  });

  factory SmsPatternMatch.fromJson(Map<String, dynamic> json) {
    return SmsPatternMatch(
      patternName: json['pattern_name'] as String? ?? '',
      patternType: json['pattern_type'] as String? ?? '',
      matchedText: json['matched_text'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String? ?? '',
    );
  }
}

/// Result of SMS analysis (`POST /sms/analyze` response).
///
/// Live backend shape (models.SMSAnalysisResult):
/// `id`, `message_id`, `is_threat`, `threat_level`, `threat_type`,
/// `confidence`, `description`, `recommendations[]`, `urls[]`,
/// `phone_numbers[]`, `emails[]`, `pattern_matches[]`, `sender_analysis`,
/// `intent_analysis`, `analyzed_at`.
class SmsAnalysisResult {
  final String id;
  final String messageId;
  final String content;
  final bool isThreat;
  final SmsThreatLevel threatLevel;

  /// Raw backend threat level (`safe`/`low`/`medium`/`high`/`critical`).
  final String rawThreatLevel;
  final SmsThreatType? threatType;

  /// Backend confidence score, 0.0 - 1.0.
  final double riskScore;
  final String description;
  final List<String> recommendations;
  final List<SmsThreat> threats;
  final List<ExtractedUrl> extractedUrls;
  final List<String> phoneNumbers;
  final List<String> emails;
  final List<SmsPatternMatch> patternMatches;
  final SenderAnalysis? senderAnalysis;
  final SmsIntentAnalysis? intentAnalysis;
  final DateTime analyzedAt;

  SmsAnalysisResult({
    required this.id,
    required this.messageId,
    required this.content,
    required this.isThreat,
    required this.threatLevel,
    required this.rawThreatLevel,
    required this.threatType,
    required this.riskScore,
    required this.description,
    required this.recommendations,
    required this.threats,
    required this.extractedUrls,
    required this.phoneNumbers,
    required this.emails,
    required this.patternMatches,
    required this.senderAnalysis,
    required this.intentAnalysis,
    required this.analyzedAt,
  });

  factory SmsAnalysisResult.fromJson(Map<String, dynamic> json) {
    final rawLevel = json['threat_level'];
    if (rawLevel is! String) {
      throw const FormatException(
          'SMS analysis response is missing "threat_level"');
    }
    final analyzedAtRaw = json['analyzed_at'];
    if (analyzedAtRaw is! String) {
      throw const FormatException(
          'SMS analysis response is missing "analyzed_at"');
    }
    final isThreat = json['is_threat'];
    if (isThreat is! bool) {
      throw const FormatException(
          'SMS analysis response is missing "is_threat"');
    }

    final threatLevel = SmsThreatLevel.fromString(rawLevel);
    final confidence =
        ((json['confidence'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0);
    final description = json['description'] as String? ?? '';
    final rawType = json['threat_type'] as String? ?? '';
    final threatType =
        rawType.isEmpty ? null : SmsThreatType.fromString(rawType);

    // The backend reports a single classified threat via
    // is_threat/threat_type/threat_level rather than a `threats` array;
    // surface it as a one-element list for the UI.
    final threats = <SmsThreat>[
      if (isThreat)
        SmsThreat(
          type: threatType ?? SmsThreatType.unknown,
          severity: SeverityLevel.fromString(rawLevel),
          confidence: confidence,
          description: description,
        ),
    ];

    return SmsAnalysisResult(
      id: json['id'] as String? ?? '',
      messageId: json['message_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      isThreat: isThreat,
      threatLevel: threatLevel,
      rawThreatLevel: rawLevel,
      threatType: threatType,
      riskScore: confidence,
      description: description,
      recommendations:
          (json['recommendations'] as List<dynamic>?)?.cast<String>() ?? [],
      threats: threats,
      extractedUrls: (json['urls'] as List<dynamic>?)
              ?.map((u) => ExtractedUrl.fromJson(u as Map<String, dynamic>))
              .toList() ??
          [],
      phoneNumbers:
          (json['phone_numbers'] as List<dynamic>?)?.cast<String>() ?? [],
      emails: (json['emails'] as List<dynamic>?)?.cast<String>() ?? [],
      patternMatches: (json['pattern_matches'] as List<dynamic>?)
              ?.map((p) => SmsPatternMatch.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      senderAnalysis: json['sender_analysis'] != null
          ? SenderAnalysis.fromJson(
              json['sender_analysis'] as Map<String, dynamic>)
          : null,
      intentAnalysis: json['intent_analysis'] != null
          ? SmsIntentAnalysis.fromJson(
              json['intent_analysis'] as Map<String, dynamic>)
          : null,
      analyzedAt: DateTime.parse(analyzedAtRaw),
    );
  }

  /// Intents detected in the message (derived from `intent_analysis`).
  List<SuspiciousIntent> get detectedIntents =>
      intentAnalysis?.detectedIntents ?? const [];

  /// Names of suspicious patterns matched in the message body.
  List<String> get matchedPatterns =>
      patternMatches.map((p) => p.patternName).toList();

  /// User-facing recommendation text (joined backend recommendations).
  String? get recommendation =>
      recommendations.isEmpty ? null : recommendations.join('\n');

  /// Whether the sender should be blocked, derived from the backend
  /// classification (threat at high/critical level).
  bool get shouldBlock =>
      isThreat &&
      (threatLevel == SmsThreatLevel.dangerous ||
          threatLevel == SmsThreatLevel.critical);

  /// Check if any threats were found
  bool get hasThreats => threats.isNotEmpty;

  /// Check if any malicious URLs were found
  bool get hasMaliciousUrls => extractedUrls.any((u) => u.isMalicious);

  /// Get the highest severity threat
  SmsThreat? get highestSeverityThreat {
    if (threats.isEmpty) return null;
    return threats
        .reduce((a, b) => a.severity.score > b.severity.score ? a : b);
  }
}

/// Individual threat detected in SMS
class SmsThreat {
  final SmsThreatType type;
  final SeverityLevel severity;
  final double confidence;
  final String description;
  final String? evidence;
  final List<String>? mitreTechniques;

  SmsThreat({
    required this.type,
    required this.severity,
    required this.confidence,
    required this.description,
    this.evidence,
    this.mitreTechniques,
  });
}

/// URL extracted from SMS (backend `urls[]` entry, models.SMSExtractedURL).
class ExtractedUrl {
  final String url;
  final String? domain;
  final bool isMalicious;
  final SeverityLevel? severity;
  final List<String>? categories;
  final bool isShortener;
  final String? expandedUrl;
  final String? threatDetails;
  final double confidence;
  final String? indicatorId;
  final String? campaignId;

  ExtractedUrl({
    required this.url,
    this.domain,
    required this.isMalicious,
    this.severity,
    this.categories,
    required this.isShortener,
    this.expandedUrl,
    this.threatDetails,
    this.confidence = 0.0,
    this.indicatorId,
    this.campaignId,
  });

  factory ExtractedUrl.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as String?;
    return ExtractedUrl(
      url: json['url'] as String? ?? '',
      domain: json['domain'] as String?,
      isMalicious: json['is_malicious'] as bool? ?? false,
      severity: json['severity'] != null
          ? SeverityLevel.fromString(json['severity'] as String)
          : null,
      categories: category != null && category.isNotEmpty ? [category] : null,
      // Backend field is `is_shortened`.
      isShortener: json['is_shortened'] as bool? ?? false,
      expandedUrl: json['expanded_url'] as String?,
      threatDetails: json['threat_details'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      indicatorId: json['indicator_id'] as String?,
      campaignId: json['campaign_id'] as String?,
    );
  }
}

/// Analysis of SMS sender (backend `sender_analysis`, models.SenderAnalysis).
///
/// Live keys: `is_short_code`, `is_alphanumeric`, `is_spoofed`,
/// `spoof_target`, `is_known_brand`, `brand_name`, `risk_score`, `notes`.
/// The backend never echoes the raw sender (it is hashed server-side).
class SenderAnalysis {
  final String sender;
  final bool isKnownSpammer;
  final bool isShortCode;
  final bool isAlphanumeric;
  final bool isSpoofed;
  final String? spoofedBrand;
  final bool isKnownBrand;
  final String? brandName;
  final double riskScore;
  final List<String>? warnings;

  SenderAnalysis({
    required this.sender,
    required this.isKnownSpammer,
    required this.isShortCode,
    required this.isAlphanumeric,
    required this.isSpoofed,
    this.spoofedBrand,
    this.isKnownBrand = false,
    this.brandName,
    required this.riskScore,
    this.warnings,
  });

  factory SenderAnalysis.fromJson(Map<String, dynamic> json) {
    final notes = json['notes'] as String?;
    final brandName = json['brand_name'] as String?;
    return SenderAnalysis(
      // Not emitted by the live backend (sender is hashed server-side).
      sender: json['sender'] as String? ?? '',
      isKnownSpammer: json['is_known_spammer'] as bool? ?? false,
      isShortCode: json['is_short_code'] as bool? ?? false,
      isAlphanumeric: json['is_alphanumeric'] as bool? ?? false,
      isSpoofed: json['is_spoofed'] as bool? ?? false,
      // Backend field is `spoof_target`.
      spoofedBrand:
          json['spoof_target'] as String? ?? json['spoofed_brand'] as String?,
      isKnownBrand: json['is_known_brand'] as bool? ?? false,
      brandName: brandName != null && brandName.isNotEmpty ? brandName : null,
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
      warnings: notes != null && notes.isNotEmpty ? [notes] : null,
    );
  }
}

/// One day of SMS analysis activity (backend `last_30_days_trend[]` entry).
class SmsTrendPoint {
  final String date; // YYYY-MM-DD
  final int analyzed;
  final int threats;

  SmsTrendPoint({
    required this.date,
    required this.analyzed,
    required this.threats,
  });

  factory SmsTrendPoint.fromJson(Map<String, dynamic> json) {
    return SmsTrendPoint(
      date: json['date'] as String? ?? '',
      analyzed: (json['analyzed'] as num?)?.toInt() ?? 0,
      threats: (json['threats'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Per-device SMS statistics (`GET /sms/stats` response).
///
/// Live shape (handlers/sms.go GetStats): `device_id`, `total_analyzed`,
/// `threats_detected`, `threats_by_type`, `threats_by_level`,
/// `false_positives_reported`, `last_24_hours{analyzed,threats}`,
/// `last_30_days_trend[]`, `last_analyzed_at`.
class SmsStatsResult {
  final String deviceId;
  final int totalAnalyzed;
  final int threatsDetected;
  final Map<String, int> threatsByType;
  final Map<String, int> threatsByLevel;
  final int falsePositivesReported;
  final int last24hAnalyzed;
  final int last24hThreats;
  final List<SmsTrendPoint> last30DaysTrend;
  final DateTime? lastAnalyzedAt;

  SmsStatsResult({
    required this.deviceId,
    required this.totalAnalyzed,
    required this.threatsDetected,
    required this.threatsByType,
    required this.threatsByLevel,
    required this.falsePositivesReported,
    required this.last24hAnalyzed,
    required this.last24hThreats,
    required this.last30DaysTrend,
    this.lastAnalyzedAt,
  });

  factory SmsStatsResult.fromJson(Map<String, dynamic> json) {
    if (json['total_analyzed'] is! num) {
      throw const FormatException(
          'SMS stats response is missing "total_analyzed"');
    }
    final last24 = json['last_24_hours'] as Map<String, dynamic>? ?? const {};
    return SmsStatsResult(
      deviceId: json['device_id'] as String? ?? '',
      totalAnalyzed: (json['total_analyzed'] as num).toInt(),
      threatsDetected: (json['threats_detected'] as num?)?.toInt() ?? 0,
      threatsByType: (json['threats_by_type'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
          {},
      threatsByLevel: (json['threats_by_level'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
          {},
      falsePositivesReported:
          (json['false_positives_reported'] as num?)?.toInt() ?? 0,
      last24hAnalyzed: (last24['analyzed'] as num?)?.toInt() ?? 0,
      last24hThreats: (last24['threats'] as num?)?.toInt() ?? 0,
      last30DaysTrend: (json['last_30_days_trend'] as List<dynamic>?)
              ?.map((p) => SmsTrendPoint.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      lastAnalyzedAt: json['last_analyzed_at'] != null
          ? DateTime.parse(json['last_analyzed_at'] as String)
          : null,
    );
  }
}

/// Local SMS detection patterns (`GET /sms/patterns` response).
///
/// The live backend returns word lists for on-device detection, not a list
/// of regex pattern objects.
class SmsDetectionPatterns {
  final String version;
  final DateTime? lastUpdated;
  final List<String> urgencyWords;
  final List<String> fearWords;
  final List<String> rewardWords;
  final List<String> personalWords;
  final List<String> financialWords;
  final List<String> urlShorteners;
  final List<String> suspiciousTlds;

  SmsDetectionPatterns({
    required this.version,
    this.lastUpdated,
    required this.urgencyWords,
    required this.fearWords,
    required this.rewardWords,
    required this.personalWords,
    required this.financialWords,
    required this.urlShorteners,
    required this.suspiciousTlds,
  });

  factory SmsDetectionPatterns.fromJson(Map<String, dynamic> json) {
    List<String> list(String key) =>
        (json[key] as List<dynamic>?)?.cast<String>() ?? [];
    return SmsDetectionPatterns(
      version: json['version'] as String? ?? '',
      lastUpdated: json['last_updated'] != null
          ? DateTime.tryParse(json['last_updated'] as String)
          : null,
      urgencyWords: list('urgency_words'),
      fearWords: list('fear_words'),
      rewardWords: list('reward_words'),
      personalWords: list('personal_words'),
      financialWords: list('financial_words'),
      urlShorteners: list('url_shorteners'),
      suspiciousTlds: list('suspicious_tlds'),
    );
  }
}

/// Phishing pattern descriptor.
///
/// Retained for compatibility; note the live `GET /sms/patterns` endpoint
/// returns [SmsDetectionPatterns] (word lists), not a list of these.
class PhishingPattern {
  final String id;
  final String name;
  final String pattern;
  final String category;
  final SeverityLevel severity;
  final String? description;
  final List<String>? examples;
  final int matchCount;
  final DateTime? lastSeen;

  PhishingPattern({
    required this.id,
    required this.name,
    required this.pattern,
    required this.category,
    required this.severity,
    this.description,
    this.examples,
    required this.matchCount,
    this.lastSeen,
  });

  factory PhishingPattern.fromJson(Map<String, dynamic> json) {
    return PhishingPattern(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      pattern: json['pattern'] as String? ?? '',
      category: json['category'] as String? ?? 'general',
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'medium'),
      description: json['description'] as String?,
      examples: (json['examples'] as List<dynamic>?)?.cast<String>(),
      matchCount: json['match_count'] as int? ?? 0,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
    );
  }
}

/// Threat level for QR codes, matching the backend enum exactly:
/// `safe`, `low`, `medium`, `high`, `critical`, `unknown`.
enum QrThreatLevel {
  safe('safe', 0),
  low('low', 1),
  medium('medium', 2),
  high('high', 3),
  critical('critical', 4),
  unknown('unknown', 0);

  final String value;
  final int score;
  const QrThreatLevel(this.value, this.score);

  static QrThreatLevel fromString(String value) {
    for (final level in QrThreatLevel.values) {
      if (level.value == value) return level;
    }
    throw FormatException('Unknown QR threat level: "$value"');
  }

  /// Get color for UI display
  int get color {
    switch (this) {
      case QrThreatLevel.safe:
        return 0xFF4CAF50; // Green
      case QrThreatLevel.low:
        return 0xFFFFC107; // Amber
      case QrThreatLevel.medium:
        return 0xFFFF9800; // Orange
      case QrThreatLevel.high:
        return 0xFFFF5722; // Deep orange
      case QrThreatLevel.critical:
        return 0xFFF44336; // Red
      case QrThreatLevel.unknown:
        return 0xFF757575; // Grey
    }
  }

  String get displayName {
    switch (this) {
      case QrThreatLevel.safe:
        return 'Safe';
      case QrThreatLevel.low:
        return 'Low Risk';
      case QrThreatLevel.medium:
        return 'Medium Risk';
      case QrThreatLevel.high:
        return 'High Risk';
      case QrThreatLevel.critical:
        return 'Critical';
      case QrThreatLevel.unknown:
        return 'Unknown';
    }
  }

  /// Map onto the shared UI threat level used by badges and filters.
  SmsThreatLevel get uiLevel {
    switch (this) {
      case QrThreatLevel.safe:
        return SmsThreatLevel.safe;
      case QrThreatLevel.low:
      case QrThreatLevel.medium:
      case QrThreatLevel.unknown:
        return SmsThreatLevel.suspicious;
      case QrThreatLevel.high:
        return SmsThreatLevel.dangerous;
      case QrThreatLevel.critical:
        return SmsThreatLevel.critical;
    }
  }
}

/// QR scan request (`POST /qr/scan`).
///
/// The backend reads `content`, `is_image`, `device_id`, `source_app` and
/// `location{latitude,longitude,accuracy}`.
class QrScanRequest {
  final String content;

  /// Client-side hint only; the backend classifies content itself.
  final String? contentType;
  final bool isImage;
  final String? deviceId;
  final String? sourceApp;
  final double? latitude;
  final double? longitude;
  final double? accuracy;

  QrScanRequest({
    required this.content,
    this.contentType,
    this.isImage = false,
    this.deviceId,
    this.sourceApp,
    this.latitude,
    this.longitude,
    this.accuracy,
  });

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'is_image': isImage,
      if (deviceId != null) 'device_id': deviceId,
      if (sourceApp != null) 'source_app': sourceApp,
      if (latitude != null && longitude != null)
        'location': {
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy ?? 0.0,
        },
    };
  }
}

/// Threat intelligence match attached to a QR threat
/// (backend `threat_intel_match`).
class QrThreatIntelMatch {
  final String indicatorId;
  final String indicatorType;
  final String? campaign;
  final String? threatActor;
  final int confidence; // 0-100

  QrThreatIntelMatch({
    required this.indicatorId,
    required this.indicatorType,
    this.campaign,
    this.threatActor,
    required this.confidence,
  });

  factory QrThreatIntelMatch.fromJson(Map<String, dynamic> json) {
    return QrThreatIntelMatch(
      indicatorId: json['indicator_id'] as String? ?? '',
      indicatorType: json['indicator_type'] as String? ?? '',
      campaign: json['campaign'] as String?,
      threatActor: json['threat_actor'] as String?,
      confidence: (json['confidence'] as num?)?.toInt() ?? 0,
    );
  }
}

/// QR scan result (`POST /qr/scan` response, models.QRScanResult).
///
/// Live shape: `id`, `raw_content`, `content_type`, `parsed_content`,
/// `threat_level`, `threat_score` (0-100), `threats[]`, `is_safe`,
/// `should_block`, `warnings[]`, `recommendations[]`, `url_preview`,
/// `scanned_at`, `analysis_duration` (nanoseconds).
class QrScanResult {
  final String id;
  final String rawContent;
  final String contentType;

  /// Dedicated QR threat level parsed from the backend value.
  final QrThreatLevel qrThreatLevel;

  /// Backend threat score in its native 0-100 range.
  final double threatScore;
  final List<QrThreat> threats;

  /// Parsed content details keyed by type (`url`, `wifi`, `email`, ...).
  final Map<String, dynamic>? parsedContent;
  final bool isSafe;
  final bool shouldBlock;
  final List<String> warnings;
  final List<String> recommendations;
  final DateTime scannedAt;
  final Duration? analysisDuration;

  QrScanResult({
    required this.id,
    required this.rawContent,
    required this.contentType,
    required this.qrThreatLevel,
    required this.threatScore,
    required this.threats,
    this.parsedContent,
    required this.isSafe,
    required this.shouldBlock,
    required this.warnings,
    required this.recommendations,
    required this.scannedAt,
    this.analysisDuration,
  });

  factory QrScanResult.fromJson(Map<String, dynamic> json) {
    final rawLevel = json['threat_level'];
    if (rawLevel is! String) {
      throw const FormatException(
          'QR scan response is missing "threat_level"');
    }
    final scannedAtRaw = json['scanned_at'];
    if (scannedAtRaw is! String) {
      throw const FormatException('QR scan response is missing "scanned_at"');
    }

    final durationNs = (json['analysis_duration'] as num?)?.toInt();

    return QrScanResult(
      id: json['id'] as String? ?? '',
      rawContent: json['raw_content'] as String? ?? '',
      contentType: json['content_type'] as String? ?? 'unknown',
      qrThreatLevel: QrThreatLevel.fromString(rawLevel),
      threatScore:
          ((json['threat_score'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 100.0),
      threats: (json['threats'] as List<dynamic>?)
              ?.map((t) => QrThreat.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      parsedContent: parseJsonBlob(json['parsed_content']),
      isSafe: json['is_safe'] as bool? ?? false,
      shouldBlock: json['should_block'] as bool? ?? false,
      warnings: (json['warnings'] as List<dynamic>?)?.cast<String>() ?? [],
      recommendations:
          (json['recommendations'] as List<dynamic>?)?.cast<String>() ?? [],
      scannedAt: DateTime.parse(scannedAtRaw),
      analysisDuration:
          durationNs != null ? Duration(microseconds: durationNs ~/ 1000) : null,
    );
  }

  /// Raw QR content (kept under the legacy name used by the UI).
  String get content => rawContent;

  /// Shared UI threat level derived from [qrThreatLevel].
  SmsThreatLevel get threatLevel => qrThreatLevel.uiLevel;

  /// Normalized risk score (0.0 - 1.0), from the backend 0-100 threat score.
  double get riskScore => (threatScore / 100.0).clamp(0.0, 1.0);

  /// User-facing recommendation text (backend recommendations + warnings).
  String? get recommendation {
    final lines = [...recommendations, ...warnings];
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// Timestamp alias kept for compatibility with older call sites.
  DateTime get analyzedAt => scannedAt;

  bool get hasThreats => threats.isNotEmpty;
}

/// QR threat (backend `threats[]` entry, models.QRThreat).
class QrThreat {
  final String type;
  final SeverityLevel severity;
  final String description;
  final String? evidence;
  final QrThreatIntelMatch? threatIntelMatch;

  QrThreat({
    required this.type,
    required this.severity,
    required this.description,
    this.evidence,
    this.threatIntelMatch,
  });

  factory QrThreat.fromJson(Map<String, dynamic> json) {
    return QrThreat(
      type: json['type'] as String? ?? 'unknown',
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'unknown'),
      description: json['description'] as String? ?? '',
      evidence: json['evidence'] as String?,
      threatIntelMatch: json['threat_intel_match'] != null
          ? QrThreatIntelMatch.fromJson(
              json['threat_intel_match'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Dark web breach check result (`POST /darkweb/check/email` response,
/// models.BreachCheckResponse).
///
/// Live shape: `email`, `is_breached`, `breach_count`, `breaches[]`,
/// `exposed_data_types[]`, `first_breach`, `latest_breach`, `risk_level`,
/// `recommendations[]`, `checked_at`. The endpoint returns 503 when no
/// breach data providers are configured (handled by the API client layer).
class BreachCheckResult {
  final String email;
  final bool isBreached;
  final int breachCount;
  final List<BreachInfo> breaches;
  final List<String> exposedDataTypes;
  final DateTime? firstBreach;
  final DateTime? latestBreach;
  final SeverityLevel riskLevel;
  final List<String> recommendations;
  final DateTime checkedAt;

  BreachCheckResult({
    required this.email,
    required this.isBreached,
    required this.breachCount,
    required this.breaches,
    this.exposedDataTypes = const [],
    this.firstBreach,
    this.latestBreach,
    this.riskLevel = SeverityLevel.unknown,
    this.recommendations = const [],
    required this.checkedAt,
  });

  factory BreachCheckResult.fromJson(Map<String, dynamic> json) {
    if (json['is_breached'] is! bool) {
      throw const FormatException(
          'Breach check response is missing "is_breached"');
    }
    return BreachCheckResult(
      email: json['email'] as String? ?? '',
      isBreached: json['is_breached'] as bool,
      breachCount: (json['breach_count'] as num?)?.toInt() ?? 0,
      breaches: (json['breaches'] as List<dynamic>?)
              ?.map((b) => BreachInfo.fromJson(b as Map<String, dynamic>))
              .toList() ??
          [],
      exposedDataTypes:
          (json['exposed_data_types'] as List<dynamic>?)?.cast<String>() ?? [],
      firstBreach: json['first_breach'] != null
          ? DateTime.tryParse(json['first_breach'] as String)
          : null,
      latestBreach: json['latest_breach'] != null
          ? DateTime.tryParse(json['latest_breach'] as String)
          : null,
      riskLevel:
          SeverityLevel.fromString(json['risk_level'] as String? ?? 'unknown'),
      recommendations:
          (json['recommendations'] as List<dynamic>?)?.cast<String>() ?? [],
      checkedAt: json['checked_at'] != null
          ? DateTime.parse(json['checked_at'] as String)
          : DateTime.now(),
    );
  }
}

/// Breach information (backend models.Breach / breach catalog entry).
///
/// Live keys: `name`, `title`, `domain`, `breach_date`, `pwn_count`,
/// `description`, `data_classes[]`, `is_verified`, `is_sensitive`,
/// `severity`, `logo_path`, plus fabrication/retirement flags.
class BreachInfo {
  final String name;
  final String title;
  final String domain;
  final DateTime? breachDate;
  final int? pwnCount;
  final List<String> dataClasses;
  final String? description;
  final bool isVerified;
  final bool isSensitive;
  final SeverityLevel severity;
  final String? logoPath;

  BreachInfo({
    required this.name,
    this.title = '',
    required this.domain,
    this.breachDate,
    this.pwnCount,
    required this.dataClasses,
    this.description,
    required this.isVerified,
    required this.isSensitive,
    this.severity = SeverityLevel.unknown,
    this.logoPath,
  });

  factory BreachInfo.fromJson(Map<String, dynamic> json) {
    // Go serializes unset time.Time as 0001-01-01; treat it as absent.
    DateTime? breachDate;
    if (json['breach_date'] != null) {
      final parsed = DateTime.tryParse(json['breach_date'] as String);
      if (parsed != null && parsed.year > 1) {
        breachDate = parsed;
      }
    }
    return BreachInfo(
      name: json['name'] as String? ?? '',
      title: json['title'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      breachDate: breachDate,
      pwnCount: (json['pwn_count'] as num?)?.toInt(),
      dataClasses:
          (json['data_classes'] as List<dynamic>?)?.cast<String>() ?? [],
      description: json['description'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      isSensitive: json['is_sensitive'] as bool? ?? false,
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'unknown'),
      logoPath: json['logo_path'] as String?,
    );
  }
}

/// Password breach result (`POST /darkweb/check/password` response,
/// models.PasswordCheckResponse).
///
/// Live shape: `is_breached`, `breach_count`, `risk_level`, `message`,
/// `checked_at`.
class PasswordBreachResult {
  final bool isBreached;
  final int exposureCount;
  final String recommendation;
  final String riskLevel;
  final DateTime? checkedAt;

  PasswordBreachResult({
    required this.isBreached,
    required this.exposureCount,
    required this.recommendation,
    this.riskLevel = '',
    this.checkedAt,
  });

  factory PasswordBreachResult.fromJson(Map<String, dynamic> json) {
    if (json['is_breached'] is! bool) {
      throw const FormatException(
          'Password check response is missing "is_breached"');
    }
    return PasswordBreachResult(
      isBreached: json['is_breached'] as bool,
      // Backend field is `breach_count`.
      exposureCount: (json['breach_count'] as num?)?.toInt() ??
          (json['exposure_count'] as num?)?.toInt() ??
          0,
      // Backend field is `message`.
      recommendation: json['message'] as String? ??
          json['recommendation'] as String? ??
          '',
      riskLevel: json['risk_level'] as String? ?? '',
      checkedAt: json['checked_at'] != null
          ? DateTime.tryParse(json['checked_at'] as String)
          : null,
    );
  }
}

/// Breach alert (`GET /darkweb/alerts` entries, models.BreachAlert).
///
/// Live shape: `id`, `asset_id`, `breach_id`, `breach_name`, `severity`,
/// `data_exposed[]`, `detected_at`, `acked_at`, `is_read`, `actions[]`.
/// The breach details are surfaced through [breach] (name + exposed data)
/// for compatibility with existing widgets.
class BreachAlert {
  final String id;
  final String assetId;
  final String breachId;
  final String assetType;
  final String assetValue;
  final BreachInfo breach;
  final List<String> dataExposed;
  final SeverityLevel severity;
  final DateTime alertedAt;
  final DateTime? ackedAt;
  final bool isRead;

  BreachAlert({
    required this.id,
    this.assetId = '',
    this.breachId = '',
    required this.assetType,
    required this.assetValue,
    required this.breach,
    this.dataExposed = const [],
    required this.severity,
    required this.alertedAt,
    this.ackedAt,
    required this.isRead,
  });

  factory BreachAlert.fromJson(Map<String, dynamic> json) {
    final detectedAtRaw =
        json['detected_at'] as String? ?? json['alerted_at'] as String?;
    if (detectedAtRaw == null) {
      throw const FormatException(
          'Breach alert is missing "detected_at"');
    }
    final dataExposed =
        (json['data_exposed'] as List<dynamic>?)?.cast<String>() ?? [];

    // The live payload carries breach_name + data_exposed rather than a
    // nested breach object; expose them through BreachInfo for the UI.
    final breach = json['breach'] is Map<String, dynamic>
        ? BreachInfo.fromJson(json['breach'] as Map<String, dynamic>)
        : BreachInfo(
            name: json['breach_name'] as String? ?? '',
            domain: '',
            dataClasses: dataExposed,
            isVerified: false,
            isSensitive: false,
          );

    return BreachAlert(
      id: json['id'] as String? ?? '',
      assetId: json['asset_id'] as String? ?? '',
      breachId: json['breach_id'] as String? ?? '',
      // Asset type/value are not included in the live alert payload
      // (only asset_id); parse them when present.
      assetType: json['asset_type'] as String? ?? '',
      assetValue: json['asset_value'] as String? ?? '',
      breach: breach,
      dataExposed: dataExposed,
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'unknown'),
      alertedAt: DateTime.parse(detectedAtRaw),
      ackedAt: json['acked_at'] != null
          ? DateTime.tryParse(json['acked_at'] as String)
          : null,
      isRead: json['is_read'] as bool? ?? false,
    );
  }
}
