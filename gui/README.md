# check_script_gui

*[Version française](README.fr.md)*

Graphical interface of check-script (Flutter, Linux).

```bash
cd gui
flutter pub get
flutter run -d linux     # run in development
flutter test             # tests
flutter build linux      # production binary
```

The interface relies on the repository's `check_script` package (`path: ..`)
and on the detected external tools (see `check-script --list-tools`). The user
manual is in [`doc/user.adoc`](../doc/user.adoc).
