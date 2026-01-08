/// Device Security Provider
/// State management for anti-theft features: locate, lock, wipe, ring, SIM monitoring

import 'package:flutter/foundation.dart';
import '../services/api/orbguard_api_client.dart';

/// Device command type
enum DeviceCommand {
  locate('Locate', 'Track device location'),
  lock('Lock', 'Lock device remotely'),
  wipe('Wipe', 'Erase all data'),
  ring('Ring', 'Play loud sound'),
  message('Message', 'Display message on screen');

  final String displayName;
  final String description;
  const DeviceCommand(this.displayName, this.description);
}

/// Command status
enum CommandStatus {
  pending('Pending'),
  sent('Sent'),
  acknowledged('Acknowledged'),
  completed('Completed'),
  failed('Failed');

  final String displayName;
  const CommandStatus(this.displayName);
}

/// Device location
class DeviceLocation {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime timestamp;
  final String? address;

  DeviceLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.timestamp,
    this.address,
  });
}

/// SIM card info
class SIMInfo {
  final String id;
  final String iccid;
  final String? carrier;
  final String? phoneNumber;
  final bool isTrusted;
  final DateTime firstSeen;
  final DateTime lastSeen;

  SIMInfo({
    required this.id,
    required this.iccid,
    this.carrier,
    this.phoneNumber,
    this.isTrusted = false,
    required this.firstSeen,
    required this.lastSeen,
  });
}

/// Anti-theft settings
class AntiTheftSettings {
  final bool locateEnabled;
  final bool lockEnabled;
  final bool wipeEnabled;
  final bool ringEnabled;
  final bool simMonitoringEnabled;
  final bool thiefSelfieEnabled;
  final int maxUnlockAttempts;
  final String? lockMessage;

  AntiTheftSettings({
    this.locateEnabled = true,
    this.lockEnabled = true,
    this.wipeEnabled = false,
    this.ringEnabled = true,
    this.simMonitoringEnabled = true,
    this.thiefSelfieEnabled = true,
    this.maxUnlockAttempts = 5,
    this.lockMessage,
  });

  AntiTheftSettings copyWith({
    bool? locateEnabled,
    bool? lockEnabled,
    bool? wipeEnabled,
    bool? ringEnabled,
    bool? simMonitoringEnabled,
    bool? thiefSelfieEnabled,
    int? maxUnlockAttempts,
    String? lockMessage,
  }) {
    return AntiTheftSettings(
      locateEnabled: locateEnabled ?? this.locateEnabled,
      lockEnabled: lockEnabled ?? this.lockEnabled,
      wipeEnabled: wipeEnabled ?? this.wipeEnabled,
      ringEnabled: ringEnabled ?? this.ringEnabled,
      simMonitoringEnabled: simMonitoringEnabled ?? this.simMonitoringEnabled,
      thiefSelfieEnabled: thiefSelfieEnabled ?? this.thiefSelfieEnabled,
      maxUnlockAttempts: maxUnlockAttempts ?? this.maxUnlockAttempts,
      lockMessage: lockMessage ?? this.lockMessage,
    );
  }
}

/// OS Vulnerability
class OSVulnerability {
  final String cveId;
  final String title;
  final String description;
  final String severity;
  final String affectedVersions;
  final String? fixedVersion;
  final bool isPatched;

  OSVulnerability({
    required this.cveId,
    required this.title,
    required this.description,
    required this.severity,
    required this.affectedVersions,
    this.fixedVersion,
    this.isPatched = false,
  });
}

/// Device security status
class DeviceSecurityStatus {
  final bool isLost;
  final bool isStolen;
  final bool isLocked;
  final DeviceLocation? lastKnownLocation;
  final DateTime? lastSeen;
  final int securityScore;
  final List<OSVulnerability> vulnerabilities;

  DeviceSecurityStatus({
    this.isLost = false,
    this.isStolen = false,
    this.isLocked = false,
    this.lastKnownLocation,
    this.lastSeen,
    this.securityScore = 100,
    this.vulnerabilities = const [],
  });
}

/// Device Security Provider
class DeviceSecurityProvider extends ChangeNotifier {
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // State
  String? _deviceId;
  DeviceSecurityStatus _status = DeviceSecurityStatus();
  AntiTheftSettings _settings = AntiTheftSettings();
  final List<DeviceLocation> _locationHistory = [];
  final List<SIMInfo> _simHistory = [];
  SIMInfo? _currentSIM;
  final List<String> _thiefSelfies = [];

  bool _isLoading = false;
  bool _isLocating = false;
  bool _isSendingCommand = false;
  String? _error;

  // Getters
  String? get deviceId => _deviceId;
  DeviceSecurityStatus get status => _status;
  AntiTheftSettings get settings => _settings;
  List<DeviceLocation> get locationHistory => List.unmodifiable(_locationHistory);
  List<SIMInfo> get simHistory => List.unmodifiable(_simHistory);
  SIMInfo? get currentSIM => _currentSIM;
  List<String> get thiefSelfies => List.unmodifiable(_thiefSelfies);
  bool get isLoading => _isLoading;
  bool get isLocating => _isLocating;
  bool get isSendingCommand => _isSendingCommand;
  String? get error => _error;

  /// Trusted SIMs
  List<SIMInfo> get trustedSIMs => _simHistory.where((s) => s.isTrusted).toList();

  /// Initialize provider
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _registerDevice();
      await Future.wait([
        loadStatus(),
        loadSettings(),
        loadLocationHistory(),
        loadSIMHistory(),
      ]);
    } catch (e) {
      _error = 'Failed to initialize: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Register device
  Future<void> _registerDevice() async {
    try {
      final result = await _api.registerDevice();
      _deviceId = result['device_id'];
    } catch (e) {
      // Generate local ID
      _deviceId = 'local-${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Load security status
  Future<void> loadStatus() async {
    if (_deviceId == null) return;

    try {
      final data = await _api.getDeviceSecurityStatus(_deviceId!);
      _status = DeviceSecurityStatus(
        isLost: data['is_lost'] ?? false,
        isStolen: data['is_stolen'] ?? false,
        isLocked: data['is_locked'] ?? false,
        securityScore: data['security_score'] ?? 100,
        lastSeen: data['last_seen'] != null
            ? DateTime.parse(data['last_seen'])
            : null,
      );
    } catch (e) {
      // Use default status
    }
    notifyListeners();
  }

  /// Load settings
  Future<void> loadSettings() async {
    if (_deviceId == null) return;

    try {
      final data = await _api.getAntiTheftSettings(_deviceId!);
      _settings = AntiTheftSettings(
        locateEnabled: data['locate_enabled'] ?? true,
        lockEnabled: data['lock_enabled'] ?? true,
        wipeEnabled: data['wipe_enabled'] ?? false,
        ringEnabled: data['ring_enabled'] ?? true,
        simMonitoringEnabled: data['sim_monitoring_enabled'] ?? true,
        thiefSelfieEnabled: data['thief_selfie_enabled'] ?? true,
        maxUnlockAttempts: data['max_unlock_attempts'] ?? 5,
        lockMessage: data['lock_message'],
      );
    } catch (e) {
      // Use default settings
    }
    notifyListeners();
  }

  /// Update settings
  Future<void> updateSettings(AntiTheftSettings newSettings) async {
    _settings = newSettings;
    notifyListeners();

    if (_deviceId != null) {
      try {
        await _api.updateAntiTheftSettings(_deviceId!, {
          'locate_enabled': newSettings.locateEnabled,
          'lock_enabled': newSettings.lockEnabled,
          'wipe_enabled': newSettings.wipeEnabled,
          'ring_enabled': newSettings.ringEnabled,
          'sim_monitoring_enabled': newSettings.simMonitoringEnabled,
          'thief_selfie_enabled': newSettings.thiefSelfieEnabled,
          'max_unlock_attempts': newSettings.maxUnlockAttempts,
          'lock_message': newSettings.lockMessage,
        });
      } catch (e) {
        _error = 'Failed to save settings: $e';
        notifyListeners();
      }
    }
  }

  /// Locate device
  Future<DeviceLocation?> locateDevice() async {
    if (_deviceId == null) return null;

    _isLocating = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.locateDevice(_deviceId!);
      final location = DeviceLocation(
        latitude: data['latitude'],
        longitude: data['longitude'],
        accuracy: data['accuracy'],
        timestamp: DateTime.now(),
        address: data['address'],
      );

      _locationHistory.insert(0, location);
      _status = DeviceSecurityStatus(
        isLost: _status.isLost,
        isStolen: _status.isStolen,
        isLocked: _status.isLocked,
        lastKnownLocation: location,
        lastSeen: DateTime.now(),
        securityScore: _status.securityScore,
        vulnerabilities: _status.vulnerabilities,
      );

      _isLocating = false;
      notifyListeners();
      return location;
    } catch (e) {
      _error = 'Failed to locate device: $e';
      _isLocating = false;
      notifyListeners();
      return null;
    }
  }

  /// Lock device
  Future<bool> lockDevice({String? message, String? pin}) async {
    return _sendCommand(DeviceCommand.lock, {
      'message': message ?? _settings.lockMessage,
      'pin': pin,
    });
  }

  /// Wipe device
  Future<bool> wipeDevice({required String confirmationCode}) async {
    return _sendCommand(DeviceCommand.wipe, {
      'confirmation_code': confirmationCode,
    });
  }

  /// Ring device
  Future<bool> ringDevice({int? duration}) async {
    return _sendCommand(DeviceCommand.ring, {
      'duration': duration ?? 60,
    });
  }

  /// Send command
  Future<bool> _sendCommand(DeviceCommand command, Map<String, dynamic> params) async {
    if (_deviceId == null) return false;

    _isSendingCommand = true;
    _error = null;
    notifyListeners();

    try {
      await _api.sendDeviceCommand(_deviceId!, command.name, params);
      _isSendingCommand = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to send command: $e';
      _isSendingCommand = false;
      notifyListeners();
      return false;
    }
  }

  /// Mark as lost
  Future<void> markAsLost() async {
    if (_deviceId == null) return;

    try {
      await _api.markDeviceLost(_deviceId!);
      _status = DeviceSecurityStatus(
        isLost: true,
        isStolen: _status.isStolen,
        isLocked: _status.isLocked,
        lastKnownLocation: _status.lastKnownLocation,
        lastSeen: _status.lastSeen,
        securityScore: _status.securityScore,
        vulnerabilities: _status.vulnerabilities,
      );
      notifyListeners();
    } catch (e) {
      _error = 'Failed to mark as lost: $e';
      notifyListeners();
    }
  }

  /// Mark as stolen
  Future<void> markAsStolen() async {
    if (_deviceId == null) return;

    try {
      await _api.markDeviceStolen(_deviceId!);
      _status = DeviceSecurityStatus(
        isLost: _status.isLost,
        isStolen: true,
        isLocked: _status.isLocked,
        lastKnownLocation: _status.lastKnownLocation,
        lastSeen: _status.lastSeen,
        securityScore: _status.securityScore,
        vulnerabilities: _status.vulnerabilities,
      );
      notifyListeners();
    } catch (e) {
      _error = 'Failed to mark as stolen: $e';
      notifyListeners();
    }
  }

  /// Mark as recovered
  Future<void> markAsRecovered() async {
    if (_deviceId == null) return;

    try {
      await _api.markDeviceRecovered(_deviceId!);
      _status = DeviceSecurityStatus(
        isLost: false,
        isStolen: false,
        isLocked: _status.isLocked,
        lastKnownLocation: _status.lastKnownLocation,
        lastSeen: _status.lastSeen,
        securityScore: _status.securityScore,
        vulnerabilities: _status.vulnerabilities,
      );
      notifyListeners();
    } catch (e) {
      _error = 'Failed to mark as recovered: $e';
      notifyListeners();
    }
  }

  /// Load location history
  Future<void> loadLocationHistory() async {
    if (_deviceId == null) return;

    try {
      final data = await _api.getLocationHistory(_deviceId!);
      _locationHistory.clear();
      for (final loc in data) {
        _locationHistory.add(DeviceLocation(
          latitude: loc['latitude'],
          longitude: loc['longitude'],
          accuracy: loc['accuracy'],
          timestamp: DateTime.parse(loc['timestamp']),
          address: loc['address'],
        ));
      }
    } catch (e) {
      // Use empty history
    }
    notifyListeners();
  }

  /// Load SIM history
  Future<void> loadSIMHistory() async {
    if (_deviceId == null) return;

    try {
      final data = await _api.getSIMHistory(_deviceId!);
      _simHistory.clear();
      for (final sim in data) {
        _simHistory.add(SIMInfo(
          id: sim['id'],
          iccid: sim['iccid'],
          carrier: sim['carrier'],
          phoneNumber: sim['phone_number'],
          isTrusted: sim['is_trusted'] ?? false,
          firstSeen: DateTime.parse(sim['first_seen']),
          lastSeen: DateTime.parse(sim['last_seen']),
        ));
      }
      if (_simHistory.isNotEmpty) {
        _currentSIM = _simHistory.first;
      }
    } catch (e) {
      // Use empty history
    }
    notifyListeners();
  }

  /// Add trusted SIM
  Future<void> addTrustedSIM(String iccid) async {
    if (_deviceId == null) return;

    try {
      await _api.addTrustedSIM(_deviceId!, iccid);
      await loadSIMHistory();
    } catch (e) {
      _error = 'Failed to add trusted SIM: $e';
      notifyListeners();
    }
  }

  /// Audit OS vulnerabilities
  Future<List<OSVulnerability>> auditVulnerabilities() async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _api.auditOSVulnerabilities();
      final vulnerabilities = <OSVulnerability>[];

      for (final vuln in data['vulnerabilities'] ?? []) {
        vulnerabilities.add(OSVulnerability(
          cveId: vuln['cve_id'],
          title: vuln['title'],
          description: vuln['description'],
          severity: vuln['severity'],
          affectedVersions: vuln['affected_versions'],
          fixedVersion: vuln['fixed_version'],
          isPatched: vuln['is_patched'] ?? false,
        ));
      }

      _status = DeviceSecurityStatus(
        isLost: _status.isLost,
        isStolen: _status.isStolen,
        isLocked: _status.isLocked,
        lastKnownLocation: _status.lastKnownLocation,
        lastSeen: _status.lastSeen,
        securityScore: data['security_score'] ?? _status.securityScore,
        vulnerabilities: vulnerabilities,
      );

      _isLoading = false;
      notifyListeners();
      return vulnerabilities;
    } catch (e) {
      _error = 'Failed to audit vulnerabilities: $e';
      _isLoading = false;
      notifyListeners();
      return [];
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
