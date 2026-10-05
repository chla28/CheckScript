# check_script_gui

*[English version](README.md)*

Interface graphique de check-script (Flutter, Linux).

```bash
cd gui
flutter pub get
flutter run -d linux     # lancement en développement
flutter test             # tests
flutter build linux      # binaire de production
```

L'interface s'appuie sur le paquet `check_script` du dépôt (`path: ..`) et sur
les outils externes détectés (voir `check-script --list-tools`). Le mode
d'emploi est dans [`doc/user.fr.adoc`](../doc/user.fr.adoc).
