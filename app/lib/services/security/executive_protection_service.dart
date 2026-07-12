/// Executive Impersonation Protection Service
///
/// Detects and prevents Business Email Compromise (BEC) and CEO fraud attacks:
/// - Executive contact identification and monitoring
/// - Sender spoofing detection (display name vs email mismatch)
/// - Domain lookalike detection (typosquatting)
/// - Urgency/pressure language analysis
/// - Wire transfer/payment request detection
/// - AI-powered impersonation scoring

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Executive contact profile
class ExecutiveProfile {
  final String id;
  final String name;
  final String email;
  final String? title;
  final String? department;
  final String? phoneNumber;
  final List<String> knownEmailDomains;
  final List<String> alternateNames;
  final bool isHighValue; // CEO, CFO, etc.
  final DateTime addedAt;

  ExecutiveProfile({
    required this.id,
    required this.name,
    required this.email,
    this.title,
    this.department,
    this.phoneNumber,
    this.knownEmailDomains = const [],
    this.alternateNames = const [],
    this.isHighValue = false,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  factory ExecutiveProfile.fromJson(Map<String, dynamic> json) {
    return ExecutiveProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      title: json['title'] as String?,
      department: json['department'] as String?,
      phoneNumber: json['phone_number'] as String?,
      knownEmailDomains: (json['known_email_domains'] as List<dynamic>?)
          ?.cast<String>() ?? [],
      alternateNames: (json['alternate_names'] as List<dynamic>?)
          ?.cast<String>() ?? [],
      isHighValue: json['is_high_value'] as bool? ?? false,
      addedAt: json['added_at'] != null
          ? DateTime.parse(json['added_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'title': title,
    'department': department,
    'phone_number': phoneNumber,
    'known_email_domains': knownEmailDomains,
    'alternate_names': alternateNames,
    'is_high_value': isHighValue,
    'added_at': addedAt.toIso8601String(),
  };

  /// Get all name variations for matching
  List<String> get allNameVariations {
    final variations = <String>[name.toLowerCase()];
    variations.addAll(alternateNames.map((n) => n.toLowerCase()));

    // Add common variations
    final parts = name.split(' ');
    if (parts.length >= 2) {
      // First Last -> F. Last, First L.
      variations.add('${parts.first[0].toLowerCase()}. ${parts.last.toLowerCase()}');
      variations.add('${parts.first.toLowerCase()} ${parts.last[0].toLowerCase()}.');
      // First Last -> Last, First
      variations.add('${parts.last.toLowerCase()}, ${parts.first.toLowerCase()}');
    }

    return variations;
  }
}

/// Message to analyze for impersonation
class MessageAnalysisRequest {
  final String senderName;
  final String senderEmail;
  final String subject;
  final String body;
  final DateTime timestamp;
  final List<String>? recipients;
  final bool hasAttachments;
  final String? replyTo;

  MessageAnalysisRequest({
    required this.senderName,
    required this.senderEmail,
    required this.subject,
    required this.body,
    required this.timestamp,
    this.recipients,
    this.hasAttachments = false,
    this.replyTo,
  });
}

/// Impersonation detection result
class ImpersonationResult {
  final bool isImpersonation;
  final double confidenceScore;
  final String riskLevel;
  final ExecutiveProfile? impersonatedExecutive;
  final List<ImpersonationIndicator> indicators;
  final String recommendation;
  final ImpersonationType? type;

  ImpersonationResult({
    required this.isImpersonation,
    required this.confidenceScore,
    required this.riskLevel,
    this.impersonatedExecutive,
    required this.indicators,
    required this.recommendation,
    this.type,
  });

  String get riskColor {
    switch (riskLevel.toLowerCase()) {
      case 'critical':
        return '#FF0000';
      case 'high':
        return '#FF4444';
      case 'medium':
        return '#FFA500';
      case 'low':
        return '#FFFF00';
      default:
        return '#00FF00';
    }
  }
}

/// Types of impersonation attacks
enum ImpersonationType {
  ceoFraud('CEO Fraud', 'Impersonating CEO to authorize payments'),
  vendorFraud('Vendor Fraud', 'Impersonating vendor to change payment details'),
  attorneyFraud('Attorney Fraud', 'Impersonating lawyer for urgent transfers'),
  dataTheft('Data Theft', 'Impersonating executive to steal sensitive data'),
  w2Scam('W-2/Tax Scam', 'Requesting employee tax information'),
  giftCardScam('Gift Card Scam', 'Requesting gift card purchases'),
  unknown('Unknown', 'Unclassified impersonation attempt');

  final String displayName;
  final String description;
  const ImpersonationType(this.displayName, this.description);
}

/// Specific impersonation indicator
class ImpersonationIndicator {
  final String type;
  final String description;
  final double weight;
  final String? evidence;

  ImpersonationIndicator({
    required this.type,
    required this.description,
    required this.weight,
    this.evidence,
  });
}

/// Executive Impersonation Protection Service
class ExecutiveProtectionService {
  // Executive profiles database
  final Map<String, ExecutiveProfile> _executives = {};

  // Corporate domains (legitimate)
  final Set<String> _corporateDomains = {};

  // Stream controllers
  final _alertController = StreamController<ImpersonationResult>.broadcast();

  // Analysis patterns
  late final List<RegExp> _urgencyPatterns;
  late final List<RegExp> _paymentPatterns;
  late final List<RegExp> _secrecyPatterns;
  late final List<RegExp> _dataRequestPatterns;
  late final Map<String, List<String>> _homoglyphMap;

  /// Stream of impersonation alerts
  Stream<ImpersonationResult> get onAlert => _alertController.stream;

  /// Initialize the service
  Future<void> initialize() async {
    _loadPatterns();
    _loadHomoglyphMap();
  }

  /// Load detection patterns
  void _loadPatterns() {
    // Urgency/pressure patterns
    _urgencyPatterns = [
      RegExp(r'\b(urgent|immediately|asap|right away|time sensitive)\b', caseSensitive: false),
      RegExp(r'\b(before (the )?end of (the )?(day|business))\b', caseSensitive: false),
      RegExp(r'\b(need(s|ed)? (this|it) (done|completed|now))\b', caseSensitive: false),
      RegExp(r'\b(critical|emergency|top priority)\b', caseSensitive: false),
      RegExp(r"\b(don'?t delay|act (now|fast|quickly))\b", caseSensitive: false),
      RegExp(r'\b(deadline|time is running out)\b', caseSensitive: false),
    ];

    // Payment/financial patterns
    _paymentPatterns = [
      RegExp(r'\b(wire transfer|bank transfer|ach|swift)\b', caseSensitive: false),
      RegExp(r'\b(payment|invoice|purchase order|po)\b', caseSensitive: false),
      RegExp(r'\b(account (number|details|information))\b', caseSensitive: false),
      RegExp(r'\b(routing number|iban|bic)\b', caseSensitive: false),
      RegExp(r'\b(authorize|approval|sign off)\b', caseSensitive: false),
      RegExp(r'\b(vendor|supplier|contractor) payment\b', caseSensitive: false),
      RegExp(r'\$[\d,]+(\.\d{2})?', caseSensitive: false), // Dollar amounts
      RegExp(r'\b\d{1,3}(,\d{3})*(\.\d{2})?\s*(usd|dollars|euros|gbp)\b', caseSensitive: false),
    ];

    // Secrecy/confidentiality patterns
    _secrecyPatterns = [
      RegExp(r'\b(confidential|private|sensitive)\b', caseSensitive: false),
      RegExp(r"\b(don'?t (tell|share|mention|discuss))\b", caseSensitive: false),
      RegExp(r'\b(between (us|you and me))\b', caseSensitive: false),
      RegExp(r'\b(keep (this|it) (quiet|private|between))\b', caseSensitive: false),
      RegExp(r'\b(discretion|discreet(ly)?)\b', caseSensitive: false),
      RegExp(r'\b(off the record)\b', caseSensitive: false),
    ];

    // Data/information request patterns
    _dataRequestPatterns = [
      RegExp(r'\b(employee (list|records|data|information))\b', caseSensitive: false),
      RegExp(r'\b(w-?2|tax (forms?|documents?|records?))\b', caseSensitive: false),
      RegExp(r'\b(ssn|social security|ein)\b', caseSensitive: false),
      RegExp(r'\b(password|credentials|login)\b', caseSensitive: false),
      RegExp(r'\b(customer (list|data|records))\b', caseSensitive: false),
      RegExp(r'\b(financial (statements?|records?|data))\b', caseSensitive: false),
      RegExp(r'\b(send (me|over) (the|all|a list))\b', caseSensitive: false),
    ];
  }

  /// Load homoglyph mapping for lookalike detection
  void _loadHomoglyphMap() {
    _homoglyphMap = {
      'a': ['а', 'ɑ', 'α', '@', '4'],
      'b': ['Ь', 'ƅ', '6'],
      'c': ['с', 'ϲ', '('],
      'd': ['ԁ', 'ɗ'],
      'e': ['е', 'ё', '3', 'є'],
      'g': ['ɡ', '9', 'ց'],
      'h': ['һ', 'ℎ'],
      'i': ['і', 'ї', '1', 'l', '|'],
      'j': ['ј', 'ʝ'],
      'k': ['κ', 'ᴋ'],
      'l': ['ⅼ', '1', 'I', '|'],
      'm': ['м', 'ⅿ', 'rn'],
      'n': ['п', 'ո', 'ɴ'],
      'o': ['о', '0', 'ο', 'ө'],
      'p': ['р', 'ρ'],
      'q': ['ԛ', 'գ'],
      'r': ['г', 'ɾ'],
      's': ['ѕ', 'ꜱ', '5', '\$'],
      't': ['т', 'ⅰ', '+'],
      'u': ['υ', 'ս', 'ц'],
      'v': ['ν', 'ⅴ'],
      'w': ['ѡ', 'ա', 'vv'],
      'x': ['х', '×'],
      'y': ['у', 'ү', 'ɣ'],
      'z': ['ᴢ', '2'],
    };
  }

  /// Add an executive profile to monitor
  void addExecutive(ExecutiveProfile executive) {
    _executives[executive.id] = executive;

    // Extract domain from email
    final emailParts = executive.email.split('@');
    if (emailParts.length == 2) {
      _corporateDomains.add(emailParts[1].toLowerCase());
    }

    // Add known domains
    _corporateDomains.addAll(
      executive.knownEmailDomains.map((d) => d.toLowerCase())
    );
  }

  /// Remove an executive profile
  void removeExecutive(String id) {
    _executives.remove(id);
  }

  /// Add corporate domain
  void addCorporateDomain(String domain) {
    _corporateDomains.add(domain.toLowerCase());
  }

  /// Get all executives
  List<ExecutiveProfile> get executives => _executives.values.toList();

  /// Analyze a message for executive impersonation
  Future<ImpersonationResult> analyzeMessage(MessageAnalysisRequest message) async {
    double score = 0.0;
    final indicators = <ImpersonationIndicator>[];
    ExecutiveProfile? impersonatedExec;
    ImpersonationType? attackType;

    // 1. Check for executive name in sender display name
    final nameMatch = _findExecutiveByName(message.senderName);
    if (nameMatch != null) {
      impersonatedExec = nameMatch;

      // Check if email domain matches
      final senderDomain = _extractDomain(message.senderEmail);
      final legitDomains = {
        ...nameMatch.knownEmailDomains.map((d) => d.toLowerCase()),
        _extractDomain(nameMatch.email),
      };

      if (!legitDomains.contains(senderDomain)) {
        score += 0.4;
        indicators.add(ImpersonationIndicator(
          type: 'domain_mismatch',
          description: 'Sender claims to be ${nameMatch.name} but email domain doesn\'t match',
          weight: 0.4,
          evidence: 'Expected: ${legitDomains.join(", ")}, Got: $senderDomain',
        ));
      }
    }

    // 2. Check for lookalike domains (typosquatting)
    final lookalikeDomain = _detectLookalikeDomain(message.senderEmail);
    if (lookalikeDomain != null) {
      score += 0.35;
      indicators.add(ImpersonationIndicator(
        type: 'lookalike_domain',
        description: 'Email domain looks similar to corporate domain',
        weight: 0.35,
        evidence: 'Suspicious domain: ${_extractDomain(message.senderEmail)} similar to $lookalikeDomain',
      ));
    }

    // 3. Check for homoglyph attacks
    final homoglyphResult = _detectHomoglyphAttack(message.senderEmail);
    if (homoglyphResult != null) {
      score += 0.4;
      indicators.add(ImpersonationIndicator(
        type: 'homoglyph_attack',
        description: 'Email contains lookalike characters',
        weight: 0.4,
        evidence: homoglyphResult,
      ));
    }

    // 4. Check reply-to mismatch
    if (message.replyTo != null &&
        message.replyTo!.toLowerCase() != message.senderEmail.toLowerCase()) {
      final replyDomain = _extractDomain(message.replyTo!);
      final senderDomain = _extractDomain(message.senderEmail);

      if (replyDomain != senderDomain) {
        score += 0.25;
        indicators.add(ImpersonationIndicator(
          type: 'reply_to_mismatch',
          description: 'Reply-To address differs from sender',
          weight: 0.25,
          evidence: 'Sender: $senderDomain, Reply-To: $replyDomain',
        ));
      }
    }

    // 5. Analyze message content
    final contentAnalysis = _analyzeContent(message.subject, message.body);
    score += contentAnalysis.score;
    indicators.addAll(contentAnalysis.indicators);

    // 6. Determine attack type based on indicators
    attackType = _determineAttackType(indicators, message.body);

    // 7. High-value executive bonus
    if (impersonatedExec?.isHighValue == true) {
      score += 0.1;
      indicators.add(ImpersonationIndicator(
        type: 'high_value_target',
        description: 'Impersonating high-value executive (${impersonatedExec!.title ?? "C-level"})',
        weight: 0.1,
      ));
    }

    // Normalize score
    score = score.clamp(0.0, 1.0);

    // Determine risk level
    String riskLevel;
    if (score >= 0.8) {
      riskLevel = 'critical';
    } else if (score >= 0.6) {
      riskLevel = 'high';
    } else if (score >= 0.4) {
      riskLevel = 'medium';
    } else if (score >= 0.2) {
      riskLevel = 'low';
    } else {
      riskLevel = 'safe';
    }

    // Generate recommendation
    final recommendation = _generateRecommendation(score, indicators, impersonatedExec);

    final result = ImpersonationResult(
      isImpersonation: score >= 0.5,
      confidenceScore: score,
      riskLevel: riskLevel,
      impersonatedExecutive: impersonatedExec,
      indicators: indicators,
      recommendation: recommendation,
      type: attackType,
    );

    // Emit alert if impersonation detected
    if (result.isImpersonation) {
      _alertController.add(result);
    }

    return result;
  }

  /// Find executive by sender name
  ExecutiveProfile? _findExecutiveByName(String senderName) {
    final normalizedName = senderName.toLowerCase().trim();

    for (final exec in _executives.values) {
      for (final variation in exec.allNameVariations) {
        if (normalizedName.contains(variation) || variation.contains(normalizedName)) {
          return exec;
        }
      }
    }

    return null;
  }

  /// Extract domain from email
  String _extractDomain(String email) {
    final parts = email.toLowerCase().split('@');
    return parts.length == 2 ? parts[1] : '';
  }

  /// Detect lookalike domains
  String? _detectLookalikeDomain(String email) {
    final senderDomain = _extractDomain(email);

    for (final corpDomain in _corporateDomains) {
      // Check for common typosquatting patterns
      if (_isLookalikeDomain(senderDomain, corpDomain)) {
        return corpDomain;
      }
    }

    return null;
  }

  /// Check if two domains are lookalikes
  bool _isLookalikeDomain(String suspicious, String legitimate) {
    if (suspicious == legitimate) return false;

    // Calculate Levenshtein distance
    final distance = _levenshteinDistance(suspicious, legitimate);

    // Very similar domains (1-2 character difference)
    if (distance <= 2 && distance > 0) {
      return true;
    }

    // Check for common substitutions
    final patterns = [
      // Character swaps: google -> gooogle, amazzon
      RegExp(r'(.)\1'),
      // Missing/extra characters
      // Domain suffix changes: .com -> .co, .net
    ];

    // Check for subdomain tricks: company.com vs company.com.attacker.com
    if (suspicious.contains(legitimate) || legitimate.contains(suspicious)) {
      return true;
    }

    // Check for hyphen tricks: company.com vs company-security.com
    final legitBase = legitimate.split('.').first;
    if (suspicious.startsWith('$legitBase-') || suspicious.startsWith('$legitBase.')) {
      return true;
    }

    return false;
  }

  /// Calculate Levenshtein distance
  int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;

      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce((a, b) => a < b ? a : b);
      }

      final temp = v0;
      v0 = v1;
      v1 = temp;
    }

    return v0[s2.length];
  }

  /// Detect homoglyph attacks
  String? _detectHomoglyphAttack(String email) {
    final domain = _extractDomain(email);

    for (final char in domain.split('')) {
      // Check if character is a known homoglyph
      for (final entry in _homoglyphMap.entries) {
        if (entry.value.contains(char)) {
          return 'Character "$char" may be impersonating "${entry.key}"';
        }
      }

      // Check for non-ASCII characters in domain
      if (char.codeUnitAt(0) > 127) {
        return 'Domain contains non-ASCII character: $char';
      }
    }

    return null;
  }

  /// Analyze message content
  _ContentAnalysis _analyzeContent(String subject, String body) {
    double score = 0.0;
    final indicators = <ImpersonationIndicator>[];
    final fullText = '$subject $body';

    // Check urgency patterns
    int urgencyCount = 0;
    for (final pattern in _urgencyPatterns) {
      if (pattern.hasMatch(fullText)) {
        urgencyCount++;
      }
    }
    if (urgencyCount > 0) {
      final urgencyScore = (urgencyCount * 0.05).clamp(0.0, 0.2);
      score += urgencyScore;
      indicators.add(ImpersonationIndicator(
        type: 'urgency_language',
        description: 'Message contains urgency/pressure language',
        weight: urgencyScore,
        evidence: 'Found $urgencyCount urgency indicators',
      ));
    }

    // Check payment patterns
    int paymentCount = 0;
    for (final pattern in _paymentPatterns) {
      if (pattern.hasMatch(fullText)) {
        paymentCount++;
      }
    }
    if (paymentCount > 0) {
      final paymentScore = (paymentCount * 0.08).clamp(0.0, 0.3);
      score += paymentScore;
      indicators.add(ImpersonationIndicator(
        type: 'payment_request',
        description: 'Message discusses financial transactions',
        weight: paymentScore,
        evidence: 'Found $paymentCount payment-related terms',
      ));
    }

    // Check secrecy patterns
    int secrecyCount = 0;
    for (final pattern in _secrecyPatterns) {
      if (pattern.hasMatch(fullText)) {
        secrecyCount++;
      }
    }
    if (secrecyCount > 0) {
      final secrecyScore = (secrecyCount * 0.1).clamp(0.0, 0.25);
      score += secrecyScore;
      indicators.add(ImpersonationIndicator(
        type: 'secrecy_request',
        description: 'Message requests confidentiality/secrecy',
        weight: secrecyScore,
        evidence: 'Found $secrecyCount secrecy indicators',
      ));
    }

    // Check data request patterns
    int dataCount = 0;
    for (final pattern in _dataRequestPatterns) {
      if (pattern.hasMatch(fullText)) {
        dataCount++;
      }
    }
    if (dataCount > 0) {
      final dataScore = (dataCount * 0.1).clamp(0.0, 0.25);
      score += dataScore;
      indicators.add(ImpersonationIndicator(
        type: 'data_request',
        description: 'Message requests sensitive information',
        weight: dataScore,
        evidence: 'Found $dataCount data request indicators',
      ));
    }

    // Check for gift card mentions (common scam)
    if (RegExp(r'\b(gift card|itunes|google play|amazon card)\b', caseSensitive: false).hasMatch(fullText)) {
      score += 0.35;
      indicators.add(ImpersonationIndicator(
        type: 'gift_card_request',
        description: 'Message mentions gift cards (common BEC indicator)',
        weight: 0.35,
      ));
    }

    return _ContentAnalysis(score: score, indicators: indicators);
  }

  /// Determine attack type
  ImpersonationType _determineAttackType(List<ImpersonationIndicator> indicators, String body) {
    final types = indicators.map((i) => i.type).toSet();

    if (types.contains('gift_card_request')) {
      return ImpersonationType.giftCardScam;
    }

    if (types.contains('data_request')) {
      if (RegExp(r'\b(w-?2|tax|ssn|social security)\b', caseSensitive: false).hasMatch(body)) {
        return ImpersonationType.w2Scam;
      }
      return ImpersonationType.dataTheft;
    }

    if (types.contains('payment_request')) {
      if (RegExp(r'\b(vendor|supplier|invoice)\b', caseSensitive: false).hasMatch(body)) {
        return ImpersonationType.vendorFraud;
      }
      if (RegExp(r'\b(attorney|lawyer|legal)\b', caseSensitive: false).hasMatch(body)) {
        return ImpersonationType.attorneyFraud;
      }
      return ImpersonationType.ceoFraud;
    }

    return ImpersonationType.unknown;
  }

  /// Generate recommendation
  String _generateRecommendation(
    double score,
    List<ImpersonationIndicator> indicators,
    ExecutiveProfile? impersonatedExec,
  ) {
    if (score >= 0.8) {
      return 'HIGH RISK: This message appears to be an impersonation attack. '
          'Do NOT respond, click links, or take any requested actions. '
          'Contact ${impersonatedExec?.name ?? "the claimed sender"} directly through a known, verified channel.';
    } else if (score >= 0.6) {
      return 'CAUTION: This message has strong indicators of impersonation. '
          'Verify the sender\'s identity through a separate communication channel before proceeding.';
    } else if (score >= 0.4) {
      return 'WARNING: This message has some suspicious characteristics. '
          'Be cautious and verify any sensitive requests through official channels.';
    } else if (score >= 0.2) {
      return 'LOW RISK: Minor warning signs detected. Exercise normal caution.';
    } else {
      return 'This message appears legitimate.';
    }
  }

  /// Bulk import executives from organization directory
  Future<int> importFromDirectory(List<Map<String, dynamic>> directory) async {
    int imported = 0;

    for (final entry in directory) {
      try {
        final profile = ExecutiveProfile.fromJson(entry);
        addExecutive(profile);
        imported++;
      } catch (e) {
        debugPrint('Failed to import executive: $e');
      }
    }

    return imported;
  }

  /// Get protection statistics
  Map<String, dynamic> getStatistics() {
    return {
      'executives_monitored': _executives.length,
      'corporate_domains': _corporateDomains.length,
      'high_value_executives': _executives.values.where((e) => e.isHighValue).length,
    };
  }

  /// Dispose resources
  void dispose() {
    _alertController.close();
  }
}

/// Content analysis result
class _ContentAnalysis {
  final double score;
  final List<ImpersonationIndicator> indicators;

  _ContentAnalysis({required this.score, required this.indicators});
}
