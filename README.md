# CheckScript — `check-script`

Évalue des scripts shell ou Python 3 et produit un classement sur cinq catégories notées
sur 10 — **Sécurité, Robustesse, Maintenabilité, Portabilité, Performance** —
avec, pour chacune, le nombre de problèmes par sévérité (Critical / High /
Medium / Low) et leur total. Sortie dans le terminal et/ou en Markdown,
AsciiDoc ou JSON, en français ou en anglais.

`check-script` exploite **ShellCheck, shfmt, bashate, checkbashisms**,
gitleaks, trufflehog et `bash -n` pour le shell, **Ruff, Bandit, Semgrep,
mypy, Radon, Vermin** (et sur demande Pylint, Pyright) pour Python,
lorsqu'ils sont installés, et les complète par des règles intégrées (64 pour
le shell, 6 pour Python : secrets, `curl | sh`, permissions, PATH,
`subprocess` sans timeout, structure…) avec un conseil de correction pour
chacune. Il corrige les défauts sûrs
(`--fix`), compare une analyse à une référence, produit du SARIF et du GitLab
Code Quality, et propose une interface graphique (`check-script-gui`).

```bash
check-script deploy.sh                         # rapport terminal
check-script deploy.sh -o rapport.md -o rapport.adoc
check-script --lang en scripts/                # un dossier, en anglais
check-script --fail-under 7 -q scripts/        # intégration continue
check-script --profile strict --context root install.sh
check-script --fix --dry-run deploy.sh         # corrections proposées (diff)
check-script -b reference.json --fail-on-new high scripts/
check-script outil.py                          # script Python (cible : 3.9)
check-script --python-target 3.11 --with pylint scripts/
check-script --list-tools                      # outils détectés
check-script-gui                               # interface graphique
./CheckScript-VERSION-x86_64.AppImage          # interface (AppImage, sans installation)
flatpak run fr.chla28.check_script_gui         # interface (Flatpak)
```

```
Catégorie        Note /10             Critical     High   Medium      Low   Total
Sécurité           0,0 ░░░░░░░░░░            3        3        3        1      10
Robustesse         1,3 █░░░░░░░░░            0        1        8        4      13
Maintenabilité     8,8 █████████░            0        0        0        5       5
Portabilité       10,0 ██████████            0        0        0        0       0
Performance        9,0 █████████░            0        0        0        4       4

Note globale : 1,5/10 (E)
```

## Documentation

- [Guide utilisateur](doc/user.adoc) — installation, options, lecture du
  rapport, calcul des notes, règles, configuration.
- [Guide développeur](doc/developer.adoc) — architecture, analyseurs,
  ajout de règles, tests, packaging, préparation de la version Flutter.
- [Exemple de configuration](doc/checkscript.example.yaml), [page de manuel](doc/check-script.1.adoc).
- Intégration continue : [GitLab CI](doc/ci/gitlab-ci.yml), [GitHub Actions](doc/ci/github-actions.yml),
  [hooks pre-commit](.pre-commit-hooks.yaml).

## Développement

```bash
dart pub get
dart run bin/check_script.dart test/fixtures/bad.sh
dart analyze --fatal-infos
dart test
(cd gui && flutter test)           # interface Flutter
dart run tool/calibrate.dart       # calibrage sur le corpus
./scripts/build-dist.sh            # → dist/check_script-VERSION-linux-ARCH.tar.gz
./scripts/build-dist.sh --rpm      # + RPM (dist/rpm/)
./scripts/build-dist.sh --install  # + installation dans ~/.local
```

Plateforme cible : Linux. L'interface Flutter (`gui/`) réutilise la
bibliothèque `lib/` ; elle est aussi lancée depuis MainGUI.

## Licence

CheckScript est un logiciel libre, distribué sous licence **GNU LGPL version 3
ou ultérieure** (LGPL-3.0-or-later) : voir [LICENSE](LICENSE).
