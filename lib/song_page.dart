// Arrangement : la chaîne de patterns (jusqu'à 128 blocs).
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
                      color: e.chain[index] == i ? cPadOn : cPad,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${i + 1}${e.patterns[i].used ? '•' : ''}',
                        style: TextStyle(
                            color: e.chain[index] == i ? cLcdInk : cText,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (p != null) e.chainSet(index, p);
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
              tooltip: 'Revenir à un seul pattern',
              onPressed: e.chain.length <= 1 ? null : e.chainReset,
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
          ListTile(
            title: Text('${e.chain.length} bloc${e.chain.length > 1 ? 's' : ''} · ${_dur(e.chainSeconds)} à ${e.bpm} BPM'),
            subtitle: const Text(
              'Raccourci sur l\'appareil : PATTERN + plusieurs touches à la suite.',
              style: TextStyle(color: cDim),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: e.chain.length,
              onReorder: e.chainMove,
              itemBuilder: (context, i) {
                final live = e.playing && e.chainIndex == i && e.chain.length > 1;
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
                    title: Text('PATTERN ${(e.chain[i] + 1).toString().padLeft(2, '0')}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: live ? cSong : cText)),
                    subtitle: e.patterns[e.chain[i]].used
                        ? null
                        : const Text('vide', style: TextStyle(color: cDim)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Dupliquer',
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: e.chain.length >= 128
                            ? null
                            : () {
                                e.chainAdd(e.chain[i]);
                                e.chainMove(e.chain.length - 1, i + 1);
                              },
                      ),
                      IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: e.chain.length <= 1 ? null : () => e.chainRemoveAt(i),
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                        onTap: () => e.chainAdd(p),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: e.patterns[p].used ? cPcb : cPad,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: e.patterns[p].used
                                    ? cPadOn.withValues(alpha: 0.6)
                                    : Colors.transparent),
                          ),
                          child: Text('${p + 1}',
                              style: const TextStyle(color: cText, fontWeight: FontWeight.w800)),
                        ),
                      ),
                  ],
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
