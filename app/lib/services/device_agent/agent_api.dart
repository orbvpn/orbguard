// Device Agent API
// Thin, contract-exact wrapper over [OrbGuardApiClient]'s generic HTTP
// helpers for the device-agent endpoints that have no dedicated client
// method yet (see notes in Wave 5 handoff):
//
//   GET  /api/v1/device/{device_id}/commands/pending
//   POST /api/v1/device/{device_id}/commands/{command_id}/ack
//   POST /api/v1/device/{device_id}/location
//   POST /api/v1/device/{device_id}/sim
//   GET  /api/v1/device/{device_id}/sim
//   POST /api/v1/device/{device_id}/selfie
//   GET  /api/v1/device/{device_id}/selfies
//   GET  /api/v1/device/{device_id}/settings
//
// Shapes mirror orbguard.lab internal/api/handlers/device_security.go and
// internal/domain/models/device_security.go exactly.

import '../api/api_config.dart';
import '../api/orbguard_api_client.dart';

class DeviceAgentApi {
  final OrbGuardApiClient _client;

  /// The backend device_id (hardware id) this agent acts for.
  final String deviceId;

  DeviceAgentApi(this._client, this.deviceId);

  String get _base => '${ApiConfig.apiVersion}/device/$deviceId';

  /// GET /device/{id}/commands/pending
  /// Response: { "device_id", "commands": [RemoteCommand...], "count" }
  Future<List<Map<String, dynamic>>> fetchPendingCommands() async {
    final data = await _client.get<Map<String, dynamic>>(
      '$_base/commands/pending',
    );
    final commands = data['commands'];
    if (commands is! List) {
      throw const FormatException(
        'Unexpected pending-commands response: missing "commands" list',
      );
    }
    return commands.whereType<Map>().map((c) => c.cast<String, dynamic>()).toList();
  }

  /// POST /device/{id}/commands/{command_id}/ack
  /// Body: { "result": "...", "error": "..." } — a non-empty "error" marks
  /// the command failed on the backend; otherwise it is marked executed.
  Future<void> ackCommand(
    String commandId, {
    String result = '',
    String error = '',
  }) async {
    await _client.post<dynamic>(
      '$_base/commands/$commandId/ack',
      data: {'result': result, 'error': error},
    );
  }

  /// POST /device/{id}/location — body is models.Location.
  Future<void> reportLocation(Map<String, dynamic> location) async {
    await _client.post<dynamic>('$_base/location', data: location);
  }

  /// POST /device/{id}/sim — body is a JSON ARRAY of models.SIMInfo.
  Future<void> reportSims(List<Map<String, dynamic>> sims) async {
    await _client.post<dynamic>('$_base/sim', data: sims);
  }

  /// GET /device/{id}/sim — response: { "device_id", "sims": [...], "count" }
  Future<List<Map<String, dynamic>>> getCurrentSims() async {
    final data = await _client.get<Map<String, dynamic>>('$_base/sim');
    final sims = data['sims'];
    if (sims is! List) {
      throw const FormatException(
        'Unexpected current-SIMs response: missing "sims" list',
      );
    }
    return sims.whereType<Map>().map((s) => s.cast<String, dynamic>()).toList();
  }

  /// POST /device/{id}/selfie — body is models.ThiefSelfie
  /// (image_url, image_hash, trigger_type, attempt_count, location?).
  /// Response: { "status": "recorded", "selfie_id": "..." }
  Future<Map<String, dynamic>> uploadSelfie({
    required String imageUrl,
    required String imageHash,
    required String triggerType,
    int attemptCount = 0,
    Map<String, dynamic>? location,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '$_base/selfie',
      data: {
        'image_url': imageUrl,
        'image_hash': imageHash,
        'trigger_type': triggerType,
        'attempt_count': attemptCount,
        if (location != null) 'location': location,
      },
    );
    return data;
  }

  /// GET /device/{id}/selfies — response: { "device_id", "selfies": [...], "count" }
  Future<List<Map<String, dynamic>>> getSelfies() async {
    final data = await _client.get<Map<String, dynamic>>('$_base/selfies');
    final selfies = data['selfies'];
    if (selfies is! List) {
      throw const FormatException(
        'Unexpected selfies response: missing "selfies" list',
      );
    }
    return selfies.whereType<Map>().map((s) => s.cast<String, dynamic>()).toList();
  }

  /// GET /device/{id}/settings — response is models.AntiTheftSettings.
  Future<Map<String, dynamic>> getSettings() async {
    return _client.get<Map<String, dynamic>>('$_base/settings');
  }
}
