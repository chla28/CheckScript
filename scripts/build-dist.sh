#!/usr/bin/env bash
# build-dist.sh — Compile et package CheckScript (check-script) pour Linux
# Produit : dist/check_script-VERSION-linux-ARCH.tar.gz
#             (inclut un SBOM CycloneDX — sbom.cdx.json — si l'outil externe
#              `sbom-generator` est présent)
#
# Contenu de l'archive :
#   bin/check-script        CLI (Dart, binaire autonome)
#   doc/                    user.adoc, developer.adoc, exemple de configuration
#   sbom.cdx.json           SBOM CycloneDX (arbre pub) — si `sbom-generator`
#                           est présent
#   install.sh / uninstall.sh
#
# À côté de l'archive, un rapport PDF de synthèse CVE du SBOM est aussi
# produit (dist/…-scan-report.pdf) via `sbom-generator scan` +
# Grype/OSV-Scanner/Trivy — best-effort, sauté si aucun scanner n'est installé.
#
# Usage : ./scripts/build-dist.sh [VERSION] [--install] [--skip-tests]
#   VERSION      numéro de version (défaut : version de pubspec.yaml)
#   --install    après un build réussi, installe le livrable dans ~/.local
#                (lance dist/<paquet>/install.sh)
#   --skip-tests ne lance pas `dart analyze` / `dart test` avant la compilation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

DEFAULT_VERSION="$(awk '/^version:/ {print $2; exit}' "$PROJECT_DIR/pubspec.yaml")"
DEFAULT_VERSION="${DEFAULT_VERSION%%+*}"
VERSION="$DEFAULT_VERSION"
DO_INSTALL=false
RUN_TESTS=true

for _arg in "$@"; do
  case "$_arg" in
  --install) DO_INSTALL=true ;;
  --skip-tests) RUN_TESTS=false ;;
  --help | -h)
    echo "Usage: $0 [VERSION] [--install] [--skip-tests]"
    echo "  VERSION       numéro de version (défaut: ${DEFAULT_VERSION}, lu depuis pubspec.yaml)"
    echo "  --install     après le build, installe le livrable dans ~/.local (dist/<paquet>/install.sh)"
    echo "  --skip-tests  ne lance pas dart analyze / dart test avant la compilation"
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
    echo "  ⚠  SBOM introuvable ($sbom) — scan sauté." >&2
    return 0
  fi
  if ! command -v grype &>/dev/null &&
    ! command -v osv-scanner &>/dev/null &&
    ! command -v trivy &>/dev/null; then
    echo "  ⚠  Aucun scanner (grype / osv-scanner / trivy) — scan CVE sauté." >&2
    return 0
  fi
  local color=never
  [[ -t 1 && -z "${NO_COLOR:-}" ]] && color=always
  if sbom-generator scan \
    --sbom "$sbom" --scanner all --format pdf --output "$pdf" \
    --color "$color" 2>&1 | sed 's/^/  /'; then
    [[ -f "$pdf" ]] && echo "  ✓ $(realpath --relative-to="${PROJECT_DIR}" "$pdf")"
  else
    echo "  ⚠  Échec du scan CVE — le packaging continue sans rapport." >&2
  fi
}

# ── Vérification des outils ──────────────────────────────────────────────────
echo "╔══════════════════════════════════════════╗"
echo "║  CheckScript — Build distribution        ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Version : ${VERSION}"
echo "Arch    : ${ARCH}"
echo "Sortie  : dist/${DIST_NAME}.tar.gz"

HAVE_SBOM_GENERATOR=false
if command -v sbom-generator &>/dev/null; then
  HAVE_SBOM_GENERATOR=true
  echo "SBOM    : oui (sbom-generator détecté, CycloneDX)"
else
  echo "SBOM    : non ('sbom-generator' introuvable dans PATH)"
fi
echo ""

for tool in dart tar; do
  if ! command -v "$tool" &>/dev/null; then
    echo "Erreur : '$tool' introuvable dans PATH." >&2
    exit 1
  fi
done

echo "Outils : dart $(dart --version 2>&1 | head -1 | awk '{print $4}')"
echo ""

# Contrôle de cohérence : la version affichée par --version doit suivre
# pubspec.yaml (lib/src/version.dart est maintenu à la main).
CODE_VERSION="$(sed -n "s/^const appVersion = '\(.*\)';/\1/p" lib/src/version.dart)"
if [[ "$CODE_VERSION" != "$DEFAULT_VERSION" ]]; then
  echo "  ⚠  lib/src/version.dart ($CODE_VERSION) ≠ pubspec.yaml ($DEFAULT_VERSION)" >&2
fi

# ── Dépendances, analyse statique et tests ───────────────────────────────────
echo "▶ Dépendances (dart pub get)…"
dart pub get 2>&1 | tail -1 | sed 's/^/  /'
if [[ "$RUN_TESTS" == true ]]; then
  echo "▶ Analyse statique (dart analyze)…"
  dart analyze --fatal-infos 2>&1 | tail -1 | sed 's/^/  /'
  echo "▶ Tests (dart test)…"
  dart test 2>&1 | tail -1 | sed 's/^/  /'
fi
echo ""

# ── Nettoyage ────────────────────────────────────────────────────────────────
rm -rf "${DIST_DIR:?}"
mkdir -p "${DIST_DIR}/bin" "${DIST_DIR}/doc"

# ── CLI : dart compile exe ───────────────────────────────────────────────────
echo "▶ Compilation du CLI (dart compile exe)…"
dart compile exe bin/check_script.dart -o "${DIST_DIR}/bin/check-script" 2>&1 |
  grep -v "^$" | sed 's/^/  /'
chmod +x "${DIST_DIR}/bin/check-script"
CLI_SIZE=$(du -sh "${DIST_DIR}/bin/check-script" | cut -f1)
echo "  ✓ check-script (${CLI_SIZE})"
echo ""

# ── Ressources ───────────────────────────────────────────────────────────────
echo "▶ Ajout des ressources…"
cp doc/user.adoc doc/developer.adoc doc/checkscript.example.yaml "${DIST_DIR}/doc/"
echo "  ✓ doc/ (user.adoc, developer.adoc, checkscript.example.yaml)"
cp README.md CHANGELOG.md "${DIST_DIR}/"
echo "  ✓ README.md / CHANGELOG.md"
cp "${SCRIPT_DIR}/install.sh" "${SCRIPT_DIR}/uninstall.sh" "${DIST_DIR}/"
chmod +x "${DIST_DIR}/install.sh" "${DIST_DIR}/uninstall.sh"
echo "  ✓ install.sh / uninstall.sh"

# SBOM (CycloneDX) : arbre des dépendances Dart (pubspec.lock). Le CLI est un
# binaire Dart autonome, sans dépendance runtime distro à déclarer ; les
# outils d'analyse (shellcheck…) sont facultatifs et détectés à l'exécution.
if [[ "$HAVE_SBOM_GENERATOR" == true ]]; then
  SBOM_REFS="$(mktemp)"
  trap 'rm -f "$SBOM_REFS"' EXIT
  echo "${PROJECT_DIR}/pubspec.lock" >"$SBOM_REFS"
  if sbom-generator -i "$SBOM_REFS" -f cyclonedx \
    -o "${DIST_DIR}/sbom.cdx.json" \
    -n "${DIST_NAME}-sbom" 2>&1 | sed 's/^/  /'; then
    echo "  ✓ sbom.cdx.json (SBOM CycloneDX : arbre pub)"
  else
    echo "  ⚠  Échec de la génération du SBOM — le packaging continue sans." >&2
  fi
fi
echo ""

# ── Scan CVE du SBOM + PDF de synthèse ───────────────────────────────────────
echo "▶ Scan CVE du SBOM (Grype + OSV-Scanner + Trivy)…"
SCAN_PDF="${PROJECT_DIR}/dist/${DIST_NAME}-scan-report.pdf"
run_scan_report "${DIST_DIR}/sbom.cdx.json" "$SCAN_PDF"
echo ""

# ── Archive ──────────────────────────────────────────────────────────────────
echo "▶ Création de l'archive…"
tar czf "$ARCHIVE" -C "${PROJECT_DIR}/dist" "${DIST_NAME}"
TOTAL_SIZE=$(du -sh "$ARCHIVE" | cut -f1)
echo "  ✓ ${ARCHIVE} (${TOTAL_SIZE})"
echo ""

# ── Installation locale (--install) ──────────────────────────────────────────
if [[ "$DO_INSTALL" == true ]]; then
  echo "▶ Installation locale (~/.local)…"
  bash "${DIST_DIR}/install.sh"
  echo ""
fi

# ── Résumé ───────────────────────────────────────────────────────────────────
echo "✅ Distribution prête !"
echo ""
echo "  dist/${DIST_NAME}.tar.gz (${TOTAL_SIZE})"
if [[ -f "$SCAN_PDF" ]]; then
  echo "  dist/${DIST_NAME}-scan-report.pdf (synthèse CVE Grype + OSV-Scanner + Trivy)"
elif [[ -f "${SCAN_PDF%.pdf}.adoc" ]]; then
  echo "  dist/${DIST_NAME}-scan-report.adoc (synthèse CVE — PDF non généré, asciidoctor-pdf absent)"
fi
if [[ -f "${DIST_DIR}/sbom.cdx.json" ]]; then
  echo "    └─ inclut sbom.cdx.json (SBOM CycloneDX : arbre pub)"
fi
echo ""
echo "Contenu de l'archive :"
tar tf "$ARCHIVE" | sed 's/^/  /'
echo ""
echo "Pour installer sur la machine cible :"
echo "  tar xzf ${DIST_NAME}.tar.gz"
echo "  cd ${DIST_NAME}"
echo "  ./install.sh              # installation utilisateur (~/.local)"
echo "  sudo ./install.sh         # installation système (/usr/local)"
