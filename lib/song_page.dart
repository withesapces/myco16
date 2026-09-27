// Page d'arrangement : enchaîner les patterns pour construire un morceau.
import 'package:flutter/material.dart';

import 'engine.dart';
import 'theme.dart';

class SongPage extends StatelessWidget {
  final Engine engine;
  const SongPage({super.key, required this.engine});

  String _dur(double s) {
    final m = s ~/ 60;
    final sec = (s % 60).round();
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _pickPattern(BuildContext context, int index) async {
    final e = engine;
    final p = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cBody,
        title: Text('Bloc ${index + 1} : quel pattern ?'),
        content: SizedBox(
          width: 280,
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (var i = 0; i < 16; i++)
                InkWell(
                  onTap: () => Navigator.pop(ctx, i),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: e.song[index] == i ? cPadOn : cPad,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${i + 1}${e.patternUsed(i) ? '•' : ''}',
                      style: TextStyle(
                        color: e.song[index] == i ? cLcdInk : cText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (p != null) e.songSet(index, p);
  }

  @override
  Widget build(BuildContext context) {
    final e = engine;
    return ListenableBuilder(
      listenable: e,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          backgroundColor: cBody,
          title: const Text('ARRANGEMENT',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3)),
          actions: [
            IconButton(
              tooltip: 'Tout effacer',
              onPressed: e.song.isEmpty
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Effacer tout l\'arrangement ?'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Annuler')),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Effacer')),
                          ],
                        ),
                      );
                      if (ok == true) e.songClear();
                    },
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: e.playing ? const Color(0xFF7BD389) : cPadOn,
          foregroundColor: cLcdInk,
          onPressed: e.togglePlay,
          child: Icon(e.playing ? Icons.stop : Icons.play_arrow),
        ),
        body: Column(children: [
          SwitchListTile(
            value: e.songMode,
            onChanged: e.setSongMode,
            activeThumbColor: cSong,
            title: const Text('Jouer l\'arrangement'),
            subtitle: Text(
              e.songMode
                  ? '${e.song.length} blocs · ${_dur(e.songSeconds)} à ${e.bpm} BPM, en boucle'
                  : 'Désactivé : le pattern courant tourne en boucle',
              style: const TextStyle(color: cDim),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: e.song.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Ajoute des patterns avec les boutons du bas.\n'
                        'Chaque bloc dure une mesure (16 pas).\n'
                        'Glisse la poignée pour réordonner, touche un bloc pour changer son pattern.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cDim, height: 1.5),
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: e.song.length,
                    onReorder: e.songMove,
                    itemBuilder: (context, i) {
                      final live = e.playing && e.songMode && e.songIndex == i;
                      return Container(
                        key: ValueKey('blk_$i'),
                        color: live ? cSong.withValues(alpha: 0.18) : null,
                        child: ListTile(
                          onTap: () => _pickPattern(context, i),
                          leading: SizedBox(
                            width: 34,
                            child: Text('${i + 1}',
                                style: const TextStyle(color: cDim, fontFamily: 'monospace')),
                          ),
                          title: Text(
                            'PATTERN ${(e.song[i] + 1).toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: live ? cSong : cText,
                            ),
                          ),
                          subtitle: e.patternUsed(e.song[i])
                              ? null
                              : const Text('vide', style: TextStyle(color: cDim)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              tooltip: 'Dupliquer',
                              icon: const Icon(Icons.copy, size: 20),
                              onPressed: () {
                                e.songAdd(e.song[i]);
                                e.songMove(e.song.length - 1, i + 1);
                              },
                            ),
                            IconButton(
                              tooltip: 'Supprimer',
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () => e.songRemoveAt(i),
                            ),
                            ReorderableDragStartListener(
                              index: i,
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.drag_handle),
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            color: cBody,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AJOUTER UN BLOC',
                      style: TextStyle(color: cDim, fontSize: 11, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 8,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 1.2,
                    children: [
                      for (var p = 0; p < 16; p++)
                        InkWell(
                          onTap: () => e.songAdd(p),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: e.patternUsed(p) ? cPcb : cPad,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: e.patternUsed(p)
                                    ? cPadOn.withValues(alpha: 0.6)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text('${p + 1}',
                                style: const TextStyle(
                                    color: cText, fontWeight: FontWeight.w800)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
