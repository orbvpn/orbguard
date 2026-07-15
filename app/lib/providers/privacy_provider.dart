// Privacy Provider
// Backs the Privacy Protection screen with the backend tracker catalogue.
//
// Honest scope: iOS and Android do NOT expose other apps' camera, microphone,
// clipboard, location, or contacts access to third-party apps, so OrbGuard
// cannot monitor or audit that on-device. This provider therefore does not
// fabricate a per-app access log or a privacy "score" — the only real data it
// has is the backend-provided catalogue of known trackers, which it surfaces
// as an informational reference (or an explicit unavailable state on failure).

import 'package:flutter/foundation.dart';

import '../services/api/orbguard_api_client.dart';

/// A known tracker from the backend catalogue.
///
/// This is an informational reference entry (what the tracker is, who operates
/// it, and what it collects). OrbGuard does not intercept or block network
/// traffic on this device, so there is deliberately no "blocked" state here —
/// the app never claims to enforce something it cannot.
class TrackerInfo {
  final String name;
  final String company;
  final String category;

  /// Categories of data the tracker collects (real backend field).
  final List<String> dataTypes;

  TrackerInfo({
    required this.name,
    required this.company,
    required this.category,
    this.dataTypes = const [],
  });
}

/// Privacy Provider
class PrivacyProvider extends ChangeNotifier {
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  final List<TrackerInfo> _trackers = [];
  bool _isLoading = false;
  String? _trackersLoadError;

  /// Known-tracker catalogue loaded from the backend (empty on failure).
  List<TrackerInfo> get trackers => List.unmodifiable(_trackers);

  bool get isLoading => _isLoading;

  /// Set when the tracker catalogue could not be loaded from the backend;
  /// [trackers] is empty in that case (never a fabricated fallback list).
  String? get trackersLoadError => _trackersLoadError;

  /// Initialize provider — loads the tracker catalogue.
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    await loadTrackers();

    _isLoading = false;
    notifyListeners();
  }

  /// Load trackers from the live backend.
  ///
  /// On failure the catalogue stays empty and [trackersLoadError] is set —
  /// no hardcoded fallback list is presented as live data.
  Future<void> loadTrackers() async {
    try {
      final data = await _api.getTrackers();
      _trackers
        ..clear()
        ..addAll(data.map((tracker) => TrackerInfo(
              name: tracker.name,
              company: tracker.company ?? 'Unknown',
              category: tracker.category,
              dataTypes: tracker.dataTypes,
            )));
      _trackersLoadError = null;
    } catch (e) {
      _trackers.clear();
      _trackersLoadError = 'Tracker catalogue unavailable: $e';
      debugPrint('PrivacyProvider: $_trackersLoadError');
    }
    notifyListeners();
  }
}
