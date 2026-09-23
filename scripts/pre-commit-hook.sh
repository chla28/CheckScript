#!/usr/bin/env bash
# pre-commit-hook.sh — Hook git « pre-commit » autonome (sans le framework
# pre-commit) : évalue la version *indexée* des scripts shell modifiés et
# bloque le commit si l'un d'eux passe sous le seuil.
#
# Installation dans un dépôt :
#   ln -s /chemin/vers/CheckScript/scripts/pre-commit-hook.sh .git/hooks/pre-commit
#
# Variables :
#   CHECK_SCRIPT_MIN   note globale minimale (défaut : 6)
#   CHECK_SCRIPT_ARGS  options supplémentaires (ex. "--profile strict")
#   CHECK_SCRIPT_SKIP  si non vide, le hook ne fait rien
set -euo pipefail

[[ -n "${CHECK_SCRIPT_SKIP:-}" ]] && exit 0

if ! command -v check-script &>/dev/null; then
  echo "pre-commit : check-script introuvable, contrôle ignoré." >&2
  exit 0
fi

# Scripts shell ajoutés / modifiés dans l'index (extension ou shebang).
mapfile -t candidates < <(git diff --cached --name-only --diff-filter=ACMR)
files=()
for f in "${candidates[@]}"; do
  case "$f" in
    *.sh | *.bash | *.ksh | *.dash | *.zsh) files+=("$f") ;;
    *.*) ;;
    *)
      if git show ":$f" 2>/dev/null | head -n1 | grep -Eq '^#!.*\b(ba|da|k|mk|z)?sh\b'; then
        files+=("$f")
      fi
      ;;
  esac
done
[[ ${#files[@]} -eq 0 ]] && exit 0

# Extraction de la version indexée (et non celle de l'arbre de travail).
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp:?}"' EXIT
git checkout-index --prefix="$tmp/" -- "${files[@]}"

read -r -a extra <<<"${CHECK_SCRIPT_ARGS:-}"
cd "$tmp" || exit 1
if ! check-script --no-color --summary --fail-under "${CHECK_SCRIPT_MIN:-6}" \
  ${extra[@]+"${extra[@]}"} "${files[@]}"; then
  echo "" >&2
  echo "pre-commit : note inférieure à ${CHECK_SCRIPT_MIN:-6}/10." >&2
  echo "  Détail : check-script --details <script> ; corrections : check-script --fix <script>" >&2
  echo "  Ignorer une fois : CHECK_SCRIPT_SKIP=1 git commit …" >&2
  exit 1
fi
