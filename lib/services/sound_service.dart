import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class SoundService {
  final AudioPlayer _sfxPlayer = AudioPlayer();
  Uint8List? _cachedChimeWav;

  SoundService() {
    _cachedChimeWav = _generateNotificationChimeWav();
  }

  /// Riproduce l'SFX quando arriva una richiesta di trasferimento file
  Future<void> playIncomingRequestSfx() async {
    try {
      final Uint8List wavBytes =
          _cachedChimeWav ?? _generateNotificationChimeWav();
      await _sfxPlayer.stop();
      await _sfxPlayer.play(BytesSource(wavBytes), volume: 0.85);
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
  }

  /// Genera un file WAV PCM 16-bit 44.1kHz stereo/mono in memoria (chime a 2 toni: 587Hz -> 880Hz)
  Uint8List _generateNotificationChimeWav() {
    const int sampleRate = 44100;
    const double durationSeconds = 0.48;
    final int numSamples = (sampleRate * durationSeconds).toInt();
    final int dataSize = numSamples * 2; // 16-bit mono = 2 byte per campione
    final ByteData buffer = ByteData(44 + dataSize);

    // Header RIFF WAVE
    _writeString(buffer, 0, 'RIFF');
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    _writeString(buffer, 8, 'WAVE');
    _writeString(buffer, 12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little); // Subchunk1Size (PCM)
    buffer.setUint16(20, 1, Endian.little); // AudioFormat = 1 (PCM)
    buffer.setUint16(22, 1, Endian.little); // NumChannels = 1 (Mono)
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
    buffer.setUint16(32, 2, Endian.little); // BlockAlign
    buffer.setUint16(34, 16, Endian.little); // BitsPerSample
    _writeString(buffer, 36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);

    // Sintesi chime armonico a due note (D5 = 587.33 Hz, A5 = 880.0 Hz)
    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final bool isSecondNote = t >= 0.16;
      final double localT = isSecondNote ? (t - 0.16) : t;
      final double freq = isSecondNote ? 880.0 : 587.33;

      final double envelope = math.exp(-localT * 9.5);
      final double wave = (math.sin(2 * math.pi * freq * t) * 0.75 +
              math.sin(2 * math.pi * (freq * 2) * t) * 0.25) *
          envelope;

      final int sample = (wave * 24000).clamp(-32767, 32767).toInt();
      buffer.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  void _writeString(ByteData data, int offset, String value) {
    for (int i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  void dispose() {
    _sfxPlayer.dispose();
  }
}
