// MYCO-16 : sampler de poche, 16 pads, 16 pas, 16 FX.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine.dart';

const cBg = Color(0xFF0E120E);
const cBody = Color(0xFF1C2A1F); // mousse
const cPcb = Color(0xFF243629);
const cPad = Color(0xFF2E3B31);
const cPadOn = Color(0xFFFF8A1F); // ambre
const cRec = Color(0xFFE5383B);
const cLcd = Color(0xFFB9C4A0);
const cLcdInk = Color(0xFF1C2317);
const cText = Color(0xFFE8EDE3);
const cDim = Color(0xFF8A9A8C);

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
        theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: cBg),
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

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ── pads ───────────────────────────────────
  void _padDown(int i) {
    HapticFeedback.lightImpact();
    switch (e.mode) {
      case Mode.sound:
        e.padPlay(i);
        break;
      case Mode.write:
        e.toggleStep(i);
        break;
      case Mode.pattern:
        e.selectPattern(i);
        break;
      case Mode.fx:
        e.fxDown(i);
        break;
      case Mode.rec:
        e.recStart(i).then((err) {
          if (err != null) _toast(err);
        });
        break;
    }
  }

  void _padUp(int i) {
    if (e.mode == Mode.fx) e.fxUp(i);
    if (e.mode == Mode.rec && e.recordingSlot == i) e.recStop();
  }

  bool _padLit(int i) {
    switch (e.mode) {
      case Mode.sound:
        return i == e.selected ||
            DateTime.now().millisecondsSinceEpoch - e.flash[i] < 90;
      case Mode.write:
        return e.patterns[e.pattern][e.selected][i];
      case Mode.pattern:
        return i == e.pattern;
      case Mode.fx:
        return e.fx == i;
      case Mode.rec:
        return e.recordingSlot == i;
    }
  }

  String _padLabel(int i) {
    switch (e.mode) {
      case Mode.fx:
        return kFxNames[i];
      case Mode.pattern:
        return e.patternUsed(i) ? 'PAT •' : 'PAT';
      case Mode.write:
        return '';
      case Mode.sound:
      case Mode.rec:
        return e.names[i];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Container(
                decoration: BoxDecoration(
                  color: cBody,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cPcb, width: 2),
                ),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                child: !e.ready
                    ? _loading()
                    : Column(
                        children: [
                          _header(),
                          const SizedBox(height: 10),
                          _lcd(),
                          const SizedBox(height: 14),
                          _controls(),
                          const SizedBox(height: 14),
                          Expanded(child: _grid()),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loading() => Center(
        child: Text(
          e.error ?? 'chargement des sons…',
          textAlign: TextAlign.center,
          style: const TextStyle(color: cText, fontFamily: 'monospace'),
        ),
      );

  Widget _header() => Row(
        children: [
          const Text('MYCO-16',
              style: TextStyle(
                  color: cText,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  fontSize: 18)),
          const SizedBox(width: 8),
          const Text('pocket sampler',
              style: TextStyle(color: cDim, fontSize: 11, letterSpacing: 1)),
          const Spacer(),
          GestureDetector(
            onTap: _help,
            child: const Icon(Icons.help_outline, color: cDim, size: 20),
          ),
        ],
      );

  Widget _lcd() {
    final modeName = {
      Mode.sound: 'SOUND',
      Mode.write: 'WRITE',
      Mode.pattern: 'PATTERN',
      Mode.fx: 'FX',
      Mode.rec: e.recordingSlot != null ? '● REC' : 'REC ARM',
    }[e.mode]!;
    const ink = TextStyle(color: cLcdInk, fontFamily: 'monospace', fontSize: 13);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cLcd,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(modeName,
                style: ink.copyWith(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(e.playing ? '▶' : '■', style: ink.copyWith(fontSize: 18)),
          ]),
          const SizedBox(height: 4),
          Text(
            'BPM ${e.bpm}  PAT ${(e.pattern + 1).toString().padLeft(2, '0')}  '
            'SND ${(e.selected + 1).toString().padLeft(2, '0')} ${e.names[e.selected]}',
            style: ink,
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(16, (i) {
              final on = e.patterns[e.pattern][e.selected][i];
              final head = e.step == i;
              return Expanded(
                child: Container(
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: head
                        ? cLcdInk
                        : (on ? cLcdInk.withOpacity(0.45) : cLcdInk.withOpacity(0.1)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    Widget b(String label, VoidCallback onTap,
        {bool active = false, Color? activeColor, VoidCallback? onLong}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            onLongPress: onLong,
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? (activeColor ?? cPadOn) : cPcb,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: active ? cLcdInk : cText,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
            ),
          ),
        ),
      );
    }

    return Column(children: [
      Row(children: [
        b('SOUND', () => e.setMode(Mode.sound), active: e.mode == Mode.sound),
        b('PATTERN', () => e.setMode(Mode.pattern), active: e.mode == Mode.pattern),
        b('BPM −', () => e.nudgeBpm(-2)),
        b('BPM +', () => e.nudgeBpm(2)),
      ]),
      Row(children: [
        b('WRITE', () => e.setMode(Mode.write), active: e.mode == Mode.write,
            onLong: () {
          e.clearTrack();
          _toast('Piste ${e.names[e.selected]} effacée');
        }),
        b('FX', () => e.setMode(Mode.fx), active: e.mode == Mode.fx),
        b('REC', () => e.setMode(Mode.rec),
            active: e.mode == Mode.rec, activeColor: cRec),
        b(e.playing ? 'STOP' : 'PLAY', e.togglePlay,
            active: e.playing, activeColor: const Color(0xFF7BD389)),
      ]),
    ]);
  }

  Widget _grid() {
    return LayoutBuilder(builder: (context, c) {
      final size = (c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight);
      return Center(
        child: SizedBox(
          width: size,
          height: size,
          child: GridView.count(
            crossAxisCount: 4,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: List.generate(16, (i) => _pad(i)),
          ),
        ),
      );
    });
  }

  Widget _pad(int i) {
    final lit = _padLit(i);
    final head = e.playing && e.step == i;
    final rec = e.mode == Mode.rec;
    final onColor = rec ? cRec : cPadOn;
    return Listener(
      onPointerDown: (_) => _padDown(i),
      onPointerUp: (_) => _padUp(i),
      onPointerCancel: (_) => _padUp(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        decoration: BoxDecoration(
          color: lit ? onColor : cPad,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: head ? cText : Colors.transparent,
            width: 2,
          ),
          boxShadow: lit
              ? [BoxShadow(color: onColor.withOpacity(0.55), blurRadius: 14)]
              : const [],
        ),
        padding: const EdgeInsets.all(7),
        child: Stack(children: [
          Align(
            alignment: Alignment.topLeft,
            child: Text('${i + 1}',
                style: TextStyle(
                    color: lit ? cLcdInk : cDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
          if (e.userSample[i] && (e.mode == Mode.sound || rec))
            const Align(
              alignment: Alignment.topRight,
              child: Icon(Icons.mic, size: 12, color: cText),
            ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Text(_padLabel(i),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                    color: lit ? cLcdInk : cText,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ),
        ]),
      ),
    );
  }

  void _help() {
    showModalBottomSheet(
      context: context,
      backgroundColor: cBody,
      builder: (_) => const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'SOUND : touche un pad pour jouer et choisir son son.\n'
          'WRITE : les pads deviennent les 16 pas du son choisi. '
          'Appui long sur WRITE = efface la piste.\n'
          'PATTERN : choisis un des 16 patterns.\n'
          'FX : garde le doigt sur un pad pour appliquer l\'effet, relâche pour revenir.\n'
          'REC : garde le doigt sur un pad et parle, tape ou fais du bruit. '
          'Relâche pour enregistrer le son dans ce pad (6 s max).\n'
          'PLAY : lance ou arrête le séquenceur.',
          style: TextStyle(color: cText, height: 1.5),
        ),
      ),
    );
  }
}
