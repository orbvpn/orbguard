/// ML Service
/// On-device machine learning orchestrator for threat detection
library ml_service;

import 'dart:async';
import 'package:flutter/foundation.dart';

import 'sms_classifier.dart';
import 'url_classifier.dart';
import 'behavior_analyzer.dart';

/// ML Service - Orchestrates on-device ML models
class MlService {
  static final MlService _instance = MlService._internal();
  factory MlService() => _instance;
  MlService._internal();

  static MlService get instance => _instance;

  // Classifiers
  late final SmsClassifier _smsClassifier;
  late final UrlClassifier _urlClassifier;
  late final BehaviorAnalyzer _behaviorAnalyzer;

  // State
  bool _isInitialized = false;
  bool _modelsLoaded = false;
  String? _error;

  // Model info
  final Map<String, ModelInfo> _modelInfo = {};

  // Getters
  bool get isInitialized => _isInitialized;
  bool get modelsLoaded => _modelsLoaded;
  String? get error => _error;
  Map<String, ModelInfo> get modelInfo => Map.unmodifiable(_modelInfo);

  /// Initialize the ML service
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      debugPrint('MlService: Initializing...');

      // Initialize classifiers
      _smsClassifier = SmsClassifier();
      _urlClassifier = UrlClassifier();
      _behaviorAnalyzer = BehaviorAnalyzer();

      // Load models
      await _loadModels();

      _isInitialized = true;
      debugPrint('MlService: Initialized successfully');
    } catch (e) {
      _error = 'Failed to initialize ML service: $e';
      debugPrint('MlService: $_error');
    }
  }

  /// Load all ML models
  Future<void> _loadModels() async {
    try {
      // Load SMS classifier model
      await _smsClassifier.loadModel();
      _modelInfo['sms'] = ModelInfo(
        name: 'SMS Phishing Classifier',
        version: _smsClassifier.modelVersion,
        isLoaded: _smsClassifier.isModelLoaded,
        inputSize: 256,
        outputClasses: ['safe', 'suspicious', 'phishing'],
      );

      // Load URL classifier model
      await _urlClassifier.loadModel();
      _modelInfo['url'] = ModelInfo(
        name: 'URL Threat Classifier',
        version: _urlClassifier.modelVersion,
        isLoaded: _urlClassifier.isModelLoaded,
        inputSize: 512,
        outputClasses: ['safe', 'suspicious', 'malicious', 'phishing'],
      );

      // Load behavior analyzer model
      await _behaviorAnalyzer.loadModel();
      _modelInfo['behavior'] = ModelInfo(
        name: 'Behavior Anomaly Detector',
        version: _behaviorAnalyzer.modelVersion,
        isLoaded: _behaviorAnalyzer.isModelLoaded,
        inputSize: 128,
        outputClasses: ['normal', 'anomaly'],
      );

      _modelsLoaded = _smsClassifier.isModelLoaded &&
          _urlClassifier.isModelLoaded &&
          _behaviorAnalyzer.isModelLoaded;

      debugPrint('MlService: Models loaded: $_modelsLoaded');
    } catch (e) {
      debugPrint('MlService: Error loading models: $e');
      _modelsLoaded = false;
    }
  }

  /// Classify SMS message
  Future<SmsClassificationResult> classifySms(String content, {String? sender}) async {
    if (!_isInitialized) {
      await init();
    }
    return _smsClassifier.classify(content, sender: sender);
  }

  /// Classify URL
  Future<UrlClassificationResult> classifyUrl(String url) async {
    if (!_isInitialized) {
      await init();
    }
    return _urlClassifier.classify(url);
  }

  /// Analyze app behavior
  Future<BehaviorAnalysisResult> analyzeBehavior(BehaviorFeatures features) async {
    if (!_isInitialized) {
      await init();
    }
    return _behaviorAnalyzer.analyze(features);
  }

  /// Batch classify SMS messages
  Future<List<SmsClassificationResult>> classifySmsBatch(List<String> messages) async {
    if (!_isInitialized) {
      await init();
    }
    return Future.wait(messages.map((m) => _smsClassifier.classify(m)));
  }

  /// Batch classify URLs
  Future<List<UrlClassificationResult>> classifyUrlBatch(List<String> urls) async {
    if (!_isInitialized) {
      await init();
    }
    return Future.wait(urls.map((u) => _urlClassifier.classify(u)));
  }

  /// Get model statistics
  MlStatistics getStatistics() {
    return MlStatistics(
      smsClassifications: _smsClassifier.classificationCount,
      urlClassifications: _urlClassifier.classificationCount,
      behaviorAnalyses: _behaviorAnalyzer.analysisCount,
      avgSmsLatency: _smsClassifier.averageLatency,
      avgUrlLatency: _urlClassifier.averageLatency,
      avgBehaviorLatency: _behaviorAnalyzer.averageLatency,
    );
  }

  /// Clear model caches
  void clearCaches() {
    _smsClassifier.clearCache();
    _urlClassifier.clearCache();
    _behaviorAnalyzer.clearCache();
  }

  /// Dispose resources
  void dispose() {
    _smsClassifier.dispose();
    _urlClassifier.dispose();
    _behaviorAnalyzer.dispose();
    _isInitialized = false;
    _modelsLoaded = false;
  }
}

/// Model information
class ModelInfo {
  final String name;
  final String version;
  final bool isLoaded;
  final int inputSize;
  final List<String> outputClasses;

  ModelInfo({
    required this.name,
    required this.version,
    required this.isLoaded,
    required this.inputSize,
    required this.outputClasses,
  });
}

/// ML statistics
class MlStatistics {
  final int smsClassifications;
  final int urlClassifications;
  final int behaviorAnalyses;
  final Duration avgSmsLatency;
  final Duration avgUrlLatency;
  final Duration avgBehaviorLatency;

  MlStatistics({
    required this.smsClassifications,
    required this.urlClassifications,
    required this.behaviorAnalyses,
    required this.avgSmsLatency,
    required this.avgUrlLatency,
    required this.avgBehaviorLatency,
  });

  int get totalClassifications =>
      smsClassifications + urlClassifications + behaviorAnalyses;

  Duration get averageLatency {
    if (totalClassifications == 0) return Duration.zero;
    final totalMs = avgSmsLatency.inMilliseconds * smsClassifications +
        avgUrlLatency.inMilliseconds * urlClassifications +
        avgBehaviorLatency.inMilliseconds * behaviorAnalyses;
    return Duration(milliseconds: totalMs ~/ totalClassifications);
  }
}
