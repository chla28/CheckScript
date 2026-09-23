#!/usr/bin/env bash
# uninstall.sh — Désinstallateur de CheckScript (CLI check-script)
set -euo pipefail

# ── Parsing des options (mêmes options que install.sh) ───────────────────────
FORCE_SYSTEM=false
CUSTOM_PREFIX=""

for arg in "$@"; do
  case "$arg" in
  --system) FORCE_SYSTEM=true ;;
  --prefix=*) CUSTOM_PREFIX="${arg#--prefix=}" ;;
  --help | -h)
    echo "Usage: $0 [--system] [--prefix=DIR]"
    exit 0
    ;;
  *)
    echo "Option inconnue : $arg" >&2
    exit 1
    ;;
  esac
done

# ── Préfixe : identique à celui retenu par install.sh ────────────────────────
if [[ -n "$CUSTOM_PREFIX" ]]; then
  PREFIX="$CUSTOM_PREFIX"
elif [[ "$FORCE_SYSTEM" == true ]] || [[ $EUID -eq 0 ]]; then
  PREFIX="/usr/local"
else
  PREFIX="${HOME}/.local"
fi

# ── Suppression du binaire et de la documentation ────────────────────────────
echo "▶ Désinstallation de CheckScript (${PREFIX})…"
for target in "${PREFIX}/bin/check-script" "${PREFIX}/share/doc/check-script"; do
  if [[ -e "$target" ]]; then
    rm -rf -- "${target:?}"
    echo "  ✓ supprimé : $target"
  fi
done
echo "✅ Désinstallation terminée."
