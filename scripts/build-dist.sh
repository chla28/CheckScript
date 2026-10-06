#!/usr/bin/env bash
# build-dist.sh — Compile et package CheckScript (check-script) pour Linux
# Produit : dist/check_script-VERSION-linux-ARCH.tar.gz
#             (inclut un SBOM CycloneDX — sbom.cdx.json — si l'outil externe
#              `sbom-generator` est présent)
#
#           dist/rpm/<distrib>/*.rpm  (avec --rpm)
#
# Archive contents:
#   bin/check-script        CLI (Dart, binaire autonome)
#   gui/                    interface Flutter (bundle release, check_script_gui)
#   man/check-script.1      page de manuel (si asciidoctor est présent)
#   completions/            complétions bash et zsh
#   doc/                    user.adoc, developer.adoc, exemple de configuration,
#                           exemples CI
#   sbom.cdx.json           SBOM CycloneDX (arbre pub) — si `sbom-generator`
#                           est présent
#   install.sh / uninstall.sh
#
# À côté de l'archive, un rapport PDF de synthèse CVE du SBOM est aussi
# produit (dist/…-scan-report.pdf) via `sbom-generator scan` +
# Grype/OSV-Scanner/Trivy — best-effort, sauté si aucun scanner n'est installé.
#
# Usage : ./scripts/build-dist.sh [VERSION] [--rpm] [--install] [--skip-tests] [--no-gui]
#   VERSION      numéro de version (défaut : version de pubspec.yaml)
#   --rpm        génère aussi les RPM (scripts/build-rpm.sh, build natif)
#   --install    après un build réussi, installe le livrable dans ~/.local
#                (lance dist/<paquet>/install.sh)
#   --skip-tests ne lance pas analyse statique et tests avant la compilation
#   --no-gui     ne construit pas l'interface Flutter
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

DEFAULT_VERSION="$(awk '/^version:/ {print $2; exit}' "$PROJECT_DIR/pubspec.yaml")"
DEFAULT_VERSION="${DEFAULT_VERSION%%+*}"
VERSION="$DEFAULT_VERSION"
DO_INSTALL=false
RUN_TESTS=true
BUILD_RPM=false
BUILD_GUI=true

for _arg in "$@"; do
  case "$_arg" in
  --install) DO_INSTALL=true ;;
  --skip-tests) RUN_TESTS=false ;;
  --rpm) BUILD_RPM=true ;;
  --no-gui) BUILD_GUI=false ;;
  --help | -h)
    echo "Usage: $0 [VERSION] [--rpm] [--install] [--skip-tests] [--no-gui]"
    echo "  VERSION       version number (default: ${DEFAULT_VERSION}, read from pubspec.yaml)"
    echo "  --rpm         also builds the RPMs (scripts/build-rpm.sh)"
    echo "  --install     after the build, installs the package into ~/.local (dist/<package>/install.sh)"
    echo "  --skip-tests  skips static analysis and tests before compiling"
    echo "  --no-gui      ne construit pas l'interface Flutter"
    exit 0
    ;;
  -*)
    echo "Option inconnue : $_arg" >&2
    exit 1
    ;;
  *) VERSION="$_arg" ;;
  esac
done
unset _arg

# Version injectée dans le bundle Flutter (lue par MainGUI via
# data/flutter_assets/version.json) : --build-name suit la release.
FLUTTER_VERSION_ARGS=()
_vbase="${VERSION#v}"
_vbase="${_vbase%%[-+]*}"
[[ "$_vbase" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] && FLUTTER_VERSION_ARGS=(--build-name="$_vbase")
unset _vbase

ARCH="$(uname -m)"
DIST_NAME="check_script-${VERSION}-linux-${ARCH}"
DIST_DIR="${PROJECT_DIR}/dist/${DIST_NAME}"
ARCHIVE="${PROJECT_DIR}/dist/${DIST_NAME}.tar.gz"

cd "$PROJECT_DIR" || exit 1

# Scanne un SBOM avec Grype + OSV-Scanner + Trivy (best-effort : chaque scanner
# absent est simplement omis) et produit un PDF de synthèse via
# `sbom-generator scan -f pdf`. N'échoue jamais le build.
#   $1 = chemin du SBOM      $2 = chemin du PDF de sortie
run_scan_report() {
  local sbom="$1" pdf="$2"
  [[ "$HAVE_SBOM_GENERATOR" == true ]] || return 0
  if [[ ! -f "$sbom" ]]; then
    echo "  ⚠  SBOM not found ($sbom) — scan skipped." >&2
    return 0
  fi
  if ! command -v grype &>/dev/null &&
    ! command -v osv-scanner &>/dev/null &&
    ! command -v trivy &>/dev/null; then
    echo "  ⚠  No scanner (grype / osv-scanner / trivy) — CVE scan skipped." >&2
    return 0
  fi
  local color=never
  [[ -t 1 && -z "${NO_COLOR:-}" ]] && color=always
  if sbom-generator scan \
    --sbom "$sbom" --scanner all --format pdf --output "$pdf" \
    --color "$color" 2>&1 | sed 's/^/  /'; then
    [[ -f "$pdf" ]] && echo "  ✓ $(realpath --relative-to="${PROJECT_DIR}" "$pdf")"
  else
    echo "  ⚠  CVE scan failed — packaging continues without a report." >&2
  fi
}

# ── Vérification des outils ──────────────────────────────────────────────────
echo "╔══════════════════════════════════════════╗"
echo "║  CheckScript — Build distribution        ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Version: ${VERSION}"
echo "Arch    : ${ARCH}"
echo "Sortie  : dist/${DIST_NAME}.tar.gz"
[[ "$BUILD_GUI" == true ]] && echo "GUI     : oui (flutter build linux)"
[[ "$BUILD_RPM" == true ]] && echo "RPM     : oui (dist/rpm/)"

HAVE_SBOM_GENERATOR=false
if command -v sbom-generator &>/dev/null; then
  HAVE_SBOM_GENERATOR=true
  echo "SBOM    : yes (sbom-generator detected, CycloneDX)"
else
  echo "SBOM    : no ('sbom-generator' not found in PATH)"
fi
echo ""

_required_tools=(dart tar)
[[ "$BUILD_GUI" == true ]] && _required_tools+=(flutter)
[[ "$BUILD_RPM" == true ]] && _required_tools+=(rpmbuild)
for tool in "${_required_tools[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    echo "Error: '$tool' not found in PATH." >&2
    exit 1
  fi
done
unset _required_tools

echo "Tools: dart $(dart --version 2>&1 | head -1 | awk '{print $4}')"
echo ""

# Contrôle de cohérence : la version affichée par --version doit suivre
# pubspec.yaml (lib/src/version.dart est maintenu à la main).
CODE_VERSION="$(sed -n "s/^const appVersion = '\(.*\)';/\1/p" lib/src/version.dart)"
if [[ "$CODE_VERSION" != "$DEFAULT_VERSION" ]]; then
  echo "  ⚠  lib/src/version.dart ($CODE_VERSION) ≠ pubspec.yaml ($DEFAULT_VERSION)" >&2
fi

# ── Dépendances, analyse statique et tests ───────────────────────────────────
echo "▶ Dependencies (dart pub get)…"
dart pub get 2>&1 | tail -1 | sed 's/^/  /'
if [[ "$RUN_TESTS" == true ]]; then
  echo "▶ Static analysis (dart analyze)…"
  dart analyze --fatal-infos 2>&1 | tail -1 | sed 's/^/  /'
  echo "▶ Tests (dart test)…"
  dart test 2>&1 | tail -1 | sed 's/^/  /'
  if [[ "$BUILD_GUI" == true ]]; then
    echo "▶ Interface: analysis and tests (flutter)…"
    (cd gui && flutter pub get >/dev/null && flutter analyze --no-fatal-infos 2>&1 | tail -1 &&
      flutter test 2>&1 | tail -1) | sed 's/^/  /'
  fi
fi
echo ""

# ── Nettoyage ────────────────────────────────────────────────────────────────
rm -rf "${DIST_DIR:?}"
mkdir -p "${DIST_DIR}/bin" "${DIST_DIR}/doc" "${DIST_DIR}/completions"

# ── CLI : dart compile exe ───────────────────────────────────────────────────
echo "▶ Compiling the CLI (dart compile exe)…"
dart compile exe bin/check_script.dart -o "${DIST_DIR}/bin/check-script" 2>&1 |
  grep -v "^$" | sed 's/^/  /'
chmod +x "${DIST_DIR}/bin/check-script"
CLI_SIZE=$(du -sh "${DIST_DIR}/bin/check-script" | cut -f1)
echo "  ✓ check-script (${CLI_SIZE})"
echo ""

# ── GUI : flutter build linux --release ─────────────────────────────────────
if [[ "$BUILD_GUI" == true ]]; then
  echo "▶ Building the Flutter interface (release)…"
  mkdir -p "${DIST_DIR}/gui"
  (
    cd gui || exit 1
    # flutter clean : le cache CMake mémorise le chemin absolu du projet.
    flutter clean >/dev/null
    flutter build linux --release ${FLUTTER_VERSION_ARGS[@]+"${FLUTTER_VERSION_ARGS[@]}"} 2>&1 |
      { grep -E "^\s*(✓|error|Error)" || true; } | sed 's/^/  /'
  )
  cp -r gui/build/linux/x64/release/bundle/. "${DIST_DIR}/gui/"
  chmod +x "${DIST_DIR}/gui/check_script_gui"
  cp assets/check_script.svg "${DIST_DIR}/gui/"
  cat >"${DIST_DIR}/gui/check_script.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=CheckScript
GenericName=Shell and Python script assessment
GenericName[fr]=Évaluation de scripts shell et Python
Comment=Rates the security, robustness and maintainability of shell and Python scripts
Comment[fr]=Évalue la sécurité, la robustesse et la maintenabilité de scripts shell et Python
Exec=check-script-gui %F
Icon=check_script
Categories=Development;Security;Utility;
Keywords=shell;bash;script;shellcheck;lint;security;
MimeType=application/x-shellscript;text/x-shellscript;text/x-python;text/x-python3;
Terminal=false
StartupNotify=true
DESKTOP
  echo "  ✓ check_script_gui + libs ($(du -sh "${DIST_DIR}/gui" | cut -f1))"
  echo ""
fi

# ── Ressources ───────────────────────────────────────────────────────────────
echo "▶ Adding resources…"
cp doc/user.adoc doc/developer.adoc doc/user.fr.adoc doc/developer.fr.adoc \
  doc/checkscript.example.yaml "${DIST_DIR}/doc/"
cp -r doc/ci "${DIST_DIR}/doc/"
echo "  ✓ doc/ (user.adoc, developer.adoc, checkscript.example.yaml, ci/)"
cp completions/check-script.bash completions/_check-script "${DIST_DIR}/completions/"
echo "  ✓ completions/ (bash, zsh)"
if command -v asciidoctor &>/dev/null; then
  mkdir -p "${DIST_DIR}/man"
  asciidoctor -b manpage doc/check-script.1.adoc -o "${DIST_DIR}/man/check-script.1"
  echo "  ✓ man/check-script.1"
else
  echo "  ⚠  asciidoctor missing: man page not generated." >&2
fi
cp README.md README.fr.md CHANGELOG.md LICENSE COPYING "${DIST_DIR}/"
echo "  ✓ README.md / CHANGELOG.md / LICENSE / COPYING"
cp "${SCRIPT_DIR}/install.sh" "${SCRIPT_DIR}/uninstall.sh" "${DIST_DIR}/"
chmod +x "${DIST_DIR}/install.sh" "${DIST_DIR}/uninstall.sh"
echo "  ✓ install.sh / uninstall.sh"

# SBOM (CycloneDX) : arbre des dépendances Dart (pubspec.lock). Le CLI est un
# binaire Dart autonome, sans dépendance runtime distro à déclarer ; les
# outils d'analyse (shellcheck…) sont facultatifs et détectés à l'exécution.
if [[ "$HAVE_SBOM_GENERATOR" == true ]]; then
  SBOM_REFS="$(mktemp)"
  trap 'rm -f "$SBOM_REFS"' EXIT
  find "$PROJECT_DIR" -name pubspec.lock -not -path '*/build/*' \
    -not -path '*/.dart_tool/*' -not -path '*/dist/*' | sort >"$SBOM_REFS"
  [[ "$BUILD_GUI" == true ]] && printf '%s\n' gtk3 glibc >>"$SBOM_REFS"
  if sbom-generator -i "$SBOM_REFS" -f cyclonedx \
    -o "${DIST_DIR}/sbom.cdx.json" \
    -n "${DIST_NAME}-sbom" 2>&1 | sed 's/^/  /'; then
    echo "  ✓ sbom.cdx.json (CycloneDX SBOM: pub tree)"
  else
    echo "  ⚠  SBOM generation failed — packaging continues without it." >&2
  fi
fi
echo ""

# ── Scan CVE du SBOM + PDF de synthèse ───────────────────────────────────────
echo "▶ CVE scan of the SBOM (Grype + OSV-Scanner + Trivy)…"
SCAN_PDF="${PROJECT_DIR}/dist/${DIST_NAME}-scan-report.pdf"
run_scan_report "${DIST_DIR}/sbom.cdx.json" "$SCAN_PDF"
echo ""

# ── Archive ──────────────────────────────────────────────────────────────────
echo "▶ Creating the archive…"
tar czf "$ARCHIVE" -C "${PROJECT_DIR}/dist" "${DIST_NAME}"
TOTAL_SIZE=$(du -sh "$ARCHIVE" | cut -f1)
echo "  ✓ ${ARCHIVE} (${TOTAL_SIZE})"
echo ""

# ── RPM (--rpm) ──────────────────────────────────────────────────────────────
if [[ "$BUILD_RPM" == true ]]; then
  _pkg=all
  [[ "$BUILD_GUI" == true ]] || _pkg=cli
  "${SCRIPT_DIR}/build-rpm.sh" --package="$_pkg" "$VERSION"
  unset _pkg
  echo ""
fi

# ── Installation locale (--install) ──────────────────────────────────────────
if [[ "$DO_INSTALL" == true ]]; then
  echo "▶ Local installation (~/.local)…"
  bash "${DIST_DIR}/install.sh"
  echo ""
fi

# ── Résumé ───────────────────────────────────────────────────────────────────
echo "✅ Distribution ready!"
echo ""
echo "  dist/${DIST_NAME}.tar.gz (${TOTAL_SIZE})"
if [[ -f "$SCAN_PDF" ]]; then
  echo "  dist/${DIST_NAME}-scan-report.pdf (CVE summary Grype + OSV-Scanner + Trivy)"
elif [[ -f "${SCAN_PDF%.pdf}.adoc" ]]; then
  echo "  dist/${DIST_NAME}-scan-report.adoc (CVE summary — PDF not generated, asciidoctor-pdf missing)"
fi
if [[ -f "${DIST_DIR}/sbom.cdx.json" ]]; then
  echo "    └─ inclut sbom.cdx.json (CycloneDX SBOM: pub tree)"
fi
if [[ "$BUILD_RPM" == true ]]; then
  find "${PROJECT_DIR}/dist/rpm" -name '*.rpm' 2>/dev/null | sort |
    while IFS= read -r r; do echo "  ${r#"${PROJECT_DIR}"/}"; done
fi
echo ""
echo "Archive contents:"
tar tf "$ARCHIVE" | grep -v '/gui/.\+/' | sed 's/^/  /'
echo ""
echo "To install on the target machine:"
echo "  tar xzf ${DIST_NAME}.tar.gz"
echo "  cd ${DIST_NAME}"
echo "  ./install.sh              # user installation (~/.local)"
echo "  sudo ./install.sh         # system installation (/usr/local)"
