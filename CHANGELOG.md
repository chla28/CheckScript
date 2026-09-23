# Changelog

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
