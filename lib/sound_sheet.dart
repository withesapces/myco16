// Bibliothèque : charger un son d'usine ou un kit dans le slot courant.
import 'package:flutter/material.dart';

import 'engine.dart';
import 'synth.dart';
import 'theme.dart';

class SoundSheet extends StatefulWidget {
  final Engine engine;
  const SoundSheet({super.key, required this.engine});
  @override
  State<SoundSheet> createState() => _SoundSheetState();
}

class _SoundSheetState extends State<SoundSheet> {
  String _cat = 'KICK';

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    return ListenableBuilder(
      listenable: e,
      builder: (context, _) {
        final drum = e.cur.drum;
        final items = [for (final d in kLibrary) if (d.cat == _cat) d];
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
            children: [
              Text('SLOT ${e.sound + 1} · ${drum ? 'BATTERIE' : 'MÉLODIQUE'}',
                  style: const TextStyle(color: cDim, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(e.cur.name,
                  style: const TextStyle(color: cText, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              if (drum) ...[
                const Text('KITS (un son par touche)',
                    style: TextStyle(color: cDim, fontSize: 11, letterSpacing: 1)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var k = 0; k < kDrumKits.length; k++)
                    ChoiceChip(
                      label: Text(kDrumKits[k].name),
                      selected: e.cur.factory == 'kit:$k',
                      selectedColor: cPadOn,
                      onSelected: (_) => e.loadKit(k),
                    ),
                ]),
                const SizedBox(height: 20),
                const Text('OU UN SON SEUL',
                    style: TextStyle(color: cDim, fontSize: 11, letterSpacing: 1)),
                const SizedBox(height: 8),
              ],
              SizedBox(
                height: 38,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final c in kCategories)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(c),
                        selected: _cat == c,
                        onSelected: (_) => setState(() => _cat = c),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final d in items)
                  ChoiceChip(
                    label: Text(d.name),
                    selected: e.cur.factory == 'mel:${d.id}',
                    selectedColor: cPadOn,
                    onSelected: (_) => e.loadLibrarySound(d.id),
                  ),
              ]),
              const SizedBox(height: 16),
              Text(
                drum
                    ? 'En slot batterie, un son seul est joué tel quel sur toutes les touches.'
                    : 'En slot mélodique, le son est joué en gamme sur les 16 touches.',
                style: const TextStyle(color: cDim, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}
