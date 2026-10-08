// Generates the reminder sounds as 16-bit mono WAV files.
//
// The sounds are synthesised rather than recorded, so there is no licence to
// track and the result is reproducible: run this and the same bytes come out.
//
//   dart run tools/generate_sounds.dart
//
// Each sound is deliberately a different shape, not the same beep at a
// different pitch, because a settings screen that offers six names for one
// sound is a fake choice. They are written twice:
//
//   assets/sounds/<id>.wav                          for the in-app preview
//   android/app/src/main/res/raw/<id>.wav           for the notification channel
//
// Android reads raw resources by file name, so the ids are lower-case with
// underscores only.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const sampleRate = 44100;

/// One summed, enveloped tone.
class Tone {
  const Tone({
    required this.start,
    required this.length,
    required this.partials,
    this.decay = 6.0,
    this.shape = Shape.sine,
  });

  /// Seconds from the start of the file.
  final double start;
  final double length;

  /// (frequency in Hz, amplitude) pairs, summed together.
  final List<(double, double)> partials;

  /// Larger is a faster fade. Bells ring out; beeps are cut off.
  final double decay;
  final Shape shape;
}

enum Shape { sine, square }

double _wave(Shape shape, double phase) {
  final s = math.sin(phase);
  return switch (shape) {
    Shape.sine => s,
    // A softened square, so it reads as "digital" without being painful.
    Shape.square => s >= 0 ? 0.6 : -0.6,
  };
}

Uint8List render(double seconds, List<Tone> tones) {
  final total = (seconds * sampleRate).round();
  final mix = List<double>.filled(total, 0);

  for (final tone in tones) {
    final first = (tone.start * sampleRate).round();
    final count = (tone.length * sampleRate).round();
    for (var i = 0; i < count && first + i < total; i++) {
      final t = i / sampleRate;
      var sample = 0.0;
      for (final (freq, amp) in tone.partials) {
        sample += amp * _wave(tone.shape, 2 * math.pi * freq * t);
      }
      // An exponential fade, plus a few milliseconds of fade-in and fade-out
      // at the edges, because an abrupt start or stop is heard as a click.
      final fade = math.exp(-tone.decay * t / tone.length);
      final edgeIn = math.min(1.0, t / 0.005);
      final edgeOut = math.min(1.0, (tone.length - t) / 0.01);
      mix[first + i] += sample * fade * edgeIn * edgeOut;
    }
  }

  // Normalise to 85% of full scale so every sound is about equally loud and
  // none of them clips.
  final peak = mix.fold<double>(0, (m, v) => math.max(m, v.abs()));
  final gain = peak == 0 ? 0.0 : 0.85 / peak;

  final data = ByteData(44 + total * 2);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      data.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + total * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, total * 2, Endian.little);
  for (var i = 0; i < total; i++) {
    final v = (mix[i] * gain * 32767).round().clamp(-32768, 32767);
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

/// A bell: a fundamental plus harmonics, ringing out slowly.
List<Tone> softBell() => [
      const Tone(
        start: 0,
        length: 2.0,
        decay: 5,
        partials: [(880, 1.0), (1760, 0.32), (2640, 0.10)],
      ),
    ];

/// A heavier bell: inharmonic partials (the ratios real bells have) give the
/// clangy, metallic character, struck twice.
List<Tone> classicBell() => [
      for (final start in [0.0, 0.95])
        Tone(
          start: start,
          length: 1.5,
          decay: 4.5,
          partials: const [(523, 1.0), (1443, 0.55), (2824, 0.35), (4610, 0.18)],
        ),
    ];

/// Three short, sharp beeps.
List<Tone> alert() => [
      for (var i = 0; i < 3; i++)
        Tone(
          start: i * 0.28,
          length: 0.18,
          decay: 1.2,
          partials: const [(1000, 1.0)],
        ),
    ];

/// Square-wave beeps alternating between two pitches.
List<Tone> digital() => [
      for (var i = 0; i < 4; i++)
        Tone(
          start: i * 0.2,
          length: 0.12,
          decay: 0.6,
          shape: Shape.square,
          partials: [(i.isEven ? 1200.0 : 900.0, 1.0)],
        ),
    ];

/// A rising arpeggio, C - E - G - C, each note ringing into the next.
List<Tone> chime() => [
      for (final (i, freq) in [523.25, 659.25, 783.99, 1046.5].indexed)
        Tone(
          start: i * 0.3,
          length: 1.0,
          decay: 5,
          partials: [(freq, 1.0), (freq * 2, 0.22)],
        ),
    ];

/// A two-tone siren. The one meant to interrupt.
List<Tone> urgent() => [
      for (var i = 0; i < 8; i++)
        Tone(
          start: i * 0.3,
          length: 0.3,
          decay: 0.4,
          shape: Shape.square,
          partials: [(i.isEven ? 700.0 : 1100.0, 1.0)],
        ),
    ];

void main() {
  final sounds = <String, Uint8List>{
    'soft_bell': render(2.2, softBell()),
    'classic_bell': render(2.6, classicBell()),
    'alert': render(1.0, alert()),
    'digital': render(0.9, digital()),
    'chime': render(2.2, chime()),
    'urgent': render(2.5, urgent()),
  };

  final targets = [
    Directory('assets/sounds'),
    Directory('android/app/src/main/res/raw'),
  ];

  for (final dir in targets) {
    dir.createSync(recursive: true);
    for (final entry in sounds.entries) {
      File('${dir.path}/${entry.key}.wav').writeAsBytesSync(entry.value);
    }
  }

  for (final entry in sounds.entries) {
    stdout.writeln('${entry.key}.wav  ${entry.value.length} bytes');
  }
}
