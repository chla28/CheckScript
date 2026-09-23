#!/usr/bin/env bash
# install.sh — Installateur de RHSA Checker (CLI + GUI)
# Utilisation : ./install.sh [--prefix=DIR] [--system]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="rhsa_checker"
DISPLAY_NAME="RHSA Checker"

# ── Parsing des options ──────────────────────────────────────────────────────
FORCE_SYSTEM=false
CUSTOM_PREFIX=""

for arg in "$@"; do
  case "$arg" in
    --system)       FORCE_SYSTEM=true ;;
    --prefix=*)     CUSTOM_PREFIX="${arg#--prefix=}" ;;
    --help|-h)
      echo "Usage: $0 [--system] [--prefix=DIR]"
      echo ""
      echo "  --system        Installation système (requiert root, /usr/local)"
      echo "  --prefix=DIR    Préfixe personnalisé (défaut: /usr/local ou ~/.local)"
      exit 0 ;;
    *) echo "Option inconnue : $arg" >&2; exit 1 ;;
  esac
done

# ── Détection du mode d'installation ────────────────────────────────────────
if [[ -n "$CUSTOM_PREFIX" ]]; then
  SYSTEM_INSTALL=false
  PREFIX="$CUSTOM_PREFIX"
elif [[ "$FORCE_SYSTEM" == true ]] || [[ $EUID -eq 0 ]]; then
  SYSTEM_INSTALL=true
  PREFIX="/usr/local"
else
  SYSTEM_INSTALL=false
  PREFIX="${HOME}/.local"
fi

GUI_DIR="${PREFIX}/lib/${APP_NAME}"
BIN_DIR="${PREFIX}/bin"
ICON_DIR="${HOME}/.local/share/icons/hicolor"
DESKTOP_DIR="${HOME}/.local/share/applications"

if [[ "$SYSTEM_INSTALL" == true ]]; then
  ICON_DIR="/usr/share/icons/hicolor"
  DESKTOP_DIR="/usr/share/applications"
fi

# ── Vérification des fichiers sources ───────────────────────────────────────
CLI_BIN="${SCRIPT_DIR}/bin/rhsa-checker"
GUI_BIN="${SCRIPT_DIR}/gui/rhsa_checker_gui"

if [[ ! -f "$CLI_BIN" ]]; then
  echo "Erreur : binaire CLI introuvable : $CLI_BIN" >&2
  exit 1
fi
if [[ ! -f "$GUI_BIN" ]]; then
  echo "Erreur : binaire GUI introuvable : $GUI_BIN" >&2
  exit 1
fi

# ── En-tête ──────────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════╗"
echo "║      RHSA Checker — Installateur    ║"
echo "╚══════════════════════════════════════╝"
echo ""
if [[ "$SYSTEM_INSTALL" == true ]]; then
  echo "Mode    : installation système"
else
  echo "Mode    : installation utilisateur"
fi
echo "Préfixe : ${PREFIX}"
echo ""

# ── CLI ──────────────────────────────────────────────────────────────────────
echo "▶ Installation du CLI…"
mkdir -p "${BIN_DIR}"
install -m755 "${CLI_BIN}" "${BIN_DIR}/rhsa-checker"
echo "  ✓ ${BIN_DIR}/rhsa-checker"

# ── GUI ──────────────────────────────────────────────────────────────────────
echo "▶ Installation du GUI…"
rm -rf "${GUI_DIR}"
mkdir -p "${GUI_DIR}"
cp -r "${SCRIPT_DIR}/gui/." "${GUI_DIR}/"
chmod +x "${GUI_DIR}/rhsa_checker_gui"
ln -sf "${GUI_DIR}/rhsa_checker_gui" "${BIN_DIR}/rhsa-checker-gui"
echo "  ✓ ${GUI_DIR}/"
echo "  ✓ ${BIN_DIR}/rhsa-checker-gui  →  ${GUI_DIR}/rhsa_checker_gui"

# ── Icône ────────────────────────────────────────────────────────────────────
if [[ -f "${SCRIPT_DIR}/gui/rhsa_checker.svg" ]]; then
  echo "▶ Installation de l'icône…"
  mkdir -p "${ICON_DIR}/scalable/apps"
  cp "${SCRIPT_DIR}/gui/rhsa_checker.svg" "${ICON_DIR}/scalable/apps/rhsa_checker.svg"
  echo "  ✓ ${ICON_DIR}/scalable/apps/rhsa_checker.svg"
  command -v gtk-update-icon-cache &>/dev/null \
    && gtk-update-icon-cache -qf "${ICON_DIR}" 2>/dev/null || true
fi

# ── Fichier .desktop ─────────────────────────────────────────────────────────
echo "▶ Installation du raccourci applications…"
mkdir -p "${DESKTOP_DIR}"
cat > "${DESKTOP_DIR}/rhsa_checker.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=${DISPLAY_NAME}
GenericName=Analyseur de sécurité RHEL
Comment=Identifie les RHSA applicables à une liste de RPMs RHEL via les données OVAL Red Hat
Exec=${BIN_DIR}/rhsa-checker-gui
Icon=rhsa_checker
Categories=System;Security;Utility;
Keywords=rhel;rpm;rhsa;cve;security;oval;
Terminal=false
StartupNotify=true
DESKTOP
echo "  ✓ ${DESKTOP_DIR}/rhsa_checker.desktop"
command -v update-desktop-database &>/dev/null \
  && update-desktop-database "${DESKTOP_DIR}" 2>/dev/null || true

# ── Vérification du PATH ─────────────────────────────────────────────────────
echo ""
if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
  echo "⚠  ${BIN_DIR} n'est pas dans votre PATH."
  echo "   Ajoutez cette ligne à votre ~/.bashrc ou ~/.zshrc :"
  echo '   export PATH="'"${BIN_DIR}"':$PATH"'
  echo ""
fi

# ── Résumé ───────────────────────────────────────────────────────────────────
echo "✅ Installation terminée !"
echo ""
echo "  rhsa-checker       — CLI"
echo "  rhsa-checker-gui   — Interface graphique"
echo ""
echo "Exemple CLI :"
echo "  rhsa-checker --rhel=8 --packages=rpms.txt --severity=important"
echo ""
echo "Pour désinstaller :"
echo "  ${SCRIPT_DIR}/uninstall.sh"
