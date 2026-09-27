// Écran LCD : afficheur 7 segments, pictos, pas, mémoire, horloge,
// et Myco, le champignon animé (personnage original de MYCO-16).
import 'dart:math';

import 'package:flutter/material.dart';

import 'engine.dart';
import 'theme.dart';

class Spore {
  double x, y, vx, vy, life;
  Spore(this.x, this.y, this.vx, this.vy, this.life);
}

class LcdPainter extends CustomPainter {
  final Engine e;
  final double t; // secondes depuis le lancement
  final List<Spore> spores;
  LcdPainter(this.e, this.t, this.spores);

  static const ink = cLcdInk;
  static final ghost = cLcdInk.withValues(alpha: 0.07);

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final w = size.width, h = size.height;

    // ── zone gauche : chiffres + pictos ──
    final leftW = w * 0.52;
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
      final tp = _text(ic, 11, bold: true);
      tp.paint(canvas, Offset(x, h * 0.52));
      x += tp.width + 8;
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

    // ── zone droite : Myco ──
    final charRect = Rect.fromLTWH(leftW, 4, w - leftW - 4, h - 8);
    _drawSpores(canvas, charRect);
    _drawMyco(canvas, charRect, nowMs);
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
    '+': 0x46, '.': 0x00, ':': 0x00, '/': 0x52, '6/8': 0x00,
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

  // ── spores ──
  void _drawSpores(Canvas canvas, Rect r) {
    for (final s in spores) {
      final p = Paint()..color = ink.withValues(alpha: (s.life).clamp(0.0, 1.0).toDouble() * 0.8);
      canvas.drawCircle(Offset(r.left + s.x * r.width, r.top + s.y * r.height), 1.8, p);
    }
  }

  // ── Myco ──
  void _drawMyco(Canvas canvas, Rect r, int nowMs) {
    final ink = Paint()..color = LcdPainter.ink;
    final bg = Paint()..color = cLcd;
    final stroke = Paint()
      ..color = LcdPainter.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final sinceHit = (nowMs - e.lastHitMs) / 1000.0;
    final sinceKick = (nowMs - e.lastKickMs) / 1000.0;
    final sleeping = e.idle;
    final recording = e.recordingSlot != null;
    final fxOn = e.liveFx != null;

    // rebond sur le temps, écrasement sur les kicks
    final bounce = e.playing ? exp(-sinceHit * 9) : 0.0;
    final squash = e.playing ? exp(-sinceKick * 12) : 0.0;
    final breathe = sin(t * 2) * 0.02;
    final cx = r.center.dx;
    final baseY = r.bottom - 6;
    final unit = min(r.width, r.height) / 10;

    var tilt = 0.0;
    if (fxOn) tilt = sin(t * 18) * 0.25;
    if (e.writeMode && !fxOn) tilt = -0.12;

    canvas.save();
    canvas.translate(cx, baseY);
    canvas.rotate(tilt);
    canvas.scale(1 + squash * 0.12, 1 - squash * 0.15 + breathe);
    canvas.translate(0, -bounce * unit * 0.8);

    // pied
    final stemW = unit * 2.6, stemH = unit * 3.4;
    final stem = RRect.fromRectAndRadius(
        Rect.fromLTWH(-stemW / 2, -stemH, stemW, stemH), Radius.circular(unit * 1.1));
    canvas.drawRRect(stem, ink);
    canvas.drawRRect(stem.deflate(2), bg);

    // bras : levés quand ça joue fort, micro quand on enregistre
    final armY = -stemH * 0.55;
    final armLift = recording ? 1.2 : (e.playing ? bounce * 1.4 : 0.2);
    canvas.drawLine(Offset(-stemW / 2, armY),
        Offset(-stemW / 2 - unit * 1.2, armY - unit * armLift), stroke);
    canvas.drawLine(Offset(stemW / 2, armY),
        Offset(stemW / 2 + unit * 1.2, armY - unit * (recording ? 1.2 : armLift * 0.7)), stroke);
    if (recording) {
      // petit micro dans la main droite
      final m = Offset(stemW / 2 + unit * 1.3, armY - unit * 1.5);
      canvas.drawCircle(m, unit * 0.45, ink);
      // ondes captées
      for (var i = 1; i <= 3; i++) {
        final rr = unit * (0.6 + i * 0.5 + (t * 2 % 0.5));
        canvas.drawArc(Rect.fromCircle(center: m, radius: rr), -0.8, 1.6, false,
            stroke..strokeWidth = 1.2);
      }
      stroke.strokeWidth = 2;
    }

    // visage
    final faceY = -stemH * 0.62;
    final blink = !sleeping && (t % 3.7) < 0.12;
    if (sleeping || blink) {
      canvas.drawLine(Offset(-unit * 0.6, faceY), Offset(-unit * 0.2, faceY), stroke);
      canvas.drawLine(Offset(unit * 0.2, faceY), Offset(unit * 0.6, faceY), stroke);
    } else {
      final look = e.writeMode ? unit * 0.12 : 0.0;
      canvas.drawCircle(Offset(-unit * 0.4, faceY + look), unit * 0.22, ink);
      canvas.drawCircle(Offset(unit * 0.4, faceY + look), unit * 0.22, ink);
    }
    final mouthY = faceY + unit * 0.7;
    if (recording) {
      canvas.drawCircle(Offset(0, mouthY), unit * 0.25, stroke);
    } else if (e.playing) {
      final open = unit * (0.15 + bounce * 0.35);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(0, mouthY), width: unit * 0.7, height: open * 2), ink);
    } else if (!sleeping) {
      canvas.drawArc(Rect.fromCenter(center: Offset(0, mouthY - unit * 0.15), width: unit * 0.8, height: unit * 0.5),
          0.3, 2.5, false, stroke);
    }

    // chapeau
    final capW = unit * 7, capH = unit * 3.6;
    final capTop = -stemH - capH + unit * 0.6 - (e.playing ? bounce * unit * 0.5 : 0);
    final cap = Path()
      ..moveTo(-capW / 2, capTop + capH)
      ..quadraticBezierTo(-capW / 2, capTop, 0, capTop)
      ..quadraticBezierTo(capW / 2, capTop, capW / 2, capTop + capH)
      ..close();
    canvas.drawPath(cap, ink);
    // taches du chapeau (elles s'allument avec le pas courant)
    final spots = [
      Offset(-capW * 0.25, capTop + capH * 0.45),
      Offset(0, capTop + capH * 0.25),
      Offset(capW * 0.25, capTop + capH * 0.5),
      Offset(-capW * 0.05, capTop + capH * 0.7),
    ];
    for (var i = 0; i < spots.length; i++) {
      final lit = e.playing && e.step >= 0 && (e.step ~/ 4) == i;
      canvas.drawCircle(spots[i], unit * (lit ? 0.62 : 0.45), bg);
    }
    canvas.restore();

    // Zzz quand il dort
    if (sleeping) {
      for (var i = 0; i < 3; i++) {
        final ph = (t * 0.6 + i / 3) % 1;
        final tp = _text('z', 10 + i * 3, bold: true);
        tp.paint(canvas, Offset(cx + unit * 2 + ph * unit * 2, r.top + r.height * 0.35 - ph * unit * 3));
      }
    }
  }

  @override
  bool shouldRepaint(covariant LcdPainter old) => true;
}

/// Widget animé qui repeint l'écran à chaque frame et gère les spores.
class LcdScreen extends StatefulWidget {
  final Engine engine;
  const LcdScreen({super.key, required this.engine});
  @override
  State<LcdScreen> createState() => _LcdScreenState();
}

class _LcdScreenState extends State<LcdScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  final List<Spore> _spores = [];
  final Random _rnd = Random();
  int _lastKickSeen = 0;
  double _t = 0;
  Duration _prev = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_frame)
      ..repeat();
  }

  void _frame() {
    final el = _ctl.lastElapsedDuration ?? Duration.zero;
    var dt = (el - _prev).inMicroseconds / 1e6;
    if (dt < 0 || dt > 0.1) dt = 1 / 60;
    _prev = el;
    _t += dt;
    final e = widget.engine;
    if (e.lastKickMs != _lastKickSeen) {
      _lastKickSeen = e.lastKickMs;
      for (var i = 0; i < 5; i++) {
        _spores.add(Spore(0.5 + (_rnd.nextDouble() - 0.5) * 0.5, 0.35,
            (_rnd.nextDouble() - 0.5) * 0.4, -0.2 - _rnd.nextDouble() * 0.3, 1));
      }
    }
    for (final s in _spores) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vy += 0.15 * dt;
      s.life -= dt * 0.8;
    }
    _spores.removeWhere((s) => s.life <= 0);
    if (_spores.length > 40) _spores.removeRange(0, _spores.length - 40);
    setState(() {});
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cLcd,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, spreadRadius: -2)],
      ),
      child: CustomPaint(painter: LcdPainter(widget.engine, _t, _spores)),
    );
  }
}
