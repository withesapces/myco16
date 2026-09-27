// Traitement des enregistrements micro : décodage WAV, passe-haut,
// débruitage par soustraction spectrale, expander, coupe des silences.
// cleanRecording() tourne dans un isolate via compute().
import 'dart:math';
import 'dart:typed_data';

import 'synth.dart';

/// Décode un WAV PCM 16 bits (mono ou stéréo) en mono float à kSr.
Float64List? decodeWav(Uint8List bytes) {
  if (bytes.length < 44) return null;
  final b = ByteData.sublistView(bytes);
  String tag(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  var o = 12, channels = 1, bits = 16, dataOff = -1, dataLen = 0, rate = kSr;
  while (o + 8 <= bytes.length) {
    final id = tag(o);
    final len = b.getUint32(o + 4, Endian.little);
    if (id == 'fmt ') {
      channels = b.getUint16(o + 10, Endian.little);
      rate = b.getUint32(o + 12, Endian.little);
      bits = b.getUint16(o + 22, Endian.little);
    } else if (id == 'data') {
      dataOff = o + 8;
      dataLen = min(len, bytes.length - dataOff);
      break;
    }
    o += 8 + len + (len & 1);
  }
  if (dataOff < 0 || bits != 16 || channels < 1) return null;
  final frames = dataLen ~/ (2 * channels);
  if (frames < 32) return null;
  final raw = Float64List(frames);
  for (var i = 0; i < frames; i++) {
    var acc = 0.0;
    for (var c = 0; c < channels; c++) {
      acc += b.getInt16(dataOff + (i * channels + c) * 2, Endian.little);
    }
    raw[i] = acc / channels / 32768.0;
  }
  if (rate == kSr || rate <= 0) return raw;
  final n = (frames * kSr / rate).floor();
  final x = Float64List(n);
  for (var i = 0; i < n; i++) {
    final p = i * rate / kSr;
    final j = p.floor();
    final fr = p - j;
    final a = raw[min(j, frames - 1)];
    final c = raw[min(j + 1, frames - 1)];
    x[i] = a + (c - a) * fr;
  }
  return x;
}

/// FFT complexe radix-2, en place.
class Fft {
  final int n;
  late final Float64List _cos;
  late final Float64List _sin;
  late final Int32List _rev;

  Fft(this.n) {
    _cos = Float64List(n ~/ 2);
    _sin = Float64List(n ~/ 2);
    for (var k = 0; k < n ~/ 2; k++) {
      _cos[k] = cos(2 * pi * k / n);
      _sin[k] = sin(2 * pi * k / n);
    }
    var bitsCount = 0;
    while ((1 << bitsCount) < n) {
      bitsCount++;
    }
    _rev = Int32List(n);
    for (var i = 0; i < n; i++) {
      var r = 0;
      for (var bIdx = 0; bIdx < bitsCount; bIdx++) {
        if ((i >> bIdx) & 1 == 1) r |= 1 << (bitsCount - 1 - bIdx);
      }
      _rev[i] = r;
    }
  }

  void run(Float64List re, Float64List im, {bool inverse = false}) {
    for (var i = 0; i < n; i++) {
      final j = _rev[i];
      if (j > i) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var size = 2; size <= n; size <<= 1) {
      final half = size >> 1;
      final step = n ~/ size;
      for (var i = 0; i < n; i += size) {
        for (var k = 0; k < half; k++) {
          final c = _cos[k * step];
          final s = inverse ? _sin[k * step] : -_sin[k * step];
          final a = i + k;
          final bb = a + half;
          final tr = re[bb] * c - im[bb] * s;
          final ti = re[bb] * s + im[bb] * c;
          re[bb] = re[a] - tr;
          im[bb] = im[a] - ti;
          re[a] += tr;
          im[a] += ti;
        }
      }
    }
    if (inverse) {
      for (var i = 0; i < n; i++) {
        re[i] /= n;
        im[i] /= n;
      }
    }
  }
}

/// Soustraction spectrale : le profil de bruit est estimé sur les trames
/// les plus calmes de l'enregistrement (le silence avant le son).
Float64List spectralDenoise(Float64List x,
    {int n = 1024, double alpha = 3.5, double floor = 0.025}) {
  final hop = n ~/ 4;
  if (x.length < n * 3) return x;
  final fft = Fft(n);
  final win = Float64List(n);
  for (var i = 0; i < n; i++) {
    win[i] = 0.5 - 0.5 * cos(2 * pi * i / n);
  }
  final frames = (x.length - n) ~/ hop + 1;
  final bins = n ~/ 2 + 1;

  // 1. énergie de chaque trame, on garde les 15 % les plus calmes
  final energy = List<double>.generate(frames, (f) {
    var e = 0.0;
    for (var i = 0; i < n; i++) {
      final v = x[f * hop + i];
      e += v * v;
    }
    return e;
  });
  final order = List<int>.generate(frames, (i) => i)
    ..sort((a, b) => energy[a].compareTo(energy[b]));
  final quietCount = max(3, (frames * 0.15).round());
  // Garde-fou : sans vrai silence dans l'enregistrement, le "bruit" estimé
  // serait le son lui-même. On ne débruite que si l'écart calme/fort > 9 dB.
  final loudCount = max(3, (frames * 0.3).round());
  var quietE = 0.0, loudE = 0.0;
  for (var q = 0; q < quietCount && q < frames; q++) {
    quietE += energy[order[q]];
  }
  for (var q = 0; q < loudCount && q < frames; q++) {
    loudE += energy[order[frames - 1 - q]];
  }
  quietE /= quietCount;
  loudE /= loudCount;
  if (loudE < quietE * 8) return x;
  final noise = Float64List(bins);
  final re = Float64List(n);
  final im = Float64List(n);
  for (var q = 0; q < quietCount && q < frames; q++) {
    final f = order[q];
    for (var i = 0; i < n; i++) {
      re[i] = x[f * hop + i] * win[i];
      im[i] = 0;
    }
    fft.run(re, im);
    for (var k = 0; k < bins; k++) {
      noise[k] += (re[k] * re[k] + im[k] * im[k]) / quietCount;
    }
  }

  // 2. atténuation bin par bin, lissée dans le temps (moins de "bruit musical")
  final out = Float64List(x.length);
  final prevG = Float64List(bins)..fillRange(0, bins, 1.0);
  final floor2 = floor * floor;
  for (var f = 0; f < frames; f++) {
    for (var i = 0; i < n; i++) {
      re[i] = x[f * hop + i] * win[i];
      im[i] = 0;
    }
    fft.run(re, im);
    for (var k = 0; k < bins; k++) {
      final p = re[k] * re[k] + im[k] * im[k] + 1e-18;
      var g = 1 - alpha * noise[k] / p;
      if (g < floor2) g = floor2;
      var gain = sqrt(g);
      gain = 0.65 * gain + 0.35 * prevG[k];
      prevG[k] = gain;
      re[k] *= gain;
      im[k] *= gain;
      if (k > 0 && k < n ~/ 2) {
        re[n - k] *= gain;
        im[n - k] *= gain;
      }
    }
    fft.run(re, im, inverse: true);
    for (var i = 0; i < n; i++) {
      out[f * hop + i] += re[i] * win[i] / 1.5;
    }
  }
  return out;
}

Float64List _highpass(Float64List x, double fc) {
  final f = Biquad.hp(fc, 0.707);
  final y = Float64List(x.length);
  for (var i = 0; i < x.length; i++) {
    y[i] = f.p(x[i]);
  }
  return y;
}

double _percentile(List<double> v, double p) {
  if (v.isEmpty) return 0;
  final s = List<double>.from(v)..sort();
  return s[min(s.length - 1, (s.length * p).floor())];
}

/// Chaîne complète. Renvoie un WAV prêt à jouer, ou une liste vide
/// si l'enregistrement est trop faible ou trop court.
Uint8List cleanRecording(Uint8List bytes) {
  final decoded = decodeWav(bytes);
  if (decoded == null) return Uint8List(0);
  var x = _highpass(decoded, 70);
  x = spectralDenoise(x);

  // enveloppe par blocs de 5 ms
  final block = (0.005 * kSr).round();
  final nb = x.length ~/ block;
  if (nb < 4) return Uint8List(0);
  final peaks = List<double>.generate(nb, (bI) {
    var m = 0.0;
    for (var i = bI * block; i < (bI + 1) * block; i++) {
      final a = x[i].abs();
      if (a > m) m = a;
    }
    return m;
  });
  final peak = peaks.reduce(max);
  if (peak < 1e-4) return Uint8List(0);
  final noiseLevel = _percentile(peaks, 0.2);
  final thr = max(noiseLevel * 4, peak * 0.04);

  var first = peaks.indexWhere((p) => p > thr);
  var last = peaks.lastIndexWhere((p) => p > thr);
  if (first < 0 || last <= first) return Uint8List(0);
  final start = max(0, first * block - (0.003 * kSr).round());
  final end = min(x.length, (last + 1) * block + (0.04 * kSr).round());
  if (end - start < (0.02 * kSr).round()) return Uint8List(0);

  // expander : ce qui reste sous le seuil est poussé vers le silence
  final out = Float64List(end - start);
  final att = exp(-1 / (0.001 * kSr));
  final rel = exp(-1 / (0.06 * kSr));
  final expThr = max(noiseLevel * 2.5, peak * 0.02);
  var env = 0.0;
  for (var i = 0; i < out.length; i++) {
    final v = x[start + i];
    final a = v.abs();
    env = a > env ? att * env + (1 - att) * a : rel * env + (1 - rel) * a;
    var g = 1.0;
    if (env < expThr) {
      final r = env / expThr;
      g = r * r;
    }
    out[i] = v * g;
  }

  var outPeak = 0.0;
  for (final v in out) {
    if (v.abs() > outPeak) outPeak = v.abs();
  }
  if (outPeak < 1e-5) return Uint8List(0);
  final gain = min(0.95 / outPeak, 16.0);
  final fadeIn = min(out.length, (0.002 * kSr).round());
  final fadeOut = min(out.length, (0.015 * kSr).round());
  for (var i = 0; i < out.length; i++) {
    var g = gain;
    if (i < fadeIn) g *= i / fadeIn;
    final fromEnd = out.length - 1 - i;
    if (fromEnd < fadeOut) g *= fromEnd / fadeOut;
    out[i] *= g;
  }
  return toWav(out);
}
