# Changelog

## 0.14.0 — 2026-09-25

- **`--watch`** : réanalyse chaque script à son enregistrement (ou toutes
  les cibles quand des rapports `-o` sont écrits) ; la vue Dossier de
  l'interface réanalyse aussi les scripts enregistrés ou créés.
- **Action GitHub** (`action.yml`) : compile check-script, installe
  ShellCheck et shfmt, annote les lignes des pull requests, ajoute le
  rapport au résumé du job et produit un SARIF ; sorties `score`, `grade`,
  `scripts`. Le dépôt s'analyse lui-même avec (`self-check.yml`).
- Formats **JUnit XML** (`-o rapport.xml`, `--format junit` : Jenkins,
  onglet Tests de GitLab) et **annotations GitHub** (`--format github`).
- `--format` s'applique à la sortie standard même avec `-o`, et
  l'extension d'un fichier `-o` prime sur `--format` (comme l'annonçait
  l'aide).
- Interface : **correction de la sélection** (cases à cocher sur les
  problèmes corrigeables, diff global avant application) ; menu **Récents**
  (10 derniers scripts et dossiers).

### Fonctionnalités

- **cli** : --watch, formats JUnit XML et annotations GitHub (a63e3f8)
- **ci** : action GitHub réutilisable (85100ff)
- **gui** : correction de la sélection, récents, surveillance du dossier (30cc1ea)

### Documentation

- watch, action GitHub, JUnit, correction de la sélection (aecb705)

## 0.13.0 — 2026-09-25

- **Scripts intégrés** : le shell des workflows GitHub Actions (`run:`), de
  GitLab CI (`script:`…), des Dockerfile (`RUN`), des Makefile (recettes)
  et des tâches Ansible (`shell:`) est analysé avec les mêmes outils ; les
  problèmes désignent les lignes du fichier d'origine. Nouvelle règle
  SEC023 (Critical) : expression GitHub non fiable insérée dans `run:`
  (injection) ; SEC007 sur `rm -rf $(VAR)/…` des Makefile. Découverte dans
  les dossiers (`.github`, `.gitlab`, `.gitlab-ci.yml` compris),
  `--no-embedded` pour s'en passer.
- **Règles personnalisées** (`rules.custom` de `.checkscript.yaml`) : motif,
  message bilingue, gravité, catégorie, conseil, langage, règle d'absence
  (`absent: true`) et remplacement appliqué par `--fix` et l'interface ;
  listées par `--list-rules` et l'onglet Règles.
- **Dépendances Python** : analyseur `pydeps` (imports classés par
  l'interpréteur sans exécution) ; PYROB005 (module introuvable et non
  déclaré), PYPOR002 (paquet non déclaré) d'après requirements,
  pyproject.toml, setup.cfg, Pipfile ou l'en-tête PEP 723 ; `pip-audit`
  (facultatif) signale les vulnérabilités des paquets importés.

### Fonctionnalités

- scripts intégrés, règles personnalisées et dépendances Python (ab401d8)

## 0.12.0 — 2026-09-25

- Adoption des **Conventional Commits** : hook `commit-msg` et
  vérification CI des messages ; `tool/release.dart` déduit la version et
  génère le CHANGELOG à partir des commits.

### Fonctionnalités

- **tool** : outillage Conventional Commits (lint, hook, publication) (d0c849e)

### Intégration continue

- vérifie les messages de commit (fddb2a0)

## 0.11.2 — 2026-09-25

- Correctif CI : le test « bad.py sous 6 » n'est joué que si Bandit et Ruff
  sont installés (sans eux, seules les règles intégrées s'appliquent) ;
  vérifié dans un environnement sans outils d'analyse, comme le runner
  GitHub.

## 0.11.1 — 2026-09-25

- Correctif CI : les tests qui vérifient des messages français fixent la
  langue (`--lang fr`) au lieu de dépendre de `LANG` (anglais sur les
  serveurs GitHub) ; la CI joue les tests dans les deux locales.

## 0.11.0 — 2026-09-25

- **Tableau de bord d'équipe** (`--dashboard FICHIER.html`) : un dépôt par
  dossier cible, note moyenne, évolution (courbe), problèmes graves,
  niveaux, règles les plus fréquentes, scripts les plus faibles ;
  historique enregistré (`--history-dir` pour le partager).
- **Faux positifs** : bouton *Signaler un faux positif* dans l'interface
  (cas anonymisé, commentaire, journal local) ; synthèse par règle avec
  `tool/false_positives.dart`.
- **Ruff avec la configuration du projet** : `tools.ruff.config: project`
  (ruff.toml, pyproject.toml) ou chemin d'un fichier ; réglage de
  l'interface.
- L'historique des dossiers passe dans la bibliothèque (CLI et interface).

## 0.10.0 — 2026-09-25

- **Licence** : GNU LGPL version 3 ou ultérieure (`LICENSE`), reprise par les
  paquets RPM, le Flatpak, l'AppImage, l'archive et les métadonnées AppStream.
- **Publication automatique** (GitHub Actions) : à chaque tag, tests puis
  archive, RPM, AppImage et Flatpak attachés à une release GitHub.
- **Flatpak testé de bout en bout**, avec deux correctifs : les outils
  installés dans `~/.local/bin` ou `~/bin` (Ruff, Bandit, trufflehog…) sont
  trouvés sur l'hôte (PATH de l'utilisateur), et lancés par leur chemin
  absolu (le portail ignorait le PATH transmis : outils notés « exécutés »
  sans résultat).
- `--skip-build` des scripts AppImage / Flatpak recompile toujours la CLI
  (seul le bundle Flutter est réutilisé).

## 0.9.0 — 2026-09-25

- **AppImage** (`scripts/build-appimage.sh`) : interface et ligne de
  commande (`--cli`, ou lien nommé `check-script`) dans un seul fichier,
  sans installation.
- **Flatpak** (`scripts/build-flatpak.sh`, manifeste
  `packaging/flatpak/`) : runtime GNOME 50 ; les outils d'analyse et
  l'éditeur sont ceux de l'hôte (`flatpak-spawn --host`), fichiers
  temporaires dans le cache de l'application.
- Fichier `.desktop` et métadonnées AppStream communs
  (`packaging/linux/`) ; le `.desktop` mentionne Python.

## 0.8.0 — 2026-09-25

- **`--changed-since REF`** : n'analyse que les scripts modifiés depuis une
  référence git (commits, modifications en cours, nouveaux fichiers) ; code
  0 si rien n'a changé.
- **Cache des résultats** (`--no-cache` pour le désactiver ; aussi dans
  l'interface) : un script inchangé — contenu, configuration, versions des
  outils — n'est pas réanalysé. Mesuré sur le corpus : 12 s → 1,5 s.
- **Configuration de projet** : le `.checkscript.yaml` le plus proche de
  chaque script (jusqu'à la racine du dépôt git) s'applique, CLI et
  interface.
- **SARIF** : corrections concrètes en `fixes` (suggestions GitHub Code
  Scanning, IDE).
- **Expliquer la note** : points retirés et gain de chaque règle, plan pour
  gagner un niveau (« Niveau B (7,6) en corrigeant : … ») ; `--explain`,
  Markdown, HTML, JSON, interface.
- **Tri par gain rapide** (`--sort impact`, interface) : le plus rentable
  d'abord, corrections automatiques favorisées.
- **Historique** des analyses d'un dossier dans l'interface (courbe de la
  note moyenne).
- **Directives obsolètes** : MNT011 signale une directive `# check-script`
  qui ne neutralise plus rien.
- Interface : **surveillance** du script ouvert (analyse relancée à
  l'enregistrement) et **ouverture dans l'éditeur** à la ligne d'un
  problème (éditeur détecté ou commande configurable).
- Correctif : barre d'outils de l'écran d'analyse défilante sur une fenêtre
  basse.

## 0.7.0 — 2026-09-25

- **Configuration** : l'interface exporte la configuration effective
  (fichier YAML et choix de l'interface) dans un `.checkscript.yaml`
  utilisable par la CLI et la CI, et l'importe (le fichier devient la
  référence). `CheckConfig.toYaml()` n'écrit que ce qui diffère du profil.
- **Analyses parallèles** : les outils d'un même script tournent en
  parallèle, et les scripts d'un dossier plusieurs à la fois (`-j, --jobs`) ;
  résultats identiques, ordre conservé. Mesuré : un script Python 5,3 → 2,2 s,
  le corpus shell (12 scripts) 19,2 → 5,1 s.
- **Calibrage Python** sur un corpus de 12 scripts : secrets en dur Critical
  quand la valeur est réaliste, exécution de code ou de données High,
  PYSEC001 Medium, PYPOR001 High ; nouvelles règles PYROB003 (cron sans
  verrou) et PYROB004 (code de retour de `main()` perdu) ; docstrings comptées
  comme documentation.
- **Semgrep hors ligne** : règles `p/python` gardées en cache une semaine
  (`~/.cache/check-script`), utilisées sans réseau ; `tools.semgrep.config`
  pour un fichier ou dossier de règles local.
- **Doublons multi-lignes** : un appel réparti sur plusieurs lignes est
  signalé une seule fois (Bandit B607 ligne 46 = Ruff S607 ligne 47).
- **Directives Python** `# noqa`, `# noqa: CODE`, `# nosec`, `# nosec CODE`
  pour tous les outils, un code visant aussi la même règle dans les autres
  outils.
- **Règles désactivées** : transmises à ShellCheck, bashate et Bandit ;
  la même règle d'un autre outil est aussi masquée (Ruff S602 ↔ Bandit B602,
  ShellCheck SC2164 ↔ ROB005…) ; `--fix` ne corrige plus une règle
  désactivée (dont le formatage si FORMAT l'est).
- **Rapport HTML de dossier** : synthèse (note moyenne, niveaux, problèmes
  par sévérité), tableau des scripts triable, règles les plus fréquentes ;
  les longues lignes de code ne débordent plus de la page.
- Interface : **Corriger les N occurrences** d'une règle depuis un problème.
- CLI : **`--list-rules --all`** (règles intégrées et codes des outils).
- RPM : `Recommends` ruff, python3-mypy ; `Suggests` pylint.
- Correctif : un script Python lu sur l'entrée standard est copié dans un
  fichier `.py` (et non `.sh`) pour les outils.

## 0.6.0 — 2026-09-25

- Interface : onglet **Règles** listant toutes les règles de détection
  (intégrées, codes classés des outils, codes rencontrés lors des analyses),
  chacune avec une case à cocher ; une règle décochée n'est plus signalée à
  partir de l'analyse suivante. Recherche, filtres (langage, outil,
  catégorie), saisie libre d'un code, *Tout réactiver*, *Relancer
  l'analyse* ; règles désactivées par le profil ou le YAML verrouillées.
  Bouton *Ne plus signaler* sur un problème déplié.
- Interface : barre de navigation défilante sur une fenêtre basse ; badge de
  sévérité réduit plutôt que de déborder (« fichier entier »).

## 0.5.1 — 2026-09-24

- Interface : barre déplaçable entre le code et les résultats (fenêtre
  large ou étroite), double-clic pour revenir à la répartition par défaut,
  flèches pour replier le code ou les résultats sans perdre leur état ;
  répartition mémorisée d'une session à l'autre.

## 0.5.0 — 2026-09-24

- **Scripts Python 3** : détectés par le shebang (`python`, `python3`,
  `python3.N`) ou l'extension `.py` / `.pyw` (`--shell python` pour
  forcer), analysés avec **Ruff** (lint et formatage), **Bandit**,
  **Semgrep** (règles `p/python`, accès réseau), **mypy**, **Radon**
  (complexité, indice de maintenabilité) et **Vermin** (version minimale) ;
  **Pylint** et **Pyright**, redondants, désactivés par défaut (`--with`).
  Contrôle syntaxique par `compile()` (sans `__pycache__`). Seuls les outils
  du langage du script sont lancés et listés.
- Classement de chaque outil sur les cinq axes et dédoublonnage entre outils
  (Ruff `S602` = Bandit `B602` = Semgrep, Ruff `PL…` = Pylint, mypy =
  Pyright…) ; secrets jamais recopiés (messages Bandit et Semgrep
  caviardés).
- 6 règles intégrées Python (PYSEC001 secret à forte entropie, PYROB001
  subprocess sans timeout, PYROB002 input() sans terminal, PYMNT001 en-tête,
  PYMNT002 garde `__main__`, PYPOR001 shebang `python` ambigu), fondées sur
  le module `ast` ; exemples de correction Python pour ces règles et les
  codes Ruff / Bandit / Pylint courants.
- `--fix` Python : corrections sûres de Ruff puis `ruff format`.
- Version cible `pythonTarget` (défaut 3.9, RHEL / Rocky 9) :
  `--python-target`, YAML (entre guillemets), réglage de l'interface.
- Interface : outils groupés par langage, Pylint / Pyright activables,
  version de Python cible.
- Découverte : `.py`, `.pyw`, shebang Python ; dossiers `venv`,
  `site-packages`, `__pycache__`, `node_modules` ignorés.

## 0.4.0 — 2026-09-24

- **Code de correction par problème** : un clic sur un problème (interface
  graphique) déplie le code à écrire, également affiché dans le rapport
  HTML — lignes avant / après quand une correction sûre existe (ShellCheck
  ou correction intégrée), sinon exemple « à éviter / à écrire » de la
  règle (toutes les règles intégrées, codes ShellCheck courants). Boutons
  *Copier* et *Appliquer cette correction* (une seule correction, contrôle
  de syntaxe).
- Interface : la copie `.orig` est écrite à la première correction d'un
  script depuis le lancement, puis conservée : elle garde le script d'avant
  la première correction.
- JSON : champ `edits` (correction concrète) sur chaque problème corrigeable.

## 0.3.0 — 2026-09-24

- **Ligne de code sous chaque problème** (terminal) avec un repère `^` sous
  la colonne signalée ; `--no-source` pour la masquer. L'extrait figure aussi
  dans les rapports Markdown, AsciiDoc, HTML, JSON et SARIF
  (`region.snippet`).
- Une ligne où un secret est détecté n'est jamais recopiée, quel que soit le
  problème qui la désigne (y compris dans la source du rapport HTML).
- bashate : colonne ignorée (toujours 1).

## 0.2.1 — 2026-09-24

- **Correctif** : plantage « type 'String' is not a subtype of type 'num?' »
  sur Rocky 9 ; les positions, codes et scores lus dans le JSON des outils
  externes (gitleaks, trufflehog, ShellCheck, shfmt) et de la référence sont
  acceptés en nombre comme en chaîne.

## 0.2.0 — 2026-09-24

- **Interface graphique** Flutter `check-script-gui` : source annoté, radar
  des notes, problèmes filtrables avec conseils et liens, correction avec
  aperçu du diff, analyse de dossier et tendance, export, réglages ;
  intégrée au lanceur MainGUI.
- **Directives** dans le script : `# check-script disable=…`,
  `disable-next-line=…`, `disable-file=…` (jokers, `all`).
- **Conseils de correction** bilingues pour chaque règle intégrée ; liens
  vers le wiki ShellCheck et la documentation des outils.
- **Profils** `strict` / `default` / `legacy` ; **contextes** `root`, `cron`,
  `systemd` (règles dédiées, sévérités relevées) ; `--fail-under` par
  catégorie.
- **Nouvelles règles** : SEC015–SEC022 (PATH non sûr, fichiers sensibles,
  archive non vérifiée, options SSH, secret exporté, secrets par entropie),
  ROB011–ROB016 (codes de retour ignorés, IFS global, trap sans EXIT, verrou,
  saisie interactive et PATH en cron).
- **gitleaks** et **trufflehog** (facultatifs) ; `--follow-source`.
- Règles structurelles et de commande fondées sur l'**arbre syntaxique de
  shfmt** (repli sur le lexer).
- **`--fix`**, `--dry-run`, `--backup` : corrections ShellCheck, intégrées et
  shfmt, abandon si la syntaxe devient invalide.
- **Rapports** SARIF 2.1.0, HTML autonome, GitLab Code Quality ;
  **référence** (`--baseline`, `--fail-on-new`) avec empreintes stables.
- Moteur : progression par outil et annulation.
- Complétions bash/zsh, page de manuel, hooks pre-commit, exemples GitLab CI
  et GitHub Actions, paquets RPM (CLI et interface).
- **Calibrage** sur un corpus de scripts réels : bashismes cassant dash
  classés High ; note globale plafonnée à la pire catégorie + 1,5 ; faux
  positif ROB012 corrigé.

## 0.1.0 — 2026-09-23

Première version.

- CLI `check-script` : analyse de fichiers, de dossiers (récursif) ou de
  l'entrée standard ; classement sur 5 catégories notées sur 10 avec
  compteurs Critical/High/Medium/Low et total ; note globale et niveau A–E.
- Intégration de ShellCheck (JSON, table de classement des codes), shfmt
  (formatage dans le style du script, détection des constructions hors
  dialecte), bashate, checkbashisms et `bash -n` ; outils facultatifs,
  détectés à l'exécution (`--list-tools`).
- 50 règles intégrées (sécurité, robustesse, maintenabilité, portabilité,
  performance), dédoublonnées avec les outils externes.
- Rapports terminal (couleurs), Markdown, AsciiDoc et JSON ; français et
  anglais (`--lang`, sinon `LANG`).
- Configuration YAML : outils, règles désactivées ou reclassées, poids de
  notation, seuils.
- `--fail-under` pour l'intégration continue ; codes de sortie documentés.
- Packaging : `scripts/build-dist.sh` (tests, binaire autonome, SBOM),
  `install.sh`, `uninstall.sh`.
