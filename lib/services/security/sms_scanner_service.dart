/// SMS Scanner Service
///
/// Native Android SMS scanning and protection:
/// - Real-time SMS monitoring
/// - Scam message detection
/// - Phishing link detection
/// - Spam filtering
/// - Message categorization
/// - Threat notifications

import 'dart:async';
import 'package:flutter/services.dart';

/// SMS message threat level
enum SMSThreatLevel {
  safe('Safe', 'No threats detected', 0),
  suspicious('Suspicious', 'Potentially suspicious content', 1),
  dangerous('Dangerous', 'Likely scam or phishing', 2),
  critical('Critical', 'Confirmed threat', 3);

  final String displayName;
  final String description;
  final int severity;

  const SMSThreatLevel(this.displayName, this.description, this.severity);
}

/// SMS message category
enum SMSCategory {
  personal('Personal', 'Personal messages'),
  transactional('Transactional', 'Bank, delivery, OTP'),
  promotional('Promotional', 'Marketing messages'),
  spam('Spam', 'Unwanted messages'),
  scam('Scam', 'Fraudulent messages'),
  phishing('Phishing', 'Credential theft attempts');

  final String displayName;
  final String description;

  const SMSCategory(this.displayName, this.description);
}

/// Scanned SMS message
class ScannedSMS {
  final String id;
  final String sender;
  final String body;
  final DateTime timestamp;
  final SMSThreatLevel threatLevel;
  final SMSCategory category;
  final List<String> detectedThreats;
  final List<String> extractedUrls;
  final Map<String, dynamic> analysis;
  final bool isBlocked;

  ScannedSMS({
    required this.id,
    required this.sender,
    required this.body,
    required this.timestamp,
    required this.threatLevel,
    required this.category,
    this.detectedThreats = const [],
    this.extractedUrls = const [],
    this.analysis = const {},
    this.isBlocked = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'sender': sender,
    'body': body,
    'timestamp': timestamp.toIso8601String(),
    'threat_level': threatLevel.name,
    'category': category.name,
    'detected_threats': detectedThreats,
    'extracted_urls': extractedUrls,
    'analysis': analysis,
    'is_blocked': isBlocked,
  };

  factory ScannedSMS.fromJson(Map<String, dynamic> json) {
    return ScannedSMS(
      id: json['id'] as String,
      sender: json['sender'] as String,
      body: json['body'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      threatLevel: SMSThreatLevel.values.firstWhere(
        (t) => t.name == json['threat_level'],
        orElse: () => SMSThreatLevel.safe,
      ),
      category: SMSCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => SMSCategory.personal,
      ),
      detectedThreats: (json['detected_threats'] as List<dynamic>?)?.cast<String>() ?? [],
      extractedUrls: (json['extracted_urls'] as List<dynamic>?)?.cast<String>() ?? [],
      analysis: json['analysis'] as Map<String, dynamic>? ?? {},
      isBlocked: json['is_blocked'] as bool? ?? false,
    );
  }
}

/// SMS scan statistics
class SMSScanStats {
  final int totalScanned;
  final int safeCount;
  final int suspiciousCount;
  final int dangerousCount;
  final int blockedCount;
  final DateTime? lastScanTime;
  final Map<SMSCategory, int> byCategory;

  SMSScanStats({
    this.totalScanned = 0,
    this.safeCount = 0,
    this.suspiciousCount = 0,
    this.dangerousCount = 0,
    this.blockedCount = 0,
    this.lastScanTime,
    this.byCategory = const {},
  });
}

/// SMS Scanner Service
class SMSScannerService {
  static const _channel = MethodChannel('com.orbvpn.orbguard/sms_scanner');
  static const _eventChannel = EventChannel('com.orbvpn.orbguard/sms_events');

  final List<ScannedSMS> _scannedMessages = [];
  final Set<String> _blockedSenders = {};
  final Set<String> _trustedSenders = {};

  StreamSubscription? _smsSubscription;
  final _scanController = StreamController<ScannedSMS>.broadcast();
  final _statsController = StreamController<SMSScanStats>.broadcast();

  Stream<ScannedSMS> get scanStream => _scanController.stream;
  Stream<SMSScanStats> get statsStream => _statsController.stream;

  bool _isMonitoring = false;
  bool get isMonitoring => _isMonitoring;

  // Scam patterns
  static const _scamPatterns = [
    // Urgency patterns
    r'urgent|immediately|act now|expires today|last chance',
    // Money/prize patterns
    r'won|winner|prize|lottery|jackpot|cash|reward',
    r'free\s+(gift|money|iphone|samsung)',
    // Banking fraud
    r'account\s+(suspended|locked|compromised|unusual)',
    r'verify\s+(your\s+)?(account|identity|payment)',
    r'update\s+(your\s+)?(payment|card|banking)',
    // Delivery scams
    r'package\s+(held|pending|failed)',
    r'delivery\s+(failed|pending|reschedule)',
    r'customs\s+(fee|charge|payment)',
    // Government impersonation
    r'(irs|tax|social\s+security)\s+(refund|payment|owes)',
    // Tech support scams
    r'(virus|malware|hacked)\s+detected',
    r'(apple|microsoft|google)\s+support',
    // Loan/investment
    r'pre-?approved\s+(loan|credit)',
    r'guaranteed\s+(returns|profit)',
    r'bitcoin|crypto\s+investment',
  ];

  // Phishing patterns
  static const _phishingPatterns = [
    r'click\s+(here|link|below)\s+to',
    r'verify\s+your\s+(account|identity)',
    r'confirm\s+(your|payment|details)',
    r'login\s+(required|now|immediately)',
    r'password\s+(expired|reset|update)',
  ];

  // URL patterns
  static final _urlPattern = RegExp(
    r'https?://[^\s]+|(?:www\.)?[a-zA-Z0-9-]+\.[a-zA-Z]{2,}(?:/[^\s]*)?',
    caseSensitive: false,
  );

  // Suspicious TLDs
  static const _suspiciousTlds = [
    '.tk', '.ml', '.ga', '.cf', '.gq', // Free TLDs often used for scams
    '.xyz', '.top', '.work', '.click', '.link',
    '.info', '.biz', '.online', '.site', '.website',
  ];

  /// Initialize the SMS scanner
  Future<void> initialize() async {
    try {
      await _channel.invokeMethod('initialize');
    } on PlatformException catch (e) {
      // Platform-specific initialization failed
      print('SMS Scanner initialization failed: ${e.message}');
    }
  }

  /// Check if SMS permission is granted
  Future<bool> hasPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasPermission');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Request SMS permission
  Future<bool> requestPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Start real-time SMS monitoring
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    try {
      await _channel.invokeMethod('startMonitoring');

      _smsSubscription = _eventChannel
          .receiveBroadcastStream()
          .map((event) => event as Map<dynamic, dynamic>)
          .listen((smsData) {
        _onSMSReceived(smsData.cast<String, dynamic>());
      });

      _isMonitoring = true;
    } on PlatformException catch (e) {
      print('Failed to start SMS monitoring: ${e.message}');
    }
  }

  /// Stop SMS monitoring
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;

    try {
      await _channel.invokeMethod('stopMonitoring');
      await _smsSubscription?.cancel();
      _smsSubscription = null;
      _isMonitoring = false;
    } on PlatformException catch (e) {
      print('Failed to stop SMS monitoring: ${e.message}');
    }
  }

  /// Handle received SMS
  void _onSMSReceived(Map<String, dynamic> smsData) {
    final sender = smsData['sender'] as String? ?? 'Unknown';
    final body = smsData['body'] as String? ?? '';
    final timestamp = smsData['timestamp'] != null
        ? DateTime.fromMillisecondsSinceEpoch(smsData['timestamp'] as int)
        : DateTime.now();

    final scannedSMS = _analyzeSMS(
      id: 'sms_${DateTime.now().millisecondsSinceEpoch}',
      sender: sender,
      body: body,
      timestamp: timestamp,
    );

    _scannedMessages.add(scannedSMS);
    _scanController.add(scannedSMS);
    _updateStats();

    // Block if dangerous and sender is blocked
    if (scannedSMS.threatLevel.severity >= SMSThreatLevel.dangerous.severity) {
      // Could trigger notification here
    }
  }

  /// Analyze a single SMS
  ScannedSMS _analyzeSMS({
    required String id,
    required String sender,
    required String body,
    required DateTime timestamp,
  }) {
    final threats = <String>[];
    final urls = _extractUrls(body);
    final analysis = <String, dynamic>{};

    // Check if sender is trusted
    if (_trustedSenders.contains(sender)) {
      return ScannedSMS(
        id: id,
        sender: sender,
        body: body,
        timestamp: timestamp,
        threatLevel: SMSThreatLevel.safe,
        category: SMSCategory.personal,
        extractedUrls: urls,
        analysis: {'trusted_sender': true},
      );
    }

    // Check if sender is blocked
    final isBlocked = _blockedSenders.contains(sender);

    // Analyze content
    var threatScore = 0.0;

    // Check for scam patterns
    for (final pattern in _scamPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(body)) {
        threats.add('Scam pattern: $pattern');
        threatScore += 0.3;
      }
    }

    // Check for phishing patterns
    for (final pattern in _phishingPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(body)) {
        threats.add('Phishing pattern: $pattern');
        threatScore += 0.4;
      }
    }

    // Analyze URLs
    for (final url in urls) {
      final urlRisk = _analyzeUrl(url);
      threatScore += urlRisk;
      if (urlRisk > 0.3) {
        threats.add('Suspicious URL: $url');
      }
    }

    // Check sender format
    final senderRisk = _analyzeSender(sender);
    threatScore += senderRisk;
    if (senderRisk > 0.2) {
      threats.add('Suspicious sender format');
    }

    // Determine threat level
    SMSThreatLevel threatLevel;
    if (threatScore >= 0.8) {
      threatLevel = SMSThreatLevel.critical;
    } else if (threatScore >= 0.5) {
      threatLevel = SMSThreatLevel.dangerous;
    } else if (threatScore >= 0.2) {
      threatLevel = SMSThreatLevel.suspicious;
    } else {
      threatLevel = SMSThreatLevel.safe;
    }

    // Categorize message
    final category = _categorizeMessage(body, sender, threatLevel);

    analysis['threat_score'] = threatScore;
    analysis['url_count'] = urls.length;
    analysis['pattern_matches'] = threats.length;

    return ScannedSMS(
      id: id,
      sender: sender,
      body: body,
      timestamp: timestamp,
      threatLevel: threatLevel,
      category: category,
      detectedThreats: threats,
      extractedUrls: urls,
      analysis: analysis,
      isBlocked: isBlocked,
    );
  }

  /// Extract URLs from message
  List<String> _extractUrls(String text) {
    return _urlPattern.allMatches(text).map((m) => m.group(0)!).toList();
  }

  /// Analyze URL for risk
  double _analyzeUrl(String url) {
    var risk = 0.0;

    // Check for IP address URLs
    if (RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}').hasMatch(url)) {
      risk += 0.4;
    }

    // Check for suspicious TLDs
    for (final tld in _suspiciousTlds) {
      if (url.toLowerCase().contains(tld)) {
        risk += 0.3;
        break;
      }
    }

    // Check for URL shorteners
    final shorteners = ['bit.ly', 'tinyurl', 'goo.gl', 't.co', 'ow.ly', 'is.gd'];
    for (final shortener in shorteners) {
      if (url.toLowerCase().contains(shortener)) {
        risk += 0.2;
        break;
      }
    }

    // Check for typosquatting of common domains
    final typosquatPatterns = [
      r'g00gle|gogle|googl\d',
      r'facebo0k|facebok|faceb00k',
      r'amaz0n|amazn|amzon',
      r'paypai|paypa1|peypal',
      r'netf1ix|netfiix|netfl1x',
    ];
    for (final pattern in typosquatPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(url)) {
        risk += 0.5;
        break;
      }
    }

    return risk.clamp(0.0, 1.0);
  }

  /// Analyze sender for risk
  double _analyzeSender(String sender) {
    var risk = 0.0;

    // Random number senders are often spam
    if (RegExp(r'^\+?\d{5,}$').hasMatch(sender)) {
      risk += 0.1;
    }

    // Very short alphanumeric senders can be spoofed
    if (sender.length <= 6 && !RegExp(r'^\d+$').hasMatch(sender)) {
      risk += 0.15;
    }

    // Check for suspicious sender names
    final suspiciousSenders = [
      'winner', 'prize', 'lottery', 'bank', 'verify', 'urgent',
      'security', 'alert', 'suspended', 'locked',
    ];
    for (final suspicious in suspiciousSenders) {
      if (sender.toLowerCase().contains(suspicious)) {
        risk += 0.2;
        break;
      }
    }

    return risk.clamp(0.0, 1.0);
  }

  /// Categorize message
  SMSCategory _categorizeMessage(
    String body,
    String sender,
    SMSThreatLevel threatLevel,
  ) {
    if (threatLevel == SMSThreatLevel.critical ||
        threatLevel == SMSThreatLevel.dangerous) {
      // Check if phishing or scam
      for (final pattern in _phishingPatterns) {
        if (RegExp(pattern, caseSensitive: false).hasMatch(body)) {
          return SMSCategory.phishing;
        }
      }
      return SMSCategory.scam;
    }

    if (threatLevel == SMSThreatLevel.suspicious) {
      return SMSCategory.spam;
    }

    // Check for transactional patterns
    final transactionalPatterns = [
      r'otp|one.?time.?password|verification.?code',
      r'order\s+(confirmed|shipped|delivered)',
      r'your\s+(package|delivery)',
      r'(bank|account)\s+balance',
      r'transaction\s+(successful|completed|failed)',
    ];
    for (final pattern in transactionalPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(body)) {
        return SMSCategory.transactional;
      }
    }

    // Check for promotional patterns
    final promotionalPatterns = [
      r'(sale|discount|offer|deal)\s',
      r'\d+%\s+off',
      r'limited\s+time',
      r'subscribe|unsubscribe',
    ];
    for (final pattern in promotionalPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(body)) {
        return SMSCategory.promotional;
      }
    }

    return SMSCategory.personal;
  }

  /// Scan all existing SMS messages
  Future<List<ScannedSMS>> scanAllMessages() async {
    try {
      final messages = await _channel.invokeMethod<List<dynamic>>('getAllMessages');
      if (messages == null) return [];

      final scannedMessages = <ScannedSMS>[];
      for (final msg in messages) {
        final msgMap = (msg as Map<dynamic, dynamic>).cast<String, dynamic>();
        final scanned = _analyzeSMS(
          id: 'sms_${msgMap['id'] ?? DateTime.now().millisecondsSinceEpoch}',
          sender: msgMap['sender'] as String? ?? 'Unknown',
          body: msgMap['body'] as String? ?? '',
          timestamp: msgMap['timestamp'] != null
              ? DateTime.fromMillisecondsSinceEpoch(msgMap['timestamp'] as int)
              : DateTime.now(),
        );
        scannedMessages.add(scanned);
      }

      _scannedMessages.addAll(scannedMessages);
      _updateStats();

      return scannedMessages;
    } on PlatformException catch (e) {
      print('Failed to scan messages: ${e.message}');
      return [];
    }
  }

  /// Analyze a single message (manual check)
  ScannedSMS analyzeMessage(String sender, String body) {
    return _analyzeSMS(
      id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
      sender: sender,
      body: body,
      timestamp: DateTime.now(),
    );
  }

  /// Block sender
  void blockSender(String sender) {
    _blockedSenders.add(sender);
    _trustedSenders.remove(sender);
  }

  /// Unblock sender
  void unblockSender(String sender) {
    _blockedSenders.remove(sender);
  }

  /// Trust sender
  void trustSender(String sender) {
    _trustedSenders.add(sender);
    _blockedSenders.remove(sender);
  }

  /// Untrust sender
  void untrustSender(String sender) {
    _trustedSenders.remove(sender);
  }

  /// Get blocked senders
  Set<String> getBlockedSenders() => Set.unmodifiable(_blockedSenders);

  /// Get trusted senders
  Set<String> getTrustedSenders() => Set.unmodifiable(_trustedSenders);

  /// Get scanned messages
  List<ScannedSMS> getScannedMessages({
    SMSThreatLevel? minThreatLevel,
    SMSCategory? category,
    int? limit,
  }) {
    var messages = _scannedMessages.where((m) {
      if (minThreatLevel != null && m.threatLevel.severity < minThreatLevel.severity) {
        return false;
      }
      if (category != null && m.category != category) {
        return false;
      }
      return true;
    }).toList();

    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (limit != null && messages.length > limit) {
      messages = messages.sublist(0, limit);
    }

    return messages;
  }

  /// Get current stats
  SMSScanStats getStats() {
    final byCategory = <SMSCategory, int>{};
    var safeCount = 0;
    var suspiciousCount = 0;
    var dangerousCount = 0;
    var blockedCount = 0;

    for (final msg in _scannedMessages) {
      byCategory[msg.category] = (byCategory[msg.category] ?? 0) + 1;

      switch (msg.threatLevel) {
        case SMSThreatLevel.safe:
          safeCount++;
          break;
        case SMSThreatLevel.suspicious:
          suspiciousCount++;
          break;
        case SMSThreatLevel.dangerous:
        case SMSThreatLevel.critical:
          dangerousCount++;
          break;
      }

      if (msg.isBlocked) blockedCount++;
    }

    return SMSScanStats(
      totalScanned: _scannedMessages.length,
      safeCount: safeCount,
      suspiciousCount: suspiciousCount,
      dangerousCount: dangerousCount,
      blockedCount: blockedCount,
      lastScanTime: _scannedMessages.isNotEmpty
          ? _scannedMessages.last.timestamp
          : null,
      byCategory: byCategory,
    );
  }

  void _updateStats() {
    _statsController.add(getStats());
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _scanController.close();
    _statsController.close();
  }
}
