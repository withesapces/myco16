// Synthèse des 16 sons d'usine et encodage WAV 16 bits mono.
import 'dart:math';
import 'dart:typed_data';

const int kSr = 44100;
final Random _rnd = Random(33);

Uint8List toWav(Float64List s) {
  final n = s.length;
  final b = ByteData(44 + n * 2);
  void str(int o, String t) {
    for (var i = 0; i < t.length; i++) {
      b.setUint8(o + i, t.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, kSr, Endian.little);
  b.setUint32(28, kSr * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final v = (s[i].clamp(-1.0, 1.0) * 32767).round();
    b.setInt16(44 + i * 2, v, Endian.little);
  }
  return b.buffer.asUint8List();
}

Float64List _buf(double seconds) => Float64List((seconds * kSr).round());
double _noise() => _rnd.nextDouble() * 2 - 1;
double _lpA(double fc) => 1 - exp(-2 * pi * fc / kSr);
double _sat(double x, double drive) => _tanh(x * drive) / _tanh(drive);
double _tanh(double x) {
  final e = exp(2 * x);
  return (e - 1) / (e + 1);
}

// Fade de 3 ms en fin de son pour éviter les clics.
Float64List _tail(Float64List s) {
  final f = (0.003 * kSr).round();
  for (var i = 0; i < f && i < s.length; i++) {
    s[s.length - 1 - i] *= i / f;
  }
  return s;
}

double _saw(double ph) => 2 * (ph - ph.floorToDouble()) - 1;
double _sq(double ph) => (ph - ph.floorToDouble()) < 0.5 ? 1.0 : -1.0;
double _hz(int midi) => 440 * pow(2, (midi - 69) / 12).toDouble();

// ── BATTERIE ─────────────────────────────────
Float64List kick() {
  final s = _buf(0.45);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    final f = 45 + 120 * exp(-t * 32);
    ph += 2 * pi * f / kSr;
    var v = sin(ph) * exp(-t * 6.5);
    if (t < 0.002) v += _noise() * 0.4;
    s[i] = _sat(v, 2.2) * 0.95;
  }
  return _tail(s);
}

Float64List snare() {
  final s = _buf(0.25);
  var ph = 0.0, hp = 0.0, prev = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * 190 / kSr;
    final n = _noise();
    hp = 0.9 * (hp + n - prev);
    prev = n;
    s[i] = (sin(ph) * exp(-t * 22) * 0.5 + hp * exp(-t * 15) * 0.6) * 0.9;
  }
  return _tail(s);
}

Float64List clap() {
  final s = _buf(0.35);
  var hp = 0.0, prev = 0.0, lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    final n = _noise();
    hp = 0.95 * (hp + n - prev);
    prev = n;
    lp += _lpA(2500) * (hp - lp);
    double env;
    if (t < 0.03) {
      env = exp(-((t % 0.01)) * 300);
    } else {
      env = exp(-(t - 0.03) * 16);
    }
    s[i] = lp * env * 1.4;
  }
  return _tail(s);
}

Float64List hat(double len, double decay) {
  final s = _buf(len);
  var prev = 0.0, hp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    final n = _noise();
    hp = 0.6 * (hp + n - prev);
    prev = n;
    s[i] = hp * exp(-t * decay) * 0.55;
  }
  return _tail(s);
}

Float64List tom() {
  final s = _buf(0.35);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * (95 + 60 * exp(-t * 18)) / kSr;
    s[i] = sin(ph) * exp(-t * 10) * 0.85;
  }
  return _tail(s);
}

Float64List rim() {
  final s = _buf(0.07);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * 1700 / kSr;
    s[i] = (sin(ph) * 0.6 + _noise() * 0.3) * exp(-t * 90);
  }
  return _tail(s);
}

Float64List zap() {
  final s = _buf(0.3);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * (80 + 2400 * exp(-t * 35)) / kSr;
    s[i] = sin(ph) * exp(-t * 11) * 0.7;
  }
  return _tail(s);
}

// ── MÉLODIQUE (Fa mineur) ────────────────────
Float64List subPluck() {
  final s = _buf(0.3);
  final f = _hz(41); // F2
  var ph = 0.0, lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += f / kSr;
    lp += _lpA(200 + 1800 * exp(-t * 25)) * (_saw(ph) - lp);
    s[i] = _sat(lp * exp(-t * 7), 1.8) * 0.9;
  }
  return _tail(s);
}

Float64List acid() {
  final s = _buf(0.28);
  final f = _hz(48); // C3
  var ph = 0.0, lp = 0.0, bp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += f / kSr;
    final fc = 300 + 3500 * exp(-t * 14);
    final a = _lpA(fc);
    // filtre résonant simple (deux pôles, rétroaction)
    lp += a * (_sq(ph) - lp - bp * 0.9);
    bp += a * (lp - bp);
    s[i] = _sat(bp * exp(-t * 6), 2.5) * 0.7;
  }
  return _tail(s);
}

Float64List bell() {
  final s = _buf(0.9);
  final f = _hz(65); // F4
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    final mod = sin(2 * pi * f * 3.5 * t) * 2.2 * exp(-t * 6);
    s[i] = sin(2 * pi * f * t + mod) * exp(-t * 4.5) * 0.6;
  }
  return _tail(s);
}

Float64List stab() {
  final s = _buf(0.35);
  final fs = [_hz(53), _hz(56), _hz(60), _hz(65)]; // F Ab C F
  final ph = List<double>.filled(4, 0);
  var lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    var v = 0.0;
    for (var k = 0; k < 4; k++) {
      ph[k] += fs[k] * (1 + 0.003 * k) / kSr;
      v += _saw(ph[k]);
    }
    lp += _lpA(900 + 4000 * exp(-t * 12)) * (v / 4 - lp);
    s[i] = lp * exp(-t * 7) * 0.9;
  }
  return _tail(s);
}

Float64List psyLead() {
  final s = _buf(0.3);
  final f = _hz(60); // C4
  var ph = 0.0, ph2 = 0.0, lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    final bend = 1 + 0.5 * exp(-t * 60);
    ph += f * bend / kSr;
    ph2 += f * bend * 1.007 / kSr;
    lp += _lpA(1500 + 5000 * exp(-t * 20)) * ((_saw(ph) + _saw(ph2)) / 2 - lp);
    s[i] = lp * exp(-t * 9) * 0.8;
  }
  return _tail(s);
}

Float64List laser() {
  final s = _buf(0.4);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * (300 + 3000 * (t / 0.4) * (t / 0.4)) / kSr;
    s[i] = sin(ph) * exp(-t * 5) * 0.55;
  }
  return _tail(s);
}

Float64List blip() {
  final s = _buf(0.12);
  final f = _hz(89); // F6
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    s[i] = sin(2 * pi * f * t) * exp(-t * 35) * 0.6;
  }
  return _tail(s);
}

Float64List riser() {
  final s = _buf(1.0);
  var lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    lp += _lpA(200 + 9000 * t * t) * (_noise() - lp);
    s[i] = lp * (t < 0.9 ? t / 0.9 : (1 - t) * 10) * 0.8;
  }
  return _tail(s);
}

/// Les 16 sons d'usine, dans l'ordre des pads.
/// 1 à 8 : mélodique, 9 à 16 : batterie (comme sur un pocket operator).
List<MapEntry<String, Float64List Function()>> factorySounds() => [
      MapEntry('SUB', subPluck),
      MapEntry('ACID', acid),
      MapEntry('BELL', bell),
      MapEntry('STAB', stab),
      MapEntry('LEAD', psyLead),
      MapEntry('LASER', laser),
      MapEntry('BLIP', blip),
      MapEntry('RISER', riser),
      MapEntry('KICK', kick),
      MapEntry('SNARE', snare),
      MapEntry('CLAP', clap),
      MapEntry('CH', () => hat(0.08, 55)),
      MapEntry('OH', () => hat(0.4, 9)),
      MapEntry('TOM', tom),
      MapEntry('RIM', rim),
      MapEntry('ZAP', zap),
    ];

/// Lit un WAV PCM 16 bits, coupe le silence du début et normalise.
/// Renvoie null si le format n'est pas reconnu.
Float64List? trimAndNormalize(Uint8List bytes, {double maxSeconds = 6}) {
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
  final raw = Float64List(frames);
  for (var i = 0; i < frames; i++) {
    raw[i] = b.getInt16(dataOff + i * 2 * channels, Endian.little) / 32768.0;
  }
  // Rééchantillonnage linéaire si besoin
  Float64List x = raw;
  if (rate != kSr && rate > 0) {
    final n = (frames * kSr / rate).floor();
    x = Float64List(n);
    for (var i = 0; i < n; i++) {
      final p = i * rate / kSr;
      final j = p.floor();
      final fr = p - j;
      final a = raw[min(j, frames - 1)];
      final c = raw[min(j + 1, frames - 1)];
      x[i] = a + (c - a) * fr;
    }
  }
  var peak = 0.0;
  for (final v in x) {
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak < 0.005) return null;
  final thr = peak * 0.08;
  var start = 0;
  while (start < x.length && x[start].abs() < thr) {
    start++;
  }
  start = max(0, start - (0.004 * kSr).round());
  final end = min(x.length, start + (maxSeconds * kSr).round());
  final out = Float64List(end - start);
  final g = 0.95 / peak;
  final fadeIn = min(out.length, (0.002 * kSr).round());
  for (var i = 0; i < out.length; i++) {
    out[i] = x[start + i] * g * (i < fadeIn ? i / fadeIn : 1);
  }
  return _tail(out);
}
