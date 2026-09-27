// Myco, le compagnon façon tamagotchi : besoins, humeur, croissance.
// L'état est sauvegardé dans pet.json et continue d'évoluer app fermée.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

enum PetStage { spore, baby, adult }

enum PetEvent { none, hatch, eat, refuse, pet, clean, evolve }

// Rythme des besoins (temps réel, y compris app fermée).
const int kFoodEveryMs = 50 * 60 * 1000; // -1 faim toutes les 50 min
const int kJoyEveryMs = 35 * 60 * 1000; // -1 joie toutes les 35 min
const int kJoyEveryDirtyMs = 15 * 60 * 1000; // plus vite s'il y a des spores
const int kPileEveryMs = 70 * 60 * 1000; // un tas de spores toutes les 70 min
const int kMaxNeed = 4;
const int kMaxPiles = 3;
const int kBarsToHatch = 2;
const int kBarsToAdult = 300;
const int kAgeToAdultMs = 24 * 3600 * 1000;

class Pet {
  int food = 3;
  int joy = 3;
  int piles = 0;
  int bars = 0;
  PetStage stage = PetStage.spore;
  int born = _nowMs();
  int _foodAt = _nowMs(), _joyAt = _nowMs(), _pileAt = _nowMs();
  int _barsFood = 0, _barsJoy = 0;
  int _lastPetJoy = 0, _lastFxJoy = 0;

  PetEvent event = PetEvent.none;
  int eventAt = 0;

  Directory? _dir;
  Timer? _saveTimer;

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  bool get hungry => food == 0;
  bool get sad => food <= 1 || joy <= 1;
  bool get content => food >= 3 && joy >= 3 && piles == 0;

  /// Événement en cours (les réactions durent un peu plus d'une seconde).
  PetEvent eventNow(int nowMs) {
    const dur = {
      PetEvent.hatch: 2400,
      PetEvent.eat: 1800,
      PetEvent.refuse: 1200,
      PetEvent.pet: 1400,
      PetEvent.clean: 1200,
      PetEvent.evolve: 2400,
    };
    final d = dur[event] ?? 0;
    return nowMs - eventAt < d ? event : PetEvent.none;
  }

  void _fire(PetEvent ev) {
    event = ev;
    eventAt = _nowMs();
  }

  // ── temps qui passe ──
  /// Applique la baisse des besoins. Renvoie true si quelque chose a changé.
  bool update([int? now]) {
    final n = now ?? _nowMs();
    if (stage == PetStage.spore) {
      // la spore n'a pas de besoins avant d'éclore
      _foodAt = _joyAt = _pileAt = n;
      return false;
    }
    var changed = false;
    final df = (n - _foodAt) ~/ kFoodEveryMs;
    if (df > 0) {
      food = max(0, food - df);
      _foodAt += df * kFoodEveryMs;
      changed = true;
    }
    final jEvery = piles > 0 ? kJoyEveryDirtyMs : kJoyEveryMs;
    final dj = (n - _joyAt) ~/ jEvery;
    if (dj > 0) {
      joy = max(0, joy - dj);
      _joyAt += dj * jEvery;
      changed = true;
    }
    final dp = (n - _pileAt) ~/ kPileEveryMs;
    if (dp > 0) {
      piles = min(kMaxPiles, piles + dp);
      _pileAt += dp * kPileEveryMs;
      changed = true;
    }
    if (changed) _saveSoon();
    return changed;
  }

  // ── actions de l'utilisateur ──
  /// Une mesure jouée par le séquenceur : la musique le nourrit et l'amuse.
  void onBar() {
    bars++;
    if (stage == PetStage.spore) {
      if (bars >= kBarsToHatch) {
        stage = PetStage.baby;
        final n = _nowMs();
        born = n;
        _foodAt = _joyAt = _pileAt = n;
        _fire(PetEvent.hatch);
      }
      _saveSoon();
      return;
    }
    _barsFood++;
    _barsJoy++;
    if (_barsFood >= 8) {
      _barsFood = 0;
      food = min(kMaxNeed, food + 1);
    }
    if (_barsJoy >= 4) {
      _barsJoy = 0;
      joy = min(kMaxNeed, joy + 1);
    }
    if (stage == PetStage.baby &&
        bars >= kBarsToAdult &&
        _nowMs() - born >= kAgeToAdultMs) {
      stage = PetStage.adult;
      _fire(PetEvent.evolve);
    }
    _saveSoon();
  }

  /// Un nouveau son (micro ou bibliothèque) = un repas.
  void onMeal(int amount) {
    if (stage == PetStage.spore) return;
    if (food >= kMaxNeed) {
      _fire(PetEvent.refuse);
      return;
    }
    food = min(kMaxNeed, food + amount);
    _fire(PetEvent.eat);
    _saveSoon();
  }

  /// Un effet joué en live l'amuse (limité à un point toutes les 20 s).
  void onFx() {
    if (stage == PetStage.spore) return;
    final n = _nowMs();
    if (n - _lastFxJoy < 20000) return;
    _lastFxJoy = n;
    joy = min(kMaxNeed, joy + 1);
    _saveSoon();
  }

  /// Tape sur l'écran : nettoie les spores s'il y en a, sinon caresse.
  void tap() {
    if (stage == PetStage.spore) {
      _fire(PetEvent.pet);
      return;
    }
    if (piles > 0) {
      piles = 0;
      _pileAt = _nowMs();
      _fire(PetEvent.clean);
      _saveSoon();
      return;
    }
    final n = _nowMs();
    if (n - _lastPetJoy > 30000) {
      _lastPetJoy = n;
      joy = min(kMaxNeed, joy + 1);
      _saveSoon();
    }
    _fire(PetEvent.pet);
  }

  // ── sauvegarde ──
  Map<String, dynamic> toJson() => {
        'food': food,
        'joy': joy,
        'piles': piles,
        'bars': bars,
        'stage': stage.index,
        'born': born,
        'foodAt': _foodAt,
        'joyAt': _joyAt,
        'pileAt': _pileAt,
        'barsFood': _barsFood,
        'barsJoy': _barsJoy,
      };

  Future<void> load(Directory dir) async {
    _dir = dir;
    final f = File('${dir.path}/pet.json');
    if (!await f.exists()) return;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      int g(String k, int d) => (j[k] as num?)?.toInt() ?? d;
      int c(int v, int hi) => max(0, min(hi, v));
      food = c(g('food', food), kMaxNeed);
      joy = c(g('joy', joy), kMaxNeed);
      piles = c(g('piles', piles), kMaxPiles);
      bars = g('bars', bars);
      stage = PetStage.values[c(g('stage', 0), PetStage.values.length - 1)];
      born = g('born', born);
      _foodAt = g('foodAt', _foodAt);
      _joyAt = g('joyAt', _joyAt);
      _pileAt = g('pileAt', _pileAt);
      _barsFood = g('barsFood', 0);
      _barsJoy = g('barsJoy', 0);
    } catch (_) {}
    update();
  }

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), save);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    final d = _dir;
    if (d == null) return;
    try {
      await File('${d.path}/pet.json').writeAsString(jsonEncode(toJson()));
    } catch (_) {}
  }
}
