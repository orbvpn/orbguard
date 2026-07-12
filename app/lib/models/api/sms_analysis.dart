/// SMS Analysis Models
/// Models for SMS/smishing analysis from OrbGuard Lab API

import 'threat_indicator.dart';

/// Threat level for SMS messages
enum SmsThreatLevel {
  safe('safe', 0),
  suspicious('suspicious', 1),
  dangerous('dangerous', 2),
  critical('critical', 3);

  final String value;
  final int score;
  const SmsThreatLevel(this.value, this.score);

  static SmsThreatLevel fromString(String value) {
    return SmsThreatLevel.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SmsThreatLevel.safe,
    );
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

/// Types of SMS threats detected
enum SmsThreatType {
  phishing('phishing'),
  smishing('smishing'),
  malwareLink('malware_link'),
  scam('scam'),
  spam('spam'),
  executiveImpersonation('executive_impersonation'),
  bankingFraud('banking_fraud'),
  packageDeliveryScam('package_delivery_scam'),
  otpFraud('otp_fraud'),
  premiumRate('premium_rate'),
  unknown('unknown');

  final String value;
  const SmsThreatType(this.value);

  static SmsThreatType fromString(String value) {
    return SmsThreatType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SmsThreatType.unknown,
    );
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

/// Request to analyze SMS
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
      'content': content,
      if (sender != null) 'sender': sender,
      if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
      if (deviceId != null) 'device_id': deviceId,
    };
  }
}

/// Result of SMS analysis
class SmsAnalysisResult {
  final String content;
  final SmsThreatLevel threatLevel;
  final double riskScore;
  final List<SmsThreat> threats;
  final List<ExtractedUrl> extractedUrls;
  final SenderAnalysis? senderAnalysis;
  final List<SuspiciousIntent> detectedIntents;
  final List<String> matchedPatterns;
  final String? recommendation;
  final bool shouldBlock;
  final DateTime analyzedAt;

  SmsAnalysisResult({
    required this.content,
    required this.threatLevel,
    required this.riskScore,
    required this.threats,
    required this.extractedUrls,
    this.senderAnalysis,
    required this.detectedIntents,
    required this.matchedPatterns,
    this.recommendation,
    required this.shouldBlock,
    required this.analyzedAt,
  });

  factory SmsAnalysisResult.fromJson(Map<String, dynamic> json) {
    return SmsAnalysisResult(
      content: json['content'] as String? ?? '',
      threatLevel:
          SmsThreatLevel.fromString(json['threat_level'] as String? ?? 'safe'),
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
      threats: (json['threats'] as List<dynamic>?)
              ?.map((t) => SmsThreat.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      extractedUrls: (json['extracted_urls'] as List<dynamic>?)
              ?.map((u) => ExtractedUrl.fromJson(u as Map<String, dynamic>))
              .toList() ??
          [],
      senderAnalysis: json['sender_analysis'] != null
          ? SenderAnalysis.fromJson(
              json['sender_analysis'] as Map<String, dynamic>)
          : null,
      detectedIntents: (json['detected_intents'] as List<dynamic>?)
              ?.map((i) => SuspiciousIntent.fromString(i as String))
              .toList() ??
          [],
      matchedPatterns:
          (json['matched_patterns'] as List<dynamic>?)?.cast<String>() ?? [],
      recommendation: json['recommendation'] as String?,
      shouldBlock: json['should_block'] as bool? ?? false,
      analyzedAt: DateTime.parse(
          json['analyzed_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }

  /// Check if any threats were found
  bool get hasThreats => threats.isNotEmpty;

  /// Check if any malicious URLs were found
  bool get hasMaliciousUrls =>
      extractedUrls.any((u) => u.isMalicious);

  /// Get the highest severity threat
  SmsThreat? get highestSeverityThreat {
    if (threats.isEmpty) return null;
    return threats.reduce((a, b) => a.severity.score > b.severity.score ? a : b);
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

  factory SmsThreat.fromJson(Map<String, dynamic> json) {
    return SmsThreat(
      type: SmsThreatType.fromString(json['type'] as String? ?? 'unknown'),
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'unknown'),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String? ?? '',
      evidence: json['evidence'] as String?,
      mitreTechniques:
          (json['mitre_techniques'] as List<dynamic>?)?.cast<String>(),
    );
  }
}

/// URL extracted from SMS
class ExtractedUrl {
  final String url;
  final String? domain;
  final bool isMalicious;
  final SeverityLevel? severity;
  final List<String>? categories;
  final bool isShortener;
  final String? expandedUrl;

  ExtractedUrl({
    required this.url,
    this.domain,
    required this.isMalicious,
    this.severity,
    this.categories,
    required this.isShortener,
    this.expandedUrl,
  });

  factory ExtractedUrl.fromJson(Map<String, dynamic> json) {
    return ExtractedUrl(
      url: json['url'] as String,
      domain: json['domain'] as String?,
      isMalicious: json['is_malicious'] as bool? ?? false,
      severity: json['severity'] != null
          ? SeverityLevel.fromString(json['severity'] as String)
          : null,
      categories: (json['categories'] as List<dynamic>?)?.cast<String>(),
      isShortener: json['is_shortener'] as bool? ?? false,
      expandedUrl: json['expanded_url'] as String?,
    );
  }
}

/// Analysis of SMS sender
class SenderAnalysis {
  final String sender;
  final bool isKnownSpammer;
  final bool isShortCode;
  final bool isAlphanumeric;
  final bool isSpoofed;
  final String? spoofedBrand;
  final double riskScore;
  final List<String>? warnings;

  SenderAnalysis({
    required this.sender,
    required this.isKnownSpammer,
    required this.isShortCode,
    required this.isAlphanumeric,
    required this.isSpoofed,
    this.spoofedBrand,
    required this.riskScore,
    this.warnings,
  });

  factory SenderAnalysis.fromJson(Map<String, dynamic> json) {
    return SenderAnalysis(
      sender: json['sender'] as String? ?? '',
      isKnownSpammer: json['is_known_spammer'] as bool? ?? false,
      isShortCode: json['is_short_code'] as bool? ?? false,
      isAlphanumeric: json['is_alphanumeric'] as bool? ?? false,
      isSpoofed: json['is_spoofed'] as bool? ?? false,
      spoofedBrand: json['spoofed_brand'] as String?,
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
      warnings: (json['warnings'] as List<dynamic>?)?.cast<String>(),
    );
  }
}

/// Phishing pattern from API
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

/// QR scan request
class QrScanRequest {
  final String content;
  final String? contentType;
  final String? deviceId;
  final double? latitude;
  final double? longitude;

  QrScanRequest({
    required this.content,
    this.contentType,
    this.deviceId,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      if (contentType != null) 'content_type': contentType,
      if (deviceId != null) 'device_id': deviceId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };
  }
}

/// QR scan result
class QrScanResult {
  final String content;
  final String contentType;
  final SmsThreatLevel threatLevel;
  final double riskScore;
  final List<QrThreat> threats;
  final String? parsedContent;
  final Map<String, dynamic>? contentDetails;
  final String? recommendation;
  final bool shouldBlock;
  final DateTime analyzedAt;

  QrScanResult({
    required this.content,
    required this.contentType,
    required this.threatLevel,
    required this.riskScore,
    required this.threats,
    this.parsedContent,
    this.contentDetails,
    this.recommendation,
    required this.shouldBlock,
    required this.analyzedAt,
  });

  factory QrScanResult.fromJson(Map<String, dynamic> json) {
    return QrScanResult(
      content: json['content'] as String? ?? '',
      contentType: json['content_type'] as String? ?? 'unknown',
      threatLevel:
          SmsThreatLevel.fromString(json['threat_level'] as String? ?? 'safe'),
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
      threats: (json['threats'] as List<dynamic>?)
              ?.map((t) => QrThreat.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      parsedContent: json['parsed_content'] as String?,
      contentDetails: json['content_details'] as Map<String, dynamic>?,
      recommendation: json['recommendation'] as String?,
      shouldBlock: json['should_block'] as bool? ?? false,
      analyzedAt: DateTime.parse(
          json['analyzed_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }

  bool get hasThreats => threats.isNotEmpty;
}

/// QR threat
class QrThreat {
  final String type;
  final SeverityLevel severity;
  final String description;
  final String? evidence;

  QrThreat({
    required this.type,
    required this.severity,
    required this.description,
    this.evidence,
  });

  factory QrThreat.fromJson(Map<String, dynamic> json) {
    return QrThreat(
      type: json['type'] as String? ?? 'unknown',
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'unknown'),
      description: json['description'] as String? ?? '',
      evidence: json['evidence'] as String?,
    );
  }
}

/// Dark web breach check result
class BreachCheckResult {
  final String email;
  final bool isBreached;
  final int breachCount;
  final List<BreachInfo> breaches;
  final DateTime checkedAt;

  BreachCheckResult({
    required this.email,
    required this.isBreached,
    required this.breachCount,
    required this.breaches,
    required this.checkedAt,
  });

  factory BreachCheckResult.fromJson(Map<String, dynamic> json) {
    return BreachCheckResult(
      email: json['email'] as String? ?? '',
      isBreached: json['is_breached'] as bool? ?? false,
      breachCount: json['breach_count'] as int? ?? 0,
      breaches: (json['breaches'] as List<dynamic>?)
              ?.map((b) => BreachInfo.fromJson(b as Map<String, dynamic>))
              .toList() ??
          [],
      checkedAt: DateTime.parse(
          json['checked_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Breach information
class BreachInfo {
  final String name;
  final String domain;
  final DateTime? breachDate;
  final int? pwnCount;
  final List<String> dataClasses;
  final String? description;
  final bool isVerified;
  final bool isSensitive;

  BreachInfo({
    required this.name,
    required this.domain,
    this.breachDate,
    this.pwnCount,
    required this.dataClasses,
    this.description,
    required this.isVerified,
    required this.isSensitive,
  });

  factory BreachInfo.fromJson(Map<String, dynamic> json) {
    return BreachInfo(
      name: json['name'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      breachDate: json['breach_date'] != null
          ? DateTime.parse(json['breach_date'] as String)
          : null,
      pwnCount: json['pwn_count'] as int?,
      dataClasses: (json['data_classes'] as List<dynamic>?)?.cast<String>() ?? [],
      description: json['description'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      isSensitive: json['is_sensitive'] as bool? ?? false,
    );
  }
}

/// Password breach result
class PasswordBreachResult {
  final bool isBreached;
  final int exposureCount;
  final String recommendation;

  PasswordBreachResult({
    required this.isBreached,
    required this.exposureCount,
    required this.recommendation,
  });

  factory PasswordBreachResult.fromJson(Map<String, dynamic> json) {
    return PasswordBreachResult(
      isBreached: json['is_breached'] as bool? ?? false,
      exposureCount: json['exposure_count'] as int? ?? 0,
      recommendation: json['recommendation'] as String? ?? '',
    );
  }
}

/// Breach alert
class BreachAlert {
  final String id;
  final String assetType;
  final String assetValue;
  final BreachInfo breach;
  final SeverityLevel severity;
  final DateTime alertedAt;
  final bool isRead;

  BreachAlert({
    required this.id,
    required this.assetType,
    required this.assetValue,
    required this.breach,
    required this.severity,
    required this.alertedAt,
    required this.isRead,
  });

  factory BreachAlert.fromJson(Map<String, dynamic> json) {
    return BreachAlert(
      id: json['id'] as String,
      assetType: json['asset_type'] as String? ?? 'email',
      assetValue: json['asset_value'] as String? ?? '',
      breach: BreachInfo.fromJson(json['breach'] as Map<String, dynamic>),
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'medium'),
      alertedAt: DateTime.parse(
          json['alerted_at'] as String? ?? DateTime.now().toIso8601String()),
      isRead: json['is_read'] as bool? ?? false,
    );
  }
}
