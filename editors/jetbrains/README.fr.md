# CheckScript dans les IDE JetBrains (IntelliJ IDEA, PyCharm, WebStorm, CLion…)

*[English version](README.md)*

Il n'existe pas de plugin dédié : `check-script lsp` est un
[serveur de langage](https://microsoft.github.io/language-server-protocol/)
standard, et le plugin gratuit [LSP4IJ](https://plugins.jetbrains.com/plugin/23257-lsp4ij)
(Red Hat) permet à n'importe quel IDE JetBrains d'en utiliser un. On obtient
les mêmes diagnostics, survols, corrections rapides et *Formater* que dans
VS Code.

> **Non testé dans un IDE JetBrains.** Les étapes suivent la configuration de
> serveurs de langage définis par l'utilisateur de LSP4IJ ; les noms de menus
> peuvent varier un peu selon les versions. Le serveur lui-même est couvert par
> les tests du projet (`test/lsp_test.dart`).

## Mise en place

1. Installer `check-script` (RPM, archive, AppImage…) de sorte que
   `check-script` soit dans le `PATH` de l'IDE (ou noter son chemin absolu).
2. *Settings → Plugins → Marketplace* : installer **LSP4IJ**.
3. *Settings → Languages & Frameworks → Language Servers → +* (*New Language
   Server*) :
   - **Name** : `CheckScript`
   - **Command** : `check-script lsp`
     (éventuellement `check-script lsp --lang fr`)
4. Onglet *Mappings* → *File name patterns* : ajouter un motif par type de
   fichier à analyser, avec l'identifiant de langage demandé
   (`shellscript`, `python`, `perl`, `ruby`, `lua`) :

   | Motif | Identifiant de langage |
   |---|---|
   | `*.sh`, `*.bash` | `shellscript` |
   | `*.py` | `python` |
   | `*.pl`, `*.pm` | `perl` |
   | `*.rb` | `ruby` |
   | `*.lua` | `lua` |
   | `*.service`, `*.timer`, `*.socket` | `systemd` |
   | `crontab`, `sudoers` | `crontab`, `sudoers` |
   | `Dockerfile`, `Makefile`, `*.yml`, `*.yaml` | `dockerfile`, `makefile`, `yaml` |

   Le serveur ignore les fichiers YAML sans script intégré. Les fichiers
   JavaScript (`*.js`) ne sont analysés que s'ils ont un shebang `node` : ne
   pas les associer.

## Options

`check-script lsp` lit le profil et les réglages du `.checkscript.yaml` du
projet ; il n'y a rien d'autre à configurer dans l'IDE.
