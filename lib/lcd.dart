// Écran LCD : afficheur 7 segments, pictos, pas, mémoire, et Myco, le
// compagnon façon tamagotchi dessiné sur une matrice de points 32 x 28
// (personnage original de MYCO-16). Animation image par image, pilotée
// par un Ticker brut pour ne pas dépendre des réglages d'animation d'Android.
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'engine.dart';
import 'pet.dart';
import 'theme.dart';

const int kGw = 32, kGh = 28;

// ═════════════ tampon de pixels ═════════════
class PixelBuf {
  final Uint8List px = Uint8List(kGw * kGh);

  void clear() => px.fillRange(0, px.length, 0);

  void on(int x, int y, [bool lit = true]) {
    if (x < 0 || y < 0 || x >= kGw || y >= kGh) return;
    px[y * kGw + x] = lit ? 1 : 0;
  }

  /// Pose un motif ('#' = pixel allumé). [flip] le retourne horizontalement.
  void stamp(List<String> rows, int x, int y, {bool flip = false, int maxCols = 99}) {
    if (rows.isEmpty) return;
    final w = rows[0].length;
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      for (var c = 0; c < row.length && c < maxCols; c++) {
        if (row.codeUnitAt(c) != 35) continue; // '#'
        on(flip ? x + w - 1 - c : x + c, y + r);
      }
    }
  }

  /// Pose une liste de points [x0, y0, x1, y1, ...] relative à (x, y).
  void points(List<int> pts, int x, int y, int w, {bool flip = false, bool lit = true}) {
    for (var i = 0; i + 1 < pts.length; i += 2) {
      final px = flip ? w - 1 - pts[i] : pts[i];
      on(x + px, y + pts[i + 1], lit);
    }
  }
}

// ═════════════ sprites ═════════════
enum Eyes { open, closed, happy, sad, down }

enum Mouth { none, neutral, smile, open, frown }

enum Arms { none, down, up, wave }

enum Legs { stand, walk, sit }

class _Rig {
  final List<String> body; // chapeau + pied, sans les jambes
  final List<String> legStand, legWalk;
  final Map<Eyes, List<int>> eyes;
  final Map<Mouth, List<int>> mouth;
  final Map<Arms, List<int>> arms;
  const _Rig(this.body, this.legStand, this.legWalk, this.eyes, this.mouth, this.arms);
  int get w => body[0].length;
  int get h => body.length + legStand.length;
}

const _Rig _adult = _Rig(
  [
    '.....######.....',
    '...##########...',
    '..####..######..',
    '.#####..###..##.',
    '.##########..##.',
    '################',
    '################',
    '..############..',
    '....#......#....',
    '....#......#....',
    '....#......#....',
    '....#......#....',
    '....#......#....',
    '.....######.....',
  ],
  ['.....#....#.....', '....##....##....'],
  ['....#......#....', '...##......##...'],
  {
    Eyes.open: [6, 8, 6, 9, 9, 8, 9, 9],
    Eyes.closed: [5, 9, 6, 9, 9, 9, 10, 9],
    Eyes.happy: [5, 9, 6, 8, 7, 9, 8, 9, 9, 8, 10, 9],
    Eyes.sad: [5, 9, 6, 8, 9, 8, 10, 9],
    Eyes.down: [6, 9, 6, 10, 9, 9, 9, 10],
  },
  {
    Mouth.none: [],
    Mouth.neutral: [7, 12, 8, 12],
    Mouth.smile: [6, 11, 7, 12, 8, 12, 9, 11],
    Mouth.open: [7, 11, 8, 11, 7, 12, 8, 12],
    Mouth.frown: [6, 12, 7, 11, 8, 11, 9, 12],
  },
  {
    Arms.none: [],
    Arms.down: [3, 10, 3, 11, 12, 10, 12, 11],
    Arms.up: [3, 9, 2, 8, 12, 9, 13, 8],
    Arms.wave: [3, 10, 3, 11, 12, 9, 13, 8],
  },
);

const _Rig _baby = _Rig(
  [
    '..######..',
    '.##..####.',
    '###..#####',
    '##########',
    '.#......#.',
    '.#......#.',
    '.#......#.',
    '.#......#.',
    '..######..',
  ],
  ['..#....#..', '.##....##.'],
  ['.#......#.', '##......##'],
  {
    Eyes.open: [3, 5, 6, 5],
    Eyes.closed: [2, 5, 3, 5, 6, 5, 7, 5],
    Eyes.happy: [2, 5, 3, 4, 4, 5, 5, 5, 6, 4, 7, 5],
    Eyes.sad: [3, 5, 6, 5, 6, 6],
    Eyes.down: [3, 6, 6, 6],
  },
  {
    Mouth.none: [],
    Mouth.neutral: [4, 7, 5, 7],
    Mouth.smile: [3, 6, 4, 7, 5, 7, 6, 6],
    Mouth.open: [4, 6, 5, 6, 4, 7, 5, 7],
    Mouth.frown: [3, 7, 4, 6, 5, 6, 6, 7],
  },
  {
    Arms.none: [],
    Arms.down: [0, 5, 0, 6, 9, 5, 9, 6],
    Arms.up: [0, 4, 0, 5, 9, 4, 9, 5],
    Arms.wave: [0, 5, 0, 6, 9, 4, 9, 5],
  },
);

const List<String> _egg = [
  '...###...',
  '.#######.',
  '.##.####.',
  '#########',
  '####.####',
  '#######.#',
  '#########',
  '.#######.',
  '...###...',
];
const List<int> _eggCrack = [4, 1, 5, 2, 4, 3, 5, 4, 4, 5];

const List<String> _heart = ['.#.#.', '#####', '.###.', '..#..'];
const List<String> _note = ['..##', '..#.', '..#.', '##..', '##..'];
const List<String> _zed = ['####', '..#.', '.#..', '####'];
const List<String> _bang = ['#', '#', '#', '.', '#'];
const List<String> _pile = ['..#..', '.###.', '#####'];
const List<String> _play = ['#..', '##.', '###', '##.', '#..'];
const List<String> _spark = ['.#.', '###', '.#.'];

int _ci(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

class _Part {
  double x, y, vx, vy, life;
  _Part(this.x, this.y, this.vx, this.vy, this.life);
}

// ═════════════ peintre ═════════════
class LcdPainter extends CustomPainter {
  final Engine e;
  final PixelBuf buf;
  LcdPainter(this.e, this.buf);

  static const ink = cLcdInk;
  static final ghost = cLcdInk.withValues(alpha: 0.07);

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    final w = size.width, h = size.height;

    // ── zone gauche : chiffres + pictos ──
    final leftW = w * 0.46;
    final digits = _digitsText(now);
    _drawSegments(canvas, Rect.fromLTWH(8, 8, leftW - 16, h * 0.42), digits);

    final icons = <String>[
      e.cur.drum ? 'DRM' : 'MEL',
      if (e.writeMode) 'WR',
      if (e.playing) '▶',
      if (e.recordingSlot != null) '●',
      if (e.liveFx != null) kFxShort[e.liveFx!],
      ['TON', 'FLT', 'TRM'][e.knobMode.index],
    ];
    var x = 8.0;
    for (final ic in icons) {
      final tp = _text(ic, 10, bold: true);
      if (x + tp.width > leftW) break;
      tp.paint(canvas, Offset(x, h * 0.52));
      x += tp.width + 6;
    }

    // mémoire (40 s)
    final memY = h * 0.52 + 18;
    final memW = leftW - 16;
    final used = (e.memoryUsed / kMaxMemory).clamp(0.0, 1.0).toDouble();
    canvas.drawRect(Rect.fromLTWH(8, memY, memW, 5), Paint()..color = ghost);
    canvas.drawRect(Rect.fromLTWH(8, memY, memW * used, 5), Paint()..color = ink);
    _text('MEM ${e.memoryUsed.toStringAsFixed(1)}s', 8).paint(canvas, Offset(8, memY + 7));

    // 16 pas du son courant
    final dotsY = h - 14;
    final pat = e.patterns[e.pattern];
    final dw = (leftW - 16) / 16;
    for (var i = 0; i < 16; i++) {
      final on = pat.tracks[e.sound][i] != null;
      final head = e.step == i;
      final hasFx = pat.fx[i] != null;
      final r = Rect.fromLTWH(8 + i * dw + 1, dotsY, dw - 2, 8);
      canvas.drawRect(
          r,
          Paint()
            ..color = head
                ? ink
                : on
                    ? ink.withValues(alpha: 0.55)
                    : ghost);
      if (hasFx) {
        canvas.drawRect(Rect.fromLTWH(r.left, dotsY - 4, r.width, 2), Paint()..color = ink);
      }
    }

    // ── zone droite : matrice de points de Myco ──
    final area = Rect.fromLTWH(leftW, 6, w - leftW - 6, h - 12);
    _drawMatrix(canvas, area);
  }

  void _drawMatrix(Canvas canvas, Rect area) {
    final cell = min(area.width / kGw, area.height / kGh);
    final ox = area.left + (area.width - cell * kGw) / 2 + cell / 2;
    final oy = area.top + (area.height - cell * kGh) / 2 + cell / 2;
    final all = Float32List(kGw * kGh * 2);
    var lit = 0;
    for (var i = 0; i < kGw * kGh; i++) {
      if (buf.px[i] == 1) lit++;
    }
    final litPts = Float32List(lit * 2);
    var k = 0, j = 0;
    for (var y = 0; y < kGh; y++) {
      for (var x = 0; x < kGw; x++) {
        final px = ox + x * cell, py = oy + y * cell;
        all[k++] = px;
        all[k++] = py;
        if (buf.px[y * kGw + x] == 1) {
          litPts[j++] = px;
          litPts[j++] = py;
        }
      }
    }
    final side = cell * 0.84;
    canvas.drawRawPoints(
        ui.PointMode.points,
        all,
        Paint()
          ..color = ghost
          ..strokeWidth = side
          ..strokeCap = StrokeCap.square);
    canvas.drawRawPoints(
        ui.PointMode.points,
        litPts,
        Paint()
          ..color = ink
          ..strokeWidth = side
          ..strokeCap = StrokeCap.square);
  }

  String _digitsText(DateTime now) {
    final tr = e.lcdTransient;
    if (tr != null) return tr;
    if (e.recordingSlot != null) return 'REC';
    if (e.processing) return '...';
    if (e.idle) {
      return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    }
    if (e.held.contains(Btn.sound)) return 'S${e.sound + 1}';
    if (e.held.contains(Btn.pattern)) return 'P${e.pattern + 1}';
    if (e.held.contains(Btn.bpm)) return '${e.bpm}';
    if (e.playing && e.chaining) {
      return '${e.chainIndex + 1}.${e.pattern + 1}';
    }
    return '${e.bpm}';
  }

  TextPainter _text(String s, double size, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: ink,
          fontSize: size,
          fontFamily: 'monospace',
          fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  }

  // ── afficheur 7 segments (4 cases) ──
  static const Map<String, int> _seg = {
    // bits : a b c d e f g
    '0': 0x3F, '1': 0x06, '2': 0x5B, '3': 0x4F, '4': 0x66, '5': 0x6D,
    '6': 0x7D, '7': 0x07, '8': 0x7F, '9': 0x6F, '-': 0x40, ' ': 0x00,
    'A': 0x77, 'B': 0x7C, 'C': 0x39, 'D': 0x5E, 'E': 0x79, 'F': 0x71,
    'G': 0x3D, 'H': 0x76, 'I': 0x06, 'L': 0x38, 'M': 0x37, 'N': 0x54,
    'O': 0x3F, 'P': 0x73, 'R': 0x50, 'S': 0x6D, 'T': 0x78, 'U': 0x3E,
    'V': 0x3E, 'W': 0x7E, 'Y': 0x6E, 'K': 0x75, 'Q': 0x67, 'X': 0x76,
    '+': 0x46, '.': 0x00, ':': 0x00, '/': 0x52,
  };

  void _drawSegments(Canvas canvas, Rect r, String text) {
    final chars = <String>[];
    final dots = <bool>[];
    for (final ch in text.toUpperCase().split('')) {
      if ((ch == '.' || ch == ':') && chars.isNotEmpty) {
        dots[dots.length - 1] = true;
        continue;
      }
      chars.add(ch);
      dots.add(false);
    }
    while (chars.length < 4) {
      chars.insert(0, ' ');
      dots.insert(0, false);
    }
    final shown = chars.sublist(chars.length - 4);
    final shownDots = dots.sublist(dots.length - 4);
    final cw = r.width / 4;
    for (var i = 0; i < 4; i++) {
      final cell = Rect.fromLTWH(r.left + i * cw + cw * 0.08, r.top, cw * 0.78, r.height);
      _digit(canvas, cell, _seg[shown[i]] ?? 0x49, shownDots[i]);
    }
  }

  void _digit(Canvas canvas, Rect c, int bits, bool dot) {
    final th = c.width * 0.16;
    final on = Paint()..color = ink;
    final off = Paint()..color = ghost;
    final midY = c.top + c.height / 2;
    final segs = <Rect>[
      Rect.fromLTWH(c.left + th, c.top, c.width - 2 * th, th), // a
      Rect.fromLTWH(c.right - th, c.top + th * 0.6, th, c.height / 2 - th * 0.9), // b
      Rect.fromLTWH(c.right - th, midY + th * 0.3, th, c.height / 2 - th * 0.9), // c
      Rect.fromLTWH(c.left + th, c.bottom - th, c.width - 2 * th, th), // d
      Rect.fromLTWH(c.left, midY + th * 0.3, th, c.height / 2 - th * 0.9), // e
      Rect.fromLTWH(c.left, c.top + th * 0.6, th, c.height / 2 - th * 0.9), // f
      Rect.fromLTWH(c.left + th, midY - th / 2, c.width - 2 * th, th), // g
    ];
    for (var s = 0; s < 7; s++) {
      final lit = (bits >> s) & 1 == 1;
      canvas.drawRRect(
          RRect.fromRectAndRadius(segs[s], Radius.circular(th / 2)), lit ? on : off);
    }
    canvas.drawCircle(Offset(c.right + th * 0.9, c.bottom - th / 2), th / 2, dot ? on : off);
  }

  @override
  bool shouldRepaint(covariant LcdPainter old) => true;
}

// ═════════════ scène animée ═════════════
class LcdScreen extends StatefulWidget {
  final Engine engine;
  const LcdScreen({super.key, required this.engine});
  @override
  State<LcdScreen> createState() => _LcdScreenState();
}

class _LcdScreenState extends State<LcdScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final PixelBuf _buf = PixelBuf();
  final Random _rnd = Random();
  final List<_Part> _parts = [];

  double _t = 0; // secondes depuis l'ouverture
  double _lastUpdate = -10;
  int _lastFrameKey = -1;

  // promenade
  int _x = 8;
  int _dir = 1;
  int _target = 8;
  int _walkPhase = 0;
  double _nextMove = 0;
  double _pauseUntil = 0;
  double _anticAt = -10;
  int _anticKind = 0;

  // sommeil
  bool _wasSleeping = false;
  double _wakeAt = -10;
  int _lastKick = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    var dt = t - _t;
    if (dt < 0 || dt > 0.1) dt = 1 / 60;
    _t = t;
    _simulate(dt);
    _compose();
    // l'écran à points ne change qu'une dizaine de fois par seconde :
    // on ne redessine que si l'image ou l'état du moteur a bougé.
    var key = 17;
    for (var i = 0; i < _buf.px.length; i++) {
      key = (key * 31 + _buf.px[i] * (i + 1)) & 0x3FFFFFFF;
    }
    final e = widget.engine;
    key = (key * 31 + e.step + 1) & 0x3FFFFFFF;
    key = (key * 31 + DateTime.now().second) & 0x3FFFFFFF;
    if (key != _lastFrameKey) {
      _lastFrameKey = key;
      setState(() {});
    }
  }

  _Rig get _rig => widget.engine.pet.stage == PetStage.adult ? _adult : _baby;

  bool _sleeping(int nowMs) {
    final e = widget.engine;
    if (e.playing || e.recordingSlot != null || e.processing) return false;
    final inactive = nowMs - e.lastActivityMs;
    final hour = DateTime.now().hour;
    final night = hour >= 22 || hour < 7;
    return inactive > 60000 || (night && inactive > 15000);
  }

  void _simulate(double dt) {
    final e = widget.engine;
    final pet = e.pet;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_t - _lastUpdate > 1) {
      _lastUpdate = _t;
      pet.update(nowMs);
    }

    final sleeping = _sleeping(nowMs);
    if (_wasSleeping && !sleeping) _wakeAt = _t;
    _wasSleeping = sleeping;

    final w = _rig.w;
    final maxX = max(0, kGw - w - pet.piles * 6);
    if (_x > maxX) _x = maxX;
    if (_target > maxX) _target = maxX;

    // spores projetées sur les kicks
    if (e.lastKickMs != _lastKick) {
      _lastKick = e.lastKickMs;
      if (e.playing && pet.stage != PetStage.spore) {
        final top = kGh - _rig.h;
        for (var i = 0; i < 3; i++) {
          _parts.add(_Part(_x + w / 2 + (_rnd.nextDouble() - 0.5) * w * 0.6, top.toDouble(),
              (_rnd.nextDouble() - 0.5) * 16, -8 - _rnd.nextDouble() * 8, 0.7));
        }
      }
    }
    for (final p in _parts) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 24 * dt;
      p.life -= dt;
    }
    _parts.removeWhere((p) => p.life <= 0);
    if (_parts.length > 24) _parts.removeRange(0, _parts.length - 24);

    // promenade quand il est réveillé et libre
    final free = !e.playing &&
        !sleeping &&
        e.recordingSlot == null &&
        !e.processing &&
        !e.writeMode &&
        pet.stage != PetStage.spore &&
        pet.eventNow(nowMs) == PetEvent.none &&
        _t - _wakeAt > 1.2;
    if (!free) return;
    if (_t < _pauseUntil || _t < _nextMove) return;
    if (_x == _target) {
      _pauseUntil = _t + 1.2 + _rnd.nextDouble() * 3;
      _target = _rnd.nextInt(maxX + 1);
      if (_rnd.nextDouble() < 0.5) {
        _anticAt = _t;
        _anticKind = _rnd.nextInt(3);
      }
      return;
    }
    final s = _target > _x ? 1 : -1;
    _x += s;
    _dir = s;
    _walkPhase++;
    _nextMove = _t + (pet.sad ? 0.5 : 0.28);
  }

  // ── composition de l'image ──
  void _compose() {
    final e = widget.engine;
    final pet = e.pet;
    final b = _buf..clear();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final blinkOn = (_t * 2).floor().isEven;

    // barre d'état : faim (note) et joie (cœur)
    if (!(pet.hungry && pet.stage != PetStage.spore && !blinkOn)) b.stamp(_note, 0, 0);
    if (!(pet.joy == 0 && pet.stage != PetStage.spore && !blinkOn)) b.stamp(_heart, 17, 0);
    for (var i = 0; i < kMaxNeed; i++) {
      final spore = pet.stage == PetStage.spore;
      for (var r = 1; r <= 4; r++) {
        if (r == 4 || (!spore && i < pet.food)) b.on(5 + i * 2, r);
        if (r == 4 || (!spore && i < pet.joy)) b.on(23 + i * 2, r);
      }
    }

    // tas de spores à nettoyer
    for (var i = 0; i < pet.piles; i++) {
      final px = kGw - 6 - i * 6;
      b.stamp(_pile, px, kGh - 3);
      final ph = ((_t * 3).floor() + i).isEven;
      b.on(px + 1, kGh - (ph ? 5 : 6));
      b.on(px + 3, kGh - (ph ? 6 : 5));
    }

    final ev = pet.eventNow(nowMs);
    final p = ((nowMs - pet.eventAt) / 1000.0);

    if (pet.stage == PetStage.spore && ev != PetEvent.hatch) {
      _drawEgg(b, e, ev == PetEvent.pet);
    } else if (ev == PetEvent.hatch) {
      _drawHatch(b, p / 2.4);
    } else if (ev == PetEvent.evolve) {
      _drawEvolve(b, p / 2.4);
    } else if (ev == PetEvent.eat || e.processing) {
      _drawEat(b, ev == PetEvent.eat ? p / 1.8 : null);
    } else if (ev == PetEvent.refuse) {
      final flip = (_t / 0.15).floor().isOdd;
      _myco(b, eyes: Eyes.closed, mouth: Mouth.frown, arms: Arms.none, flip: flip);
    } else if (ev == PetEvent.pet) {
      _drawPetted(b, p / 1.4);
    } else if (ev == PetEvent.clean) {
      _drawClean(b, p / 1.2);
    } else if (e.recordingSlot != null) {
      _drawSing(b);
    } else if (e.playing) {
      _drawDance(b, e);
    } else if (_wasSleeping) {
      _drawSleep(b);
    } else if (_t - _wakeAt < 1.2) {
      final early = _t - _wakeAt < 0.6;
      _myco(b,
          eyes: early ? Eyes.closed : Eyes.open,
          mouth: early ? Mouth.open : Mouth.smile,
          arms: Arms.up);
    } else if (e.writeMode) {
      _myco(b, eyes: Eyes.down, mouth: Mouth.neutral, arms: Arms.down);
    } else {
      _drawIdle(b, pet);
    }

    for (final pt in _parts) {
      b.on(pt.x.round(), pt.y.round());
    }
  }

  /// Dessine Myco à sa position ; renvoie la ligne du haut du sprite.
  int _myco(PixelBuf b,
      {Eyes eyes = Eyes.open,
      Mouth mouth = Mouth.smile,
      Arms arms = Arms.down,
      Legs legs = Legs.stand,
      int dy = 0,
      bool? flip,
      _Rig? rig}) {
    final r = rig ?? _rig;
    final f = flip ?? _dir < 0;
    var top = kGh - r.h + dy;
    if (legs == Legs.sit) top += r.legStand.length;
    b.stamp(r.body, _x, top, flip: f);
    if (legs != Legs.sit) {
      b.stamp(legs == Legs.walk ? r.legWalk : r.legStand, _x, top + r.body.length, flip: f);
    }
    b.points(r.eyes[eyes]!, _x, top, r.w, flip: f);
    b.points(r.mouth[mouth]!, _x, top, r.w, flip: f);
    b.points(r.arms[arms]!, _x, top, r.w, flip: f);
    return top;
  }

  void _drawEgg(PixelBuf b, Engine e, bool tapped) {
    var off = 0;
    if (e.playing) {
      off = (max(0, e.step) ~/ 2).isEven ? 0 : 1;
    } else if (tapped) {
      off = (_t * 10).floor().isEven ? -1 : 1;
    } else if (_t % 3 < 0.5) {
      off = (_t * 8).floor().isEven ? 0 : 1;
    }
    final x = (kGw - 9) ~/ 2 + off;
    final y = kGh - 9;
    b.stamp(_egg, x, y);
    if (e.pet.bars >= 1) b.points(_eggCrack, x, y, 9, lit: false);
    // invite à lancer la lecture pour le faire éclore
    if (!e.playing && (_t * 1.5).floor().isEven) b.stamp(_play, 14, 9);
  }

  void _drawHatch(PixelBuf b, double p) {
    final cx = kGw ~/ 2, cy = kGh - 5;
    if (p < 0.5) {
      final off = (_t * 14).floor().isEven ? -1 : 1;
      final x = (kGw - 9) ~/ 2 + off;
      b.stamp(_egg, x, kGh - 9);
      b.points(_eggCrack, x, kGh - 9, 9, lit: false);
      if ((_t * 6).floor().isEven) b.points(const [2, 3, 3, 4, 6, 3, 5, 5], x, kGh - 9, 9, lit: false);
      return;
    }
    if (p < 0.65) {
      final rad = ((p - 0.5) / 0.15 * 10).round() + 2;
      for (var a = 0; a < 8; a++) {
        final ang = a * pi / 4;
        b.on(cx + (cos(ang) * rad).round(), cy + (sin(ang) * rad * 0.8).round());
      }
      return;
    }
    _x = (kGw - _baby.w) ~/ 2;
    final top = _myco(b, eyes: Eyes.happy, mouth: Mouth.smile, arms: Arms.up, rig: _baby,
        dy: (_t * 4).floor().isEven ? -1 : 0);
    _sparkles(b, top);
  }

  void _drawEvolve(PixelBuf b, double p) {
    if (p < 0.6) {
      final big = (_t / 0.15).floor().isEven;
      final r = big ? _adult : _baby;
      _x = ((kGw - r.w) ~/ 2);
      _myco(b, eyes: Eyes.closed, mouth: Mouth.neutral, arms: Arms.none, rig: r);
      return;
    }
    _x = (kGw - _adult.w) ~/ 2;
    final top = _myco(b, eyes: Eyes.happy, mouth: Mouth.open, arms: Arms.up, rig: _adult);
    _sparkles(b, top);
  }

  void _sparkles(PixelBuf b, int top) {
    if ((_t * 5).floor().isEven) {
      b.stamp(_spark, _x - 4, top + 1);
      b.stamp(_spark, _x + _rig.w + 1, top + 3);
    } else {
      b.stamp(_spark, _x - 3, top + 4);
      b.stamp(_spark, _x + _rig.w, top);
    }
  }

  /// Il mange un son : une note devant la bouche, croquée en trois bouchées.
  void _drawEat(PixelBuf b, double? p) {
    final chew = (_t * 5).floor().isEven;
    final top = _myco(b,
        eyes: Eyes.happy, mouth: chew ? Mouth.open : Mouth.neutral, arms: Arms.down, flip: false);
    final int bites = p == null ? (_t * 1.5).floor() % 3 : _ci((p * 3).floor(), 0, 3);
    final left = 4 - bites;
    if (left <= 0) return;
    final r = _rig;
    final mouthRow = r == _adult ? 10 : 5;
    // la note est à droite de Myco ; les bouchées la rognent côté bouche
    final nx = min(_x + r.w, kGw - 4);
    final cropped = [for (final row in _note) row.substring(4 - left)];
    b.stamp(cropped, nx + (4 - left), top + mouthRow - 2);
  }

  void _drawPetted(PixelBuf b, double p) {
    final top = _myco(b,
        eyes: Eyes.happy,
        mouth: Mouth.smile,
        arms: Arms.up,
        dy: (_t * 4).floor().isEven ? -1 : 0);
    final rise = (p * 6).floor();
    final hx = _x + _rig.w ~/ 2 - 2;
    b.stamp(_heart, hx - 3, top - 5 - rise);
    if (p > 0.3) b.stamp(_heart, hx + 4, top - 3 - (rise ~/ 2));
  }

  void _drawClean(PixelBuf b, double p) {
    _myco(b, eyes: Eyes.happy, mouth: Mouth.smile, arms: Arms.wave, flip: false);
    final col = kGw - 1 - (p * (kGw + 2)).floor();
    for (var y = 6; y < kGh; y++) {
      b.on(col, y);
      if (y.isEven) b.on(col + 2, y);
    }
  }

  void _drawSing(PixelBuf b) {
    final open = (_t * 4).floor().isEven;
    final top = _myco(b,
        eyes: Eyes.closed, mouth: open ? Mouth.open : Mouth.smile, arms: Arms.up, flip: false);
    final ph = (_t * 6) % 8;
    b.stamp(_note, _x + _rig.w, top + 2 - ph.floor());
    b.stamp(_note, _x + _rig.w + 4, top + 6 - ((ph + 4) % 8).floor());
  }

  void _drawDance(PixelBuf b, Engine e) {
    final s = max(0, e.step);
    final onBeat = s % 4 == 0;
    final fx = e.liveFx != null;
    final pet = e.pet;
    final top = _myco(b,
        eyes: fx ? Eyes.closed : (onBeat ? Eyes.happy : Eyes.open),
        mouth: pet.sad ? Mouth.neutral : (onBeat ? Mouth.open : Mouth.smile),
        arms: (s ~/ 2).isEven ? Arms.up : Arms.down,
        legs: (s ~/ 2).isOdd ? Legs.walk : Legs.stand,
        dy: onBeat ? -1 : 0,
        flip: fx ? (s ~/ 2).isOdd : _dir < 0);
    // une note qui s'envole sur chaque mesure
    final ph = s % 16;
    if (ph < 8) {
      final side = (s ~/ 16).isEven;
      final nx = side ? _x - 5 : _x + _rig.w + 1;
      b.stamp(_note, _ci(nx, 0, kGw - 4), top + 3 - ph);
    }
  }

  void _drawSleep(PixelBuf b) {
    final top = _myco(b, eyes: Eyes.closed, mouth: Mouth.none, arms: Arms.none, legs: Legs.sit);
    final ph = (_t * 0.8) % 1;
    final zx = _ci(_x + _rig.w, 0, kGw - 4);
    b.stamp(_zed, zx, top + 2 - (ph * 6).floor());
    if (ph > 0.5) b.stamp(_zed, _ci(zx - 2, 0, kGw - 4), top + 5 - ((ph - 0.5) * 6).floor());
  }

  void _drawIdle(PixelBuf b, Pet pet) {
    final moving = _x != _target && _t >= _pauseUntil;
    final blink = (_t % 3.3) < 0.14;
    var arms = Arms.down;
    var dy = 0;
    var flip = _dir < 0;
    final a = _t - _anticAt;
    if (!moving && a < 1.2) {
      switch (_anticKind) {
        case 0: // regarde autour de lui
          flip = a < 0.6 ? !flip : flip;
          break;
        case 1: // petit saut
          dy = (a * 5).floor().isEven ? -1 : 0;
          break;
        default: // salue
          arms = (a * 4).floor().isEven ? Arms.wave : Arms.down;
      }
    }
    final top = _myco(b,
        eyes: blink ? Eyes.closed : (pet.sad ? Eyes.sad : Eyes.open),
        mouth: pet.sad ? Mouth.frown : (pet.content ? Mouth.smile : Mouth.neutral),
        arms: arms,
        legs: moving && _walkPhase.isOdd ? Legs.walk : Legs.stand,
        dy: dy,
        flip: flip);
    // il réclame : faim, ennui ou spores à nettoyer
    final needs = pet.hungry || pet.joy == 0 || pet.piles >= 2;
    if (needs && _t % 4 < 1.6) {
      b.stamp(_bang, _ci(_x + _rig.w ~/ 2 + 5, 0, kGw - 1), max(6, top - 6));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        e.tapPet();
      },
      child: Container(
        decoration: BoxDecoration(
          color: cLcd,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, spreadRadius: -2)],
        ),
        // SizedBox.expand : sans lui, le CustomPaint (sans enfant) prend une
        // taille nulle dans la Row et tout l'écran est dessiné hors cadre.
        child: SizedBox.expand(child: CustomPaint(painter: LcdPainter(e, _buf))),
      ),
    );
  }
}
