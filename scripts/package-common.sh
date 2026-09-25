#!/usr/bin/env bash
# Chargé par des scripts en « set -euo pipefail » : ces options s'appliquent.
# check-script disable-file=ROB001,ROB003,ROB011
#
# package-common.sh — Fonctions communes à build-flatpak.sh et
# build-appimage.sh (à charger avec « source », pas à exécuter).
#
#   PROJECT_DIR, APP_ID, VERSION, ARCH       variables définies ici
#   build_binaries DEST                       bundle Flutter + CLI compilée
#   glibc_report DIR                          glibc minimale requise

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# Variables utilisées par les scripts qui chargent ce fichier.
# shellcheck disable=SC2034
APP_ID="fr.chla28.check_script_gui"
VERSION="$(awk '/^version:/ {print $2; exit}' "$PROJECT_DIR/pubspec.yaml")"
VERSION="${VERSION%%+*}"
# shellcheck disable=SC2034
ARCH="$(uname -m)"

# Construit dans DEST : bundle/ (interface Flutter, --build-name=VERSION) et
# check-script-cli (dart compile exe, toujours recompilée). SKIP_BUILD=1
# réutilise le bundle Flutter existant de gui/build.
build_binaries() {
  local dest="$1"
  mkdir -p "$dest"
  command -v dart >/dev/null || {
    echo "dart introuvable" >&2
    exit 1
  }
  if [[ "${SKIP_BUILD:-0}" != 1 ]]; then
    command -v flutter >/dev/null || {
      echo "flutter introuvable" >&2
      exit 1
    }
    echo "→ interface : flutter build linux --release"
    (cd "$PROJECT_DIR/gui" && flutter build linux --release --build-name="$VERSION" >/dev/null)
  fi
  # La CLI est toujours recompilée (quelques secondes) : --skip-build ne
  # réutilise que le bundle Flutter, long à construire.
  echo "→ ligne de commande : dart compile exe"
  (cd "$PROJECT_DIR" && dart compile exe bin/check_script.dart -o "$dest/check-script-cli" >/dev/null)
  local bundle="$PROJECT_DIR/gui/build/linux/x64/release/bundle"
  [[ -x "$bundle/check_script_gui" ]] || {
    echo "bundle Flutter absent : $bundle" >&2
    exit 1
  }
  rm -rf "${dest:?}/bundle"
  cp -r "$bundle" "$dest/bundle"
}

# Plus haute version de glibc exigée par les binaires de DIR : le paquet ne
# démarre que sur un système (ou un runtime) au moins aussi récent.
glibc_report() {
  local max
  # objdump échoue sur les fichiers qui ne sont pas des binaires ELF
  # (scripts) : pipefail est levé pour ce seul calcul.
  max="$(
    set +o pipefail
    find "$1" -type f \( -name '*.so' -o -perm -u+x \) -print0 |
      xargs -0 objdump -T 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1
  )"
  echo "  glibc minimale requise : ${max:-inconnue} (système hôte : $(ldd --version | head -1 | awk '{print $NF}'))"
}
