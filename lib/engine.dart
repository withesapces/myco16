// Moteur : sons (SoLoud), micro, séquenceur 16 pas, FX punch-in,
// arrangement (chaîne de patterns) et sauvegarde automatique du projet.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'dsp.dart';
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

  // sons
  final Map<String, AudioSource> _cache = {};
  final List<String> padSound = List<String>.of(kKits[0].pads);
  final List<double> padTune = List<double>.filled(16, 0); // demi-tons
  final List<double> padVol = List<double>.filled(16, 1);
  final List<String> micFiles = []; // mic_<horodatage>.wav

  // patterns : 16 patterns x 16 pads x 16 pas
  final List<List<List<bool>>> patterns = List.generate(
      16, (_) => List.generate(16, (_) => List<bool>.filled(16, false)));

  // arrangement
  final List<int> song = [];
  bool songMode = false;
  int songIndex = 0;

  bool ready = false;
  String? error;
  Mode mode = Mode.sound;
  int pattern = 0;
  int bpm = 140;
  int selected = 8;
  bool playing = false;
  int step = -1;
  int? fx;
  int? recordingSlot;
  bool processing = false;
  final List<int> flash = List<int>.filled(16, 0);

  Directory? _dir;
  Timer? _timer;
  Timer? _saveTimer;
  Timer? _recTimeout;
  final Stopwatch _sw = Stopwatch();
  int _nextUs = 0;
  int _pos = 0;
  int _fxTick = 0;
  int _fxAnchor = 0;
  final List<_Pending> _pending = [];

  // ── démarrage ─────────────────────────────
  Future<void> init() async {
    try {
      await _sl.init(bufferSize: 512);
      _dir = await getApplicationDocumentsDirectory();
      _scanMics();
      final loaded = await _loadProject();
      if (!loaded) _demoPattern();
      for (var i = 0; i < 16; i++) {
        if (await _source(padSound[i]) == null) {
          padSound[i] = kKits[0].pads[i];
          await _source(padSound[i]);
        }
      }
      ready = true;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  void _scanMics() {
    final d = _dir;
    if (d == null) return;
    final names = d
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.startsWith('mic_') && n.endsWith('.wav'))
        .toList()
      ..sort();
    micFiles
      ..clear()
      ..addAll(names);
  }

  void _demoPattern() {
    final p = patterns[0];
    for (var s = 0; s < 16; s += 4) {
      p[8][s] = true;
    }
    for (var s = 2; s < 16; s += 4) {
      p[12][s] = true;
    }
    for (final s in [1, 3, 5, 7, 9, 11, 13, 15]) {
      p[11][s] = true;
    }
    for (final s in [1, 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 15]) {
      p[0][s] = true;
    }
    p[10][4] = true;
    p[10][12] = true;
    p[5][14] = true;
  }

  // ── sons ──────────────────────────────────
  String nameOf(String id) {
    if (id.startsWith('mic:')) {
      final i = micFiles.indexOf(id.substring(4));
      return 'MIC ${i + 1}';
    }
    return kLibraryById[id]?.name ?? '?';
  }

  String padName(int i) => nameOf(padSound[i]);
  bool padIsMic(int i) => padSound[i].startsWith('mic:');

  Future<AudioSource?> _source(String id) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    try {
      AudioSource src;
      if (id.startsWith('mic:')) {
        final f = File('${_dir!.path}/${id.substring(4)}');
        if (!await f.exists()) return null;
        src = await _sl.loadFile(f.path);
      } else {
        final def = kLibraryById[id];
        if (def == null) return null;
        src = await _sl.loadMem('lib_$id.wav', toWav(def.gen()));
      }
      _cache[id] = src;
      return src;
    } catch (_) {
      return null;
    }
  }

  void _play(int slot, {double vol = 1, double speed = 1}) {
    final src = _cache[padSound[slot]];
    if (src == null) return;
    flash[slot] = DateTime.now().millisecondsSinceEpoch;
    try {
      final h = _sl.play(src, volume: vol * padVol[slot]);
      final sp = speed * pow(2, padTune[slot] / 12).toDouble();
      if ((sp - 1).abs() > 1e-6) _sl.setRelativePlaySpeed(h, sp);
    } catch (_) {}
  }

  void padPlay(int slot) {
    selected = slot;
    _play(slot);
    notifyListeners();
  }

  void preview(int slot) => _play(slot);

  Future<void> assignPad(int pad, String id) async {
    if (await _source(id) == null) return;
    padSound[pad] = id;
    selected = pad;
    _play(pad);
    _changed();
  }

  void setTune(int pad, double semis) {
    padTune[pad] = semis;
    _changed();
  }

  void setVol(int pad, double v) {
    padVol[pad] = v;
    _changed();
  }

  Future<void> applyKit(int k) async {
    final kit = kKits[k];
    for (var i = 0; i < 16; i++) {
      await _source(kit.pads[i]);
      padSound[i] = kit.pads[i];
      padTune[i] = 0;
      padVol[i] = 1;
    }
    _changed();
  }

  Future<void> deleteMic(String file) async {
    final id = 'mic:$file';
    for (var i = 0; i < 16; i++) {
      if (padSound[i] == id) {
        padSound[i] = kKits[0].pads[i];
        await _source(padSound[i]);
      }
    }
    final src = _cache.remove(id);
    if (src != null) {
      try {
        await _sl.disposeSource(src);
      } catch (_) {}
    }
    try {
      await File('${_dir!.path}/$file').delete();
    } catch (_) {}
    micFiles.remove(file);
    _changed();
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
      if (songMode && song.isNotEmpty) {
        songIndex = 0;
        pattern = song[0];
      }
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
        case 0:
          play = _fxAnchor;
          break;
        case 1:
          play = (_fxAnchor + k % 2) % 16;
          break;
        case 2:
          play = (_fxAnchor + k % 4) % 16;
          break;
        case 3:
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
          speed = 1.4983;
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
        if (f == 13 && s >= 8) continue;
        if (f == 14 && s < 8) continue;
        _play(s, speed: speed);
        if (f == 8) {
          _pending.add(_Pending(atUs + _stepUs * 3, s, 0.45, speed));
          _pending.add(_Pending(atUs + _stepUs * 6, s, 0.2, speed));
        }
      }
    }
    if (!stutterSub || _fxTick.isEven) {
      _pos = (_pos + 1) % 16;
      // fin de mesure : on passe au bloc suivant de l'arrangement
      if (_pos == 0 && songMode && song.isNotEmpty) {
        songIndex = (songIndex + 1) % song.length;
        pattern = song[songIndex];
      }
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
    _changed();
  }

  void clearTrack() {
    patterns[pattern][selected].fillRange(0, 16, false);
    _changed();
  }

  void selectPattern(int p) {
    pattern = p;
    notifyListeners();
  }

  bool patternUsed(int p) => patterns[p].any((t) => t.contains(true));

  void copyPattern(int from, int to) {
    for (var s = 0; s < 16; s++) {
      patterns[to][s] = List<bool>.of(patterns[from][s]);
    }
    pattern = to;
    _changed();
  }

  void clearPattern(int p) {
    for (final t in patterns[p]) {
      t.fillRange(0, 16, false);
    }
    _changed();
  }

  void setMode(Mode m) {
    mode = mode == m && m != Mode.sound ? Mode.sound : m;
    notifyListeners();
  }

  void setBpm(int v) {
    bpm = v.clamp(60, 200);
    _changed();
  }

  // ── arrangement ────────────────────────────
  void songAdd(int p) {
    song.add(p);
    _changed();
  }

  void songRemoveAt(int i) {
    if (i < 0 || i >= song.length) return;
    song.removeAt(i);
    if (songIndex >= song.length) songIndex = 0;
    _changed();
  }

  void songSet(int i, int p) {
    song[i] = p;
    _changed();
  }

  void songMove(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final v = song.removeAt(oldIndex);
    song.insert(newIndex, v);
    _changed();
  }

  void songClear() {
    song.clear();
    songIndex = 0;
    _changed();
  }

  void setSongMode(bool on) {
    songMode = on;
    if (on && song.isNotEmpty && !playing) {
      songIndex = 0;
      pattern = song[0];
    }
    _changed();
  }

  /// Durée de l'arrangement en secondes (1 bloc = 1 mesure de 16 pas).
  double get songSeconds => song.length * 16 * 60 / bpm / 4;

  // ── enregistrement micro ───────────────────
  Future<String?> recStart(int slot) async {
    if (recordingSlot != null || processing) return null;
    try {
      if (!await _rec.hasPermission()) return 'Autorise le micro dans les réglages';
      final path = '${_dir!.path}/rec_raw.wav';
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

  /// Arrête l'enregistrement, nettoie le son et l'assigne au pad.
  /// Renvoie un message à afficher, ou null si tout va bien.
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
      final name = 'mic_${DateTime.now().millisecondsSinceEpoch}.wav';
      await File('${_dir!.path}/$name').writeAsBytes(cleaned);
      micFiles.add(name);
      final id = 'mic:$name';
      _cache[id] = await _sl.loadMem(name, cleaned);
      padSound[slot] = id;
      padTune[slot] = 0;
      padVol[slot] = 1;
      _play(slot);
      _changed();
      return null;
    } catch (e) {
      return 'Enregistrement : $e';
    } finally {
      processing = false;
      notifyListeners();
    }
  }

  // ── sauvegarde ─────────────────────────────
  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveProject);
  }

  int _bits(List<bool> t) {
    var b = 0;
    for (var i = 0; i < 16; i++) {
      if (t[i]) b |= 1 << i;
    }
    return b;
  }

  Future<void> _saveProject() async {
    final d = _dir;
    if (d == null) return;
    final data = {
      'v': 1,
      'bpm': bpm,
      'pattern': pattern,
      'padSound': padSound,
      'padTune': padTune,
      'padVol': padVol,
      'patterns': [
        for (final p in patterns) [for (final t in p) _bits(t)]
      ],
      'song': song,
      'songMode': songMode,
    };
    try {
      await File('${d.path}/project.json').writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<bool> _loadProject() async {
    final d = _dir;
    if (d == null) return false;
    final f = File('${d.path}/project.json');
    if (!await f.exists()) return false;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      bpm = (j['bpm'] as num).toInt();
      pattern = (j['pattern'] as num).toInt();
      final ps = (j['padSound'] as List).cast<String>();
      final pt = (j['padTune'] as List).map((e) => (e as num).toDouble()).toList();
      final pv = (j['padVol'] as List).map((e) => (e as num).toDouble()).toList();
      for (var i = 0; i < 16; i++) {
        padSound[i] = ps[i];
        padTune[i] = pt[i];
        padVol[i] = pv[i];
      }
      final pats = j['patterns'] as List;
      for (var p = 0; p < 16; p++) {
        final tracks = pats[p] as List;
        for (var s = 0; s < 16; s++) {
          final bits = (tracks[s] as num).toInt();
          for (var k = 0; k < 16; k++) {
            patterns[p][s][k] = (bits >> k) & 1 == 1;
          }
        }
      }
      song
        ..clear()
        ..addAll((j['song'] as List).map((e) => (e as num).toInt()));
      songMode = j['songMode'] == true;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _saveTimer?.cancel();
    _saveProject();
    _rec.dispose();
    _sl.deinit();
    super.dispose();
  }
}
