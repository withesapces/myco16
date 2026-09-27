// Feuille de choix du son d'un pad : kits, bibliothèque, micro, accord, volume.
import 'package:flutter/material.dart';

import 'engine.dart';
import 'synth.dart';
import 'theme.dart';

class SoundSheet extends StatefulWidget {
  final Engine engine;
  final int pad;
  const SoundSheet({super.key, required this.engine, required this.pad});
  @override
  State<SoundSheet> createState() => _SoundSheetState();
}

class _SoundSheetState extends State<SoundSheet> {
  late String _cat;

  @override
  void initState() {
    super.initState();
    final id = widget.engine.padSound[widget.pad];
    _cat = id.startsWith('mic:') ? 'MICRO' : (kLibraryById[id]?.cat ?? 'KICK');
  }

  Future<void> _confirmDeleteMic(String file) async {
    final e = widget.engine;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer ${e.nameOf('mic:$file')} ?'),
        content: const Text('Le son est effacé du téléphone. '
            'Les pads qui l\'utilisent reprennent un son du kit PSY.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) await e.deleteMic(file);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    final pad = widget.pad;
    return ListenableBuilder(
      listenable: e,
      builder: (context, _) {
        final current = e.padSound[pad];
        final cats = [...kCategories, 'MICRO'];
        final List<MapEntry<String, String>> items; // id -> nom
        if (_cat == 'MICRO') {
          items = [for (final f in e.micFiles) MapEntry('mic:$f', e.nameOf('mic:$f'))];
        } else {
          items = [
            for (final d in kLibrary)
              if (d.cat == _cat) MapEntry(d.id, d.name)
          ];
        }
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: cDim, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Text('PAD ${pad + 1}',
                    style: const TextStyle(color: cDim, fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(e.padName(pad),
                      style: const TextStyle(
                          color: cText, fontSize: 22, fontWeight: FontWeight.w900)),
                ),
                IconButton(
                  onPressed: () => e.preview(pad),
                  icon: const Icon(Icons.play_arrow, color: cPadOn),
                ),
              ]),
              const SizedBox(height: 8),
              _slider(
                label: 'ACCORD',
                value: e.padTune[pad],
                min: -12,
                max: 12,
                divisions: 24,
                text: '${e.padTune[pad] > 0 ? '+' : ''}${e.padTune[pad].round()} dt',
                onChanged: (v) => e.setTune(pad, v),
                onEnd: () => e.preview(pad),
              ),
              _slider(
                label: 'VOLUME',
                value: e.padVol[pad],
                min: 0,
                max: 1.5,
                divisions: 30,
                text: '${(e.padVol[pad] * 100).round()} %',
                onChanged: (v) => e.setVol(pad, v),
                onEnd: () => e.preview(pad),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final c in cats)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: _cat == c,
                          onSelected: (_) => setState(() => _cat = c),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Aucun son enregistré. Passe en mode REC et garde le doigt sur un pad.',
                    style: TextStyle(color: cDim),
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final it in items)
                    GestureDetector(
                      onLongPress: it.key.startsWith('mic:')
                          ? () => _confirmDeleteMic(it.key.substring(4))
                          : null,
                      child: ChoiceChip(
                        label: Text(it.value),
                        selected: current == it.key,
                        selectedColor: cPadOn,
                        labelStyle: TextStyle(
                          color: current == it.key ? cLcdInk : cText,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: (_) => e.assignPad(pad, it.key),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('CHARGER UN KIT COMPLET (remplace les 16 pads)',
                  style: TextStyle(color: cDim, fontSize: 11, letterSpacing: 1)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var k = 0; k < kKits.length; k++)
                  OutlinedButton(
                    onPressed: () async {
                      await e.applyKit(k);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Kit ${kKits[k].name} chargé')),
                        );
                      }
                    },
                    child: Text(kKits[k].name),
                  ),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String text,
    required ValueChanged<double> onChanged,
    required VoidCallback onEnd,
  }) {
    return Row(children: [
      SizedBox(
        width: 70,
        child: Text(label,
            style: const TextStyle(color: cDim, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
      Expanded(
        child: Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeEnd: (_) => onEnd(),
        ),
      ),
      SizedBox(
        width: 56,
        child: Text(text,
            textAlign: TextAlign.right,
            style: const TextStyle(color: cText, fontFamily: 'monospace')),
      ),
    ]);
  }
}
