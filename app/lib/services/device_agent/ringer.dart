// Device Ringer
// Plays a loud warble alarm in response to a remote "ring" command. The
// tone is synthesized in-memory as a 16-bit mono WAV (no bundled asset
// required) and looped at full player volume through the Android ALARM
// audio usage / iOS playback category so it sounds even when media volume
// behaviors differ.

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

class DeviceRinger {
  AudioPlayer? _player;
  Timer? _stopTimer;

  bool get isRinging => _player != null;

  /// Starts the alarm for [duration] (default 60s, the backend command
  /// payload can override). Throws on real playback failure so the caller
  /// can ack the command as failed with the true reason.
  Future<void> start({Duration duration = const Duration(seconds: 60)}) async {
    await stop();

    final player = AudioPlayer();
    _player = player;

    await player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.alarm,
        audioFocus: AndroidAudioFocus.gain,
        stayAwake: true,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
      ),
    ));
    await player.setReleaseMode(ReleaseMode.loop);
    await player.setVolume(1.0);
    await player.play(BytesSource(_buildAlarmWav(), mimeType: 'audio/wav'));

    _stopTimer = Timer(duration, () {
      stop();
    });

    developer.log('alarm started for ${duration.inSeconds}s', name: 'DeviceRinger');
  }

  Future<void> stop() async {
    _stopTimer?.cancel();
    _stopTimer = null;
    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.stop();
        await player.dispose();
      } catch (e) {
        developer.log('ringer stop failed: $e', name: 'DeviceRinger');
      }
    }
  }

  /// Builds a 2-second siren-style warble (880 Hz <-> 1760 Hz) as a
  /// 44.1 kHz 16-bit mono PCM WAV. Looped by the player.
  Uint8List _buildAlarmWav() {
    const sampleRate = 44100;
    const seconds = 2;
    const sampleCount = sampleRate * seconds;

    final samples = Int16List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      // Sweep frequency up and down twice per second.
      final sweep = (math.sin(2 * math.pi * 2 * t) + 1) / 2; // 0..1
      final freq = 880 + (1760 - 880) * sweep;
      final amplitude = 0.85 * 32767;
      samples[i] = (amplitude * math.sin(2 * math.pi * freq * t)).round();
    }

    final dataLength = samples.length * 2;
    final bytes = BytesBuilder();

    void writeString(String s) => bytes.add(s.codeUnits);
    void writeUint32(int v) {
      final b = ByteData(4)..setUint32(0, v, Endian.little);
      bytes.add(b.buffer.asUint8List());
    }

    void writeUint16(int v) {
      final b = ByteData(2)..setUint16(0, v, Endian.little);
      bytes.add(b.buffer.asUint8List());
    }

    writeString('RIFF');
    writeUint32(36 + dataLength);
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16); // PCM chunk size
    writeUint16(1); // PCM format
    writeUint16(1); // mono
    writeUint32(sampleRate);
    writeUint32(sampleRate * 2); // byte rate (mono 16-bit)
    writeUint16(2); // block align
    writeUint16(16); // bits per sample
    writeString('data');
    writeUint32(dataLength);
    bytes.add(samples.buffer.asUint8List());

    return bytes.toBytes();
  }
}
