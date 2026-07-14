// Device Agent — the on-device anti-theft executor.
//
// Responsibilities (Wave 5, W5.3):
//  * Periodic + on-demand location reporting (geolocator) honoring the
//    user's enable_remote_locate setting, battery-conscious via
//    significant-change filtering and a configurable interval.
//  * Remote-command polling (GET /device/{id}/commands/pending) on a
//    foreground timer and on app resume, with honest execution + ack
//    (POST /device/{id}/commands/{command_id}/ack) for every supported
//    command. Commands that need privileges this app does not hold are
//    acked FAILED with the true reason — never silently "executed".
//  * SIM-change monitoring and reporting (POST /device/{id}/sim).
//  * Thief-selfie capture on the take_selfie command
//    (POST /device/{id}/selfie).
//
// BACKGROUND EXECUTION (documented limitation): a Dart foreground timer
// dies with the app. True background polling uses the workmanager plugin:
// on Android a 15-minute periodic task is registered (WorkManager's
// platform minimum) running [deviceAgentBackgroundDispatcher] in a
// headless isolate. On iOS, BGTaskScheduler registration requires native
// AppDelegate/Info.plist wiring owned by the platform-channel stream, so
// background polling is reported as unavailable there — foreground timer +
// resume polling still work.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import '../../utils/platform_info.dart';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../api/orbguard_api_client.dart';
import '../notifications/notification_service.dart';
import '../security/auto_scan_scheduler.dart';
import 'agent_api.dart';
import 'device_admin.dart';
import 'location_reporter.dart';
import 'ringer.dart';
import 'selfie_capture.dart';
import 'sim_monitor.dart';

/// SharedPreferences key the API auth interceptor persists the registered
/// device id under (lib/services/api/api_interceptors.dart). The background
/// isolate has no provider tree, so it re-reads the id from here.
const String kRegisteredDeviceIdPrefsKey = 'orbguard_device_id';

const String _kLastLocationReportKey = 'device_agent.last_location_report';
const String _kPolicyKey = 'device_agent.policy';
const String _kBackgroundTaskUniqueName = 'orbguard.device_agent.poll';
const String _kBackgroundTaskName = 'deviceAgentPoll';

/// The agent-relevant subset of the backend models.AntiTheftSettings.
class AgentPolicy {
  final bool remoteLocateEnabled;
  final bool remoteLockEnabled;
  final bool remoteWipeEnabled;
  final bool thiefSelfieEnabled;
  final bool simAlertEnabled;

  /// How often periodic location reports are sent when nothing moved.
  final Duration locationReportInterval;

  /// Movement beyond this distance triggers a report before the interval
  /// elapses (significant-change, battery-conscious).
  final double significantChangeMeters;

  const AgentPolicy({
    required this.remoteLocateEnabled,
    required this.remoteLockEnabled,
    required this.remoteWipeEnabled,
    required this.thiefSelfieEnabled,
    required this.simAlertEnabled,
    this.locationReportInterval = const Duration(minutes: 15),
    this.significantChangeMeters = 150,
  });

  /// Parses the backend models.AntiTheftSettings JSON shape.
  factory AgentPolicy.fromBackendJson(Map<String, dynamic> json) {
    return AgentPolicy(
      remoteLocateEnabled: json['enable_remote_locate'] == true,
      remoteLockEnabled: json['enable_remote_lock'] == true,
      remoteWipeEnabled: json['enable_remote_wipe'] == true,
      thiefSelfieEnabled: json['enable_thief_selfie'] == true,
      simAlertEnabled: json['enable_sim_alert'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'enable_remote_locate': remoteLocateEnabled,
        'enable_remote_lock': remoteLockEnabled,
        'enable_remote_wipe': remoteWipeEnabled,
        'enable_thief_selfie': thiefSelfieEnabled,
        'enable_sim_alert': simAlertEnabled,
        'location_report_interval_min': locationReportInterval.inMinutes,
        'significant_change_meters': significantChangeMeters,
      };

  factory AgentPolicy.fromLocalJson(Map<String, dynamic> json) {
    return AgentPolicy(
      remoteLocateEnabled: json['enable_remote_locate'] == true,
      remoteLockEnabled: json['enable_remote_lock'] == true,
      remoteWipeEnabled: json['enable_remote_wipe'] == true,
      thiefSelfieEnabled: json['enable_thief_selfie'] == true,
      simAlertEnabled: json['enable_sim_alert'] == true,
      locationReportInterval: Duration(
          minutes: (json['location_report_interval_min'] as num?)?.toInt() ?? 15),
      significantChangeMeters:
          (json['significant_change_meters'] as num?)?.toDouble() ?? 150,
    );
  }
}

/// One executed (or honestly failed / deferred) remote command.
class CommandExecution {
  final String commandId;
  final String type;
  final DateTime at;

  /// executed | failed | deferred (deferred = left pending for a foreground
  /// poll because the capability needs UI/camera access).
  final String outcome;
  final String? detail;

  const CommandExecution({
    required this.commandId,
    required this.type,
    required this.at,
    required this.outcome,
    this.detail,
  });

  bool get ok => outcome == 'executed';
}

/// A message-command payload surfaced to the UI.
class AgentDisplayMessage {
  final String title;
  final String message;
  final DateTime receivedAt;

  const AgentDisplayMessage({
    required this.title,
    required this.message,
    required this.receivedAt,
  });
}

class DeviceAgent extends ChangeNotifier with WidgetsBindingObserver {
  static DeviceAgent? _instance;
  static DeviceAgent get instance => _instance ??= DeviceAgent._(headless: false);

  DeviceAgent._({required bool headless}) : _headless = headless;

  final bool _headless;

  DeviceAgentApi? _api;
  AgentPolicy _policy = const AgentPolicy(
    remoteLocateEnabled: false,
    remoteLockEnabled: false,
    remoteWipeEnabled: false,
    thiefSelfieEnabled: false,
    simAlertEnabled: false,
  );

  final LocationReporter _locationReporter = LocationReporter();
  final SimMonitor _simMonitor = SimMonitor();
  final SelfieCapture _selfieCapture = SelfieCapture();
  final DeviceRinger _ringer = DeviceRinger();
  final DeviceAdminBridge _adminBridge = DeviceAdminBridge();

  Timer? _pollTimer;
  bool _running = false;
  bool _polling = false;

  DateTime? _lastPollAt;
  String? _lastError;
  String? _locationStatus;
  String? _simStatus;
  String? _backgroundStatus;
  AgentDisplayMessage? _lastDisplayMessage;
  final List<CommandExecution> _recentExecutions = [];

  // ---- public state ----
  bool get isRunning => _running;
  String? get deviceId => _api?.deviceId;
  AgentPolicy get policy => _policy;
  DateTime? get lastPollAt => _lastPollAt;
  String? get lastError => _lastError;

  /// Honest description of the last location-report attempt.
  String? get locationStatus => _locationStatus;

  /// Honest description of the SIM-monitoring state.
  String? get simStatus => _simStatus;

  /// Honest description of background-polling support on this platform.
  String? get backgroundStatus => _backgroundStatus;

  AgentDisplayMessage? get lastDisplayMessage => _lastDisplayMessage;

  List<CommandExecution> get recentExecutions =>
      List.unmodifiable(_recentExecutions);

  /// Starts the agent for the registered device. Idempotent; re-starting
  /// with a new device id rebinds.
  Future<void> start({
    required String deviceId,
    required AgentPolicy policy,
  }) async {
    _api = DeviceAgentApi(OrbGuardApiClient.instance, deviceId);
    _policy = policy;
    await _persistPolicy(policy);

    if (!_running) {
      _running = true;
      if (!_headless) {
        WidgetsBinding.instance.addObserver(this);
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(
          const Duration(seconds: 60),
          (_) => pollNow(),
        );
        await _registerBackgroundTask();
      }
    }
    notifyListeners();

    // Initial cycle — do not block the caller's init path.
    unawaited(pollNow());
  }

  Future<void> updatePolicy(AgentPolicy policy) async {
    _policy = policy;
    await _persistPolicy(policy);
    notifyListeners();
  }

  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_running && !_headless) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _running = false;
    await _ringer.stop();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _running) {
      unawaited(pollNow());
    }
  }

  /// Runs one full agent cycle: pending commands, due location report,
  /// SIM check. Reentrancy-guarded.
  Future<void> pollNow() async {
    final api = _api;
    if (api == null || !_running || _polling) return;
    _polling = true;
    try {
      await _runCycle(api, foreground: !_headless);
      _lastError = null;
    } catch (e) {
      _lastError = 'agent cycle failed: $e';
      developer.log(_lastError!, name: 'DeviceAgent');
    } finally {
      _lastPollAt = DateTime.now();
      _polling = false;
      notifyListeners();
    }
  }

  // -------------------------------------------------------------------
  // Cycle
  // -------------------------------------------------------------------

  Future<void> _runCycle(DeviceAgentApi api, {required bool foreground}) async {
    // 1. Remote commands.
    List<Map<String, dynamic>> commands;
    try {
      commands = await api.fetchPendingCommands();
    } catch (e) {
      _lastError = 'failed to fetch pending commands: $e';
      developer.log(_lastError!, name: 'DeviceAgent');
      commands = const [];
    }
    for (final cmd in commands) {
      await _executeCommand(api, cmd, foreground: foreground);
    }

    // 2. Periodic location report (independent of locate commands).
    if (_policy.remoteLocateEnabled) {
      await _reportLocationIfDue(api);
    } else {
      _locationStatus = 'periodic location reporting disabled in settings';
    }

    // 3. SIM monitoring.
    if (_policy.simAlertEnabled) {
      final sim = await _simMonitor.detectAndReport(api);
      if (sim.detail != null) {
        _simStatus = sim.detail;
      } else if (sim.reported) {
        _simStatus = 'SIM state reported at ${DateTime.now().toIso8601String()}';
      } else {
        _simStatus = 'SIM unchanged since last report';
      }
    } else {
      _simStatus = 'SIM monitoring disabled in settings';
    }
  }

  /// Battery-conscious reporting: a report is sent only when the configured
  /// interval has elapsed OR the device moved more than the
  /// significant-change distance since the last report.
  Future<void> _reportLocationIfDue(DeviceAgentApi api) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic>? last;
    final raw = prefs.getString(_kLastLocationReportKey);
    if (raw != null) {
      try {
        last = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        last = null;
      }
    }

    final now = DateTime.now();
    final lastAt = last != null
        ? DateTime.fromMillisecondsSinceEpoch((last['at'] as num).toInt())
        : null;
    final intervalElapsed = lastAt == null ||
        now.difference(lastAt) >= _policy.locationReportInterval;

    if (!intervalElapsed) {
      // Interval not reached — only report early on significant movement,
      // which we can check cheaply against the OS-cached position without
      // powering up the GPS radio.
      try {
        final cached = await Geolocator.getLastKnownPosition();
        if (cached == null || last == null) return;
        final moved = Geolocator.distanceBetween(
          (last['lat'] as num).toDouble(),
          (last['lon'] as num).toDouble(),
          cached.latitude,
          cached.longitude,
        );
        if (moved < _policy.significantChangeMeters) return;
      } catch (_) {
        return; // can't determine movement cheaply; wait for the interval
      }
    }

    final fix = await _locationReporter.getCurrentFix();
    if (!fix.isAvailable) {
      _locationStatus = 'location unavailable: ${fix.unavailableReason}';
      return;
    }

    try {
      await api.reportLocation(fix.location!);
      _locationStatus = 'location reported at ${now.toIso8601String()}';
      await prefs.setString(
        _kLastLocationReportKey,
        jsonEncode({
          'at': now.millisecondsSinceEpoch,
          'lat': fix.position!.latitude,
          'lon': fix.position!.longitude,
        }),
      );
    } catch (e) {
      _locationStatus = 'failed to report location: $e';
      developer.log(_locationStatus!, name: 'DeviceAgent');
    }
  }

  // -------------------------------------------------------------------
  // Command execution
  // -------------------------------------------------------------------

  Future<void> _executeCommand(
    DeviceAgentApi api,
    Map<String, dynamic> cmd, {
    required bool foreground,
  }) async {
    final commandId = cmd['id']?.toString() ?? '';
    final type = cmd['type']?.toString() ?? '';
    if (commandId.isEmpty || type.isEmpty) {
      developer.log('skipping malformed command: $cmd', name: 'DeviceAgent');
      return;
    }

    Map<String, dynamic> payload = const {};
    final rawPayload = cmd['payload'];
    if (rawPayload is String && rawPayload.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPayload);
        if (decoded is Map<String, dynamic>) payload = decoded;
      } catch (e) {
        developer.log('command $commandId has unparseable payload: $e',
            name: 'DeviceAgent');
      }
    }

    Future<void> ackExecuted(String result) =>
        api.ackCommand(commandId, result: result);
    Future<void> ackFailed(String reason) =>
        api.ackCommand(commandId, error: reason);

    String outcome = 'failed';
    String? detail;

    try {
      switch (type) {
        case 'locate':
          if (!_policy.remoteLocateEnabled) {
            detail = 'remote locate is disabled in anti-theft settings';
            await ackFailed(detail);
            break;
          }
          final fix = await _locationReporter.getCurrentFix();
          if (!fix.isAvailable) {
            detail = fix.unavailableReason;
            await ackFailed(detail!);
            break;
          }
          await api.reportLocation(fix.location!);
          detail = jsonEncode({
            'latitude': fix.position!.latitude,
            'longitude': fix.position!.longitude,
            'accuracy_meters': fix.position!.accuracy,
          });
          await ackExecuted(detail);
          outcome = 'executed';
          break;

        case 'ring':
          final seconds =
              (payload['duration'] as num?)?.toInt() ?? 60;
          try {
            await _ringer.start(duration: Duration(seconds: seconds));
            detail = 'alarm playing for ${seconds}s';
            await ackExecuted(detail);
            outcome = 'executed';
          } catch (e) {
            detail = 'alarm playback failed: $e';
            await ackFailed(detail);
          }
          break;

        case 'lock':
          if (!_policy.remoteLockEnabled) {
            detail = 'remote lock is disabled in anti-theft settings';
            await ackFailed(detail);
            break;
          }
          final lock = await _adminBridge.lockNow();
          if (lock.ok) {
            detail = 'device locked via device administrator';
            await ackExecuted(detail);
            outcome = 'executed';
          } else {
            detail = lock.failureReason;
            await ackFailed(detail!);
          }
          break;

        case 'wipe':
          if (!_policy.remoteWipeEnabled) {
            detail = 'remote wipe is disabled in anti-theft settings';
            await ackFailed(detail);
            break;
          }
          final wipe = await _adminBridge.wipe(
            wipeSdCard: payload['wipe_sd_card'] == true,
          );
          if (wipe.ok) {
            detail = 'factory reset initiated via device administrator';
            await ackExecuted(detail);
            outcome = 'executed';
          } else {
            detail = wipe.failureReason;
            await ackFailed(detail!);
          }
          break;

        case 'take_selfie':
          if (!foreground) {
            // Camera capture needs the app process in the foreground; leave
            // the command pending so the next foreground poll runs it
            // (commands expire server-side if that never happens).
            //
            // LATENCY (honest): this client has NO push channel for commands
            // — they are HTTP-polled (60s foreground timer + poll-on-resume;
            // Android adds a 15-min WorkManager cycle, iOS has no background
            // scheduling here). So a remote selfie is captured the next time
            // the app is foregrounded, NOT instantly. The genuinely prompt
            // path on iOS is the in-app biometric lock (app_lock.dart), whose
            // failed-unlock attempts capture a selfie while the app is open.
            outcome = 'deferred';
            detail = 'selfie deferred to next foreground poll '
                '(camera unavailable in background isolate)';
            developer.log(detail, name: 'DeviceAgent');
            break;
          }
          if (!_policy.thiefSelfieEnabled) {
            detail = 'thief selfie is disabled in anti-theft settings';
            await ackFailed(detail);
            break;
          }
          final selfie = await _selfieCapture.captureAndUpload(
            api,
            triggerType: 'remote_command',
          );
          if (selfie.ok) {
            detail = jsonEncode({'selfie_id': selfie.selfieId});
            await ackExecuted(detail);
            outcome = 'executed';
          } else {
            detail = selfie.failureReason;
            await ackFailed(detail!);
          }
          break;

        case 'message':
          if (!foreground) {
            outcome = 'deferred';
            detail = 'message display deferred to next foreground poll';
            developer.log(detail, name: 'DeviceAgent');
            break;
          }
          final title = payload['title']?.toString() ?? 'Message from owner';
          final body = payload['message']?.toString() ?? '';
          _lastDisplayMessage = AgentDisplayMessage(
            title: title,
            message: body,
            receivedAt: DateTime.now(),
          );
          try {
            await NotificationService.instance.init();
            await NotificationService.instance.showNotification(
              title: title,
              body: body.isEmpty ? '(no message text)' : body,
            );
            detail = 'message displayed as notification';
            await ackExecuted(detail);
            outcome = 'executed';
          } catch (e) {
            detail = 'failed to display message: $e';
            await ackFailed(detail);
          }
          break;

        case 'get_status':
          detail = jsonEncode({
            'platform': PlatformInfo.operatingSystem,
            'os_version': PlatformInfo.operatingSystemVersion,
            'agent_running': true,
            'remote_locate_enabled': _policy.remoteLocateEnabled,
            'sim_alert_enabled': _policy.simAlertEnabled,
            'device_admin_active': await _adminBridge.isAdminActive(),
            'reported_at': DateTime.now().toUtc().toIso8601String(),
          });
          await ackExecuted(detail);
          outcome = 'executed';
          break;

        case 'unlock':
          detail = 'remote unlock is not supported by this client '
              '(requires resetting the device credential, which Android '
              'prohibits for third-party apps since API 24)';
          await ackFailed(detail);
          break;

        case 'backup':
          detail = 'remote backup is not implemented in this client';
          await ackFailed(detail);
          break;

        default:
          detail = 'unknown command type "$type"';
          await ackFailed(detail);
          break;
      }
    } catch (e) {
      detail = 'command execution error: $e';
      developer.log('command $commandId ($type) raised: $e',
          name: 'DeviceAgent');
      try {
        await ackFailed(detail);
      } catch (ackErr) {
        developer.log('ack for $commandId also failed: $ackErr',
            name: 'DeviceAgent');
      }
    }

    if (outcome != 'deferred' || foreground) {
      _recentExecutions.insert(
        0,
        CommandExecution(
          commandId: commandId,
          type: type,
          at: DateTime.now(),
          outcome: outcome,
          detail: detail,
        ),
      );
      if (_recentExecutions.length > 50) {
        _recentExecutions.removeRange(50, _recentExecutions.length);
      }
    }
  }

  // -------------------------------------------------------------------
  // Background scheduling
  // -------------------------------------------------------------------

  Future<void> _registerBackgroundTask() async {
    if (!PlatformInfo.isAndroid) {
      _backgroundStatus =
          'background polling unavailable on ${PlatformInfo.operatingSystem}: '
          'iOS/desktop background scheduling requires native registration '
          'not present in this build; the agent polls while the app is open '
          'and on every app resume';
      developer.log(_backgroundStatus!, name: 'DeviceAgent');
      return;
    }
    try {
      await Workmanager().initialize(deviceAgentBackgroundDispatcher);
      await Workmanager().registerPeriodicTask(
        _kBackgroundTaskUniqueName,
        _kBackgroundTaskName,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(networkType: NetworkType.connected),
      );
      _backgroundStatus =
          'Android WorkManager periodic task registered (15 min minimum '
          'interval enforced by the platform)';
      developer.log(_backgroundStatus!, name: 'DeviceAgent');
    } catch (e) {
      _backgroundStatus = 'failed to register background task: $e';
      developer.log(_backgroundStatus!, name: 'DeviceAgent');
    }
  }

  Future<void> _persistPolicy(AgentPolicy policy) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPolicyKey, jsonEncode(policy.toJson()));
    } catch (e) {
      developer.log('failed to persist agent policy: $e', name: 'DeviceAgent');
    }
  }

  /// One headless cycle for the background isolate. Returns false (so
  /// WorkManager retries) only on infrastructure failure; "nothing to do"
  /// is success.
  static Future<bool> runHeadlessCycle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString(kRegisteredDeviceIdPrefsKey);
      if (deviceId == null || deviceId.isEmpty) {
        developer.log(
          'background cycle skipped: device not registered yet',
          name: 'DeviceAgent',
        );
        return true;
      }

      // The client init loads the persisted device id + api key from
      // SharedPreferences; it only re-registers when no id exists, which we
      // just verified it does.
      await OrbGuardApiClient.instance.init();

      final api = DeviceAgentApi(OrbGuardApiClient.instance, deviceId);

      // Fresh policy from the backend; fall back to the last policy the
      // foreground agent persisted if that fetch fails.
      AgentPolicy policy;
      try {
        policy = AgentPolicy.fromBackendJson(await api.getSettings());
      } catch (e) {
        developer.log(
          'background cycle: settings fetch failed ($e), using persisted '
          'local policy',
          name: 'DeviceAgent',
        );
        final raw = prefs.getString(_kPolicyKey);
        if (raw == null) {
          developer.log(
            'background cycle skipped: no persisted policy available',
            name: 'DeviceAgent',
          );
          return true;
        }
        policy = AgentPolicy.fromLocalJson(
            jsonDecode(raw) as Map<String, dynamic>);
      }

      final agent = DeviceAgent._(headless: true);
      agent._api = api;
      agent._policy = policy;
      agent._running = true;
      await agent._runCycle(api, foreground: false);
      await agent._ringer.stop();

      // Piggyback the automatic security scan on the same background cycle
      // (self-throttled to the user's scan frequency).
      await AutoScanScheduler.instance.runIfDue();
      return true;
    } catch (e) {
      developer.log('background cycle failed: $e', name: 'DeviceAgent');
      return false;
    }
  }
}

/// WorkManager entry point. Must be a top-level (or static) function and
/// survive tree-shaking, hence the pragma.
@pragma('vm:entry-point')
void deviceAgentBackgroundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    return DeviceAgent.runHeadlessCycle();
  });
}
