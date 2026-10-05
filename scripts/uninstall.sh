#!/usr/bin/env bash
# uninstall.sh — Désinstallateur de CheckScript (CLI et interface graphique)
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
echo "▶ Uninstalling CheckScript (${PREFIX})…"
for target in \
  "${PREFIX}/bin/check-script" \
  "${PREFIX}/bin/check-script-gui" \
  "${PREFIX}/lib/check_script" \
  "${PREFIX}/share/doc/check-script" \
  "${PREFIX}/share/man/man1/check-script.1" \
  "${PREFIX}/share/bash-completion/completions/check-script" \
  "${PREFIX}/share/zsh/site-functions/_check-script" \
  "${PREFIX}/share/icons/hicolor/scalable/apps/check_script.svg" \
  "${PREFIX}/share/applications/check_script.desktop"; do
  if [[ -e "$target" || -L "$target" ]]; then
    rm -rf -- "${target:?}"
    echo "  ✓ removed: $target"
  fi
done
# Cache des types MIME partagé avec les autres applications : régénéré, pas
# supprimé.
if [[ -d "${PREFIX}/share/applications" ]] && command -v update-desktop-database &>/dev/null; then
  update-desktop-database "${PREFIX}/share/applications" 2>/dev/null || true
fi
echo "✅ Uninstallation complete."
