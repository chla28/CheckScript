# CheckScript for VS Code

*[Version française](README.fr.md)*

Analyzes shell and Python scripts — and the shell of GitHub Actions
workflows, GitLab CI, Dockerfiles, Makefiles and Ansible tasks —
with [CheckScript](https://github.com/chla28/CheckScript):

- issues underlined and listed in the *Problems* panel (severity,
  rule, advice, link to the documentation); full analysis on open and on
  save, built-in rules while typing;
- quick fixes (light bulb, Ctrl+.): fix one issue or the whole rule,
  ignore the rule on the line or in the file;
- hover: explanation, advice and a "avoid / write" example;
- script score in the status bar (click: re-analyze);
- *Format Document*: shfmt (shell) or `ruff format` (Python).

## Requirements

`check-script` 0.16 or later (RPM, archive or `~/.local/bin`), and
preferably ShellCheck, shfmt, Ruff… The extension runs `check-script lsp`.

## Settings

| Setting | Default | Purpose |
|---|---|---|
| `checkScript.path` | `check-script` | Executable (PATH or absolute path) |
| `checkScript.lang` | environment language | `fr` or `en` |
| `checkScript.profile` | the one from `.checkscript.yaml` | `strict`, `default`, `legacy` |
| `checkScript.analyzeOnType` | `true` | Built-in rules while typing |
| `checkScript.typingDelay` | `600` | Typing pause (ms) |

The project configuration (nearest `.checkscript.yaml`) applies as on the
command line.

Installation: `code --install-extension check-script-VERSION.vsix`.
