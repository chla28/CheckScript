# CheckScript in JetBrains IDEs (IntelliJ IDEA, PyCharm, WebStorm, CLion…)

*[Version française](README.fr.md)*

There is no dedicated plugin: `check-script lsp` is a standard
[Language Server](https://microsoft.github.io/language-server-protocol/), and
the free [LSP4IJ](https://plugins.jetbrains.com/plugin/23257-lsp4ij) plugin
(Red Hat) lets any JetBrains IDE use one. You get the same diagnostics, hover,
quick fixes and *Format* as in VS Code.

> **Not tested in a JetBrains IDE.** The steps below follow LSP4IJ's
> documented user-defined language servers; menu names may differ slightly
> between versions. The server itself is covered by the project's tests
> (`test/lsp_test.dart`).

## Setup

1. Install `check-script` (RPM, archive, AppImage…) so that `check-script`
   is in the `PATH` of the IDE (or note its absolute path).
2. *Settings → Plugins → Marketplace*: install **LSP4IJ**.
3. *Settings → Languages & Frameworks → Language Servers → +* (*New Language
   Server*):
   - **Name**: `CheckScript`
   - **Command**: `check-script lsp`
     (optionally `check-script lsp --lang en`)
4. *Mappings* tab → *File name patterns*: add one pattern per file kind to
   analyze, with the matching language identifier when asked
   (`shellscript`, `python`, `perl`, `ruby`, `lua`):

   | Pattern | Language id |
   |---|---|
   | `*.sh`, `*.bash` | `shellscript` |
   | `*.py` | `python` |
   | `*.pl`, `*.pm` | `perl` |
   | `*.rb` | `ruby` |
   | `*.lua` | `lua` |
   | `*.service`, `*.timer`, `*.socket` | `systemd` |
   | `crontab`, `sudoers` | `crontab`, `sudoers` |
   | `Dockerfile`, `Makefile`, `*.yml`, `*.yaml` | `dockerfile`, `makefile`, `yaml` |

   The server ignores YAML files without an embedded script. JavaScript files
   (`*.js`) are only analyzed when they have a `node` shebang: do not map them.

## Options

`check-script lsp` takes its profile and settings from the project's
`.checkscript.yaml`; there is nothing else to configure in the IDE.
