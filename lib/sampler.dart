// Slots d'échantillons façon micro-sampler :
// 1 à 8 = mélodique (le son entier, joué en gamme sur les 16 touches)
// 9 à 16 = batterie (le son est découpé en tranches, une par touche)
import 'dart:math';
import 'dart:typed_data';

import 'synth.dart';

/// Gamme mineure sur 16 touches, la touche 8 joue le son à sa hauteur d'origine.
const List<int> kScale = [
  -12, -10, -9, -7, -5, -4, -2, 0, 2, 3, 5, 7, 8, 10, 12, 14,
];

class Slot {
  String name;
  bool drum;
  String? factory; // 'mel:<id>' ou 'kit:<index>'
  String? file; // enregistrement micro (nom de fichier)
  Float64List data;
  List<int> slices; // débuts des tranches (batterie)

  // réglages (knobs)
  double pitch = 0; // demi-tons -12..12
  double vol = 0.8; // 0..1
  double filter = 0; // -1 passe-bas .. 0 neutre .. 1 passe-haut
  double res = 0; // 0..1
  double trimStart = 0, trimLen = 1; // mélodique
  final List<double> sliceStart = List<double>.filled(16, 0);
  final List<double> sliceLen = List<double>.filled(16, 1);

  Slot({
    required this.name,
    required this.drum,
    required this.data,
    List<int>? slices,
    this.factory,
    this.file,
  }) : slices = slices ?? <int>[0];

  bool get isEmpty => data.isEmpty;
  double get seconds => data.length / kSr;
  int get sliceCount => drum ? max(1, slices.length) : 1;

  /// Tranche jouée par une touche (les touches au-delà du nombre de tranches bouclent).
  int sliceForKey(int key) => drum ? key % sliceCount : 0;

  Slot copy() {
    final s = Slot(
      name: name,
      drum: drum,
      data: Float64List.fromList(data),
      slices: List<int>.of(slices),
      factory: factory,
      file: file,
    );
    s
      ..pitch = pitch
      ..vol = vol
      ..filter = filter
      ..res = res
      ..trimStart = trimStart
      ..trimLen = trimLen;
    s.sliceStart.setAll(0, sliceStart);
    s.sliceLen.setAll(0, sliceLen);
    return s;
  }

  Map<String, dynamic> paramsJson() => {
        'name': name,
        'drum': drum,
        'factory': factory,
        'file': file,
        'slices': slices,
        'pitch': pitch,
        'vol': vol,
        'filter': filter,
        'res': res,
        'trimStart': trimStart,
        'trimLen': trimLen,
        'sliceStart': sliceStart,
        'sliceLen': sliceLen,
      };

  void applyParams(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    pitch = d('pitch', 0);
    vol = d('vol', 0.8);
    filter = d('filter', 0);
    res = d('res', 0);
    trimStart = d('trimStart', 0);
    trimLen = d('trimLen', 1);
    final ss = j['sliceStart'] as List?;
    final sl = j['sliceLen'] as List?;
    for (var i = 0; i < 16; i++) {
      if (ss != null && i < ss.length) sliceStart[i] = (ss[i] as num).toDouble();
      if (sl != null && i < sl.length) sliceLen[i] = (sl[i] as num).toDouble();
    }
  }
}

Slot emptySlot(int index) =>
    Slot(name: '---', drum: index >= 8, data: Float64List(0));

Slot factorySlot(int index) {
  if (index < 8) {
    final id = kMelodicDefaults[index];
    return melodicFromLibrary(id);
  }
  return drumFromKit(index - 8);
}

Slot melodicFromLibrary(String id) {
  final def = kLibraryById[id]!;
  return Slot(name: def.name, drum: false, data: def.gen(), factory: 'mel:$id');
}

Slot drumFromKit(int k) {
  final kit = kDrumKits[k];
  final built = buildDrumKit(kit);
  return Slot(
    name: 'KIT ${kit.name}',
    drum: true,
    data: built.data,
    slices: built.slices,
    factory: 'kit:$k',
  );
}

/// Détection des attaques pour découper un enregistrement batterie.
/// Renvoie jusqu'à 16 débuts de tranches.
List<int> detectSlices(Float64List x) {
  final hop = 256;
  final n = x.length ~/ hop;
  if (n < 4) return [0];
  final env = Float64List(n);
  for (var b = 0; b < n; b++) {
    var e = 0.0;
    for (var i = b * hop; i < (b + 1) * hop; i++) {
      e += x[i] * x[i];
    }
    env[b] = sqrt(e / hop);
  }
  final peak = env.reduce(max);
  if (peak <= 0) return [0];
  final onsets = <int>[0];
  final minGap = (0.08 * kSr / hop).round(); // 80 ms entre deux coups
  for (var b = 2; b < n; b++) {
    final rise = env[b] - (env[b - 1] + env[b - 2]) / 2;
    if (rise > peak * 0.12 && env[b] > peak * 0.15 && b - onsets.last >= minGap) {
      onsets.add(b);
    }
  }
  final starts = onsets.map((b) => max(0, b * hop - 128)).toList();
  starts[0] = 0;
  if (starts.length > 16) return starts.sublist(0, 16);
  return starts;
}

/// Rendu d'une voix : tranche + trim + filtre + inversion éventuelle.
/// fq : filtre quantifié -10..10, rq : résonance quantifiée 0..4.
Float64List renderVoice(Slot s, int slice, int fq, int rq, bool reverse) {
  if (s.data.isEmpty) return Float64List(0);
  int a, b;
  double ts, tl;
  if (s.drum) {
    final i = slice.clamp(0, s.slices.length - 1).toInt();
    a = s.slices[i];
    b = i + 1 < s.slices.length ? s.slices[i + 1] : s.data.length;
    ts = s.sliceStart[slice % 16];
    tl = s.sliceLen[slice % 16];
  } else {
    a = 0;
    b = s.data.length;
    ts = s.trimStart;
    tl = s.trimLen;
  }
  final region = b - a;
  final start = a + (region * ts.clamp(0.0, 0.95).toDouble()).round();
  final len = max(64, (region * tl.clamp(0.02, 1.0).toDouble()).round());
  final end = min(b, start + len);
  if (end <= start) return Float64List(0);
  final out = Float64List.fromList(s.data.sublist(start, end));

  if (fq != 0) {
    final q = 0.7 + rq * 1.8;
    final Biquad f;
    if (fq < 0) {
      // passe-bas de 18 kHz (fq=-1) à 150 Hz (fq=-10)
      final cut = 18000 * pow(150 / 18000, (-fq - 1) / 9).toDouble();
      f = Biquad.lp(cut, q);
    } else {
      // passe-haut de 60 Hz (fq=1) à 6 kHz (fq=10)
      final cut = 60 * pow(6000 / 60, (fq - 1) / 9).toDouble();
      f = Biquad.hp(cut, q);
    }
    var peak = 0.0;
    for (var i = 0; i < out.length; i++) {
      out[i] = f.p(out[i]);
      if (out[i].abs() > peak) peak = out[i].abs();
    }
    if (peak > 0.99) {
      for (var i = 0; i < out.length; i++) {
        out[i] *= 0.99 / peak;
      }
    }
  }
  final fade = min(out.length ~/ 2, (0.003 * kSr).round());
  for (var i = 0; i < fade; i++) {
    out[i] *= i / fade;
    out[out.length - 1 - i] *= i / fade;
  }
  if (reverse) {
    for (var i = 0, j = out.length - 1; i < j; i++, j--) {
      final t = out[i];
      out[i] = out[j];
      out[j] = t;
    }
  }
  return out;
}

int quantFilter(double f) => (f * 10).round().clamp(-10, 10).toInt();
int quantRes(double r) => (r * 4).round().clamp(0, 4).toInt();
