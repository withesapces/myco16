# MYCO-16

Sampler de poche pour Android, écrit en Flutter : 16 pads, 16 pas, 16 patterns et 16 effets punch-in. On peut enregistrer au micro directement sur un pad.

L'APK est compilé par GitHub Actions à chaque push sur `main`. Pour le récupérer, ouvre l'onglet **Releases** ou **Actions**, puis l'artefact `myco16-apk`.

- `lib/synth.dart` : les 16 sons d'usine, synthétisés en Dart (fa mineur), et le nettoyage des enregistrements (coupe du silence, normalisation).
- `lib/engine.dart` : SoLoud pour la lecture, `record` pour le micro, le séquenceur et les effets.
- `lib/main.dart` : l'interface.

Le dossier `android/` est généré pendant la compilation par `flutter create`. Le workflow y ajoute la permission micro et fixe minSdk à 24.
