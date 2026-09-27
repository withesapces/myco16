// Moteur : sons (SoLoud), enregistrement micro, séquenceur 16 pas, FX punch-in.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'synth.dart';

enum Mode { sound, write, pattern, fx, rec }

const List<String> kFxNames = [
  'LOOP16', 'LOOP8', 'LOOP4', 'STUT', //
  'OCT+', 'OCT-', 'FIFTH', 'SCRTCH', //
  'ECHO', 'RANDOM', 'REVRS', 'HALF', //
  'DOUBLE', 'NO DRM', 'NO MEL', 'GATE',
];

class _Pending {
  final int atUs;
  final int slot;
  final double vol;
  final double speed;
  _Pending(this.atUs, this.slot, this.vol, this.speed);
}

class Engine extends ChangeNotifier {
  final SoLoud _sl = SoLoud.instance;
  final AudioRecorder _rec = AudioRecorder();
  final Random _rnd = Random();

  final List<AudioSource?> _src = List<AudioSource?>.filled(16, null);
  final List<String> names = List<String>.filled(16, '');
  final List<bool> userSample = List<bool>.filled(16, false);

  // 16 patterns x 16 sons x 16 pas
  final List<List<List<bool>>> patterns = List.generate(
      16, (_) => List.generate(16, (_) => List<bool>.filled(16, false)));

  bool ready = false;
  String? error;
  Mode mode = Mode.sound;
  int pattern = 0;
  int bpm = 140;
  int selected = 8;
  bool playing = false;
  int step = -1; // pas affiché (celui qui est joué)
  int? fx;
  int? recordingSlot;
  final List<int> flash = List<int>.filled(16, 0); // horodatage du dernier déclenchement

  // horloge
  Timer? _timer;
  final Stopwatch _sw = Stopwatch();
  int _nextUs = 0;
  int _pos = 0; // position "réelle" dans la mesure, continue pendant les FX
  int _fxTick = 0;
  int _fxAnchor = 0;
  final List<_Pending> _pending = [];
  int _loadCounter = 0;
  Timer? _recTimeout;

  Future<void> init() async {
    try {
      await _sl.init(bufferSize: 512);
      final f = factorySounds();
      for (var i = 0; i < 16; i++) {
        names[i] = f[i].key;
        _src[i] = await _sl.loadMem('factory_$i.wav', toWav(f[i].value()));
      }
      _demoPattern();
      ready = true;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  void _demoPattern() {
    final p = patterns[0];
    for (var s = 0; s < 16; s += 4) {
      p[8][s] = true; // kick
    }
    for (var s = 2; s < 16; s += 4) {
      p[12][s] = true; // open hat
    }
    for (final s in [1, 3, 5, 7, 9, 11, 13, 15]) {
      p[11][s] = true; // closed hat
    }
    for (final s in [1, 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 15]) {
      p[0][s] = true; // basse roulante
    }
    p[10][4] = true;
    p[10][12] = true; // clap
    p[5][14] = true; // laser
  }

  // ── lecture ────────────────────────────────
  Future<void> _play(int slot, {double vol = 1, double speed = 1}) async {
    final src = _src[slot];
    if (src == null) return;
    flash[slot] = DateTime.now().millisecondsSinceEpoch;
    try {
      final h = _sl.play(src, volume: vol);
      if (speed != 1) _sl.setRelativePlaySpeed(h, speed);
    } catch (_) {}
  }

  void padPlay(int slot) {
    selected = slot;
    _play(slot);
    notifyListeners();
  }

  // ── séquenceur ─────────────────────────────
  int get _stepUs => (60000000 / bpm / 4).round();

  void togglePlay() {
    if (playing) {
      playing = false;
      _timer?.cancel();
      _sw.stop();
      _pending.clear();
      step = -1;
    } else {
      playing = true;
      _pos = 0;
      _sw
        ..reset()
        ..start();
      _nextUs = 0;
      _timer = Timer.periodic(const Duration(milliseconds: 2), (_) => _tick());
    }
    notifyListeners();
  }

  void _tick() {
    final now = _sw.elapsedMicroseconds;
    // échos en attente
    if (_pending.isNotEmpty) {
      final due = _pending.where((p) => p.atUs <= now).toList();
      _pending.removeWhere((p) => p.atUs <= now);
      for (final p in due) {
        _play(p.slot, vol: p.vol, speed: p.speed);
      }
    }
    var changed = false;
    while (now >= _nextUs) {
      final isStutter = fx == 3;
      _doStep(_nextUs);
      _nextUs += isStutter ? _stepUs ~/ 2 : _stepUs;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void _doStep(int atUs) {
    final f = fx;
    int play = _pos;
    bool trigger = true;
    double speed = 1;
    bool stutterSub = false;

    if (f != null) {
      final k = _fxTick;
      switch (f) {
        case 0: // loop 1 pas
          play = _fxAnchor;
          break;
        case 1: // loop 2 pas
          play = (_fxAnchor + k % 2) % 16;
          break;
        case 2: // loop 4 pas
          play = (_fxAnchor + k % 4) % 16;
          break;
        case 3: // stutter double vitesse
          play = _fxAnchor;
          stutterSub = true;
          break;
        case 4:
          speed = 2;
          break;
        case 5:
          speed = 0.5;
          break;
        case 6:
          speed = 1.4983; // quinte juste
          break;
        case 7:
          speed = k.isEven ? 0.7 : 1.35;
          break;
        case 9:
          play = _rnd.nextInt(16);
          break;
        case 10:
          play = ((_fxAnchor - k) % 16 + 16) % 16;
          break;
        case 11:
          play = (_fxAnchor + k ~/ 2) % 16;
          trigger = k.isEven;
          break;
        case 12:
          play = (_fxAnchor + k * 2) % 16;
          break;
        case 15:
          trigger = k.isEven;
          break;
      }
      _fxTick++;
    }

    step = play;
    if (trigger) {
      final p = patterns[pattern];
      for (var s = 0; s < 16; s++) {
        if (!p[s][play]) continue;
        if (f == 13 && s >= 8) continue; // sans batterie
        if (f == 14 && s < 8) continue; // sans mélodique
        _play(s, speed: speed);
        if (f == 8) {
          _pending.add(_Pending(atUs + _stepUs * 3, s, 0.45, speed));
          _pending.add(_Pending(atUs + _stepUs * 6, s, 0.2, speed));
        }
      }
    }
    // la position réelle avance toujours d'un pas entier (sauf sous-pas du stutter)
    if (!stutterSub || _fxTick.isEven) {
      _pos = (_pos + 1) % 16;
    }
  }

  void fxDown(int i) {
    fx = i;
    _fxTick = 0;
    final base = i == 1 ? 2 : (i == 2 ? 4 : 1);
    _fxAnchor = playing ? (_pos - (_pos % base)) % 16 : 0;
    notifyListeners();
  }

  void fxUp(int i) {
    if (fx == i) fx = null;
    notifyListeners();
  }

  void toggleStep(int s) {
    final t = patterns[pattern][selected];
    t[s] = !t[s];
    if (t[s] && !playing) _play(selected);
    notifyListeners();
  }

  void clearTrack() {
    patterns[pattern][selected].fillRange(0, 16, false);
    notifyListeners();
  }

  void selectPattern(int p) {
    pattern = p;
    notifyListeners();
  }

  bool patternUsed(int p) => patterns[p].any((t) => t.contains(true));

  void setMode(Mode m) {
    mode = mode == m && m != Mode.sound ? Mode.sound : m;
    notifyListeners();
  }

  void nudgeBpm(int d) {
    bpm = (bpm + d).clamp(60, 200);
    notifyListeners();
  }

  // ── enregistrement micro ───────────────────
  Future<String?> recStart(int slot) async {
    if (recordingSlot != null) return null;
    try {
      if (!await _rec.hasPermission()) return 'Autorise le micro dans les réglages';
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/slot_$slot.wav';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
        path: path,
      );
      recordingSlot = slot;
      selected = slot;
      _recTimeout = Timer(const Duration(seconds: 6), () => recStop());
      notifyListeners();
      return null;
    } catch (e) {
      return 'Micro indisponible : $e';
    }
  }

  Future<void> recStop() async {
    final slot = recordingSlot;
    if (slot == null) return;
    _recTimeout?.cancel();
    recordingSlot = null;
    notifyListeners();
    try {
      final path = await _rec.stop();
      if (path == null) return;
      final bytes = await File(path).readAsBytes();
      final cleaned = trimAndNormalize(bytes);
      final AudioSource fresh;
      _loadCounter++;
      if (cleaned != null) {
        fresh = await _sl.loadMem('user_${slot}_$_loadCounter.wav', toWav(cleaned));
      } else {
        fresh = await _sl.loadMem('user_${slot}_$_loadCounter.wav', bytes);
      }
      final old = _src[slot];
      _src[slot] = fresh;
      names[slot] = 'MIC ${slot + 1}';
      userSample[slot] = true;
      if (old != null) await _sl.disposeSource(old);
      _play(slot);
    } catch (e) {
      error = 'Enregistrement : $e';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rec.dispose();
    _sl.deinit();
    super.dispose();
  }
}
