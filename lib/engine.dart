// Moteur MYCO-16 : combinaisons de boutons, séquenceur, verrouillage de
// paramètres, 16 effets, chaînes de patterns, micro, sauvegarde.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'dsp.dart';
import 'pet.dart';
import 'sampler.dart';
import 'synth.dart';

enum Btn { sound, pattern, bpm, fx, record, write, play }

enum KnobMode { tone, filter, trim }

enum Knob { a, b }

const List<String> kFxNames = [
  'LOOP 16', 'LOOP 12', 'LOOP SHORT', 'LOOP SHORTER', //
  'UNISON', 'UNISON LOW', 'OCTAVE UP', 'OCTAVE DOWN', //
  'STUTTER 4', 'STUTTER 3', 'SCRATCH', 'SCRATCH FAST', //
  '6/8 QUANTIZE', 'RETRIGGER', 'REVERSE', 'NO FX',
];
const List<String> kFxShort = [
  'L16', 'L12', 'LSH', 'LSR', 'UNI', 'UNL', 'OC+', 'OC-', //
  'ST4', 'ST3', 'SCR', 'SCF', '6/8', 'RTG', 'REV', 'OFF',
];
const List<int> kBpmPresets = [80, 120, 140];
const double kMaxMemory = 40; // secondes d'enregistrement

class Step {
  int note;
  double? pitch, vol, filter, res; // verrous de paramètres
  Step(this.note);

  Step copy() => Step(note)
    ..pitch = pitch
    ..vol = vol
    ..filter = filter
    ..res = res;

  List<Object?> toJson() => [note, pitch, vol, filter, res];

  static Step fromJson(List<dynamic> j) {
    double? d(int i) => i < j.length ? (j[i] as num?)?.toDouble() : null;
    return Step((j[0] as num).toInt())
      ..pitch = d(1)
      ..vol = d(2)
      ..filter = d(3)
      ..res = d(4);
  }
}

class Pattern {
  final List<List<Step?>> tracks =
      List.generate(16, (_) => List<Step?>.filled(16, null));
  final List<int?> fx = List<int?>.filled(16, null);

  bool get used => tracks.any((t) => t.any((s) => s != null));

  void clear() {
    for (final t in tracks) {
      t.fillRange(0, 16, null);
    }
    fx.fillRange(0, 16, null);
  }

  void copyFrom(Pattern o) {
    for (var s = 0; s < 16; s++) {
      for (var k = 0; k < 16; k++) {
        tracks[s][k] = o.tracks[s][k]?.copy();
      }
    }
    fx.setAll(0, o.fx);
  }

  Map<String, dynamic> toJson() => {
        'steps': [
          for (var s = 0; s < 16; s++)
            for (var k = 0; k < 16; k++)
              if (tracks[s][k] != null) [s, k, ...tracks[s][k]!.toJson()]
        ],
        'fx': fx,
      };

  void fromJson(Map<String, dynamic> j) {
    clear();
    for (final e in (j['steps'] as List)) {
      final l = e as List;
      final s = (l[0] as num).toInt();
      final k = (l[1] as num).toInt();
      tracks[s][k] = Step.fromJson(l.sublist(2));
    }
    final f = j['fx'] as List;
    for (var i = 0; i < 16 && i < f.length; i++) {
      fx[i] = (f[i] as num?)?.toInt();
    }
  }
}

class _Pending {
  final int atUs;
  final int slot;
  final int note;
  final Step? lock;
  final double speedMul;
  final double volMul;
  final bool rev;
  _Pending(this.atUs, this.slot, this.note, this.lock,
      {this.speedMul = 1, this.volMul = 1, this.rev = false});
}

class Engine extends ChangeNotifier {
  final SoLoud _sl = SoLoud.instance;
  final AudioRecorder _rec = AudioRecorder();
  final Random _rnd = Random();
  final Pet pet = Pet();

  // ── état ──
  final List<Slot> slots = List<Slot>.generate(16, emptySlot);
  final List<Pattern> patterns = List<Pattern>.generate(16, (_) => Pattern());
  final List<int> chain = [0];
  int chainIndex = 0;

  bool ready = false;
  String? error;
  int sound = 8;
  int pattern = 0;
  int bpm = 140;
  double swing = 0;
  int masterVol = 10; // 1..16
  bool writeMode = false;
  bool playing = false;
  int step = -1;
  KnobMode knobMode = KnobMode.tone;
  final List<int> lastNote = List<int>.generate(16, (i) => i < 8 ? 7 : 0);
  int? liveFx;
  int? recordingSlot;
  bool processing = false;

  // affichage / animation
  String? lcdText;
  int _lcdUntil = 0;
  int lastHitMs = 0;
  int lastKickMs = 0;
  int lastActivityMs = DateTime.now().millisecondsSinceEpoch;
  final List<int> keyFlash = List<int>.filled(16, 0);

  // boutons maintenus
  final Set<Btn> held = {};
  final Map<Btn, bool> _usedWhileHeld = {};
  final Map<Btn, int> _downAt = {};
  bool _chainStarted = false;
  bool _switchAtBar = false;

  // horloge
  Directory? _dir;
  Timer? _timer;
  Timer? _saveTimer;
  Timer? _recTimeout;
  Timer? _warmTimer;
  final Stopwatch _sw = Stopwatch();
  int _gridUs = 0;
  int _pos = 0;
  int _fxTick = 0;
  int? _fxKey;
  int? _loopFx;
  int _loopNextUs = 0;
  int _lastHitStep = 0;
  int? _prevStepFx;
  final List<_Pending> _pending = [];

  // voix pré-rendues
  final Map<String, AudioSource> _voices = {};
  final Set<String> _loading = {};
  final List<int> _gen = List<int>.filled(16, 0);

  int get _now => DateTime.now().millisecondsSinceEpoch;
  double get masterGain => masterVol / 10;
  int get position => _pos;
  bool get idle => !playing && _now - lastActivityMs > 20000;
  bool get chaining => chain.length > 1;
  Slot get cur => slots[sound];

  double get memoryUsed {
    final files = <String>{};
    var t = 0.0;
    for (final s in slots) {
      if (s.file != null && files.add(s.file!)) t += s.seconds;
    }
    return t;
  }

  // ═════════════ démarrage ═════════════
  Future<void> init() async {
    try {
      await _sl.init(bufferSize: 512);
      _dir = await getApplicationDocumentsDirectory();
      await pet.load(_dir!);
      final loaded = await _loadProject();
      if (!loaded) {
        for (var i = 0; i < 16; i++) {
          slots[i] = factorySlot(i);
        }
        _demo();
      }
      for (var i = 0; i < 16; i++) {
        await _warmSlot(i);
      }
      ready = true;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  void _demo() {
    final p = patterns[0];
    // slot 9 = kit PSY : 0 kick, 4 ch, 6 oh, 3 clap
    for (var s = 0; s < 16; s += 4) {
      p.tracks[8][s] = Step(0);
    }
    for (final s in [2, 6, 10, 14]) {
      p.tracks[8][s] = Step(6);
    }
    for (final s in [4, 12]) {
      p.tracks[8][s] = Step(3);
    }
    // slot 2 = basse roulante sur la tonique
    for (final s in [1, 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 15]) {
      p.tracks[1][s] = Step(7);
    }
    p.tracks[1][15] = Step(8);
    chain
      ..clear()
      ..add(0);
  }

  // ═════════════ voix ═════════════
  String _vkey(int si, int slice, int fq, int rq, bool rev) =>
      '$si:${_gen[si]}:$slice:$fq:$rq:${rev ? 1 : 0}';

  Future<void> _ensureVoice(int si, int slice, int fq, int rq, bool rev) async {
    final k = _vkey(si, slice, fq, rq, rev);
    if (_voices.containsKey(k) || _loading.contains(k)) return;
    _loading.add(k);
    try {
      final data = renderVoice(slots[si], slice, fq, rq, rev);
      if (data.isNotEmpty) {
        _voices[k] = await _sl.loadMem('v_$k.wav', toWav(data));
      }
    } catch (_) {
    } finally {
      _loading.remove(k);
    }
  }

  Future<void> _warmSlot(int si, {bool reverse = false}) async {
    final s = slots[si];
    if (s.isEmpty) return;
    final fq = quantFilter(s.filter), rq = quantRes(s.res);
    for (var sl = 0; sl < s.sliceCount; sl++) {
      await _ensureVoice(si, sl, 0, 0, false);
      if (fq != 0) await _ensureVoice(si, sl, fq, rq, false);
      if (reverse) await _ensureVoice(si, sl, fq, rq, true);
    }
  }

  /// Invalide les voix d'un slot (données ou trim modifiés).
  void _invalidate(int si) {
    final prefix = '$si:${_gen[si]}:';
    final old = _voices.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in old) {
      final src = _voices.remove(k);
      if (src != null) {
        _sl.disposeSource(src).catchError((_) {});
      }
    }
    _gen[si]++;
  }

  void _scheduleWarm(int si) {
    _warmTimer?.cancel();
    _warmTimer = Timer(const Duration(milliseconds: 150), () => _warmSlot(si));
  }

  void _trigger(int si, int key,
      {Step? lock, double speedMul = 1, double volMul = 1, double pan = 0, bool rev = false}) {
    final s = slots[si];
    if (s.isEmpty) return;
    final slice = s.sliceForKey(key);
    final fq = quantFilter(lock?.filter ?? s.filter);
    final rq = quantRes(lock?.res ?? s.res);
    final pitch = lock?.pitch ?? s.pitch;
    final vol = lock?.vol ?? s.vol;
    var src = _voices[_vkey(si, slice, fq, rq, rev)];
    if (src == null) {
      _ensureVoice(si, slice, fq, rq, rev);
      src = _voices[_vkey(si, slice, 0, 0, false)];
      if (src == null) {
        _ensureVoice(si, slice, 0, 0, false);
        return;
      }
    }
    final semis = pitch + (s.drum ? 0 : kScale[key]);
    final speed = pow(2, semis / 12).toDouble() * speedMul;
    try {
      final h = _sl.play(src, volume: vol * volMul * masterGain, pan: pan);
      if ((speed - 1).abs() > 1e-6) _sl.setRelativePlaySpeed(h, speed);
    } catch (_) {}
    final now = _now;
    lastHitMs = now;
    if (s.drum && slice <= 1) lastKickMs = now;
    if (si == sound) keyFlash[key] = now;
  }

  /// Déclenche une note en appliquant l'effet actif.
  void _hit(int si, int note, Step? lock, int? fx, int atUs) {
    final st = _stepUs;
    switch (fx) {
      case 4: // unison
        _trigger(si, note, lock: lock, speedMul: 1.0087, pan: -0.7, volMul: 0.8);
        _trigger(si, note, lock: lock, speedMul: 0.9913, pan: 0.7, volMul: 0.8);
        break;
      case 5: // unison low
        _trigger(si, note, lock: lock, speedMul: 1.0087, pan: -0.7, volMul: 0.7);
        _trigger(si, note, lock: lock, speedMul: 0.9913, pan: 0.7, volMul: 0.7);
        _trigger(si, note, lock: lock, speedMul: 0.5, volMul: 0.7);
        break;
      case 6:
        _trigger(si, note, lock: lock, speedMul: 2);
        break;
      case 7:
        _trigger(si, note, lock: lock, speedMul: 0.5);
        break;
      case 8:
      case 9:
        {
          final n = fx == 8 ? 4 : 3;
          _trigger(si, note, lock: lock);
          for (var j = 1; j < n; j++) {
            _pending.add(_Pending(atUs + st * j ~/ n, si, note, lock));
          }
        }
        break;
      case 10:
        _trigger(si, note, lock: lock);
        _pending.add(_Pending(atUs + st ~/ 2, si, note, lock, rev: true, speedMul: 1.2));
        break;
      case 11:
        _trigger(si, note, lock: lock, speedMul: 1.1);
        for (var j = 1; j < 4; j++) {
          _pending.add(_Pending(atUs + st * j ~/ 4, si, note, lock,
              rev: j.isOdd, speedMul: j.isOdd ? 1.3 : 1.1));
        }
        break;
      case 14:
        _trigger(si, note, lock: lock, rev: true);
        break;
      default:
        _trigger(si, note, lock: lock);
    }
  }

  // ═════════════ séquenceur ═════════════
  int get _stepUs => (60000000 / bpm / 4).round();

  void togglePlay() {
    _touch();
    if (playing) {
      playing = false;
      _timer?.cancel();
      _sw.stop();
      _pending.clear();
      _loopFx = null;
      step = -1;
    } else {
      playing = true;
      _pos = 0;
      _fxTick = 0;
      if (chain.isNotEmpty) {
        chainIndex = 0;
        pattern = chain[0];
      }
      _switchAtBar = false;
      _sw
        ..reset()
        ..start();
      _gridUs = 0;
      _timer = Timer.periodic(const Duration(milliseconds: 2), (_) => _tick());
    }
    notifyListeners();
  }

  void _tick() {
    final now = _sw.elapsedMicroseconds;
    var changed = false;
    if (_pending.isNotEmpty) {
      final due = _pending.where((p) => p.atUs <= now).toList();
      if (due.isNotEmpty) {
        _pending.removeWhere((p) => p.atUs <= now);
        for (final p in due) {
          _trigger(p.slot, p.note,
              lock: p.lock, speedMul: p.speedMul, volMul: p.volMul, rev: p.rev);
        }
      }
    }
    final loop = _loopFx;
    if (loop != null) {
      const ratios = [1.0, 4 / 3, 0.5, 0.25];
      final interval = (_stepUs * ratios[loop]).round();
      while (now >= _loopNextUs) {
        final pat = patterns[pattern];
        for (var s = 0; s < 16; s++) {
          final st = pat.tracks[s][_lastHitStep];
          if (st != null) _trigger(s, st.note, lock: st);
        }
        _loopNextUs += interval;
      }
    }
    while (true) {
      final delay = _pos.isOdd ? (swing * _stepUs * 0.5).round() : 0;
      if (now < _gridUs + delay) break;
      _doStep(_gridUs + delay);
      _gridUs += _stepUs;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void _doStep(int atUs) {
    final pat = patterns[pattern];
    // FX enregistrés dans le pattern (FX maintenu + mode écriture)
    if (writeMode && liveFx != null && held.contains(Btn.fx)) {
      pat.fx[_pos] = liveFx == 15 ? null : liveFx;
    }
    final fx = liveFx ?? pat.fx[_pos];
    if (fx != _prevStepFx) _fxTick = 0;
    _prevStepFx = fx;

    // effets de boucle : l'horloge de boucle prend le relais
    if (fx != null && fx <= 3) {
      if (_loopFx != fx) {
        _loopFx = fx;
        _loopNextUs = atUs;
      }
    } else {
      _loopFx = null;
    }

    var play = _pos;
    var trig = _loopFx == null;
    if (fx == 12 && _pos % 4 == 3) trig = false; // 6/8
    if (fx == 13) play = _fxTick % 16; // retrigger : repart du pas 1

    step = play;
    if (trig) {
      var any = false;
      for (var s = 0; s < 16; s++) {
        final st = pat.tracks[s][play];
        if (st == null) continue;
        _hit(s, st.note, st, fx, atUs);
        any = true;
      }
      if (any) _lastHitStep = play;
    }
    _fxTick++;
    _pos = (_pos + 1) % 16;
    if (_pos == 0) _barEnd();
  }

  void _barEnd() {
    pet.onBar();
    if (_switchAtBar) {
      _switchAtBar = false;
      chainIndex = 0;
      pattern = chain[0];
    } else if (chain.length > 1) {
      chainIndex = (chainIndex + 1) % chain.length;
      pattern = chain[chainIndex];
    }
  }

  // ═════════════ boutons ═════════════
  void _touch() => lastActivityMs = _now;

  /// Tape sur l'écran LCD : caresser Myco ou nettoyer ses spores.
  void tapPet() {
    _touch();
    pet.tap();
    notifyListeners();
  }

  void _lcd(String t) {
    lcdText = t;
    _lcdUntil = _now + 1300;
  }

  String? get lcdTransient => _now < _lcdUntil ? lcdText : null;

  void _markUsed() {
    for (final b in held) {
      _usedWhileHeld[b] = true;
    }
  }

  void btnDown(Btn b) {
    _touch();
    _markUsed(); // un bouton pressé pendant qu'un autre est tenu = combinaison
    held.add(b);
    _usedWhileHeld[b] = false;
    _downAt[b] = _now;
    switch (b) {
      case Btn.play:
        togglePlay();
        break;
      case Btn.pattern:
        _chainStarted = false;
        if (held.contains(Btn.record)) {
          patterns[pattern].clear();
          _lcd('CLR');
          _usedWhileHeld[b] = true;
          _changed();
        }
        break;
      case Btn.sound:
        if (held.contains(Btn.record)) {
          _deleteSound(sound);
          _usedWhileHeld[b] = true;
        }
        break;
      case Btn.record:
        if (held.contains(Btn.pattern)) {
          patterns[pattern].clear();
          _lcd('CLR');
          _usedWhileHeld[b] = true;
          _changed();
        }
        break;
      default:
        break;
    }
    notifyListeners();
  }

  void btnUp(Btn b) {
    held.remove(b);
    final tap = _usedWhileHeld[b] != true && _now - (_downAt[b] ?? 0) < 450;
    if (tap) {
      switch (b) {
        case Btn.write:
          writeMode = !writeMode;
          _lcd(writeMode ? 'WR' : '--');
          break;
        case Btn.fx:
          knobMode = KnobMode.values[(knobMode.index + 1) % 3];
          _lcd(['TON', 'FLT', 'TRM'][knobMode.index]);
          break;
        case Btn.bpm:
          {
            final i = kBpmPresets.indexOf(bpm);
            bpm = kBpmPresets[(i + 1) % kBpmPresets.length];
            _lcd('$bpm');
            _changed();
          }
          break;
        default:
          break;
      }
    }
    if (b == Btn.fx) {
      liveFx = null;
      _fxKey = null;
    }
    notifyListeners();
  }

  Future<String?> keyDown(int k) async {
    _touch();
    _markUsed();
    if (held.contains(Btn.record)) {
      return recStart(k);
    }
    if (held.contains(Btn.sound)) {
      if (held.contains(Btn.write)) {
        slots[k] = cur.copy();
        _invalidate(k);
        await _warmSlot(k);
        _lcd('CPY');
      } else {
        sound = k;
        _lcd('S${k + 1}');
      }
      _changed();
      return null;
    }
    if (held.contains(Btn.pattern)) {
      if (held.contains(Btn.write)) {
        patterns[k].copyFrom(patterns[pattern]);
        _lcd('P${k + 1}');
        _changed();
        return null;
      }
      if (!_chainStarted) {
        _chainStarted = true;
        chain
          ..clear()
          ..add(k);
        if (playing) {
          _switchAtBar = true;
        } else {
          pattern = k;
          chainIndex = 0;
        }
      } else if (chain.length < 128) {
        chain.add(k);
      }
      _lcd(chain.length > 1 ? 'C${chain.length}' : 'P${k + 1}');
      _changed();
      return null;
    }
    if (held.contains(Btn.bpm)) {
      masterVol = k + 1;
      _lcd('V${k + 1}');
      _changed();
      return null;
    }
    if (held.contains(Btn.fx)) {
      if (k == 15) {
        if (writeMode) patterns[pattern].fx.fillRange(0, 16, null);
        liveFx = null;
        _lcd('OFF');
      } else {
        liveFx = k;
        _fxKey = k;
        _fxTick = 0;
        if (k == 14) {
          for (var s = 0; s < 16; s++) {
            _warmSlot(s, reverse: true);
          }
        }
        if (k == 10 || k == 11) {
          for (var s = 0; s < 16; s++) {
            _warmSlot(s, reverse: true);
          }
        }
        if (k <= 3 && playing) {
          _loopFx = k;
          _loopNextUs = _sw.elapsedMicroseconds;
        }
        _lcd(kFxShort[k]);
        pet.onFx();
      }
      if (writeMode) _changed();
      notifyListeners();
      return null;
    }
    if (held.contains(Btn.write) && playing) {
      // enregistrement live, quantifié au pas le plus proche
      final now = _sw.elapsedMicroseconds;
      final prevStart = _gridUs - _stepUs;
      final q = now - prevStart < _stepUs ~/ 2 ? (_pos + 15) % 16 : _pos;
      patterns[pattern].tracks[sound][q] = Step(k);
      lastNote[sound] = k;
      _trigger(sound, k);
      _changed();
      return null;
    }
    if (writeMode) {
      final t = patterns[pattern].tracks[sound];
      if (t[k] == null) {
        t[k] = Step(lastNote[sound]);
        if (!playing) _trigger(sound, lastNote[sound]);
      } else {
        t[k] = null;
      }
      _changed();
      return null;
    }
    // jeu direct
    lastNote[sound] = k;
    _hit(sound, k, null, liveFx, _sw.elapsedMicroseconds);
    notifyListeners();
    return null;
  }

  Future<String?> keyUp(int k) async {
    if (recordingSlot == k) return recStop();
    if (_fxKey == k && liveFx != null) {
      liveFx = null;
      _fxKey = null;
      notifyListeners();
    }
    return null;
  }

  // ═════════════ knobs A / B ═════════════
  String knobLabel(Knob k) {
    if (held.contains(Btn.bpm)) return k == Knob.a ? 'SWING' : 'TEMPO';
    switch (knobMode) {
      case KnobMode.tone:
        return k == Knob.a ? 'PITCH' : 'VOL';
      case KnobMode.filter:
        return k == Knob.a ? 'FILTRE' : 'RÉSO';
      case KnobMode.trim:
        return k == Knob.a ? 'DÉBUT' : 'LONG.';
    }
  }

  /// Valeur normalisée 0..1 du knob (pour l'afficher).
  double knobValue(Knob k) {
    if (held.contains(Btn.bpm)) {
      return k == Knob.a ? swing : (bpm - 60) / 180;
    }
    final s = cur;
    final sl = lastNote[sound] % 16;
    switch (knobMode) {
      case KnobMode.tone:
        return k == Knob.a ? (s.pitch + 12) / 24 : s.vol;
      case KnobMode.filter:
        return k == Knob.a ? (s.filter + 1) / 2 : s.res;
      case KnobMode.trim:
        if (s.drum) {
          return k == Knob.a ? s.sliceStart[sl] / 0.95 : s.sliceLen[sl];
        }
        return k == Knob.a ? s.trimStart / 0.95 : s.trimLen;
    }
  }

  void knobTurn(Knob k, double delta) {
    _touch();
    _markUsed();
    if (held.contains(Btn.bpm)) {
      if (k == Knob.a) {
        swing = (swing + delta).clamp(0.0, 1.0).toDouble();
        _lcd('SW${(swing * 99).round()}');
      } else {
        bpm = (bpm + delta * 180).round().clamp(60, 240).toInt();
        _lcd('$bpm');
      }
      _changed();
      return;
    }
    final s = cur;
    // verrouillage de paramètre : WRITE maintenu pendant la lecture
    if (held.contains(Btn.write) && playing && knobMode != KnobMode.trim) {
      final st = patterns[pattern].tracks[sound][step < 0 ? 0 : step];
      if (st != null) {
        switch (knobMode) {
          case KnobMode.tone:
            if (k == Knob.a) {
              st.pitch = ((st.pitch ?? s.pitch) + delta * 24).clamp(-12.0, 12.0).toDouble();
              _lcd(_signed(st.pitch!.round()));
            } else {
              st.vol = ((st.vol ?? s.vol) + delta).clamp(0.0, 1.0).toDouble();
              _lcd('${(st.vol! * 99).round()}');
            }
            break;
          case KnobMode.filter:
            if (k == Knob.a) {
              st.filter = ((st.filter ?? s.filter) + delta * 2).clamp(-1.0, 1.0).toDouble();
              _lcd(_signed((st.filter! * 10).round()));
            } else {
              st.res = ((st.res ?? s.res) + delta).clamp(0.0, 1.0).toDouble();
              _lcd('${(st.res! * 99).round()}');
            }
            _ensureVoice(sound, s.sliceForKey(st.note), quantFilter(st.filter ?? s.filter),
                quantRes(st.res ?? s.res), false);
            break;
          case KnobMode.trim:
            break;
        }
        _changed();
      }
      return;
    }
    switch (knobMode) {
      case KnobMode.tone:
        if (k == Knob.a) {
          s.pitch = (s.pitch + delta * 24).clamp(-12.0, 12.0).toDouble();
          _lcd(_signed(s.pitch.round()));
        } else {
          s.vol = (s.vol + delta).clamp(0.0, 1.0).toDouble();
          _lcd('${(s.vol * 99).round()}');
        }
        break;
      case KnobMode.filter:
        if (k == Knob.a) {
          s.filter = (s.filter + delta * 2).clamp(-1.0, 1.0).toDouble();
          _lcd(_signed((s.filter * 10).round()));
        } else {
          s.res = (s.res + delta).clamp(0.0, 1.0).toDouble();
          _lcd('${(s.res * 99).round()}');
        }
        _scheduleWarm(sound);
        break;
      case KnobMode.trim:
        final int sl = s.drum ? s.sliceForKey(lastNote[sound]) : 0;
        if (k == Knob.a) {
          if (s.drum) {
            s.sliceStart[sl] = (s.sliceStart[sl] + delta).clamp(0.0, 0.95).toDouble();
            _lcd('${(s.sliceStart[sl] * 99).round()}');
          } else {
            s.trimStart = (s.trimStart + delta).clamp(0.0, 0.95).toDouble();
            _lcd('${(s.trimStart * 99).round()}');
          }
        } else {
          if (s.drum) {
            s.sliceLen[sl] = (s.sliceLen[sl] + delta).clamp(0.02, 1.0).toDouble();
            _lcd('${(s.sliceLen[sl] * 99).round()}');
          } else {
            s.trimLen = (s.trimLen + delta).clamp(0.02, 1.0).toDouble();
            _lcd('${(s.trimLen * 99).round()}');
          }
        }
        _invalidate(sound);
        _scheduleWarm(sound);
        break;
    }
    _changed();
  }

  /// Relâchement d'un knob : on fait entendre le son réglé.
  void knobRelease() {
    if (!playing && !held.contains(Btn.bpm)) _trigger(sound, lastNote[sound]);
  }

  String _signed(int v) => v > 0 ? '+$v' : '$v';

  // ═════════════ sons ═════════════
  void _deleteSound(int si) {
    _invalidate(si);
    slots[si] = emptySlot(si);
    _lcd('DEL');
    _changed();
  }

  Future<void> loadLibrarySound(String id) async {
    final def = kLibraryById[id];
    if (def == null) return;
    _invalidate(sound);
    final s = cur.drum
        ? Slot(name: def.name, drum: true, data: def.gen(), factory: 'mel:$id')
        : melodicFromLibrary(id);
    slots[sound] = s;
    await _warmSlot(sound);
    _trigger(sound, lastNote[sound]);
    pet.onMeal(1);
    _changed();
  }

  Future<void> loadKit(int k) async {
    _invalidate(sound);
    final s = drumFromKit(k);
    if (!cur.drum) s.drum = false;
    slots[sound] = s;
    await _warmSlot(sound);
    _trigger(sound, lastNote[sound]);
    pet.onMeal(1);
    _changed();
  }

  Future<void> resetFactory() async {
    for (var i = 0; i < 16; i++) {
      _invalidate(i);
      slots[i] = factorySlot(i);
      await _warmSlot(i);
    }
    _changed();
  }

  void clearAllPatterns() {
    for (final p in patterns) {
      p.clear();
    }
    chain
      ..clear()
      ..add(0);
    pattern = 0;
    _changed();
  }

  // ═════════════ micro ═════════════
  Future<String?> recStart(int slot) async {
    if (recordingSlot != null || processing) return null;
    final free = kMaxMemory - memoryUsed;
    if (free < 0.3) {
      _lcd('FUL');
      notifyListeners();
      return 'Mémoire pleine (40 s). Supprime un son : REC + SOUND.';
    }
    try {
      if (!await _rec.hasPermission()) return 'Autorise le micro dans les réglages';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
        path: '${_dir!.path}/rec_raw.wav',
      );
      recordingSlot = slot;
      sound = slot;
      final maxMs = (min(free, 20.0) * 1000).round();
      _recTimeout = Timer(Duration(milliseconds: maxMs), () => recStop());
      notifyListeners();
      return null;
    } catch (e) {
      return 'Micro indisponible : $e';
    }
  }

  Future<String?> recStop() async {
    final slot = recordingSlot;
    if (slot == null) return null;
    _recTimeout?.cancel();
    recordingSlot = null;
    processing = true;
    notifyListeners();
    try {
      final path = await _rec.stop();
      if (path == null) return 'Enregistrement vide';
      final bytes = await File(path).readAsBytes();
      final cleaned = await compute(cleanRecording, bytes);
      if (cleaned.isEmpty) return 'Rien entendu : rapproche-toi du micro';
      final data = decodeWav(cleaned);
      if (data == null) return 'Enregistrement illisible';
      final name = 'mic_${_now}.wav';
      await File('${_dir!.path}/$name').writeAsBytes(cleaned);
      final drum = slot >= 8;
      _invalidate(slot);
      slots[slot] = Slot(
        name: 'MIC ${slot + 1}',
        drum: drum,
        data: data,
        slices: drum ? detectSlices(data) : null,
        file: name,
      );
      await _warmSlot(slot);
      _trigger(slot, drum ? 0 : 7);
      _lcd(drum ? '${slots[slot].sliceCount}SL' : 'OK');
      pet.onMeal(2);
      _changed();
      return null;
    } catch (e) {
      return 'Enregistrement : $e';
    } finally {
      processing = false;
      notifyListeners();
    }
  }

  // ═════════════ arrangement (chaîne) ═════════════
  void chainAdd(int p) {
    if (chain.length < 128) chain.add(p);
    _changed();
  }

  void chainRemoveAt(int i) {
    if (chain.length <= 1) return;
    chain.removeAt(i);
    if (chainIndex >= chain.length) chainIndex = 0;
    _changed();
  }

  void chainSet(int i, int p) {
    chain[i] = p;
    _changed();
  }

  void chainMove(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final v = chain.removeAt(oldIndex);
    chain.insert(newIndex, v);
    _changed();
  }

  void chainReset() {
    chain
      ..clear()
      ..add(pattern);
    chainIndex = 0;
    _changed();
  }

  double get chainSeconds => chain.length * 16 * 60 / bpm / 4;

  // ═════════════ sauvegarde ═════════════
  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveProject);
  }

  Future<void> _saveProject() async {
    final d = _dir;
    if (d == null) return;
    final data = {
      'v': 3,
      'bpm': bpm,
      'swing': swing,
      'masterVol': masterVol,
      'sound': sound,
      'pattern': pattern,
      'chain': chain,
      'slots': [for (final s in slots) s.paramsJson()],
      'patterns': [for (final p in patterns) p.toJson()],
    };
    try {
      await File('${d.path}/project3.json').writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<bool> _loadProject() async {
    final d = _dir;
    if (d == null) return false;
    final f = File('${d.path}/project3.json');
    if (!await f.exists()) return false;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      bpm = (j['bpm'] as num).toInt();
      swing = (j['swing'] as num).toDouble();
      masterVol = (j['masterVol'] as num).toInt();
      sound = (j['sound'] as num).toInt();
      pattern = (j['pattern'] as num).toInt();
      chain
        ..clear()
        ..addAll((j['chain'] as List).map((e) => (e as num).toInt()));
      if (chain.isEmpty) chain.add(pattern);
      final sj = j['slots'] as List;
      for (var i = 0; i < 16; i++) {
        slots[i] = await _slotFromJson(i, sj[i] as Map<String, dynamic>);
      }
      final pj = j['patterns'] as List;
      for (var i = 0; i < 16; i++) {
        patterns[i].fromJson(pj[i] as Map<String, dynamic>);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Slot> _slotFromJson(int i, Map<String, dynamic> j) async {
    final factory = j['factory'] as String?;
    final file = j['file'] as String?;
    final drum = j['drum'] == true;
    Slot s;
    if (file != null) {
      final f = File('${_dir!.path}/$file');
      Float64List? data;
      if (await f.exists()) data = decodeWav(await f.readAsBytes());
      if (data == null) return emptySlot(i);
      final sl = (j['slices'] as List?)?.map((e) => (e as num).toInt()).toList();
      s = Slot(name: j['name'] as String? ?? 'MIC', drum: drum, data: data, slices: sl, file: file);
    } else if (factory != null && factory.startsWith('kit:')) {
      s = drumFromKit(int.parse(factory.substring(4)));
      s.drum = drum;
    } else if (factory != null && factory.startsWith('mel:')) {
      final id = factory.substring(4);
      if (kLibraryById[id] == null) return factorySlot(i);
      s = melodicFromLibrary(id);
      s.drum = drum;
    } else {
      return emptySlot(i);
    }
    s.applyParams(j);
    return s;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _saveTimer?.cancel();
    _saveProject();
    pet.save();
    _rec.dispose();
    _sl.deinit();
    super.dispose();
  }
}
