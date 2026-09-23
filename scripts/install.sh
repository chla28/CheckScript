#!/usr/bin/env bash
# install.sh — Installateur de CheckScript (CLI check-script)
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
CLI_BIN="${SCRIPT_DIR}/bin/check-script"

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

# ── Documentation ────────────────────────────────────────────────────────────
if [[ -d "${SCRIPT_DIR}/doc" ]]; then
  mkdir -p "${DOC_DIR}"
  cp -r "${SCRIPT_DIR}/doc/." "${DOC_DIR}/"
  echo "  ✓ ${DOC_DIR}/"
fi
echo ""

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
