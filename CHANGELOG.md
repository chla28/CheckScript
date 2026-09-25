# Changelog

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
