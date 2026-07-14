// Device Security Provider
// State management for anti-theft features: locate, lock, wipe, ring,
// SIM monitoring, thief selfies and the on-device agent lifecycle.
//
// All parsing matches the orbguard.lab contracts exactly
// (internal/domain/models/device_security.go). There are no fabricated
// defaults: when the backend cannot be reached the provider surfaces the
// error instead of pretending the device scored 100/100.

import 'dart:async';
import 'dart:developer' as developer;
import '../utils/platform_info.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api/orbguard_api_client.dart';
import '../services/device_agent/agent_api.dart';
import '../services/device_agent/device_agent.dart';
import '../services/device_agent/push_service.dart';

/// Device command type (backend models.CommandType values).
enum DeviceCommand {
  locate('locate', 'Locate', 'Track device location'),
  lock('lock', 'Lock', 'Lock device remotely'),
  wipe('wipe', 'Wipe', 'Erase all data'),
  ring('ring', 'Ring', 'Play loud sound'),
  takeSelfie('take_selfie', 'Selfie', 'Capture front-camera photo'),
  message('message', 'Message', 'Display message on screen');

  final String apiValue;
  final String displayName;
  final String description;
  const DeviceCommand(this.apiValue, this.displayName, this.description);
}

/// Command status (backend models.CommandStatus values).
enum CommandStatus {
  pending('pending', 'Pending'),
  sent('sent', 'Sent'),
  delivered('delivered', 'Delivered'),
  executed('executed', 'Executed'),
  failed('failed', 'Failed'),
  expired('expired', 'Expired');

  final String apiValue;
  final String displayName;
  const CommandStatus(this.apiValue, this.displayName);

  static CommandStatus fromApi(String? value) {
    for (final s in CommandStatus.values) {
      if (s.apiValue == value) return s;
    }
    return CommandStatus.pending;
  }
}

/// Device location (backend models.Location).
class DeviceLocation {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime timestamp;
  final String? address;
  final String? provider;

  DeviceLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.timestamp,
    this.address,
    this.provider,
  });

  static DeviceLocation? fromBackendJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final lat = (json['latitude'] as num?)?.toDouble();
    final lon = (json['longitude'] as num?)?.toDouble();
    final ts = json['timestamp'] as String?;
    if (lat == null || lon == null || ts == null) return null;
    return DeviceLocation(
      latitude: lat,
      longitude: lon,
      accuracy: (json['accuracy_meters'] as num?)?.toDouble(),
      timestamp: DateTime.tryParse(ts) ?? DateTime.now(),
      address: (json['address'] as String?)?.isEmpty == true
          ? null
          : json['address'] as String?,
      provider: json['provider'] as String?,
    );
  }
}

/// SIM card info (backend models.SIMInfo). [isTrusted] is derived from the
/// anti-theft settings' trusted_sim_iccids list (the backend stores trust on
/// the settings, not on the SIM record).
class SIMInfo {
  final String id;
  final int slotIndex;
  final String iccid;
  final String? carrier;
  final String? countryCode;
  final String? phoneNumber;
  final bool isActive;
  final bool isEsim;
  final bool isTrusted;
  final DateTime? firstSeen;
  final DateTime? lastSeen;

  SIMInfo({
    required this.id,
    required this.slotIndex,
    required this.iccid,
    this.carrier,
    this.countryCode,
    this.phoneNumber,
    this.isActive = false,
    this.isEsim = false,
    this.isTrusted = false,
    this.firstSeen,
    this.lastSeen,
  });

  static SIMInfo? fromBackendJson(
    Map<String, dynamic>? json, {
    required Set<String> trustedIccids,
  }) {
    if (json == null) return null;
    final iccid = json['iccid'] as String?;
    if (iccid == null || iccid.isEmpty) return null;
    return SIMInfo(
      id: json['id']?.toString() ?? '',
      slotIndex: (json['slot_index'] as num?)?.toInt() ?? 0,
      iccid: iccid,
      carrier: json['carrier'] as String?,
      countryCode: json['country_code'] as String?,
      phoneNumber: json['phone_number'] as String?,
      isActive: json['is_active'] == true,
      isEsim: json['is_esim'] == true,
      isTrusted: trustedIccids.contains(iccid),
      firstSeen: DateTime.tryParse(json['first_seen']?.toString() ?? ''),
      lastSeen: DateTime.tryParse(json['last_seen']?.toString() ?? ''),
    );
  }
}

/// SIM change event (backend models.SIMChangeEvent).
class SIMChangeEvent {
  final String id;
  final String eventType; // inserted | removed | swapped | changed
  final String riskLevel; // critical | high | medium | low
  final SIMInfo? oldSim;
  final SIMInfo? newSim;
  final DateTime detectedAt;

  SIMChangeEvent({
    required this.id,
    required this.eventType,
    required this.riskLevel,
    this.oldSim,
    this.newSim,
    required this.detectedAt,
  });
}

/// Thief selfie record (backend models.ThiefSelfie).
class ThiefSelfie {
  final String id;
  final String imageUrl;
  final String imageHash;
  final String triggerType;
  final int attemptCount;
  final DateTime? capturedAt;

  ThiefSelfie({
    required this.id,
    required this.imageUrl,
    required this.imageHash,
    required this.triggerType,
    required this.attemptCount,
    this.capturedAt,
  });
}

/// Anti-theft settings.
///
/// locate/lock/wipe/selfie/SIM-monitoring map to the backend
/// models.AntiTheftSettings fields. [ringEnabled] and [lockMessage] have NO
/// backend field — they are persisted on-device in SharedPreferences and
/// documented as local-only (ring commands are always accepted by the
/// backend; the lock message is sent per-command in the lock payload).
class AntiTheftSettings {
  final bool locateEnabled;
  final bool lockEnabled;
  final bool wipeEnabled;
  final bool ringEnabled;
  final bool simMonitoringEnabled;
  final bool thiefSelfieEnabled;
  final int maxUnlockAttempts;
  final String? lockMessage;
  final List<String> trustedSimIccids;

  AntiTheftSettings({
    this.locateEnabled = true,
    this.lockEnabled = true,
    this.wipeEnabled = false,
    this.ringEnabled = true,
    this.simMonitoringEnabled = true,
    this.thiefSelfieEnabled = true,
    this.maxUnlockAttempts = 5,
    this.lockMessage,
    this.trustedSimIccids = const [],
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
    List<String>? trustedSimIccids,
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
      trustedSimIccids: trustedSimIccids ?? this.trustedSimIccids,
    );
  }

  AgentPolicy toAgentPolicy() => AgentPolicy(
        remoteLocateEnabled: locateEnabled,
        remoteLockEnabled: lockEnabled,
        remoteWipeEnabled: wipeEnabled,
        thiefSelfieEnabled: thiefSelfieEnabled,
        simAlertEnabled: simMonitoringEnabled,
      );
}

/// OS Vulnerability (backend models.OSVulnerability).
class OSVulnerability {
  final String cveId;
  final String title;
  final String description;
  final String severity;
  final double cvssScore;
  final String affectedVersions;
  final String? fixedVersion;
  final bool isExploited;

  OSVulnerability({
    required this.cveId,
    required this.title,
    required this.description,
    required this.severity,
    required this.cvssScore,
    required this.affectedVersions,
    this.fixedVersion,
    this.isExploited = false,
  });

  static OSVulnerability fromBackendJson(Map<String, dynamic> json) {
    final ranges = (json['affected_versions'] as List? ?? const [])
        .whereType<Map>()
        .map((r) {
      final min = r['min_version']?.toString() ?? '';
      final max = r['max_version']?.toString() ?? '';
      if (min.isNotEmpty && max.isNotEmpty) return '$min - $max';
      if (min.isNotEmpty) return '>= $min';
      if (max.isNotEmpty) return '<= $max';
      return '';
    }).where((s) => s.isNotEmpty);
    return OSVulnerability(
      cveId: json['id']?.toString() ?? 'unknown',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'unknown',
      cvssScore: (json['cvss_score'] as num?)?.toDouble() ?? 0,
      affectedVersions: ranges.isEmpty ? 'unknown' : ranges.join(', '),
      fixedVersion: json['patched_in']?.toString().isEmpty == true
          ? null
          : json['patched_in']?.toString(),
      isExploited: json['is_exploited'] == true,
    );
  }
}

/// Device security status (backend models.DeviceSecurityStatus).
class DeviceSecurityStatus {
  final bool isLost;
  final bool isStolen;
  final bool isLocked;
  final bool isRooted;
  final bool antiTheftEnabled;
  final int pendingCommands;
  final int simChangeAlerts;
  final DeviceLocation? lastKnownLocation;
  final DateTime? lastSeen;

  /// Backend overall_score (0-100, higher is better). Null until the
  /// backend has actually computed it — never fabricated.
  final int? securityScore;
  final List<OSVulnerability> vulnerabilities;

  DeviceSecurityStatus({
    this.isLost = false,
    this.isStolen = false,
    this.isLocked = false,
    this.isRooted = false,
    this.antiTheftEnabled = false,
    this.pendingCommands = 0,
    this.simChangeAlerts = 0,
    this.lastKnownLocation,
    this.lastSeen,
    this.securityScore,
    this.vulnerabilities = const [],
  });

  DeviceSecurityStatus copyWith({
    bool? isLost,
    bool? isStolen,
    bool? isLocked,
    DeviceLocation? lastKnownLocation,
    DateTime? lastSeen,
    int? securityScore,
    List<OSVulnerability>? vulnerabilities,
  }) {
    return DeviceSecurityStatus(
      isLost: isLost ?? this.isLost,
      isStolen: isStolen ?? this.isStolen,
      isLocked: isLocked ?? this.isLocked,
      isRooted: isRooted,
      antiTheftEnabled: antiTheftEnabled,
      pendingCommands: pendingCommands,
      simChangeAlerts: simChangeAlerts,
      lastKnownLocation: lastKnownLocation ?? this.lastKnownLocation,
      lastSeen: lastSeen ?? this.lastSeen,
      securityScore: securityScore ?? this.securityScore,
      vulnerabilities: vulnerabilities ?? this.vulnerabilities,
    );
  }
}

/// A remote command issued from this UI, with its observed lifecycle.
class IssuedCommand {
  final String commandId;
  final DeviceCommand command;
  final DateTime issuedAt;
  CommandStatus status;
  String? detail;

  IssuedCommand({
    required this.commandId,
    required this.command,
    required this.issuedAt,
    this.status = CommandStatus.pending,
    this.detail,
  });
}

/// Device Security Provider
class DeviceSecurityProvider extends ChangeNotifier {
  static const _ringEnabledPrefsKey = 'device_security.ring_enabled';
  static const _lockMessagePrefsKey = 'device_security.lock_message';

  final OrbGuardApiClient _api = OrbGuardApiClient.instance;
  final DeviceAgent _agent = DeviceAgent.instance;
  DeviceAgentApi? _agentApi;

  // State
  String? _deviceId;
  DeviceSecurityStatus _status = DeviceSecurityStatus();
  AntiTheftSettings _settings = AntiTheftSettings();
  final List<DeviceLocation> _locationHistory = [];
  final List<SIMChangeEvent> _simEvents = [];
  final List<SIMInfo> _currentSims = [];
  final List<ThiefSelfie> _thiefSelfies = [];
  final List<IssuedCommand> _issuedCommands = [];

  bool _initialized = false;
  bool _isLoading = false;
  bool _isLocating = false;
  bool _isSendingCommand = false;
  String? _error;

  DeviceSecurityProvider() {
    _agent.addListener(_onAgentChanged);
  }

  void _onAgentChanged() {
    _refreshIssuedCommandStates();
    notifyListeners();
  }

  @override
  void dispose() {
    _agent.removeListener(_onAgentChanged);
    super.dispose();
  }

  // Getters
  String? get deviceId => _deviceId;
  DeviceSecurityStatus get status => _status;
  AntiTheftSettings get settings => _settings;
  List<DeviceLocation> get locationHistory =>
      List.unmodifiable(_locationHistory);
  List<SIMChangeEvent> get simEvents => List.unmodifiable(_simEvents);
  List<SIMInfo> get currentSims => List.unmodifiable(_currentSims);
  List<ThiefSelfie> get thiefSelfies => List.unmodifiable(_thiefSelfies);
  List<IssuedCommand> get issuedCommands =>
      List.unmodifiable(_issuedCommands);
  bool get isLoading => _isLoading;
  bool get isLocating => _isLocating;
  bool get isSendingCommand => _isSendingCommand;
  String? get error => _error;

  // Agent state passthrough (real device state, no fabrication).
  bool get agentRunning => _agent.isRunning;
  DateTime? get agentLastPollAt => _agent.lastPollAt;
  String? get agentLastError => _agent.lastError;
  String? get agentLocationStatus => _agent.locationStatus;
  String? get agentSimStatus => _agent.simStatus;
  String? get agentBackgroundStatus => _agent.backgroundStatus;
  AgentDisplayMessage? get agentDisplayMessage => _agent.lastDisplayMessage;
  List<CommandExecution> get agentExecutions => _agent.recentExecutions;

  /// Trusted SIMs (from the settings whitelist, matched against seen SIMs).
  List<SIMInfo> get trustedSIMs =>
      _currentSims.where((s) => s.isTrusted).toList();

  SIMInfo? get currentSIM {
    for (final sim in _currentSims) {
      if (sim.isActive) return sim;
    }
    return _currentSims.isNotEmpty ? _currentSims.first : null;
  }

  /// Initialize provider: register the device, load all device-security
  /// state and start the on-device agent.
  Future<void> init() async {
    if (PlatformInfo.isWeb) {
      // Anti-theft (locate/lock/wipe/ring/selfie, SIM monitoring) needs a
      // real device agent — none of it can run in a browser sandbox.
      _error = 'Device security / anti-theft is not available in the browser. '
          'Use the OrbGuard mobile or desktop app.';
      notifyListeners();
      return;
    }
    if (_initialized) {
      // Re-entered from screen initState; refresh quietly.
      unawaited(refreshAll());
      return;
    }
    _isLoading = true;
    notifyListeners();

    try {
      await _registerDevice();
      if (_deviceId != null) {
        await refreshAll();
        await _agent.start(
          deviceId: _deviceId!,
          policy: _settings.toAgentPolicy(),
        );

        // Wire up push wake-ups now that the device is registered. With FCM
        // disabled (the default build) this is a logged no-op and the agent's
        // HTTP polling stays the wake mechanism; once Firebase is enabled
        // (docs/FCM_SETUP.md) it obtains + registers the token and registers
        // the message handler that calls DevicePushService.onPushReceived().
        unawaited(DevicePushService.instance.init());

        _initialized = true;
      }
    } catch (e) {
      _error = 'Failed to initialize device security: $e';
      developer.log(_error!, name: 'DeviceSecurityProvider');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshAll() async {
    await Future.wait([
      loadStatus(),
      loadSettings(),
      loadLocationHistory(),
      loadSIMHistory(),
      loadSelfies(),
    ]);
  }

  /// Registers this device with the auth layer (POST /auth/device) and the
  /// device-security service (POST /device/register). No fabricated local
  /// IDs: if registration fails, anti-theft is reported unavailable.
  Future<void> _registerDevice() async {
    final result = await _api.registerDevice({});
    final id = result['device_id']?.toString();
    if (id == null || id.isEmpty) {
      _error = 'Device registration failed: backend returned no device_id. '
          'Anti-theft features are unavailable.';
      developer.log(_error!, name: 'DeviceSecurityProvider');
      return;
    }
    _deviceId = id;
    _agentApi = DeviceAgentApi(_api, id);

    // Device-security registration (separate repo from auth) — required for
    // /device/{id}/security-status to resolve.
    try {
      await _api.post<dynamic>(
        '/api/v1/device/register',
        data: await _collectSecureDeviceInfo(id),
      );
    } catch (e) {
      // Non-fatal when the device already exists; surface real failures.
      developer.log('device-security registration: $e',
          name: 'DeviceSecurityProvider');
    }
  }

  Future<Map<String, dynamic>> _collectSecureDeviceInfo(String id) async {
    final info = <String, dynamic>{'device_id': id};
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (PlatformInfo.isAndroid) {
        final a = await deviceInfo.androidInfo;
        info.addAll({
          'name': '${a.manufacturer} ${a.model}',
          'model': a.model,
          'manufacturer': a.manufacturer,
          'platform': 'android',
          'os_version': a.version.release,
          'security_patch': a.version.securityPatch ?? '',
          'api_level': a.version.sdkInt,
        });
        info['is_rooted'] = await _checkRootedAndroid();
      } else if (PlatformInfo.isIOS) {
        final i = await deviceInfo.iosInfo;
        info.addAll({
          'name': i.name,
          'model': i.model,
          'manufacturer': 'Apple',
          'platform': 'ios',
          'os_version': i.systemVersion,
        });
      } else {
        info.addAll({
          'name': PlatformInfo.localHostname,
          'platform': PlatformInfo.operatingSystem,
          'os_version': PlatformInfo.operatingSystemVersion,
        });
      }
    } catch (e) {
      developer.log('device info collection incomplete: $e',
          name: 'DeviceSecurityProvider');
    }
    return info;
  }

  /// Real root check via the existing com.orb.guard/system channel; returns
  /// false (logged) when the native side is unavailable.
  Future<bool> _checkRootedAndroid() async {
    try {
      const channel = MethodChannel('com.orb.guard/system');
      final result = await channel.invokeMethod('checkRootAccess');
      if (result is Map) return result['hasRoot'] == true;
      return false;
    } catch (e) {
      developer.log('root check unavailable: $e',
          name: 'DeviceSecurityProvider');
      return false;
    }
  }

  /// Load security status — parses the real models.DeviceSecurityStatus
  /// shape. Failures surface as errors; no default-status swallow.
  Future<void> loadStatus() async {
    if (_deviceId == null) return;

    try {
      final data = await _api.getDeviceSecurityStatus();
      final deviceInfo = data['device_info'] as Map<String, dynamic>?;
      final deviceStatus = deviceInfo?['status']?.toString() ?? '';

      _status = DeviceSecurityStatus(
        isLost: deviceStatus == 'lost',
        isStolen: deviceStatus == 'stolen',
        isLocked: deviceStatus == 'locked',
        isRooted: data['is_rooted'] == true,
        antiTheftEnabled: data['anti_theft_enabled'] == true,
        pendingCommands: (data['pending_commands'] as num?)?.toInt() ?? 0,
        simChangeAlerts: (data['sim_change_alerts'] as num?)?.toInt() ?? 0,
        lastKnownLocation: DeviceLocation.fromBackendJson(
            data['last_location'] as Map<String, dynamic>?),
        lastSeen: DateTime.tryParse(
            deviceInfo?['last_seen']?.toString() ?? ''),
        securityScore: (data['overall_score'] as num?)?.round(),
        vulnerabilities: _status.vulnerabilities,
      );
      _error = null;
    } catch (e) {
      _error = 'Failed to load device security status: $e';
      developer.log(_error!, name: 'DeviceSecurityProvider');
    }
    notifyListeners();
  }

  /// Load settings — parses the backend models.AntiTheftSettings field
  /// names; ring/lock-message come from local persistence.
  Future<void> loadSettings() async {
    if (_deviceId == null) return;

    try {
      final data = await _api.getAntiTheftSettings();
      final prefs = await SharedPreferences.getInstance();
      _settings = AntiTheftSettings(
        locateEnabled: data['enable_remote_locate'] == true,
        lockEnabled: data['enable_remote_lock'] == true,
        wipeEnabled: data['enable_remote_wipe'] == true,
        thiefSelfieEnabled: data['enable_thief_selfie'] == true,
        simMonitoringEnabled: data['enable_sim_alert'] == true,
        maxUnlockAttempts:
            (data['selfie_after_attempts'] as num?)?.toInt() ?? 5,
        ringEnabled: prefs.getBool(_ringEnabledPrefsKey) ?? true,
        lockMessage: prefs.getString(_lockMessagePrefsKey),
        trustedSimIccids: (data['trusted_sim_iccids'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
      await _agent.updatePolicy(_settings.toAgentPolicy());
      _error = null;
    } catch (e) {
      _error = 'Failed to load anti-theft settings: $e';
      developer.log(_error!, name: 'DeviceSecurityProvider');
    }
    notifyListeners();
  }

  /// Update settings — pushes the backend-owned toggles to the server,
  /// persists the local-only ones, and re-policies the agent.
  Future<void> updateSettings(AntiTheftSettings newSettings) async {
    final previous = _settings;
    _settings = newSettings;
    notifyListeners();

    // Local-only fields.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_ringEnabledPrefsKey, newSettings.ringEnabled);
      if (newSettings.lockMessage != null) {
        await prefs.setString(_lockMessagePrefsKey, newSettings.lockMessage!);
      }
    } catch (e) {
      developer.log('failed to persist local settings: $e',
          name: 'DeviceSecurityProvider');
    }

    if (_deviceId == null) return;
    try {
      await _api.updateAntiTheftSettings({
        'enable_remote_locate': newSettings.locateEnabled,
        'enable_remote_lock': newSettings.lockEnabled,
        'enable_remote_wipe': newSettings.wipeEnabled,
        'enable_thief_selfie': newSettings.thiefSelfieEnabled,
        'enable_sim_alert': newSettings.simMonitoringEnabled,
        'selfie_after_attempts': newSettings.maxUnlockAttempts,
        'selfie_on_wrong_pin': newSettings.thiefSelfieEnabled,
      });
      await _agent.updatePolicy(newSettings.toAgentPolicy());
    } catch (e) {
      _settings = previous; // server rejected — roll back honestly
      _error = 'Failed to save settings: $e';
      notifyListeners();
    }
  }

  /// Locate device. The backend issues a locate command
  /// ({status, command_id}); since this app instance IS the device, the
  /// agent polls immediately, executes the command (fresh GPS fix +
  /// POST /location + ack) and the result is read back from the location
  /// history.
  Future<DeviceLocation?> locateDevice() async {
    if (_deviceId == null) return null;

    _isLocating = true;
    _error = null;
    notifyListeners();

    try {
      final resp = await _api.locateDevice();
      final commandId = resp['command_id']?.toString() ?? '';
      _trackIssuedCommand(commandId, DeviceCommand.locate);

      // Execute locally right away (this device is the target).
      await _agent.pollNow();
      _refreshIssuedCommandStates();

      await loadLocationHistory();
      final latest =
          _locationHistory.isNotEmpty ? _locationHistory.first : null;

      final execution = _findExecution(commandId);
      if (execution != null && !execution.ok) {
        _error = 'Locate failed: ${execution.detail}';
      } else if (latest != null) {
        _status = _status.copyWith(
          lastKnownLocation: latest,
          lastSeen: DateTime.now(),
        );
      }

      _isLocating = false;
      notifyListeners();
      return latest;
    } catch (e) {
      _error = 'Failed to locate device: $e';
      _isLocating = false;
      notifyListeners();
      return null;
    }
  }

  /// Lock device (POST /device/{id}/lock, then immediate local execution).
  Future<bool> lockDevice({String? message, String? pin}) async {
    if (_deviceId == null) return false;
    _isSendingCommand = true;
    _error = null;
    notifyListeners();

    try {
      final resp = await _api.lockDevice(
        message: message ?? _settings.lockMessage,
        pin: pin,
      );
      final ok = await _executeIssued(
          resp['command_id']?.toString() ?? '', DeviceCommand.lock);
      _isSendingCommand = false;
      notifyListeners();
      return ok;
    } catch (e) {
      _error = 'Failed to send lock command: $e';
      _isSendingCommand = false;
      notifyListeners();
      return false;
    }
  }

  /// Wipe device — requires the typed confirmation code, sent as the
  /// backend's mandatory confirmation_id.
  Future<bool> wipeDevice({required String confirmationCode}) async {
    if (_deviceId == null) return false;
    _isSendingCommand = true;
    _error = null;
    notifyListeners();

    try {
      final resp = await _api.wipeDevice(confirmationId: confirmationCode);
      final ok = await _executeIssued(
          resp['command_id']?.toString() ?? '', DeviceCommand.wipe);
      _isSendingCommand = false;
      notifyListeners();
      return ok;
    } catch (e) {
      _error = 'Failed to send wipe command: $e';
      _isSendingCommand = false;
      notifyListeners();
      return false;
    }
  }

  /// Ring device (POST /device/{id}/ring, then immediate local execution).
  Future<bool> ringDevice({int? duration}) async {
    if (_deviceId == null) return false;
    if (!_settings.ringEnabled) {
      _error = 'Remote ring is disabled in settings';
      notifyListeners();
      return false;
    }
    _isSendingCommand = true;
    _error = null;
    notifyListeners();

    try {
      final resp = await _api.ringDevice();
      final ok = await _executeIssued(
          resp['command_id']?.toString() ?? '', DeviceCommand.ring);
      _isSendingCommand = false;
      notifyListeners();
      return ok;
    } catch (e) {
      _error = 'Failed to send ring command: $e';
      _isSendingCommand = false;
      notifyListeners();
      return false;
    }
  }

  /// Trigger a thief selfie capture remotely (generic command endpoint).
  Future<bool> takeSelfie() async {
    if (_deviceId == null) return false;
    _isSendingCommand = true;
    _error = null;
    notifyListeners();

    try {
      await _api.sendDeviceCommand(DeviceCommand.takeSelfie.apiValue);
      await _agent.pollNow();
      await loadSelfies();
      _isSendingCommand = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to trigger selfie: $e';
      _isSendingCommand = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> _executeIssued(String commandId, DeviceCommand command) async {
    _trackIssuedCommand(commandId, command);
    await _agent.pollNow();
    _refreshIssuedCommandStates();
    final execution = _findExecution(commandId);
    if (execution == null) {
      // Command was issued but this poll did not pick it up (e.g. agent
      // stopped); the backend keeps it pending — report honestly.
      _error = '${command.displayName} command issued; awaiting execution '
          '(agent ${_agent.isRunning ? 'will retry on next poll' : 'is not running'})';
      return false;
    }
    if (!execution.ok) {
      _error = '${command.displayName} failed: ${execution.detail}';
      return false;
    }
    return true;
  }

  void _trackIssuedCommand(String commandId, DeviceCommand command) {
    if (commandId.isEmpty) return;
    _issuedCommands.insert(
      0,
      IssuedCommand(
        commandId: commandId,
        command: command,
        issuedAt: DateTime.now(),
        status: CommandStatus.pending,
      ),
    );
    if (_issuedCommands.length > 20) {
      _issuedCommands.removeRange(20, _issuedCommands.length);
    }
  }

  CommandExecution? _findExecution(String commandId) {
    if (commandId.isEmpty) return null;
    for (final e in _agent.recentExecutions) {
      if (e.commandId == commandId) return e;
    }
    return null;
  }

  void _refreshIssuedCommandStates() {
    for (final issued in _issuedCommands) {
      final execution = _findExecution(issued.commandId);
      if (execution != null) {
        issued.status = execution.ok
            ? CommandStatus.executed
            : (execution.outcome == 'deferred'
                ? CommandStatus.pending
                : CommandStatus.failed);
        issued.detail = execution.detail;
      }
    }
  }

  /// Mark as lost.
  Future<void> markAsLost() async {
    if (_deviceId == null) return;
    try {
      await _api.markDeviceLost();
      await loadStatus();
    } catch (e) {
      _error = 'Failed to mark as lost: $e';
      notifyListeners();
    }
  }

  /// Mark as stolen.
  Future<void> markAsStolen() async {
    if (_deviceId == null) return;
    try {
      await _api.markDeviceStolen();
      await loadStatus();
    } catch (e) {
      _error = 'Failed to mark as stolen: $e';
      notifyListeners();
    }
  }

  /// Mark as recovered.
  Future<void> markAsRecovered() async {
    if (_deviceId == null) return;
    try {
      await _api.markDeviceRecovered();
      await loadStatus();
    } catch (e) {
      _error = 'Failed to mark as recovered: $e';
      notifyListeners();
    }
  }

  /// Load location history (models.Location list).
  Future<void> loadLocationHistory() async {
    if (_deviceId == null) return;
    try {
      final data = await _api.getLocationHistory();
      _locationHistory
        ..clear()
        ..addAll(data
            .map(DeviceLocation.fromBackendJson)
            .whereType<DeviceLocation>());
      // Backend returns newest-first ordering from the repository; sort
      // defensively so the UI's "Latest" claim is true.
      _locationHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      _error = 'Failed to load location history: $e';
      developer.log(_error!, name: 'DeviceSecurityProvider');
    }
    notifyListeners();
  }

  /// Load SIM state: current SIMs (GET /sim) and change events
  /// (GET /sim/history — models.SIMChangeEvent list).
  Future<void> loadSIMHistory() async {
    if (_deviceId == null || _agentApi == null) return;
    final trusted = _settings.trustedSimIccids.toSet();

    try {
      final sims = await _agentApi!.getCurrentSims();
      _currentSims
        ..clear()
        ..addAll(sims
            .map((s) => SIMInfo.fromBackendJson(s, trustedIccids: trusted))
            .whereType<SIMInfo>());
    } catch (e) {
      _error = 'Failed to load current SIMs: $e';
      developer.log(_error!, name: 'DeviceSecurityProvider');
    }

    try {
      final events = await _api.getSIMHistory();
      _simEvents.clear();
      for (final event in events) {
        _simEvents.add(SIMChangeEvent(
          id: event['id']?.toString() ?? '',
          eventType: event['event_type']?.toString() ?? 'unknown',
          riskLevel: event['risk_level']?.toString() ?? 'low',
          oldSim: SIMInfo.fromBackendJson(
              event['old_sim'] as Map<String, dynamic>?,
              trustedIccids: trusted),
          newSim: SIMInfo.fromBackendJson(
              event['new_sim'] as Map<String, dynamic>?,
              trustedIccids: trusted),
          detectedAt:
              DateTime.tryParse(event['detected_at']?.toString() ?? '') ??
                  DateTime.now(),
        ));
      }
    } catch (e) {
      _error = 'Failed to load SIM history: $e';
      developer.log(_error!, name: 'DeviceSecurityProvider');
    }
    notifyListeners();
  }

  /// Load captured thief selfies (GET /device/{id}/selfies).
  Future<void> loadSelfies() async {
    if (_agentApi == null) return;
    try {
      final data = await _agentApi!.getSelfies();
      _thiefSelfies
        ..clear()
        ..addAll(data.map((s) => ThiefSelfie(
              id: s['id']?.toString() ?? '',
              imageUrl: s['image_url']?.toString() ?? '',
              imageHash: s['image_hash']?.toString() ?? '',
              triggerType: s['trigger_type']?.toString() ?? '',
              attemptCount: (s['attempt_count'] as num?)?.toInt() ?? 0,
              capturedAt:
                  DateTime.tryParse(s['captured_at']?.toString() ?? ''),
            )));
    } catch (e) {
      developer.log('Failed to load selfies: $e',
          name: 'DeviceSecurityProvider');
    }
    notifyListeners();
  }

  /// Add trusted SIM (POST /device/{id}/sim/trusted).
  Future<void> addTrustedSIM(String iccid) async {
    if (_deviceId == null) return;
    try {
      await _api.addTrustedSIM(iccid, 'Trusted SIM');
      await loadSettings();
      await loadSIMHistory();
    } catch (e) {
      _error = 'Failed to add trusted SIM: $e';
      notifyListeners();
    }
  }

  /// Audit OS vulnerabilities (POST /device/vulnerabilities/audit).
  /// Parses the real models.OSSecurityAuditResult shape and refreshes the
  /// overall status so the score reflects the new audit.
  Future<List<OSVulnerability>> auditVulnerabilities() async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _api.auditOSVulnerabilities();
      final vulnerabilities = (data['vulnerabilities'] as List? ?? const [])
          .whereType<Map>()
          .map((v) =>
              OSVulnerability.fromBackendJson(v.cast<String, dynamic>()))
          .toList();

      _status = _status.copyWith(vulnerabilities: vulnerabilities);
      _error = null;
      _isLoading = false;
      notifyListeners();

      // The backend recomputes the overall score from the audit on the next
      // status read.
      unawaited(loadStatus());
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
