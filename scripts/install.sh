#!/usr/bin/env bash
# install.sh — Installateur de CheckScript (CLI check-script + interface
# graphique check-script-gui si présente dans l'archive)
# Utilisation : ./install.sh [--prefix=DIR] [--system]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parsing des options ──────────────────────────────────────────────────────
FORCE_SYSTEM=false
CUSTOM_PREFIX=""

for arg in "$@"; do
  case "$arg" in
  --system) FORCE_SYSTEM=true ;;
  --prefix=*) CUSTOM_PREFIX="${arg#--prefix=}" ;;
  --help | -h)
    echo "Usage: $0 [--system] [--prefix=DIR]"
    echo ""
    echo "  --system        Installation système (requiert root, /usr/local)"
    echo "  --prefix=DIR    Préfixe personnalisé (défaut: /usr/local ou ~/.local)"
    exit 0
    ;;
  *)
    echo "Option inconnue : $arg" >&2
    exit 1
    ;;
  esac
done

# ── Détection du mode d'installation ────────────────────────────────────────
if [[ -n "$CUSTOM_PREFIX" ]]; then
  PREFIX="$CUSTOM_PREFIX"
elif [[ "$FORCE_SYSTEM" == true ]] || [[ $EUID -eq 0 ]]; then
  PREFIX="/usr/local"
else
  PREFIX="${HOME}/.local"
fi

BIN_DIR="${PREFIX}/bin"
DOC_DIR="${PREFIX}/share/doc/check-script"
MAN_DIR="${PREFIX}/share/man/man1"
GUI_DIR="${PREFIX}/lib/check_script"
BASH_COMP_DIR="${PREFIX}/share/bash-completion/completions"
ZSH_COMP_DIR="${PREFIX}/share/zsh/site-functions"
ICON_DIR="${PREFIX}/share/icons/hicolor/scalable/apps"
DESKTOP_DIR="${PREFIX}/share/applications"
CLI_BIN="${SCRIPT_DIR}/bin/check-script"
GUI_BIN="${SCRIPT_DIR}/gui/check_script_gui"

if [[ ! -f "$CLI_BIN" ]]; then
  echo "Erreur : binaire CLI introuvable : $CLI_BIN" >&2
  exit 1
fi

echo "╔══════════════════════════════════════╗"
echo "║     CheckScript — Installateur       ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "Préfixe : ${PREFIX}"
echo ""

# ── CLI ──────────────────────────────────────────────────────────────────────
echo "▶ Installation du CLI…"
mkdir -p "${BIN_DIR}"
install -m755 "${CLI_BIN}" "${BIN_DIR}/check-script"
echo "  ✓ ${BIN_DIR}/check-script"

# ── Documentation, page de manuel, complétions ───────────────────────────────
if [[ -d "${SCRIPT_DIR}/doc" ]]; then
  mkdir -p "${DOC_DIR}"
  cp -r "${SCRIPT_DIR}/doc/." "${DOC_DIR}/"
  echo "  ✓ ${DOC_DIR}/"
fi
if [[ -f "${SCRIPT_DIR}/man/check-script.1" ]]; then
  install -Dm644 "${SCRIPT_DIR}/man/check-script.1" "${MAN_DIR}/check-script.1"
  echo "  ✓ ${MAN_DIR}/check-script.1"
fi
if [[ -d "${SCRIPT_DIR}/completions" ]]; then
  install -Dm644 "${SCRIPT_DIR}/completions/check-script.bash" "${BASH_COMP_DIR}/check-script"
  install -Dm644 "${SCRIPT_DIR}/completions/_check-script" "${ZSH_COMP_DIR}/_check-script"
  echo "  ✓ complétions bash / zsh"
fi
echo ""

# ── Interface graphique ──────────────────────────────────────────────────────
if [[ -f "$GUI_BIN" ]]; then
  echo "▶ Installation de l'interface graphique…"
  rm -rf "${GUI_DIR:?}"
  mkdir -p "${GUI_DIR}"
  cp -r "${SCRIPT_DIR}/gui/." "${GUI_DIR}/"
  chmod +x "${GUI_DIR}/check_script_gui"
  ln -sf "${GUI_DIR}/check_script_gui" "${BIN_DIR}/check-script-gui"
  echo "  ✓ ${BIN_DIR}/check-script-gui"
  if [[ -f "${GUI_DIR}/check_script.svg" ]]; then
    install -Dm644 "${GUI_DIR}/check_script.svg" "${ICON_DIR}/check_script.svg"
  fi
  if [[ -f "${GUI_DIR}/check_script.desktop" ]]; then
    mkdir -p "${DESKTOP_DIR}"
    sed "s|^Exec=.*|Exec=${BIN_DIR}/check-script-gui %F|" \
      "${GUI_DIR}/check_script.desktop" >"${DESKTOP_DIR}/check_script.desktop"
    command -v update-desktop-database &>/dev/null &&
      update-desktop-database "${DESKTOP_DIR}" 2>/dev/null || true
    echo "  ✓ ${DESKTOP_DIR}/check_script.desktop"
  fi
  echo ""
fi

# ── Outils d'analyse (facultatifs) ───────────────────────────────────────────
echo "▶ Outils d'analyse détectés :"
missing=()
for tool in shellcheck shfmt bashate checkbashisms; do
  if command -v "$tool" &>/dev/null; then
    echo "  ✓ $tool"
  else
    echo "  ✗ $tool (facultatif)"
    missing+=("$tool")
  fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo ""
  echo "  Pour une analyse complète (Fedora/RHEL) :"
  echo "    sudo dnf install ShellCheck shfmt devscripts-checkbashisms"
  echo "    pip install --user bashate"
  echo "  (Debian/Ubuntu : sudo apt install shellcheck shfmt devscripts ; pip install --user bashate)"
fi
echo ""

if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
  echo "⚠  ${BIN_DIR} n'est pas dans le PATH. Ajoutez à ~/.bashrc :"
  echo "   export PATH=\"${BIN_DIR}:\$PATH\""
  echo ""
fi
echo "✅ Installation terminée : check-script --help"
[[ -f "$GUI_BIN" ]] && echo "   Interface graphique : check-script-gui"
exit 0
