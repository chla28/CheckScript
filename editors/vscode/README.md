# CheckScript pour VS Code

Analyse les scripts shell et Python — et le shell des workflows GitHub
Actions, de GitLab CI, des Dockerfile, des Makefile et des tâches Ansible —
avec [CheckScript](https://github.com/chla28/CheckScript) :

- problèmes soulignés et listés dans le panneau *Problèmes* (sévérité,
  règle, conseil, lien vers la documentation) ; analyse complète à
  l'ouverture et à l'enregistrement, règles intégrées pendant la frappe ;
- corrections rapides (ampoule, Ctrl+.) : corriger un problème ou toute la
  règle, ignorer la règle sur la ligne ou dans le fichier ;
- survol : explication, conseil et exemple « à éviter / à écrire » ;
- note du script dans la barre d'état (clic : réanalyser) ;
- *Formater le document* : shfmt (shell) ou `ruff format` (Python).

## Prérequis

`check-script` 0.16 ou plus récent (RPM, archive ou `~/.local/bin`), et
de préférence ShellCheck, shfmt, Ruff… L'extension lance `check-script lsp`.

## Réglages

| Réglage | Défaut | Rôle |
|---|---|---|
| `checkScript.path` | `check-script` | Exécutable (PATH ou chemin absolu) |
| `checkScript.lang` | langue de l'environnement | `fr` ou `en` |
| `checkScript.profile` | celui de `.checkscript.yaml` | `strict`, `default`, `legacy` |
| `checkScript.analyzeOnType` | `true` | Règles intégrées pendant la frappe |
| `checkScript.typingDelay` | `600` | Pause de frappe (ms) |

La configuration du projet (`.checkscript.yaml` le plus proche) s'applique
comme en ligne de commande.

Installation : `code --install-extension check-script-VERSION.vsix`.
