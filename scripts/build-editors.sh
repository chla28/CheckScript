#!/usr/bin/env bash
# build-editors.sh — Construit les extensions d'éditeurs de CheckScript.
# Produit dans dist/ :
#   check-script-VERSION.vsix          extension VS Code
#   check-script-eclipse-VERSION.zip   site de mise à jour Eclipse (Tycho)
#
# Usage : ./scripts/build-editors.sh [VERSION] [--skip-tests] [--no-vscode] [--no-eclipse]
#   VERSION       numéro de version (défaut : version de pubspec.yaml) ;
#                 sert uniquement à nommer les fichiers, les manifestes sont
#                 synchronisés par tool/release.dart
#   --skip-tests  ne lance pas « npm test » (VS Code de bout en bout)
#   --no-vscode   ne construit pas l'extension VS Code
#   --no-eclipse  ne construit pas le plugin Eclipse
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

VERSION="$(awk '/^version:/ {print $2; exit}' "$PROJECT_DIR/pubspec.yaml")"
VERSION="${VERSION%%+*}"
RUN_TESTS=true
BUILD_VSCODE=true
BUILD_ECLIPSE=true

for _arg in "$@"; do
  case "$_arg" in
  --skip-tests) RUN_TESTS=false ;;
  --no-vscode) BUILD_VSCODE=false ;;
  --no-eclipse) BUILD_ECLIPSE=false ;;
  --help | -h)
    sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  -*)
    echo "Option inconnue : $_arg" >&2
    exit 1
    ;;
  *) VERSION="${_arg#v}" ;;
  esac
done

DIST="$PROJECT_DIR/dist"
mkdir -p "$DIST"

need() {
  command -v "$1" >/dev/null || {
    echo "$1 introuvable (requis)" >&2
    exit 1
  }
}

# Serveur LSP utilisé par les tests de l'extension VS Code.
build_server() {
  need dart
  CHECK_SCRIPT="$(mktemp -d)/check-script"
  echo "→ serveur LSP : dart compile exe"
  (cd "$PROJECT_DIR" && dart compile exe bin/check_script.dart -o "$CHECK_SCRIPT" >/dev/null)
  export CHECK_SCRIPT
}

# Lance « npm test » avec un écran : le VS Code des tests est graphique.
run_vscode_tests() {
  if [[ -n "${DISPLAY:-}" ]]; then
    npm test
  elif command -v xvfb-run >/dev/null; then
    xvfb-run -a npm test
  else
    echo "  ! ni DISPLAY ni xvfb-run : tests VS Code sautés" >&2
  fi
}

build_vscode() {
  need node
  need npm
  echo "→ VS Code : npm ci / test / package"
  cd "$PROJECT_DIR/editors/vscode"
  npm ci --no-audit --no-fund
  if [[ "$RUN_TESTS" == true ]]; then
    build_server
    run_vscode_tests
  fi
  npm run package
  mv -f check-script.vsix "$DIST/check-script-$VERSION.vsix"
  echo "  ✓ dist/check-script-$VERSION.vsix"
}

build_eclipse() {
  need mvn
  need java
  echo "→ Eclipse : mvn verify (Tycho)"
  # Le plugin embarque la licence ; la copie est ignorée par git.
  cp "$PROJECT_DIR/LICENSE" \
    "$PROJECT_DIR/editors/eclipse/bundles/fr.chla28.checkscript/LICENSE"
  mvn -B -q -f "$PROJECT_DIR/editors/eclipse/pom.xml" verify
  cp "$PROJECT_DIR"/editors/eclipse/sites/fr.chla28.checkscript.site/target/*.zip \
    "$DIST/check-script-eclipse-$VERSION.zip"
  echo "  ✓ dist/check-script-eclipse-$VERSION.zip"
}

[[ "$BUILD_VSCODE" == true ]] && (build_vscode)
[[ "$BUILD_ECLIPSE" == true ]] && (build_eclipse)
echo "Terminé."
