/// TFLite ML Service
///
/// On-device machine learning using TensorFlow Lite:
/// - Scam message classification
/// - URL risk scoring
/// - App behavior analysis
/// - Image classification (screenshots)
/// - Intent detection

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// ML model type
enum MLModelType {
  scamClassifier('scam_classifier', 'Scam Message Detection'),
  urlClassifier('url_classifier', 'URL Risk Scoring'),
  appRiskClassifier('app_risk', 'App Risk Assessment'),
  imageClassifier('image_classifier', 'Screenshot Analysis'),
  intentClassifier('intent_model', 'Intent Detection');

  final String modelName;
  final String description;

  const MLModelType(this.modelName, this.description);
}

/// Prediction result
class PredictionResult {
  final MLModelType modelType;
  final String label;
  final double confidence;
  final Map<String, double> allScores;
  final Duration inferenceTime;

  PredictionResult({
    required this.modelType,
    required this.label,
    required this.confidence,
    this.allScores = const {},
    required this.inferenceTime,
  });

  bool get isHighConfidence => confidence >= 0.8;
  bool get isMediumConfidence => confidence >= 0.5 && confidence < 0.8;
  bool get isLowConfidence => confidence < 0.5;

  Map<String, dynamic> toJson() => {
    'model_type': modelType.name,
    'label': label,
    'confidence': confidence,
    'all_scores': allScores,
    'inference_time_ms': inferenceTime.inMilliseconds,
  };
}

/// Text classification result
class TextClassificationResult extends PredictionResult {
  final String text;
  final List<String> tokens;
  final Map<String, double> featureImportance;

  TextClassificationResult({
    required super.modelType,
    required super.label,
    required super.confidence,
    super.allScores,
    required super.inferenceTime,
    required this.text,
    this.tokens = const [],
    this.featureImportance = const {},
  });
}

/// URL classification result
class URLClassificationResult extends PredictionResult {
  final String url;
  final Map<String, dynamic> urlFeatures;

  URLClassificationResult({
    required super.modelType,
    required super.label,
    required super.confidence,
    super.allScores,
    required super.inferenceTime,
    required this.url,
    this.urlFeatures = const {},
  });

  bool get isPhishing => label == 'phishing' && confidence >= 0.7;
  bool get isMalware => label == 'malware' && confidence >= 0.7;
  bool get isSafe => label == 'safe' && confidence >= 0.7;
}

/// Image classification result
class ImageClassificationResult extends PredictionResult {
  final String imagePath;
  final List<DetectedObject> detectedObjects;
  final bool containsSensitiveContent;

  ImageClassificationResult({
    required super.modelType,
    required super.label,
    required super.confidence,
    super.allScores,
    required super.inferenceTime,
    required this.imagePath,
    this.detectedObjects = const [],
    this.containsSensitiveContent = false,
  });
}

/// Detected object in image
class DetectedObject {
  final String label;
  final double confidence;
  final Rect boundingBox;

  DetectedObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });
}

/// Bounding box
class Rect {
  final double left;
  final double top;
  final double width;
  final double height;

  Rect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

/// Model status
class ModelStatus {
  final MLModelType type;
  final bool isLoaded;
  final String? version;
  final int? sizeBytes;
  final DateTime? loadedAt;
  final String? error;

  ModelStatus({
    required this.type,
    required this.isLoaded,
    this.version,
    this.sizeBytes,
    this.loadedAt,
    this.error,
  });
}

/// TFLite ML Service
class TFLiteMLService {
  static const _channel = MethodChannel('com.orbvpn.orbguard/tflite');

  final Map<MLModelType, ModelStatus> _modelStatus = {};
  bool _isInitialized = false;

  // Scam detection keywords (for fallback/preprocessing)
  static const _scamKeywords = [
    'urgent', 'immediately', 'act now', 'winner', 'prize',
    'lottery', 'cash', 'reward', 'free gift', 'verify',
    'account suspended', 'click here', 'login required',
    'password expired', 'confirm identity', 'bank alert',
  ];

  // Suspicious URL patterns
  static const _suspiciousUrlPatterns = [
    r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',  // IP addresses
    r'\.tk$|\.ml$|\.ga$|\.cf$|\.gq$',        // Free TLDs
    r'login|signin|verify|secure|update',    // Phishing keywords
    r'bit\.ly|tinyurl|goo\.gl',              // URL shorteners
  ];

  /// Initialize the ML service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _channel.invokeMethod('initialize');
      _isInitialized = true;

      // Check which models are available
      for (final type in MLModelType.values) {
        _modelStatus[type] = ModelStatus(
          type: type,
          isLoaded: false,
        );
      }
    } on PlatformException catch (e) {
      print('TFLite initialization failed: ${e.message}');
      // Continue with fallback implementations
      _isInitialized = true;
    }
  }

  /// Load a specific model
  Future<bool> loadModel(MLModelType type) async {
    try {
      final result = await _channel.invokeMethod<bool>('loadModel', {
        'model_name': type.modelName,
      });

      if (result == true) {
        _modelStatus[type] = ModelStatus(
          type: type,
          isLoaded: true,
          loadedAt: DateTime.now(),
        );
        return true;
      }
    } on PlatformException catch (e) {
      _modelStatus[type] = ModelStatus(
        type: type,
        isLoaded: false,
        error: e.message,
      );
    }
    return false;
  }

  /// Unload a model to free memory
  Future<void> unloadModel(MLModelType type) async {
    try {
      await _channel.invokeMethod('unloadModel', {
        'model_name': type.modelName,
      });
      _modelStatus[type] = ModelStatus(
        type: type,
        isLoaded: false,
      );
    } on PlatformException {
      // Ignore errors
    }
  }

  /// Classify text for scam detection
  Future<TextClassificationResult> classifyScamText(String text) async {
    final startTime = DateTime.now();

    try {
      // Try TFLite first
      if (_modelStatus[MLModelType.scamClassifier]?.isLoaded == true) {
        final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'classifyText',
          {
            'model_name': MLModelType.scamClassifier.modelName,
            'text': text,
          },
        );

        if (result != null) {
          final scores = (result['scores'] as Map<dynamic, dynamic>)
              .map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));

          return TextClassificationResult(
            modelType: MLModelType.scamClassifier,
            label: result['label'] as String,
            confidence: (result['confidence'] as num).toDouble(),
            allScores: scores,
            inferenceTime: DateTime.now().difference(startTime),
            text: text,
            tokens: (result['tokens'] as List<dynamic>?)?.cast<String>() ?? [],
          );
        }
      }

      // Fallback to rule-based classification
      return _fallbackScamClassification(text, startTime);

    } on PlatformException {
      return _fallbackScamClassification(text, startTime);
    }
  }

  /// Fallback scam classification using rules
  TextClassificationResult _fallbackScamClassification(
    String text,
    DateTime startTime,
  ) {
    final lowerText = text.toLowerCase();
    var scamScore = 0.0;
    final matchedKeywords = <String>[];

    for (final keyword in _scamKeywords) {
      if (lowerText.contains(keyword.toLowerCase())) {
        scamScore += 0.1;
        matchedKeywords.add(keyword);
      }
    }

    // Check for URLs
    if (RegExp(r'https?://').hasMatch(text) ||
        RegExp(r'\.[a-z]{2,}').hasMatch(text)) {
      scamScore += 0.15;
    }

    // Check for urgency patterns
    if (RegExp(r'!{2,}').hasMatch(text) ||
        RegExp(r'URGENT|IMMEDIATELY|NOW', caseSensitive: false).hasMatch(text)) {
      scamScore += 0.2;
    }

    scamScore = scamScore.clamp(0.0, 1.0);

    final isScam = scamScore >= 0.4;

    return TextClassificationResult(
      modelType: MLModelType.scamClassifier,
      label: isScam ? 'scam' : 'safe',
      confidence: isScam ? scamScore : 1 - scamScore,
      allScores: {'scam': scamScore, 'safe': 1 - scamScore},
      inferenceTime: DateTime.now().difference(startTime),
      text: text,
      tokens: matchedKeywords,
      featureImportance: {
        for (final kw in matchedKeywords) kw: 0.1,
      },
    );
  }

  /// Classify URL for risk
  Future<URLClassificationResult> classifyUrl(String url) async {
    final startTime = DateTime.now();

    try {
      if (_modelStatus[MLModelType.urlClassifier]?.isLoaded == true) {
        final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'classifyUrl',
          {
            'model_name': MLModelType.urlClassifier.modelName,
            'url': url,
          },
        );

        if (result != null) {
          final scores = (result['scores'] as Map<dynamic, dynamic>)
              .map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));

          return URLClassificationResult(
            modelType: MLModelType.urlClassifier,
            label: result['label'] as String,
            confidence: (result['confidence'] as num).toDouble(),
            allScores: scores,
            inferenceTime: DateTime.now().difference(startTime),
            url: url,
            urlFeatures: result['features'] as Map<String, dynamic>? ?? {},
          );
        }
      }

      // Fallback to rule-based classification
      return _fallbackUrlClassification(url, startTime);

    } on PlatformException {
      return _fallbackUrlClassification(url, startTime);
    }
  }

  /// Fallback URL classification using rules
  URLClassificationResult _fallbackUrlClassification(
    String url,
    DateTime startTime,
  ) {
    final lowerUrl = url.toLowerCase();
    var riskScore = 0.0;
    final features = <String, dynamic>{};

    // Extract features
    final uri = Uri.tryParse(url);
    if (uri != null) {
      features['host'] = uri.host;
      features['path_length'] = uri.path.length;
      features['has_query'] = uri.hasQuery;
      features['scheme'] = uri.scheme;
    }

    // Check patterns
    for (final pattern in _suspiciousUrlPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(lowerUrl)) {
        riskScore += 0.25;
      }
    }

    // Check for IP address
    if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}').hasMatch(uri?.host ?? '')) {
      riskScore += 0.3;
      features['is_ip'] = true;
    }

    // Check path depth
    final pathDepth = uri?.pathSegments.length ?? 0;
    if (pathDepth > 5) {
      riskScore += 0.1;
    }
    features['path_depth'] = pathDepth;

    // Check for suspicious TLDs
    final suspiciousTlds = ['.tk', '.ml', '.ga', '.cf', '.gq', '.xyz', '.top'];
    for (final tld in suspiciousTlds) {
      if (lowerUrl.contains(tld)) {
        riskScore += 0.2;
        features['suspicious_tld'] = true;
        break;
      }
    }

    riskScore = riskScore.clamp(0.0, 1.0);

    String label;
    if (riskScore >= 0.7) {
      label = 'phishing';
    } else if (riskScore >= 0.4) {
      label = 'suspicious';
    } else {
      label = 'safe';
    }

    return URLClassificationResult(
      modelType: MLModelType.urlClassifier,
      label: label,
      confidence: label == 'safe' ? 1 - riskScore : riskScore,
      allScores: {
        'phishing': riskScore,
        'suspicious': riskScore * 0.7,
        'safe': 1 - riskScore,
      },
      inferenceTime: DateTime.now().difference(startTime),
      url: url,
      urlFeatures: features,
    );
  }

  /// Classify image for content analysis
  Future<ImageClassificationResult> classifyImage(String imagePath) async {
    final startTime = DateTime.now();

    try {
      if (_modelStatus[MLModelType.imageClassifier]?.isLoaded == true) {
        final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'classifyImage',
          {
            'model_name': MLModelType.imageClassifier.modelName,
            'image_path': imagePath,
          },
        );

        if (result != null) {
          final scores = (result['scores'] as Map<dynamic, dynamic>)
              .map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));

          final objects = (result['objects'] as List<dynamic>?)?.map((o) {
            final obj = o as Map<dynamic, dynamic>;
            return DetectedObject(
              label: obj['label'] as String,
              confidence: (obj['confidence'] as num).toDouble(),
              boundingBox: Rect(
                left: (obj['left'] as num).toDouble(),
                top: (obj['top'] as num).toDouble(),
                width: (obj['width'] as num).toDouble(),
                height: (obj['height'] as num).toDouble(),
              ),
            );
          }).toList() ?? [];

          return ImageClassificationResult(
            modelType: MLModelType.imageClassifier,
            label: result['label'] as String,
            confidence: (result['confidence'] as num).toDouble(),
            allScores: scores,
            inferenceTime: DateTime.now().difference(startTime),
            imagePath: imagePath,
            detectedObjects: objects,
            containsSensitiveContent: result['sensitive'] as bool? ?? false,
          );
        }
      }

      // Fallback: basic image info
      return ImageClassificationResult(
        modelType: MLModelType.imageClassifier,
        label: 'unknown',
        confidence: 0.0,
        inferenceTime: DateTime.now().difference(startTime),
        imagePath: imagePath,
      );

    } on PlatformException {
      return ImageClassificationResult(
        modelType: MLModelType.imageClassifier,
        label: 'error',
        confidence: 0.0,
        inferenceTime: DateTime.now().difference(startTime),
        imagePath: imagePath,
      );
    }
  }

  /// Detect intent from text
  Future<PredictionResult> detectIntent(String text) async {
    final startTime = DateTime.now();

    try {
      if (_modelStatus[MLModelType.intentClassifier]?.isLoaded == true) {
        final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'classifyText',
          {
            'model_name': MLModelType.intentClassifier.modelName,
            'text': text,
          },
        );

        if (result != null) {
          final scores = (result['scores'] as Map<dynamic, dynamic>)
              .map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));

          return PredictionResult(
            modelType: MLModelType.intentClassifier,
            label: result['label'] as String,
            confidence: (result['confidence'] as num).toDouble(),
            allScores: scores,
            inferenceTime: DateTime.now().difference(startTime),
          );
        }
      }

      // Fallback: simple intent detection
      return _fallbackIntentDetection(text, startTime);

    } on PlatformException {
      return _fallbackIntentDetection(text, startTime);
    }
  }

  /// Fallback intent detection
  PredictionResult _fallbackIntentDetection(String text, DateTime startTime) {
    final lowerText = text.toLowerCase();

    // Simple pattern matching for common intents
    final intentPatterns = {
      'money_request': ['send money', 'transfer', 'payment', 'pay me', 'wire'],
      'credential_request': ['password', 'login', 'username', 'verify account'],
      'urgency': ['urgent', 'immediately', 'right now', 'asap', 'emergency'],
      'threat': ['suspended', 'locked', 'closed', 'terminated', 'deleted'],
      'reward': ['winner', 'prize', 'lottery', 'reward', 'gift'],
    };

    var maxScore = 0.0;
    var detectedIntent = 'unknown';

    for (final entry in intentPatterns.entries) {
      var score = 0.0;
      for (final pattern in entry.value) {
        if (lowerText.contains(pattern)) {
          score += 0.3;
        }
      }
      if (score > maxScore) {
        maxScore = score;
        detectedIntent = entry.key;
      }
    }

    maxScore = maxScore.clamp(0.0, 1.0);

    if (maxScore < 0.3) {
      detectedIntent = 'benign';
      maxScore = 1 - maxScore;
    }

    return PredictionResult(
      modelType: MLModelType.intentClassifier,
      label: detectedIntent,
      confidence: maxScore,
      inferenceTime: DateTime.now().difference(startTime),
    );
  }

  /// Get model status
  ModelStatus? getModelStatus(MLModelType type) => _modelStatus[type];

  /// Get all model statuses
  Map<MLModelType, ModelStatus> getAllModelStatus() =>
      Map.unmodifiable(_modelStatus);

  /// Check if service is ready
  bool get isReady => _isInitialized;

  /// Dispose resources
  Future<void> dispose() async {
    for (final type in MLModelType.values) {
      await unloadModel(type);
    }
  }
}
