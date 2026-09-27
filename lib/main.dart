// MYCO-16 : micro-sampler de poche.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine.dart';
import 'lcd.dart';
import 'song_page.dart';
import 'sound_sheet.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MycoApp());
}

class MycoApp extends StatelessWidget {
  const MycoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MYCO-16',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: cBg,
          colorScheme: const ColorScheme.dark(primary: cPadOn, surface: cBody),
        ),
        home: const DevicePage(),
      );
}

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});
  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final Engine e = Engine();

  @override
  void initState() {
    super.initState();
    e.addListener(_refresh);
    e.init();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    e.removeListener(_refresh);
    e.dispose();
    super.dispose();
  }

  void _toast(String? msg) {
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ── touches 1-16 ──
  bool _keyLit(int k) {
    final h = e.held;
    if (e.recordingSlot == k) return true;
    if (h.contains(Btn.record)) return false;
    if (h.contains(Btn.sound)) return k == e.sound;
    if (h.contains(Btn.pattern)) return k == e.pattern;
    if (h.contains(Btn.bpm)) return k < e.masterVol;
    if (h.contains(Btn.fx)) return k == e.liveFx;
    if (e.writeMode) return e.patterns[e.pattern].tracks[e.sound][k] != null;
    return DateTime.now().millisecondsSinceEpoch - e.keyFlash[k] < 110;
  }

  String _keyLabel(int k) {
    final h = e.held;
    if (h.contains(Btn.record)) return e.slots[k].isEmpty ? 'REC' : e.slots[k].name;
    if (h.contains(Btn.sound)) return e.slots[k].name;
    if (h.contains(Btn.pattern)) {
      final inChain = e.chain.length > 1 && e.chain.contains(k);
      return 'PAT${e.patterns[k].used ? ' •' : ''}${inChain ? ' ♪' : ''}';
    }
    if (h.contains(Btn.bpm)) return 'VOL ${k + 1}';
    if (h.contains(Btn.fx)) return kFxShort[k];
    if (e.writeMode) return '';
    return '';
  }

  Color _keyColor(int k) {
    final h = e.held;
    if (e.recordingSlot == k || h.contains(Btn.record)) return cRec;
    if (h.contains(Btn.fx)) return const Color(0xFFB98CFF);
    if (h.contains(Btn.pattern) || h.contains(Btn.sound)) return cSong;
    return cPadOn;
  }

  // ── menu ──
  void _menu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: cBody,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: const Text('Arrangement (chaîne de patterns)'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => SongPage(engine: e)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.library_music),
            title: Text('Bibliothèque : charger un son dans le slot ${e.sound + 1}'),
            onTap: () {
              Navigator.pop(ctx);
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: cBody,
                builder: (_) => SoundSheet(engine: e),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Aide : toutes les combinaisons'),
            onTap: () {
              Navigator.pop(ctx);
              _help();
            },
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Remettre les 16 sons d\'usine'),
            onTap: () async {
              Navigator.pop(ctx);
              if (await _confirm('Remplacer les 16 sons par ceux d\'usine ?')) {
                await e.resetFactory();
                _toast('Sons d\'usine rechargés');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: const Text('Effacer tous les patterns'),
            onTap: () async {
              Navigator.pop(ctx);
              if (await _confirm('Effacer les 16 patterns et la chaîne ?')) {
                e.clearAllPatterns();
                _toast('Patterns effacés');
              }
            },
          ),
        ]),
      ),
    );
  }

  Future<bool> _confirm(String q) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(q),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                decoration: BoxDecoration(
                  color: cBody,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cPcb, width: 2),
                ),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                child: !e.ready
                    ? Center(
                        child: Text(e.error ?? 'préparation des sons…',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: cText, fontFamily: 'monospace')),
                      )
                    : Column(children: [
                        _header(),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 150,
                          child: Row(children: [
                            Expanded(child: LcdScreen(engine: e)),
                            const SizedBox(width: 10),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                KnobWidget(engine: e, knob: Knob.a),
                                KnobWidget(engine: e, knob: Knob.b),
                              ],
                            ),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        _functionRows(),
                        const SizedBox(height: 12),
                        Expanded(child: _grid()),
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(children: [
        const Text('MYCO-16',
            style: TextStyle(
                color: cText, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 17)),
        const SizedBox(width: 8),
        Text('slot ${e.sound + 1} · ${e.cur.name}',
            style: const TextStyle(color: cDim, fontSize: 11)),
        const Spacer(),
        GestureDetector(
          onTap: _menu,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.menu, color: cDim, size: 22),
          ),
        ),
      ]);

  Widget _functionRows() {
    Widget fb(Btn b, String label, {bool lit = false, Color? litColor}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: FuncButton(
              label: label,
              pressed: e.held.contains(b),
              lit: lit,
              litColor: litColor ?? cPadOn,
              onDown: () {
                HapticFeedback.selectionClick();
                e.btnDown(b);
              },
              onUp: () => e.btnUp(b),
            ),
          ),
        );
    return Column(children: [
      Row(children: [
        fb(Btn.sound, 'SOUND'),
        fb(Btn.pattern, 'PATTERN', lit: e.chaining, litColor: cSong),
        fb(Btn.bpm, 'BPM'),
        fb(Btn.fx, 'FX', lit: e.liveFx != null, litColor: const Color(0xFFB98CFF)),
      ]),
      Row(children: [
        fb(Btn.record, 'RECORD', lit: e.recordingSlot != null, litColor: cRec),
        fb(Btn.write, 'WRITE', lit: e.writeMode),
        fb(Btn.play, e.playing ? 'STOP' : 'PLAY',
            lit: e.playing, litColor: const Color(0xFF7BD389)),
      ]),
    ]);
  }

  Widget _grid() {
    return LayoutBuilder(builder: (context, c) {
      final size = min(c.maxWidth, c.maxHeight);
      return Center(
        child: SizedBox(
          width: size,
          height: size,
          child: GridView.count(
            crossAxisCount: 4,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 9,
            crossAxisSpacing: 9,
            children: List.generate(16, _key),
          ),
        ),
      );
    });
  }

  Widget _key(int k) {
    final lit = _keyLit(k);
    final color = _keyColor(k);
    final head = e.playing && e.step == k;
    final label = _keyLabel(k);
    return Listener(
      onPointerDown: (_) {
        HapticFeedback.lightImpact();
        e.keyDown(k).then(_toast);
      },
      onPointerUp: (_) => e.keyUp(k).then(_toast),
      onPointerCancel: (_) => e.keyUp(k).then(_toast),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50),
        decoration: BoxDecoration(
          color: lit ? color : cPad,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: head ? cText : Colors.transparent, width: 2),
          boxShadow: lit ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12)] : const [],
        ),
        padding: const EdgeInsets.all(6),
        child: Stack(children: [
          Align(
            alignment: Alignment.topLeft,
            child: Text('${k + 1}',
                style: TextStyle(
                    color: lit ? cLcdInk : cDim, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          if (k == 7 && !e.cur.drum && e.held.isEmpty && !e.writeMode)
            Align(
              alignment: Alignment.topRight,
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                    color: lit ? cLcdInk : cDim, shape: BoxShape.circle),
              ),
            ),
          if (label.isNotEmpty)
            Align(
              alignment: Alignment.bottomLeft,
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                      color: lit ? cLcdInk : cText,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    );
  }

  void _help() {
    showModalBottomSheet(
      context: context,
      backgroundColor: cBody,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: const [
            _HelpSection('SONS', [
              'Touches 1-16 : jouer le son choisi. Slots 1-8 = mélodique (gamme mineure, touche 8 = hauteur d\'origine). Slots 9-16 = batterie (une tranche par touche).',
              'SOUND + touche : choisir le son.',
              'RECORD + touche (maintenus) : enregistrer au micro dans ce slot. Le souffle est nettoyé, les enregistrements batterie sont découpés automatiquement. Mémoire totale : 40 s.',
              'RECORD + SOUND : supprimer le son courant.',
              'WRITE + SOUND + touche : copier le son courant vers ce slot.',
            ]),
            _HelpSection('KNOBS A / B', [
              'Toucher FX (sans touche) change le mode des knobs : TON (hauteur / volume), FLT (filtre passe-bas ↔ passe-haut / résonance), TRM (début / longueur du son ; en batterie, la dernière tranche jouée).',
              'BPM + knob A : swing. BPM + knob B : tempo (60-240).',
            ]),
            _HelpSection('SÉQUENCEUR', [
              'PLAY : lecture / stop.',
              'WRITE (toucher) : mode écriture, les touches deviennent les 16 pas du son courant (avec la dernière note jouée).',
              'WRITE maintenu + touches pendant la lecture : enregistrement live, quantifié.',
              'WRITE maintenu + knobs pendant la lecture : verrouille hauteur, volume, filtre ou résonance sur le pas en cours.',
              'BPM (toucher) : presets 80 / 120 / 140. BPM + touche : volume général 1-16.',
            ]),
            _HelpSection('PATTERNS', [
              'PATTERN + touche : choisir le pattern (bascule à la fin de la mesure pendant la lecture).',
              'PATTERN + plusieurs touches à la suite : chaîner les patterns (jusqu\'à 128, répétitions permises).',
              'WRITE + PATTERN + touche : copier le pattern courant vers cette touche.',
              'RECORD + PATTERN : effacer le pattern courant.',
              'Menu ☰ > Arrangement : voir et réordonner la chaîne.',
            ]),
            _HelpSection('EFFETS (FX + touche maintenue)', [
              '1 loop 16 · 2 loop 12 · 3 loop short · 4 loop shorter · 5 unison · 6 unison low · 7 octave up · 8 octave down · 9 stutter 4 · 10 stutter 3 · 11 scratch · 12 scratch fast · 13 6/8 · 14 retrigger · 15 reverse · 16 aucun.',
              'En mode écriture pendant la lecture, l\'effet est enregistré sur les pas qui défilent. FX + 16 en mode écriture efface les effets du pattern.',
            ]),
            _HelpSection('MYCO, TON COMPAGNON', [
              'Myco naît sous forme de spore : lance la lecture (▶) et il éclot au bout de deux mesures.',
              'En haut de son écran : la note = sa faim, le cœur = sa joie (4 crans chacun). Ils baissent avec le temps, même app fermée.',
              'Il se nourrit de sons : un enregistrement micro = gros repas, un son chargé depuis la bibliothèque = en-cas. S\'il est déjà repu, il refuse.',
              'La musique le nourrit et l\'amuse : chaque mesure jouée compte. Les effets live lui font plaisir aussi.',
              'Tape sur l\'écran pour le caresser. S\'il a laissé des tas de spores, le même geste les nettoie (sinon sa joie baisse plus vite).',
              'Un « ! » au-dessus de sa tête : il a faim, il s\'ennuie ou c\'est sale.',
              'Il danse pendant la lecture, chante quand tu enregistres, mange le son pendant le nettoyage, se promène quand il est libre et dort après 1 min sans rien faire (15 s la nuit).',
              'Après 300 mesures jouées et au moins un jour de vie, il devient adulte.',
            ]),
            _HelpSection('ÉCRAN', [
              'Au repos, les chiffres affichent l\'heure. Tout est sauvegardé automatiquement.',
            ]),
          ],
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  final String title;
  final List<String> lines;
  const _HelpSection(this.title, this.lines);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: cPadOn, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(height: 6),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $l', style: const TextStyle(color: cText, height: 1.4)),
            ),
        ]),
      );
}

class FuncButton extends StatelessWidget {
  final String label;
  final bool pressed;
  final bool lit;
  final Color litColor;
  final VoidCallback onDown;
  final VoidCallback onUp;
  const FuncButton({
    super.key,
    required this.label,
    required this.pressed,
    required this.lit,
    required this.litColor,
    required this.onDown,
    required this.onUp,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onDown(),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) => onUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pressed ? cText : (lit ? litColor : cPcb),
          borderRadius: BorderRadius.circular(21),
        ),
        child: Text(label,
            style: TextStyle(
                color: pressed || lit ? cLcdInk : cText,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
      ),
    );
  }
}

class KnobWidget extends StatelessWidget {
  final Engine engine;
  final Knob knob;
  const KnobWidget({super.key, required this.engine, required this.knob});

  @override
  Widget build(BuildContext context) {
    final v = engine.knobValue(knob).clamp(0.0, 1.0).toDouble();
    return GestureDetector(
      onPanUpdate: (d) => engine.knobTurn(knob, (d.delta.dx - d.delta.dy) / 220),
      onPanEnd: (_) => engine.knobRelease(),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 56,
          height: 56,
          child: CustomPaint(painter: _KnobPainter(v, knob == Knob.a ? 'A' : 'B')),
        ),
        Text(engine.knobLabel(knob),
            style: const TextStyle(color: cDim, fontSize: 9, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double v;
  final String name;
  _KnobPainter(this.v, this.name);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    const start = pi * 0.75, sweep = pi * 1.5;
    canvas.drawCircle(c, r, Paint()..color = cPcb);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r + 2),
        start,
        sweep,
        false,
        Paint()
          ..color = cPad
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r + 2),
        start,
        sweep * v,
        false,
        Paint()
          ..color = cPadOn
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    final a = start + sweep * v;
    canvas.drawLine(
        c + Offset(cos(a), sin(a)) * r * 0.25,
        c + Offset(cos(a), sin(a)) * r * 0.85,
        Paint()
          ..color = cText
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    final tp = TextPainter(
      text: TextSpan(
          text: name,
          style: const TextStyle(color: cDim, fontSize: 10, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c + Offset(-tp.width / 2, r * 0.35));
  }

  @override
  bool shouldRepaint(covariant _KnobPainter old) => old.v != v || old.name != name;
}
