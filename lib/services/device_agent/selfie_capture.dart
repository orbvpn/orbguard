/// Thief Selfie Capture
/// Captures a real photo from the front camera in response to a remote
/// "take_selfie" command and uploads it per the backend contract
/// (POST /api/v1/device/{device_id}/selfie with models.ThiefSelfie:
/// image_url, image_hash, trigger_type, attempt_count, location?).
///
/// The image is embedded as a base64 data URI in image_url (the backend
/// stores the field verbatim) with a SHA-256 hash in image_hash so the
/// stored image is integrity-verifiable.
///
/// SCOPE NOTE (honest): third-party apps cannot hook the OPERATING-SYSTEM lock
/// screen's failed-attempt events — on iOS there is no DeviceAdminReceiver
/// equivalent at all, and on Android the OEM "wrong passcode -> selfie" flow is
/// not exposed to apps. There are therefore exactly two real triggers:
///   1. The remote 'take_selfie' command (device_agent.dart), which on iOS is
///      delivered by HTTP polling — so it runs on the next foreground poll, not
///      instantly (the app has no push channel for commands; see latency note
///      in device_agent.dart's take_selfie handler).
///   2. The IN-APP biometric app-lock (app_lock.dart): N failed unlock attempts
///      of OrbGuard's own lock call [captureAndUpload] with triggerType
///      'wrong_pin'. This is the platform-supported "best extent" of the
///      feature within the app sandbox.

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:permission_handler/permission_handler.dart';

import 'agent_api.dart';

class SelfieCaptureResult {
  /// The backend-assigned selfie id when upload succeeded.
  final String? selfieId;

  /// Honest failure detail when [selfieId] is null.
  final String? failureReason;

  const SelfieCaptureResult.success(this.selfieId) : failureReason = null;

  const SelfieCaptureResult.failure(this.failureReason) : selfieId = null;

  bool get ok => selfieId != null;
}

class SelfieCapture {
  /// Captures a front-camera photo and uploads it. Every failure mode
  /// returns an explicit reason for the command ack — no silent success.
  Future<SelfieCaptureResult> captureAndUpload(
    DeviceAgentApi api, {
    required String triggerType,
    int attemptCount = 0,
    Map<String, dynamic>? location,
  }) async {
    final permission = await Permission.camera.request();
    if (!permission.isGranted) {
      return const SelfieCaptureResult.failure(
        'camera permission not granted',
      );
    }

    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } catch (e) {
      return SelfieCaptureResult.failure('failed to enumerate cameras: $e');
    }

    CameraDescription? front;
    for (final cam in cameras) {
      if (cam.lensDirection == CameraLensDirection.front) {
        front = cam;
        break;
      }
    }
    if (front == null) {
      return const SelfieCaptureResult.failure(
        'no front camera available on this device',
      );
    }

    CameraController? controller;
    try {
      controller = CameraController(
        front,
        // Medium keeps the JSON payload reasonable (~100-300 KB base64)
        // while remaining identifiable.
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();

      final hash = sha256.convert(bytes).toString();
      final dataUri = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      final response = await api.uploadSelfie(
        imageUrl: dataUri,
        imageHash: hash,
        triggerType: triggerType,
        attemptCount: attemptCount,
        location: location,
      );

      final selfieId = response['selfie_id']?.toString();
      if (selfieId == null || selfieId.isEmpty) {
        return const SelfieCaptureResult.failure(
          'backend did not return a selfie_id',
        );
      }

      developer.log(
        'thief selfie captured and uploaded (id=$selfieId, '
        '${bytes.length} bytes, trigger=$triggerType)',
        name: 'SelfieCapture',
      );
      return SelfieCaptureResult.success(selfieId);
    } on CameraException catch (e) {
      return SelfieCaptureResult.failure(
        'camera error: ${e.code} ${e.description ?? ''}'.trim(),
      );
    } catch (e) {
      return SelfieCaptureResult.failure('selfie capture failed: $e');
    } finally {
      try {
        await controller?.dispose();
      } catch (e) {
        developer.log('camera dispose failed: $e', name: 'SelfieCapture');
      }
    }
  }
}
