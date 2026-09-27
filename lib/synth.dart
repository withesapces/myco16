// Banque de sons synthétisés en Dart + encodage WAV 16 bits mono.
// Tout est généré au lancement : l'APK n'embarque aucun fichier audio.
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
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
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

/// Filtre biquad (formules RBJ).
class Biquad {
  double _b0 = 1, _b1 = 0, _b2 = 0, _a1 = 0, _a2 = 0, _z1 = 0, _z2 = 0;

  Biquad.lp(double f, double q) {
    setLp(f, q);
  }
  Biquad.hp(double f, double q) {
    _set(1, f, q);
  }
  Biquad.bp(double f, double q) {
    _set(2, f, q);
  }

  void setLp(double f, double q) => _set(0, f, q);

  void _set(int type, double f, double q) {
    final fc = f.clamp(10.0, kSr * 0.45);
    final w = 2 * pi * fc / kSr;
    final cw = cos(w);
    final al = sin(w) / (2 * q);
    final a0 = 1 + al;
    double b0, b1, b2;
    if (type == 0) {
      b0 = (1 - cw) / 2;
      b1 = 1 - cw;
      b2 = (1 - cw) / 2;
    } else if (type == 1) {
      b0 = (1 + cw) / 2;
      b1 = -(1 + cw);
      b2 = (1 + cw) / 2;
    } else {
      b0 = al;
      b1 = 0;
      b2 = -al;
    }
    _b0 = b0 / a0;
    _b1 = b1 / a0;
    _b2 = b2 / a0;
    _a1 = -2 * cw / a0;
    _a2 = (1 - al) / a0;
  }

  double p(double x) {
    final y = _b0 * x + _z1;
    _z1 = _b1 * x - _a1 * y + _z2;
    _z2 = _b2 * x - _a2 * y;
    return y;
  }
}

Float64List _buf(double seconds) => Float64List((seconds * kSr).round());
double _noise() => _rnd.nextDouble() * 2 - 1;
double _lpA(double fc) => 1 - exp(-2 * pi * fc / kSr);
double _tanh(double x) {
  if (x > 20) return 1;
  if (x < -20) return -1;
  final e = exp(2 * x);
  return (e - 1) / (e + 1);
}

double _sat(double x, double drive) => _tanh(x * drive) / _tanh(drive);
double _saw(double ph) => 2 * (ph - ph.floorToDouble()) - 1;
double _sq(double ph) => (ph - ph.floorToDouble()) < 0.5 ? 1.0 : -1.0;
double _hz(int midi) => 440 * pow(2, (midi - 69) / 12).toDouble();

Float64List _tail(Float64List s) {
  final f = (0.004 * kSr).round();
  for (var i = 0; i < f && i < s.length; i++) {
    s[s.length - 1 - i] *= i / f;
  }
  return s;
}

Float64List _norm(Float64List s, [double target = 0.9]) {
  var p = 0.0;
  for (final v in s) {
    if (v.abs() > p) p = v.abs();
  }
  if (p > 0) {
    final g = target / p;
    for (var i = 0; i < s.length; i++) {
      s[i] *= g;
    }
  }
  return _tail(s);
}

// ════════════════ KICKS ════════════════
Float64List kick({
  double len = 0.45,
  double f0 = 160,
  double f1 = 45,
  double pd = 32,
  double ad = 6.5,
  double click = 0.4,
  double drive = 2.2,
  double hold = 0,
}) {
  final s = _buf(len);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    final f = f1 + (f0 - f1) * exp(-t * pd);
    ph += 2 * pi * f / kSr;
    final env = t < hold ? 1.0 : exp(-(t - hold) * ad);
    var v = sin(ph) * env;
    if (t < 0.003) v += _noise() * click * (1 - t / 0.003);
    s[i] = _sat(v, drive);
  }
  return _norm(s, 0.95);
}

Float64List rumbleKick() {
  final k = kick(len: 1.1, f0: 230, f1: 50, pd: 25, ad: 6, click: 0.5, drive: 1.8);
  final lp = Biquad.lp(140, 0.9);
  var ph = 0.0;
  for (var i = 0; i < k.length; i++) {
    final t = i / kSr - 0.06;
    if (t < 0) continue;
    ph += 2 * pi * 46 / kSr;
    final env = (1 - exp(-t * 25)) * exp(-t * 3.2);
    final r = lp.p(_noise() * 0.7 + sin(ph) * 0.8) * env;
    k[i] += _sat(r * 2.5, 2) * 0.55;
  }
  return _norm(k, 0.95);
}

Float64List tribalKick() {
  final s = kick(len: 0.3, f0: 220, f1: 80, pd: 30, ad: 14, click: 0.2, drive: 1.5);
  final bp = Biquad.bp(1200, 3);
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    s[i] += bp.p(_noise()) * exp(-t * 60) * 0.6;
  }
  return _norm(s);
}

// ════════════════ CAISSES / CLAPS ════════════════
Float64List snare() {
  final s = _buf(0.25);
  final hp = Biquad.hp(1500, 0.7);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * 190 / kSr;
    s[i] = sin(ph) * exp(-t * 22) * 0.5 + hp.p(_noise()) * exp(-t * 15) * 0.7;
  }
  return _norm(s);
}

Float64List snare909() {
  final s = _buf(0.35);
  final hp = Biquad.hp(2200, 0.7);
  var p1 = 0.0, p2 = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    p1 += 2 * pi * 180 / kSr;
    p2 += 2 * pi * 330 / kSr;
    s[i] = (sin(p1) + 0.5 * sin(p2)) * exp(-t * 20) * 0.45 +
        hp.p(_noise()) * exp(-t * 9) * 0.6;
  }
  return _norm(s);
}

Float64List clap({double tail = 16, double len = 0.35}) {
  final s = _buf(len);
  final bp = Biquad.bp(1300, 1.2);
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    final env = t < 0.03 ? exp(-(t % 0.01) * 300) : exp(-(t - 0.03) * tail);
    s[i] = bp.p(_noise()) * env;
  }
  return _norm(s);
}

Float64List snap() {
  final s = _buf(0.12);
  final bp = Biquad.bp(2600, 1.5);
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    s[i] = bp.p(_noise()) * exp(-t * 55);
  }
  return _norm(s);
}

Float64List rim() {
  final s = _buf(0.07);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * 1700 / kSr;
    s[i] = (sin(ph) * 0.6 + _noise() * 0.3) * exp(-t * 90);
  }
  return _norm(s, 0.7);
}

// ════════════════ HATS ════════════════
Float64List noiseHat(double len, double decay) {
  final s = _buf(len);
  final hp = Biquad.hp(7000, 0.7);
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    s[i] = hp.p(_noise()) * exp(-t * decay);
  }
  return _norm(s, 0.6);
}

Float64List metalHat(double len, double decay, {double hpF = 7000, double tune = 1}) {
  final s = _buf(len);
  const fr = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0];
  final ph = List<double>.filled(6, 0);
  final hp = Biquad.hp(hpF, 0.8);
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    var v = 0.0;
    for (var k = 0; k < 6; k++) {
      ph[k] += fr[k] * 1.7 * tune / kSr;
      v += _sq(ph[k]);
    }
    s[i] = hp.p(v / 6 + _noise() * 0.15) * exp(-t * decay);
  }
  return _norm(s, 0.6);
}

Float64List shaker() {
  final s = _buf(0.16);
  final bp = Biquad.bp(6500, 1.2);
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    final env = min(1.0, t / 0.02) * exp(-t * 20);
    s[i] = bp.p(_noise()) * env;
  }
  return _norm(s, 0.55);
}

// ════════════════ PERCUS ════════════════
Float64List tom(double base) {
  final s = _buf(0.35);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * (base + base * 0.6 * exp(-t * 18)) / kSr;
    s[i] = sin(ph) * exp(-t * 10);
  }
  return _norm(s, 0.85);
}

Float64List conga() {
  final s = _buf(0.3);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * 220 * (1 + 0.3 * exp(-t * 80)) / kSr;
    var v = sin(ph) * exp(-t * 14);
    if (t < 0.002) v += _noise() * 0.5;
    s[i] = v;
  }
  return _norm(s, 0.8);
}

Float64List woodblock() {
  final s = _buf(0.1);
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    s[i] = (sin(2 * pi * 900 * t) + 0.3 * sin(2 * pi * 1420 * t)) * exp(-t * 45);
  }
  return _norm(s, 0.8);
}

Float64List cowbell() {
  final s = _buf(0.35);
  final bp = Biquad.bp(800, 2);
  var p1 = 0.0, p2 = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    p1 += 540 / kSr;
    p2 += 800 / kSr;
    s[i] = bp.p(_sq(p1) + _sq(p2)) * exp(-t * 12);
  }
  return _norm(s, 0.7);
}

Float64List tick() {
  final s = _buf(0.03);
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    s[i] = _noise() * exp(-t * 400) + sin(2 * pi * 3000 * t) * exp(-t * 300);
  }
  return _norm(s, 0.7);
}

Float64List metal() {
  final s = _buf(0.8);
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    final idx = 5 * exp(-t * 6);
    s[i] = sin(2 * pi * 330 * t + idx * sin(2 * pi * 330 * 1.41 * t)) * exp(-t * 5);
  }
  return _norm(s, 0.7);
}

Float64List zap() {
  final s = _buf(0.3);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * (80 + 2400 * exp(-t * 35)) / kSr;
    s[i] = sin(ph) * exp(-t * 11);
  }
  return _norm(s, 0.75);
}

// ════════════════ BASSES (Fa) ════════════════
Float64List subPluck() {
  final s = _buf(0.3);
  final f = _hz(41);
  var ph = 0.0, lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += f / kSr;
    lp += _lpA(200 + 1800 * exp(-t * 25)) * (_saw(ph) - lp);
    s[i] = _sat(lp * exp(-t * 7), 1.8);
  }
  return _norm(s);
}

Float64List rollBass() {
  final s = _buf(0.16);
  final f = _hz(41);
  final lp = Biquad.lp(2000, 1.4);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += f / kSr;
    if (i % 16 == 0) lp.setLp(180 + 2600 * exp(-t * 40), 1.4);
    s[i] = _sat(lp.p(_saw(ph)) * exp(-t * 14), 2);
  }
  return _norm(s);
}

Float64List acid() {
  final s = _buf(0.28);
  final f = _hz(48);
  var ph = 0.0, lp = 0.0, bp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += f / kSr;
    final a = _lpA(300 + 3500 * exp(-t * 14));
    lp += a * (_sq(ph) - lp - bp * 0.9);
    bp += a * (lp - bp);
    s[i] = _sat(bp * exp(-t * 6), 2.5);
  }
  return _norm(s, 0.75);
}

Float64List reese() {
  final s = _buf(0.9);
  final f = _hz(41);
  final lp = Biquad.lp(650, 0.9);
  var p1 = 0.0, p2 = 0.0, p3 = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    p1 += f * 1.007 / kSr;
    p2 += f * 0.993 / kSr;
    p3 += f / 2 / kSr;
    final env = min(1.0, t / 0.01) * (t > 0.75 ? (0.9 - t) / 0.15 : 1.0);
    s[i] = (lp.p((_saw(p1) + _saw(p2)) / 2) + sin(2 * pi * p3) * 0.5) * env;
  }
  return _norm(s);
}

Float64List bounceBass() {
  final s = _buf(0.35);
  final f = _hz(41);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * f * (1 + exp(-t * 30)) / kSr;
    s[i] = _sat(sin(ph) * exp(-t * 6), 2);
  }
  return _norm(s);
}

Float64List fmBass() {
  final s = _buf(0.5);
  final f = _hz(41);
  final lp = Biquad.lp(1600, 0.8);
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    final idx = 1 + 4 * exp(-t * 8);
    s[i] = lp.p(sin(2 * pi * f * t + idx * sin(2 * pi * f * t))) * exp(-t * 5);
  }
  return _norm(s);
}

// ════════════════ SYNTHS ════════════════
Float64List bell() {
  final s = _buf(0.9);
  final f = _hz(65);
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    final mod = sin(2 * pi * f * 3.5 * t) * 2.2 * exp(-t * 6);
    s[i] = sin(2 * pi * f * t + mod) * exp(-t * 4.5);
  }
  return _norm(s, 0.7);
}

Float64List stab() {
  final s = _buf(0.35);
  final fs = [_hz(53), _hz(56), _hz(60), _hz(65)];
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
    s[i] = lp * exp(-t * 7);
  }
  return _norm(s, 0.8);
}

Float64List psyLead() {
  final s = _buf(0.3);
  final f = _hz(60);
  var ph = 0.0, ph2 = 0.0, lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    final bend = 1 + 0.5 * exp(-t * 60);
    ph += f * bend / kSr;
    ph2 += f * bend * 1.007 / kSr;
    lp += _lpA(1500 + 5000 * exp(-t * 20)) * ((_saw(ph) + _saw(ph2)) / 2 - lp);
    s[i] = lp * exp(-t * 9);
  }
  return _norm(s, 0.8);
}

Float64List pluck() {
  final f = _hz(65);
  final n = (kSr / f).round();
  final line = Float64List(n);
  for (var i = 0; i < n; i++) {
    line[i] = _noise();
  }
  final s = _buf(0.9);
  var idx = 0;
  for (var i = 0; i < s.length; i++) {
    final nxt = (idx + 1) % n;
    final v = line[idx];
    line[idx] = 0.996 * 0.5 * (line[idx] + line[nxt]);
    s[i] = v;
    idx = nxt;
  }
  return _norm(s, 0.75);
}

Float64List vox() {
  final s = _buf(0.8);
  final f1 = Biquad.bp(700, 8), f2 = Biquad.bp(1220, 10), f3 = Biquad.bp(2600, 12);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += _hz(48) * (1 + 0.01 * sin(2 * pi * 5.5 * t)) / kSr;
    final src = _saw(ph);
    final v = f1.p(src) + 0.5 * f2.p(src) + 0.3 * f3.p(src);
    s[i] = v * min(1.0, t / 0.03) * exp(-t * 2.5);
  }
  return _norm(s, 0.75);
}

Float64List drone() {
  final s = _buf(2.0);
  final lp = Biquad.lp(800, 1.2);
  final fs = [_hz(41), _hz(41) * 1.004, _hz(48), _hz(53) * 0.997];
  final ph = List<double>.filled(4, 0);
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    var v = 0.0;
    for (var k = 0; k < 4; k++) {
      ph[k] += fs[k] / kSr;
      v += _saw(ph[k]);
    }
    if (i % 32 == 0) lp.setLp(500 + 900 * (0.5 + 0.5 * sin(2 * pi * 0.6 * t)), 1.2);
    final env = min(1.0, t / 0.4) * min(1.0, (2.0 - t) / 0.4);
    s[i] = lp.p(v / 4) * env;
  }
  return _norm(s, 0.7);
}

// ════════════════ FX ════════════════
Float64List laser() {
  final s = _buf(0.4);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * (300 + 3000 * (t / 0.4) * (t / 0.4)) / kSr;
    s[i] = sin(ph) * exp(-t * 5);
  }
  return _norm(s, 0.6);
}

Float64List blip() {
  final s = _buf(0.12);
  final f = _hz(89);
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    s[i] = sin(2 * pi * f * t) * exp(-t * 35);
  }
  return _norm(s, 0.6);
}

Float64List riser() {
  final s = _buf(1.0);
  var lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    lp += _lpA(200 + 9000 * t * t) * (_noise() - lp);
    s[i] = lp * (t < 0.9 ? t / 0.9 : (1 - t) * 10);
  }
  return _norm(s, 0.75);
}

Float64List downlifter() {
  final s = _buf(1.0);
  final lp = Biquad.lp(9000, 1.5);
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    if (i % 32 == 0) lp.setLp(200 + 9000 * (1 - t) * (1 - t), 1.5);
    s[i] = lp.p(_noise()) * (1 - t);
  }
  return _norm(s, 0.75);
}

Float64List impact() {
  final s = _buf(1.5);
  final lp = Biquad.lp(3000, 0.7);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * (40 + 60 * exp(-t * 20)) / kSr;
    s[i] = _sat(sin(ph) * exp(-t * 3) + lp.p(_noise()) * exp(-t * 8) * 0.7, 2.5);
  }
  return _norm(s, 0.9);
}

Float64List whoop() {
  final s = _buf(0.5);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * (300 + 1500 * sin(pi * t / 0.5)) / kSr;
    s[i] = sin(ph) * sin(pi * t / 0.5);
  }
  return _norm(s, 0.6);
}

Float64List bird() {
  final s = _buf(0.32);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * (3200 + 900 * sin(2 * pi * 14 * t)) / kSr;
    final local = t % 0.09;
    s[i] = sin(ph) * exp(-local * 45) * (t < 0.27 ? 1 : 0);
  }
  return _norm(s, 0.5);
}

Float64List drop() {
  final s = _buf(0.15);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / kSr;
    ph += 2 * pi * (600 + 1400 * (1 - exp(-t * 40))) / kSr;
    s[i] = sin(ph) * exp(-t * 30);
  }
  return _norm(s, 0.65);
}

// ════════════════ BIBLIOTHÈQUE ════════════════
class SoundDef {
  final String id;
  final String name;
  final String cat;
  final Float64List Function() gen;
  const SoundDef(this.id, this.name, this.cat, this.gen);
}

const List<String> kCategories = [
  'KICK', 'CAISSE', 'HAT', 'PERCU', 'BASSE', 'SYNTH', 'FX', //
];

final List<SoundDef> kLibrary = [
  SoundDef('k_psy', 'K PSY', 'KICK',
      () => kick(len: 0.35, f0: 180, f1: 48, pd: 40, ad: 9, click: 0.5, drive: 2.5)),
  SoundDef('k_909', 'K 909', 'KICK',
      () => kick(len: 0.5, f0: 230, f1: 50, pd: 25, ad: 5.5, click: 0.6, drive: 1.6)),
  SoundDef('k_808', 'K 808', 'KICK',
      () => kick(len: 1.2, f0: 110, f1: 42, pd: 18, ad: 2.2, click: 0.2, drive: 1.3)),
  SoundDef('k_hard', 'K HARD', 'KICK',
      () => kick(len: 0.6, f0: 300, f1: 52, pd: 18, ad: 4, click: 0.8, drive: 8)),
  SoundDef('k_gabber', 'K GABBER', 'KICK',
      () => kick(len: 0.45, f0: 400, f1: 60, pd: 12, ad: 5, click: 0.6, drive: 20)),
  SoundDef('k_rumble', 'K RUMBLE', 'KICK', rumbleKick),
  SoundDef('k_forest', 'K FOREST', 'KICK',
      () => kick(len: 0.3, f0: 140, f1: 55, pd: 50, ad: 11, click: 0.7, drive: 3)),
  SoundDef('k_dark', 'K DARK', 'KICK',
      () => kick(len: 0.7, f0: 120, f1: 38, pd: 22, ad: 4, click: 0.3, drive: 2)),
  SoundDef('k_dub', 'K DUB', 'KICK',
      () => kick(len: 0.5, f0: 90, f1: 50, pd: 30, ad: 6, click: 0, drive: 1.1)),
  SoundDef('k_tribal', 'K TRIBAL', 'KICK', tribalKick),
  SoundDef('k_top', 'K TOP', 'KICK',
      () => kick(len: 0.12, f0: 900, f1: 120, pd: 80, ad: 30, click: 0.8, drive: 2)),
  SoundDef('k_boom', 'K BOOM', 'KICK',
      () => kick(len: 1.5, f0: 160, f1: 40, pd: 10, ad: 1.6, click: 0.3, drive: 4)),
  SoundDef('sn', 'SNARE', 'CAISSE', snare),
  SoundDef('sn909', 'SNARE 909', 'CAISSE', snare909),
  SoundDef('clap', 'CLAP', 'CAISSE', () => clap()),
  SoundDef('clapbig', 'CLAP BIG', 'CAISSE', () => clap(tail: 5, len: 0.8)),
  SoundDef('snap', 'SNAP', 'CAISSE', snap),
  SoundDef('rim', 'RIM', 'CAISSE', rim),
  SoundDef('ch', 'CH', 'HAT', () => noiseHat(0.08, 55)),
  SoundDef('oh', 'OH', 'HAT', () => noiseHat(0.4, 9)),
  SoundDef('ch808', 'CH 808', 'HAT', () => metalHat(0.1, 45)),
  SoundDef('oh808', 'OH 808', 'HAT', () => metalHat(0.5, 7)),
  SoundDef('ride', 'RIDE', 'HAT', () => metalHat(1.2, 3, hpF: 4000, tune: 1.3)),
  SoundDef('shaker', 'SHAKER', 'HAT', shaker),
  SoundDef('tom', 'TOM LO', 'PERCU', () => tom(95)),
  SoundDef('tomhi', 'TOM HI', 'PERCU', () => tom(160)),
  SoundDef('conga', 'CONGA', 'PERCU', conga),
  SoundDef('wood', 'WOOD', 'PERCU', woodblock),
  SoundDef('cowbell', 'COWBELL', 'PERCU', cowbell),
  SoundDef('tick', 'TICK', 'PERCU', tick),
  SoundDef('metal', 'METAL', 'PERCU', metal),
  SoundDef('zap', 'ZAP', 'PERCU', zap),
  SoundDef('sub', 'SUB', 'BASSE', subPluck),
  SoundDef('roll', 'ROLL', 'BASSE', rollBass),
  SoundDef('acid', 'ACID', 'BASSE', acid),
  SoundDef('reese', 'REESE', 'BASSE', reese),
  SoundDef('bounce', 'BOUNCE', 'BASSE', bounceBass),
  SoundDef('fmbass', 'FM BASS', 'BASSE', fmBass),
  SoundDef('stab', 'STAB', 'SYNTH', stab),
  SoundDef('lead', 'LEAD', 'SYNTH', psyLead),
  SoundDef('bell', 'BELL', 'SYNTH', bell),
  SoundDef('pluck', 'PLUCK', 'SYNTH', pluck),
  SoundDef('vox', 'VOX AH', 'SYNTH', vox),
  SoundDef('drone', 'DRONE', 'SYNTH', drone),
  SoundDef('laser', 'LASER', 'FX', laser),
  SoundDef('blip', 'BLIP', 'FX', blip),
  SoundDef('riser', 'RISER', 'FX', riser),
  SoundDef('down', 'DOWNLIFT', 'FX', downlifter),
  SoundDef('impact', 'IMPACT', 'FX', impact),
  SoundDef('whoop', 'WHOOP', 'FX', whoop),
  SoundDef('bird', 'BIRD', 'FX', bird),
  SoundDef('drop', 'DROP', 'FX', drop),
];

final Map<String, SoundDef> kLibraryById = {for (final d in kLibrary) d.id: d};

class Kit {
  final String name;
  final List<String> pads; // 16 ids : 1-8 mélodique, 9-16 batterie
  const Kit(this.name, this.pads);
}

const List<Kit> kKits = [
  Kit('PSY', [
    'sub', 'acid', 'bell', 'stab', 'lead', 'laser', 'blip', 'riser', //
    'k_psy', 'sn', 'clap', 'ch', 'oh', 'tom', 'rim', 'zap',
  ]),
  Kit('TECHNO', [
    'reese', 'bounce', 'stab', 'drone', 'impact', 'riser', 'down', 'vox', //
    'k_909', 'k_rumble', 'clap', 'ch808', 'oh808', 'ride', 'rim', 'cowbell',
  ]),
  Kit('HARD', [
    'fmbass', 'reese', 'stab', 'laser', 'impact', 'down', 'vox', 'zap', //
    'k_hard', 'k_gabber', 'k_top', 'clapbig', 'ch', 'oh', 'metal', 'snap',
  ]),
  Kit('FOREST', [
    'roll', 'pluck', 'bell', 'vox', 'drone', 'bird', 'drop', 'whoop', //
    'k_forest', 'k_dark', 'conga', 'wood', 'shaker', 'ch', 'tick', 'snap',
  ]),
];
