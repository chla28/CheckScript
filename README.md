# CheckScript — `check-script`

Évalue des scripts shell ou Python 3 et produit un classement sur cinq catégories notées
sur 10 — **Sécurité, Robustesse, Maintenabilité, Portabilité, Performance** —
avec, pour chacune, le nombre de problèmes par sévérité (Critical / High /
Medium / Low) et leur total. Sortie dans le terminal et/ou en Markdown,
AsciiDoc ou JSON, en français ou en anglais.

`check-script` exploite **ShellCheck, shfmt, bashate, checkbashisms**,
gitleaks, trufflehog et `bash -n` pour le shell, **Ruff, Bandit, Semgrep,
mypy, Radon, Vermin** (et sur demande Pylint, Pyright) pour Python,
lorsqu'ils sont installés, et les complète par des règles intégrées (81 pour
le shell, 10 pour Python : secrets, `curl | sh`, permissions, PATH,
`subprocess` sans timeout, dépendances non déclarées, structure…) avec un
conseil de correction pour chacune, et par les règles personnalisées du
projet (`rules.custom`). Il analyse aussi le shell intégré aux workflows
GitHub Actions et GitLab CI, aux Dockerfile, aux Makefile et aux tâches
Ansible (dont l'injection d'expressions GitHub non fiables). Il corrige les défauts sûrs
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
check-script Dockerfile .github/workflows/     # scripts intégrés
check-script --watch scripts/                  # réanalyse à chaque enregistrement
check-script -o rapport.xml scripts/           # JUnit XML (Jenkins, GitLab)
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

## Référentiels

Chaque problème porte ses références **CWE**, **OWASP** (Top 10 2021, Top 10
CI/CD) et **ANSSI** (configuration GNU/Linux, conteneurs Docker, OpenSSH) ;
le rapport HTML en fait une vue de conformité et `--ref CWE-78` (ou `A08`,
`ANSSI`…) filtre l'affichage. Les Dockerfile et les workflows ont leurs
propres règles (image non épinglée, conteneur en root, action non épinglée,
`pull_request_target`, secrets en clair…), complétées par hadolint,
actionlint et zizmor s'ils sont installés.

## Éditeurs

`check-script lsp` est un serveur LSP : problèmes soulignés, corrections
rapides, survol avec exemple, formatage, note du script. Extension
**VS Code** (`.vsix`) et plugin **Eclipse** (site de mise à jour `.zip`)
attachés à chaque release ; configuration **Geany** dans
`editors/geany/lsp.conf`.

## Action GitHub

```yaml
- uses: actions/checkout@v7
- uses: chla28/CheckScript@v0.17.0
  with:
    paths: scripts .github
    fail-under: '6'
```

Annotations sur les lignes des pull requests, rapport dans le résumé du job,
SARIF pour Code Scanning ; sorties `score` et `grade` (voir le guide
utilisateur, « Intégration continue »).

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

## Contribuer

Messages de commit au format *Conventional Commits* (`feat(gui): …`,
`fix: …`), contrôlés par un hook (`scripts/install-git-hooks.sh`) et par la
CI ; `dart run tool/release.dart` publie une version (numéro et CHANGELOG
déduits des commits). Voir le guide développeur.

## Licence

CheckScript est un logiciel libre, distribué sous licence **GNU LGPL version 3
ou ultérieure** (LGPL-3.0-or-later) : voir [LICENSE](LICENSE). L'interface
embarque la police JetBrains Mono (SIL Open Font License 1.1 :
[gui/fonts/JetBrainsMono/OFL.txt](gui/fonts/JetBrainsMono/OFL.txt)).
