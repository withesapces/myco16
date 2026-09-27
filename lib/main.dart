// MYCO-16 : sampler de poche, 16 pads, 16 pas, 16 FX, arrangement.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine.dart';
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
  final List<Timer?> _longPress = List<Timer?>.filled(16, null);
  final List<bool> _longFired = List<bool>.filled(16, false);

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
    _longFired[i] = false;
    _longPress[i]?.cancel();
    if (e.mode == Mode.sound || e.mode == Mode.pattern) {
      _longPress[i] = Timer(const Duration(milliseconds: 450), () {
        _longFired[i] = true;
        HapticFeedback.mediumImpact();
        if (e.mode == Mode.sound) _openSoundSheet(i);
        if (e.mode == Mode.pattern) _patternMenu(i);
      });
    }
    switch (e.mode) {
      case Mode.sound:
        e.padPlay(i);
        break;
      case Mode.write:
        e.toggleStep(i);
        break;
      case Mode.pattern:
        break; // sélection au relâchement (pour laisser place à l'appui long)
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
    _longPress[i]?.cancel();
    if (e.mode == Mode.pattern && !_longFired[i]) e.selectPattern(i);
    if (e.mode == Mode.fx) e.fxUp(i);
    if (e.mode == Mode.rec && e.recordingSlot == i) {
      e.recStop().then((msg) {
        if (msg != null) _toast(msg);
      });
    }
  }

  void _openSoundSheet(int pad) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cBody,
      builder: (_) => SoundSheet(engine: e, pad: pad),
    );
  }

  void _patternMenu(int p) {
    final cur = e.pattern;
    showModalBottomSheet(
      context: context,
      backgroundColor: cBody,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text('PATTERN ${p + 1}',
                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2)),
          ),
          if (p != cur)
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text('Copier le pattern ${cur + 1} ici'),
              onTap: () {
                e.copyPattern(cur, p);
                Navigator.pop(ctx);
                _toast('Pattern ${cur + 1} copié dans ${p + 1}');
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text('Effacer le pattern ${p + 1}'),
            onTap: () {
              e.clearPattern(p);
              Navigator.pop(ctx);
              _toast('Pattern ${p + 1} effacé');
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: Text('Ajouter le pattern ${p + 1} à l\'arrangement'),
            onTap: () {
              e.songAdd(p);
              Navigator.pop(ctx);
              _toast('Ajouté (bloc ${e.song.length})');
            },
          ),
        ]),
      ),
    );
  }

  void _openBpm() {
    showModalBottomSheet(
      context: context,
      backgroundColor: cBody,
      builder: (_) => BpmSheet(engine: e),
    );
  }

  void _openSong() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SongPage(engine: e)));
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
        final inSong = e.song.contains(i);
        return '${e.patternUsed(i) ? 'PAT •' : 'PAT'}${inSong ? ' ♪' : ''}';
      case Mode.write:
        return '';
      case Mode.sound:
      case Mode.rec:
        return e.padName(i);
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
    final String modeName;
    if (e.processing) {
      modeName = 'NETTOYAGE…';
    } else {
      modeName = {
        Mode.sound: 'SOUND',
        Mode.write: 'WRITE',
        Mode.pattern: 'PATTERN',
        Mode.fx: 'FX',
        Mode.rec: e.recordingSlot != null ? '● REC' : 'REC ARM',
      }[e.mode]!;
    }
    const ink = TextStyle(color: cLcdInk, fontFamily: 'monospace', fontSize: 13);
    final songTxt = e.songMode && e.song.isNotEmpty
        ? 'SONG ${(e.songIndex + 1).toString().padLeft(2, '0')}/${e.song.length.toString().padLeft(2, '0')}'
        : 'LOOP';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: cLcd, borderRadius: BorderRadius.circular(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(modeName, style: ink.copyWith(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(songTxt, style: ink),
            const SizedBox(width: 8),
            Text(e.playing ? '▶' : '■', style: ink.copyWith(fontSize: 18)),
          ]),
          const SizedBox(height: 4),
          Text(
            'BPM ${e.bpm}  PAT ${(e.pattern + 1).toString().padLeft(2, '0')}  '
            'SND ${(e.selected + 1).toString().padLeft(2, '0')} ${e.padName(e.selected)}',
            style: ink,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
                        : (on
                            ? cLcdInk.withValues(alpha: 0.45)
                            : cLcdInk.withValues(alpha: 0.1)),
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
        b('SONG', _openSong, active: e.songMode, activeColor: const Color(0xFF9AD1FF)),
        b('${e.bpm}', _openBpm),
      ]),
      Row(children: [
        b('WRITE', () => e.setMode(Mode.write), active: e.mode == Mode.write, onLong: () {
          e.clearTrack();
          _toast('Piste ${e.padName(e.selected)} effacée');
        }),
        b('FX', () => e.setMode(Mode.fx), active: e.mode == Mode.fx),
        b('REC', () => e.setMode(Mode.rec), active: e.mode == Mode.rec, activeColor: cRec),
        b(e.playing ? 'STOP' : 'PLAY', e.togglePlay,
            active: e.playing, activeColor: const Color(0xFF7BD389)),
      ]),
    ]);
  }

  Widget _grid() {
    return LayoutBuilder(builder: (context, c) {
      final size = c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;
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
          border: Border.all(color: head ? cText : Colors.transparent, width: 2),
          boxShadow: lit
              ? [BoxShadow(color: onColor.withValues(alpha: 0.55), blurRadius: 14)]
              : const [],
        ),
        padding: const EdgeInsets.all(7),
        child: Stack(children: [
          Align(
            alignment: Alignment.topLeft,
            child: Text('${i + 1}',
                style: TextStyle(
                    color: lit ? cLcdInk : cDim, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          if (e.padIsMic(i) && (e.mode == Mode.sound || rec))
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
      isScrollControlled: true,
      builder: (_) => const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Text(
            'SOUND : touche un pad pour le jouer. Appui long = choisir son son '
            '(50 sons, 4 kits), l\'accorder et régler son volume.\n\n'
            'WRITE : les pads deviennent les 16 pas du son choisi. '
            'Appui long sur WRITE = efface la piste.\n\n'
            'PATTERN : touche un pad pour choisir le pattern. Appui long = copier le '
            'pattern courant ici, l\'effacer, ou l\'ajouter à l\'arrangement.\n\n'
            'SONG : construis ton morceau en enchaînant les patterns, réordonne-les '
            'et active la lecture de l\'arrangement.\n\n'
            'FX : garde le doigt sur un pad pour appliquer l\'effet.\n\n'
            'REC : garde le doigt sur un pad et fais du bruit, relâche. Le souffle '
            'du micro est nettoyé automatiquement (6 s max). Laisse une demi-seconde '
            'de silence avant le son pour un nettoyage optimal.\n\n'
            'Tout est sauvegardé automatiquement.',
            style: TextStyle(color: cText, height: 1.5),
          ),
        ),
      ),
    );
  }
}

class BpmSheet extends StatefulWidget {
  final Engine engine;
  const BpmSheet({super.key, required this.engine});
  @override
  State<BpmSheet> createState() => _BpmSheetState();
}

class _BpmSheetState extends State<BpmSheet> {
  final List<int> _taps = [];

  void _tap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_taps.isNotEmpty && now - _taps.last > 2000) _taps.clear();
    _taps.add(now);
    if (_taps.length > 5) _taps.removeAt(0);
    if (_taps.length >= 2) {
      final avg = (_taps.last - _taps.first) / (_taps.length - 1);
      widget.engine.setBpm((60000 / avg).round());
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    return ListenableBuilder(
      listenable: e,
      builder: (context, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${e.bpm} BPM',
                style: const TextStyle(
                    color: cText, fontSize: 28, fontWeight: FontWeight.w900)),
            Slider(
              value: e.bpm.toDouble(),
              min: 60,
              max: 200,
              divisions: 140,
              onChanged: (v) => e.setBpm(v.round()),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final d in [-5, -1, 1, 5])
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: OutlinedButton(
                    onPressed: () => e.setBpm(e.bpm + d),
                    child: Text(d > 0 ? '+$d' : '$d'),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final preset in [128, 138, 145, 150, 160])
                ActionChip(label: Text('$preset'), onPressed: () => e.setBpm(preset)),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(onPressed: _tap, child: const Text('TAP TEMPO')),
            ),
          ]),
        ),
      ),
    );
  }
}
