# Changelog

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
