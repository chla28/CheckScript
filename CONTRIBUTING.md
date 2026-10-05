# Contributing / Contribuer

*[Français plus bas](#français)*

## English

Thanks for your interest in CheckScript! Issues and pull requests may be
written in **English or French**.

- **Setup and tests**: `dart pub get`, `dart test`, `(cd gui && flutter test)`
  — see the [developer guide](doc/developer.adoc) (architecture, adding rules,
  packaging).
- **Commits**: [Conventional Commits](https://www.conventionalcommits.org)
  (`feat(gui): …`, `fix: …`), with type, scope and description in English, no
  trailing period, first line at most 100 characters. Enable the check with
  `scripts/install-git-hooks.sh`; CI verifies new commits too.
- **Documentation**: every user-facing document exists in English (default)
  and French (`.fr` suffix). When you change one, update the other, or say in
  the pull request that the translation is still to do.
- **Messages**: tool and interface texts go through the translation helpers
  (`_t(fr, en)`); never add a French-only or English-only string.
- **Rules**: a new rule comes with a fix suggestion, a test and an entry in
  the rule table of the user guide.
- **Security issues**: please do not open a public issue; see [SECURITY.md](SECURITY.md).

## Français

Merci de votre intérêt pour CheckScript ! Les issues et pull requests peuvent
être rédigées en **anglais ou en français**.

- **Installation et tests** : `dart pub get`, `dart test`,
  `(cd gui && flutter test)` — voir le [guide développeur](doc/developer.fr.adoc)
  (architecture, ajout de règles, packaging).
- **Commits** : [Conventional Commits](https://www.conventionalcommits.org)
  (`feat(gui): …`, `fix: …`), type, portée et description en anglais, sans
  point final, première ligne de 100 caractères au plus. Contrôle local avec
  `scripts/install-git-hooks.sh` ; la CI vérifie aussi les nouveaux commits.
- **Documentation** : chaque document destiné aux utilisateurs existe en
  anglais (par défaut) et en français (suffixe `.fr`). Quand vous en modifiez
  un, mettez l'autre à jour, ou précisez dans la pull request que la
  traduction reste à faire.
- **Messages** : les textes de l'outil et de l'interface passent par les
  fonctions de traduction (`_t(fr, en)`) ; n'ajoutez jamais de chaîne
  uniquement française ou uniquement anglaise.
- **Règles** : une nouvelle règle s'accompagne d'un conseil de correction,
  d'un test et d'une entrée dans le tableau des règles du guide utilisateur.
- **Failles de sécurité** : n'ouvrez pas d'issue publique ; voir [SECURITY.md](SECURITY.md).
