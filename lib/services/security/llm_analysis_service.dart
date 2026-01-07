/// LLM-Powered Analysis Service
///
/// Uses Large Language Models for advanced threat analysis:
/// - Natural language understanding of messages
/// - Context-aware scam detection
/// - Intent extraction and classification
/// - Semantic similarity for phishing detection
/// - Explanation generation for detected threats
/// - Multi-language support

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// LLM analysis request
class LLMAnalysisRequest {
  final String text;
  final AnalysisType type;
  final String? context;
  final String? language;
  final Map<String, dynamic>? metadata;

  LLMAnalysisRequest({
    required this.text,
    required this.type,
    this.context,
    this.language,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'type': type.name,
    'context': context,
    'language': language,
    'metadata': metadata,
  };
}

/// Types of LLM analysis
enum AnalysisType {
  scamDetection('Scam Detection', 'Analyze text for scam/fraud indicators'),
  phishingAnalysis('Phishing Analysis', 'Detect phishing attempts'),
  intentExtraction('Intent Extraction', 'Extract sender intent'),
  entityRecognition('Entity Recognition', 'Extract entities like names, amounts'),
  sentimentAnalysis('Sentiment Analysis', 'Analyze emotional tone'),
  urgencyDetection('Urgency Detection', 'Detect pressure/urgency tactics'),
  impersonationCheck('Impersonation Check', 'Check for identity spoofing'),
  explanationGeneration('Explanation', 'Generate threat explanation');

  final String displayName;
  final String description;
  const AnalysisType(this.displayName, this.description);
}

/// LLM analysis result
class LLMAnalysisResult {
  final bool isThreat;
  final double confidenceScore;
  final String threatType;
  final String explanation;
  final List<ExtractedEntity> entities;
  final List<String> indicators;
  final String? suggestedAction;
  final Map<String, double> categoryScores;
  final String modelUsed;
  final int processingTimeMs;

  LLMAnalysisResult({
    required this.isThreat,
    required this.confidenceScore,
    required this.threatType,
    required this.explanation,
    required this.entities,
    required this.indicators,
    this.suggestedAction,
    required this.categoryScores,
    required this.modelUsed,
    required this.processingTimeMs,
  });

  factory LLMAnalysisResult.fromJson(Map<String, dynamic> json) {
    return LLMAnalysisResult(
      isThreat: json['is_threat'] as bool? ?? false,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0.0,
      threatType: json['threat_type'] as String? ?? 'unknown',
      explanation: json['explanation'] as String? ?? '',
      entities: (json['entities'] as List<dynamic>?)
          ?.map((e) => ExtractedEntity.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      indicators: (json['indicators'] as List<dynamic>?)?.cast<String>() ?? [],
      suggestedAction: json['suggested_action'] as String?,
      categoryScores: (json['category_scores'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ?? {},
      modelUsed: json['model_used'] as String? ?? 'unknown',
      processingTimeMs: json['processing_time_ms'] as int? ?? 0,
    );
  }
}

/// Extracted entity from text
class ExtractedEntity {
  final String text;
  final String type;
  final double confidence;
  final int startIndex;
  final int endIndex;
  final Map<String, dynamic>? metadata;

  ExtractedEntity({
    required this.text,
    required this.type,
    required this.confidence,
    required this.startIndex,
    required this.endIndex,
    this.metadata,
  });

  factory ExtractedEntity.fromJson(Map<String, dynamic> json) {
    return ExtractedEntity(
      text: json['text'] as String,
      type: json['type'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      startIndex: json['start_index'] as int? ?? 0,
      endIndex: json['end_index'] as int? ?? 0,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Conversation context for multi-turn analysis
class ConversationContext {
  final String id;
  final List<ConversationMessage> messages;
  final Map<String, dynamic> metadata;
  final DateTime startTime;

  ConversationContext({
    required this.id,
    this.messages = const [],
    this.metadata = const {},
    DateTime? startTime,
  }) : startTime = startTime ?? DateTime.now();

  void addMessage(ConversationMessage message) {
    messages.add(message);
  }
}

/// Message in conversation
class ConversationMessage {
  final String role; // 'user', 'assistant', 'system'
  final String content;
  final DateTime timestamp;

  ConversationMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// LLM Analysis Service
class LLMAnalysisService {
  // API configuration
  static const String _apiBaseUrl = 'https://api.orbguard.io/v1/llm';
  String? _apiKey;

  // Caching
  final Map<String, LLMAnalysisResult> _cache = {};
  static const int _maxCacheSize = 100;
  static const Duration _cacheTTL = Duration(hours: 1);

  // Rate limiting
  int _requestCount = 0;
  DateTime _rateLimitReset = DateTime.now();
  static const int _maxRequestsPerMinute = 60;

  // Conversation contexts
  final Map<String, ConversationContext> _contexts = {};

  // Stream controllers
  final _analysisResultController = StreamController<LLMAnalysisResult>.broadcast();

  /// Stream of analysis results
  Stream<LLMAnalysisResult> get onAnalysisResult => _analysisResultController.stream;

  /// Initialize the service
  Future<void> initialize({String? apiKey}) async {
    _apiKey = apiKey;
  }

  /// Analyze text for threats using LLM
  Future<LLMAnalysisResult> analyzeText(
    String text, {
    AnalysisType type = AnalysisType.scamDetection,
    String? context,
    String? language,
    bool useCache = true,
  }) async {
    // Check cache
    final cacheKey = _generateCacheKey(text, type);
    if (useCache && _cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      return cached;
    }

    // Check rate limit
    await _checkRateLimit();

    final startTime = DateTime.now();

    try {
      // Try API first
      if (_apiKey != null) {
        final result = await _analyzeWithAPI(text, type, context, language);
        _cacheResult(cacheKey, result);
        _analysisResultController.add(result);
        return result;
      }

      // Fallback to local analysis
      final result = await _analyzeLocally(text, type, startTime);
      _cacheResult(cacheKey, result);
      _analysisResultController.add(result);
      return result;
    } catch (e) {
      debugPrint('LLM analysis error: $e');
      // Fallback to local analysis on error
      return _analyzeLocally(text, type, startTime);
    }
  }

  /// Analyze using cloud API
  Future<LLMAnalysisResult> _analyzeWithAPI(
    String text,
    AnalysisType type,
    String? context,
    String? language,
  ) async {
    final response = await http.post(
      Uri.parse('$_apiBaseUrl/analyze'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: json.encode({
        'text': text,
        'analysis_type': type.name,
        'context': context,
        'language': language ?? 'en',
        'include_entities': true,
        'include_explanation': true,
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return LLMAnalysisResult.fromJson(data);
    } else {
      throw Exception('API error: ${response.statusCode}');
    }
  }

  /// Local analysis using patterns and heuristics
  Future<LLMAnalysisResult> _analyzeLocally(
    String text,
    AnalysisType type,
    DateTime startTime,
  ) async {
    double score = 0.0;
    final indicators = <String>[];
    final entities = <ExtractedEntity>[];
    final categoryScores = <String, double>{};
    String threatType = 'none';

    switch (type) {
      case AnalysisType.scamDetection:
        final scamResult = _detectScamPatterns(text);
        score = scamResult.score;
        indicators.addAll(scamResult.indicators);
        categoryScores.addAll(scamResult.categories);
        threatType = scamResult.primaryCategory;
        break;

      case AnalysisType.intentExtraction:
        final intentResult = _extractIntent(text);
        score = intentResult.confidence;
        indicators.add('Detected intent: ${intentResult.intent}');
        categoryScores['intent_${intentResult.intent}'] = intentResult.confidence;
        break;

      case AnalysisType.entityRecognition:
        entities.addAll(_extractEntities(text));
        score = entities.isNotEmpty ? 0.8 : 0.2;
        break;

      case AnalysisType.urgencyDetection:
        final urgencyResult = _detectUrgency(text);
        score = urgencyResult.score;
        indicators.addAll(urgencyResult.indicators);
        break;

      default:
        // Generic analysis
        final genericResult = _genericAnalysis(text);
        score = genericResult.score;
        indicators.addAll(genericResult.indicators);
    }

    final processingTime = DateTime.now().difference(startTime).inMilliseconds;

    return LLMAnalysisResult(
      isThreat: score >= 0.5,
      confidenceScore: score,
      threatType: threatType,
      explanation: _generateExplanation(score, indicators, threatType),
      entities: entities,
      indicators: indicators,
      suggestedAction: _getSuggestedAction(score, threatType),
      categoryScores: categoryScores,
      modelUsed: 'local_heuristics',
      processingTimeMs: processingTime,
    );
  }

  /// Detect scam patterns
  _ScamAnalysis _detectScamPatterns(String text) {
    double score = 0.0;
    final indicators = <String>[];
    final categories = <String, double>{};
    String primaryCategory = 'unknown';

    final patterns = {
      'financial_scam': [
        RegExp(r'\b(bank|account|wire|transfer|payment|credit card)\b', caseSensitive: false),
        RegExp(r'\b(verify|confirm|update|suspend)\s+(your|account)\b', caseSensitive: false),
      ],
      'lottery_scam': [
        RegExp(r'\b(won|winner|prize|lottery|claim|congratulations)\b', caseSensitive: false),
        RegExp(r'\b(selected|chosen|lucky)\b', caseSensitive: false),
      ],
      'urgency_scam': [
        RegExp(r'\b(urgent|immediately|asap|expire|limited time)\b', caseSensitive: false),
        RegExp(r'\b(act now|don\'t wait|hurry)\b', caseSensitive: false),
      ],
      'impersonation': [
        RegExp(r'\b(ceo|cfo|director|manager|hr|it department)\b', caseSensitive: false),
        RegExp(r'\b(on behalf of|representing|from the office)\b', caseSensitive: false),
      ],
      'tech_support': [
        RegExp(r'\b(virus|infected|hacked|compromised)\b', caseSensitive: false),
        RegExp(r'\b(call us|tech support|microsoft|apple)\b', caseSensitive: false),
      ],
      'investment_scam': [
        RegExp(r'\b(invest|bitcoin|crypto|trading|profit|returns)\b', caseSensitive: false),
        RegExp(r'\b(guaranteed|double|triple|opportunity)\b', caseSensitive: false),
      ],
    };

    double maxCategoryScore = 0.0;

    for (final entry in patterns.entries) {
      double categoryScore = 0.0;
      for (final pattern in entry.value) {
        final matches = pattern.allMatches(text);
        if (matches.isNotEmpty) {
          categoryScore += 0.15 * matches.length;
          indicators.add('${entry.key}: ${matches.first.group(0)}');
        }
      }
      categoryScore = categoryScore.clamp(0.0, 1.0);
      categories[entry.key] = categoryScore;

      if (categoryScore > maxCategoryScore) {
        maxCategoryScore = categoryScore;
        primaryCategory = entry.key;
      }

      score += categoryScore * 0.2;
    }

    // Check for URLs
    final urlPattern = RegExp(r'https?://[^\s]+');
    if (urlPattern.hasMatch(text)) {
      score += 0.1;
      indicators.add('Contains URL');
    }

    // Check for phone numbers
    final phonePattern = RegExp(r'\+?[\d\s\-\(\)]{10,}');
    if (phonePattern.hasMatch(text)) {
      score += 0.05;
      indicators.add('Contains phone number');
    }

    return _ScamAnalysis(
      score: score.clamp(0.0, 1.0),
      indicators: indicators,
      categories: categories,
      primaryCategory: primaryCategory,
    );
  }

  /// Extract intent from text
  _IntentResult _extractIntent(String text) {
    final intents = {
      'request_money': RegExp(r'\b(send|transfer|pay|wire)\s+(money|\$|dollars|funds)\b', caseSensitive: false),
      'request_info': RegExp(r'\b(send|provide|share|give)\s+(your|me|us).*(info|data|details|password|ssn)\b', caseSensitive: false),
      'create_urgency': RegExp(r'\b(urgent|immediately|asap|now|hurry|expire)\b', caseSensitive: false),
      'offer_prize': RegExp(r'\b(won|winner|prize|reward|claim)\b', caseSensitive: false),
      'threaten': RegExp(r'\b(arrest|legal action|suspend|terminate|close)\b', caseSensitive: false),
      'verify_identity': RegExp(r'\b(verify|confirm|validate)\s+(your|identity|account)\b', caseSensitive: false),
    };

    String detectedIntent = 'unknown';
    double confidence = 0.3;

    for (final entry in intents.entries) {
      if (entry.value.hasMatch(text)) {
        detectedIntent = entry.key;
        confidence = 0.8;
        break;
      }
    }

    return _IntentResult(intent: detectedIntent, confidence: confidence);
  }

  /// Extract entities from text
  List<ExtractedEntity> _extractEntities(String text) {
    final entities = <ExtractedEntity>[];

    // Extract monetary amounts
    final moneyPattern = RegExp(r'\$[\d,]+(\.\d{2})?|\b\d+\s*(dollars|usd|euros|gbp)\b', caseSensitive: false);
    for (final match in moneyPattern.allMatches(text)) {
      entities.add(ExtractedEntity(
        text: match.group(0)!,
        type: 'MONEY',
        confidence: 0.9,
        startIndex: match.start,
        endIndex: match.end,
      ));
    }

    // Extract URLs
    final urlPattern = RegExp(r'https?://[^\s]+');
    for (final match in urlPattern.allMatches(text)) {
      entities.add(ExtractedEntity(
        text: match.group(0)!,
        type: 'URL',
        confidence: 0.95,
        startIndex: match.start,
        endIndex: match.end,
      ));
    }

    // Extract email addresses
    final emailPattern = RegExp(r'\b[\w.+-]+@[\w.-]+\.\w{2,}\b');
    for (final match in emailPattern.allMatches(text)) {
      entities.add(ExtractedEntity(
        text: match.group(0)!,
        type: 'EMAIL',
        confidence: 0.95,
        startIndex: match.start,
        endIndex: match.end,
      ));
    }

    // Extract phone numbers
    final phonePattern = RegExp(r'\+?[\d\s\-\(\)]{10,15}');
    for (final match in phonePattern.allMatches(text)) {
      entities.add(ExtractedEntity(
        text: match.group(0)!,
        type: 'PHONE',
        confidence: 0.85,
        startIndex: match.start,
        endIndex: match.end,
      ));
    }

    // Extract dates
    final datePattern = RegExp(r'\b\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}\b');
    for (final match in datePattern.allMatches(text)) {
      entities.add(ExtractedEntity(
        text: match.group(0)!,
        type: 'DATE',
        confidence: 0.8,
        startIndex: match.start,
        endIndex: match.end,
      ));
    }

    return entities;
  }

  /// Detect urgency in text
  _UrgencyAnalysis _detectUrgency(String text) {
    double score = 0.0;
    final indicators = <String>[];

    final urgencyPatterns = [
      (RegExp(r'\b(urgent|urgently|emergency)\b', caseSensitive: false), 0.3, 'Urgency keyword'),
      (RegExp(r'\b(immediately|right away|asap|now)\b', caseSensitive: false), 0.25, 'Immediate action'),
      (RegExp(r'\b(expire|expires|expiring|deadline)\b', caseSensitive: false), 0.2, 'Time pressure'),
      (RegExp(r'\b(limited time|act fast|don\'t wait)\b', caseSensitive: false), 0.25, 'Scarcity tactic'),
      (RegExp(r'\b(last chance|final notice|final warning)\b', caseSensitive: false), 0.3, 'Finality pressure'),
      (RegExp(r'!!!|!!!|\?\?\?', caseSensitive: false), 0.1, 'Excessive punctuation'),
      (RegExp(r'\b[A-Z]{4,}\b'), 0.1, 'Shouting (all caps)'),
    ];

    for (final pattern in urgencyPatterns) {
      if (pattern.$1.hasMatch(text)) {
        score += pattern.$2;
        indicators.add(pattern.$3);
      }
    }

    return _UrgencyAnalysis(
      score: score.clamp(0.0, 1.0),
      indicators: indicators,
    );
  }

  /// Generic analysis
  _GenericAnalysis _genericAnalysis(String text) {
    double score = 0.0;
    final indicators = <String>[];

    // Check text length
    if (text.length < 20) {
      indicators.add('Very short message');
    } else if (text.length > 1000) {
      indicators.add('Very long message');
      score += 0.1;
    }

    // Check for suspicious patterns
    if (text.contains(RegExp(r'https?://'))) {
      score += 0.15;
      indicators.add('Contains URL');
    }

    if (text.contains(RegExp(r'\$\d+'))) {
      score += 0.1;
      indicators.add('Contains monetary amount');
    }

    return _GenericAnalysis(score: score, indicators: indicators);
  }

  /// Generate explanation for the analysis
  String _generateExplanation(double score, List<String> indicators, String threatType) {
    if (score >= 0.8) {
      return 'This message shows strong indicators of a $threatType. '
          'Key warning signs: ${indicators.take(3).join(", ")}. '
          'Do not respond or click any links.';
    } else if (score >= 0.5) {
      return 'This message has suspicious characteristics suggesting possible $threatType. '
          'Warning signs include: ${indicators.take(2).join(", ")}. '
          'Exercise caution.';
    } else if (score >= 0.3) {
      return 'This message has some minor warning signs but appears mostly legitimate. '
          'Noted: ${indicators.isNotEmpty ? indicators.first : "General caution advised"}.';
    } else {
      return 'This message appears to be legitimate with no significant threat indicators detected.';
    }
  }

  /// Get suggested action based on analysis
  String? _getSuggestedAction(double score, String threatType) {
    if (score >= 0.8) {
      return 'Block sender and report as $threatType';
    } else if (score >= 0.5) {
      return 'Mark as suspicious and verify sender identity';
    } else if (score >= 0.3) {
      return 'Review carefully before responding';
    }
    return null;
  }

  /// Multi-turn conversation analysis
  Future<LLMAnalysisResult> analyzeConversation(
    String conversationId,
    String newMessage, {
    String role = 'user',
  }) async {
    // Get or create context
    final context = _contexts.putIfAbsent(
      conversationId,
      () => ConversationContext(id: conversationId),
    );

    // Add new message
    context.addMessage(ConversationMessage(role: role, content: newMessage));

    // Build conversation context string
    final contextString = context.messages
        .map((m) => '${m.role}: ${m.content}')
        .join('\n');

    // Analyze with context
    return analyzeText(
      newMessage,
      type: AnalysisType.scamDetection,
      context: contextString,
    );
  }

  /// Batch analyze multiple texts
  Future<List<LLMAnalysisResult>> batchAnalyze(
    List<String> texts, {
    AnalysisType type = AnalysisType.scamDetection,
  }) async {
    final results = <LLMAnalysisResult>[];

    for (final text in texts) {
      final result = await analyzeText(text, type: type);
      results.add(result);
    }

    return results;
  }

  /// Check rate limit
  Future<void> _checkRateLimit() async {
    if (DateTime.now().isAfter(_rateLimitReset)) {
      _requestCount = 0;
      _rateLimitReset = DateTime.now().add(const Duration(minutes: 1));
    }

    if (_requestCount >= _maxRequestsPerMinute) {
      final waitTime = _rateLimitReset.difference(DateTime.now());
      await Future.delayed(waitTime);
      _requestCount = 0;
    }

    _requestCount++;
  }

  /// Generate cache key
  String _generateCacheKey(String text, AnalysisType type) {
    final hash = text.hashCode.toString();
    return '${type.name}_$hash';
  }

  /// Cache result
  void _cacheResult(String key, LLMAnalysisResult result) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = result;
  }

  /// Clear conversation context
  void clearContext(String conversationId) {
    _contexts.remove(conversationId);
  }

  /// Get service statistics
  Map<String, dynamic> getStatistics() {
    return {
      'cached_results': _cache.length,
      'active_conversations': _contexts.length,
      'requests_this_minute': _requestCount,
      'api_configured': _apiKey != null,
    };
  }

  /// Dispose resources
  void dispose() {
    _analysisResultController.close();
    _cache.clear();
    _contexts.clear();
  }
}

// Helper classes
class _ScamAnalysis {
  final double score;
  final List<String> indicators;
  final Map<String, double> categories;
  final String primaryCategory;

  _ScamAnalysis({
    required this.score,
    required this.indicators,
    required this.categories,
    required this.primaryCategory,
  });
}

class _IntentResult {
  final String intent;
  final double confidence;

  _IntentResult({required this.intent, required this.confidence});
}

class _UrgencyAnalysis {
  final double score;
  final List<String> indicators;

  _UrgencyAnalysis({required this.score, required this.indicators});
}

class _GenericAnalysis {
  final double score;
  final List<String> indicators;

  _GenericAnalysis({required this.score, required this.indicators});
}
