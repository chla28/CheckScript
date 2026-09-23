#!/usr/bin/env bash
# build-dist.sh — Compile et package RHSA Checker pour Linux
# Produit : dist/rhsa_checker-VERSION-linux-ARCH.tar.gz
#             (inclut un SBOM CycloneDX : dépendances runtime + arbre pub —
#              sbom.cdx.json — si l'outil externe `sbom-generator` est présent)
#           dist/rpm/fedora44/*.rpm  (avec --rpm)
#             + dist/rhsa_checker-VERSION-linux-ARCH-rpms.cdx.json
#               (SBOM CycloneDX des RPM produits ; à côté, pas dans l'archive)
#
# Contenu de l'archive :
#   bin/rhsa-checker        CLI (Dart, autonome)
#   gui/                    application Flutter (bundle release)
#   sbom.cdx.json           SBOM CycloneDX (deps runtime + arbre pub) — si
#                           l'outil externe `sbom-generator` est présent
#   install.sh / uninstall.sh
#
# À côté de l'archive, un rapport PDF de synthèse CVE du SBOM est aussi
# produit (dist/…-scan-report.pdf, et …-rpms-scan-report.pdf avec --rpm)
# via `sbom-generator scan` + Grype/OSV-Scanner/Trivy — best-effort,
# instantané daté, sauté si aucun scanner n'est installé.
#
# Le SBOM est généré via l'outil externe `sbom-generator` (non fourni par ce
# dépôt) s'il est présent dans le PATH ; sinon, un avertissement est affiché
# et le packaging continue sans SBOM.
#
# Usage : ./scripts/build-dist.sh [VERSION] [--rpm] [--install]
#   --install : après un build réussi, installe le livrable dans ~/.local
#               (lance dist/<paquet>/install.sh)
#   VERSION : numéro de version (défaut : version de pubspec.yaml)
#   --rpm   : génère également les paquets RPM (délègue à scripts/build-rpm.sh
#             --target=fedora44 ; nécessite rpm-build). Les specs vivent dans
#             packaging/rpm/ et recompilent depuis une archive source git ;
#             build-rpm.sh gère aussi les cibles conteneurisées el9/el10.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

DEFAULT_VERSION="$(grep -m1 '^version:' "$PROJECT_DIR/pubspec.yaml" | awk '{print $2}')"
DEFAULT_VERSION="${DEFAULT_VERSION%%+*}"
VERSION="$DEFAULT_VERSION"
BUILD_RPM=false
DO_INSTALL=false

for _arg in "$@"; do
  case "$_arg" in
    --rpm)     BUILD_RPM=true ;;
    --install) DO_INSTALL=true ;;
    --help|-h)
      echo "Usage: $0 [VERSION] [--rpm] [--install]"
      echo "  --install  après le build, installe le livrable dans ~/.local (dist/<paquet>/install.sh)"
      echo "  VERSION  numéro de version (défaut: ${DEFAULT_VERSION}, lu depuis pubspec.yaml)"
      echo "  --rpm    génère les RPMs en plus du tar.gz (via scripts/build-rpm.sh --target=fedora44)"
      exit 0 ;;
    -*)        echo "Option inconnue : $_arg" >&2; exit 1 ;;
    *)         VERSION="$_arg" ;;
  esac
done
unset _arg

# ── Version injectee dans le bundle Flutter (lue par MainGUI) ──────────────
# MainGUI lit data/flutter_assets/version.json, ecrit par `flutter build`
# depuis --build-name (sinon depuis le champ version: du pubspec, parfois
# fige). On force --build-name au VERSION calcule ci-dessus pour que la
# version affichee suive la release. Le build-number reste celui du pubspec.
FLUTTER_VERSION_ARGS=()
_vbase="${VERSION#v}"; _vbase="${_vbase%%[-+]*}"
[[ "$_vbase" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] && FLUTTER_VERSION_ARGS=(--build-name="$_vbase")
unset _vbase || true

ARCH="$(uname -m)"
DIST_NAME="rhsa_checker-${VERSION}-linux-${ARCH}"
DIST_DIR="${PROJECT_DIR}/dist/${DIST_NAME}"
ARCHIVE="${PROJECT_DIR}/dist/${DIST_NAME}.tar.gz"

cd "$PROJECT_DIR"

# Scanne un SBOM avec Grype + OSV-Scanner + Trivy (best-effort : chaque scanner
# absent est simplement omis) et produit un PDF de synthèse via
# `sbom-generator scan -f pdf`. Le PDF est déposé À CÔTÉ de l'archive dans
# dist/ (instantané CVE daté, pas un livrable figé). N'échoue jamais le build :
# si `sbom-generator`, tout scanner ou asciidoctor-pdf manque, on saute (le
# .adoc est conservé si seul asciidoctor-pdf manque).
#   $1 = chemin du SBOM      $2 = chemin du PDF de sortie
run_scan_report() {
  local sbom="$1" pdf="$2"
  [[ "$HAVE_SBOM_GENERATOR" == true ]] || return 0
  if [[ ! -f "$sbom" ]]; then
    echo "  ⚠  SBOM introuvable ($sbom) — scan sauté." >&2
    return 0
  fi
  if ! command -v grype &>/dev/null \
     && ! command -v osv-scanner &>/dev/null \
     && ! command -v trivy &>/dev/null; then
    echo "  ⚠  Aucun scanner (grype / osv-scanner / trivy) — scan CVE sauté." >&2
    return 0
  fi
  # `scan -f pdf` sort 0 dès qu'un rapport est produit (même avec des CVE) ; si
  # asciidoctor-pdf manque, le .adoc est conservé à côté. Chaque CVE Critical
  # (rouge) / High (orange) est listée sur stdout : on force la couleur si le
  # terminal du build la supporte (le `sed` la préserve).
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
echo "║  RHSA Checker — Build distribution       ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Version : ${VERSION}"
echo "Arch    : ${ARCH}"
echo "Sortie  : dist/${DIST_NAME}.tar.gz"
[[ "$BUILD_RPM" == true ]] && echo "RPM     : oui (dist/rpm/fedora44/)"

# sbom-generator est un outil externe (non fourni par ce dépôt) : optionnel,
# le packaging reste utilisable sans lui, avec un simple avertissement.
HAVE_SBOM_GENERATOR=false
if command -v sbom-generator &>/dev/null; then
  HAVE_SBOM_GENERATOR=true
  echo "SBOM    : oui (sbom-generator détecté, CycloneDX)"
else
  echo "SBOM    : non ('sbom-generator' introuvable dans PATH)"
fi
echo ""

_required_tools=(dart flutter tar)
[[ "$BUILD_RPM" == true ]] && _required_tools+=(rpmbuild)
for tool in "${_required_tools[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    echo "Erreur : '$tool' introuvable dans PATH." >&2
    [[ "$tool" == "rpmbuild" ]] && echo "  Installez : sudo dnf install rpm-build" >&2
    exit 1
  fi
done
unset _required_tools

echo "Outils : dart $(dart --version 2>&1 | head -1 | awk '{print $4}') • $(flutter --version 2>&1 | head -1)"
echo ""

# ── Nettoyage ────────────────────────────────────────────────────────────────
rm -rf "$DIST_DIR"
mkdir -p "${DIST_DIR}/bin" "${DIST_DIR}/gui"

# ── CLI : dart compile exe ───────────────────────────────────────────────────
echo "▶ Compilation du CLI (dart compile exe)…"
dart compile exe bin/rhsa_checker.dart -o "${DIST_DIR}/bin/rhsa-checker" 2>&1 \
  | grep -v "^$" | sed 's/^/  /'
chmod +x "${DIST_DIR}/bin/rhsa-checker"
CLI_SIZE=$(du -sh "${DIST_DIR}/bin/rhsa-checker" | cut -f1)
echo "  ✓ rhsa-checker (${CLI_SIZE})"
echo ""

# ── GUI : flutter build linux --release ─────────────────────────────────────
echo "▶ Build du GUI Flutter (release)…"
cd gui
# `flutter clean` d'abord : le cache CMake de gui/build/ mémorise le chemin
# absolu du projet et fait échouer le build si l'arborescence a été déplacée
# ou clonée ailleurs ("CMakeCache.txt directory ... is different").
flutter clean 2>&1 | sed 's/^/  /'
flutter build linux --release ${FLUTTER_VERSION_ARGS[@]+"${FLUTTER_VERSION_ARGS[@]}"} 2>&1 \
  | grep -E "^\s*(✓|Building|error|warning|▶)" | sed 's/^/  /'
cp -r build/linux/x64/release/bundle/. "${DIST_DIR}/gui/"
chmod +x "${DIST_DIR}/gui/rhsa_checker_gui"
cd "$PROJECT_DIR"
GUI_SIZE=$(du -sh "${DIST_DIR}/gui" | cut -f1)
echo "  ✓ rhsa_checker_gui + libs (${GUI_SIZE})"
echo ""

# ── Ressources ───────────────────────────────────────────────────────────────
echo "▶ Ajout des ressources…"

# Icône SVG
if [[ -f "${PROJECT_DIR}/assets/rhsa_checker.svg" ]]; then
  cp "${PROJECT_DIR}/assets/rhsa_checker.svg" "${DIST_DIR}/gui/"
  echo "  ✓ rhsa_checker.svg"
fi

# Fichier .desktop (l'Exec sera réécrit à l'installation)
cat > "${DIST_DIR}/gui/rhsa_checker.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=RHSA Checker
GenericName=Analyseur de sécurité RHEL
Comment=Identifie les RHSA applicables à une liste de RPMs RHEL via les données OVAL Red Hat
Exec=rhsa-checker-gui
Icon=rhsa_checker
Categories=System;Security;Utility;
Keywords=rhel;rpm;rhsa;cve;security;oval;
Terminal=false
StartupNotify=true
DESKTOP
echo "  ✓ rhsa_checker.desktop"

# Scripts install / uninstall
cp "${SCRIPT_DIR}/install.sh"   "${DIST_DIR}/"
cp "${SCRIPT_DIR}/uninstall.sh" "${DIST_DIR}/"
chmod +x "${DIST_DIR}/install.sh" "${DIST_DIR}/uninstall.sh"
echo "  ✓ install.sh / uninstall.sh"

# SBOM (CycloneDX) : dépendances runtime du GUI (paquets distro, alignées sur
# les `Requires:` de packaging/rpm/rhsa-checker-gui.spec) + arbre des
# dépendances Dart/Flutter (tous les pubspec.lock du projet). Le CLI est un
# binaire Dart statique, sans dépendance runtime distro à déclarer.
if [[ "$HAVE_SBOM_GENERATOR" == true ]]; then
  SBOM_REFS="$(mktemp)"
  cat > "$SBOM_REFS" <<'PKGS'
gtk3
libsecret
xdg-utils
glibc
PKGS
  find "$PROJECT_DIR" -name pubspec.lock \
    -not -path '*/build/*' -not -path '*/.dart_tool/*' | sort >> "$SBOM_REFS"
  if sbom-generator -i "$SBOM_REFS" -f cyclonedx \
       -o "${DIST_DIR}/sbom.cdx.json" \
       -n "${DIST_NAME}-sbom" 2>&1 | sed 's/^/  /'; then
    echo "  ✓ sbom.cdx.json (SBOM CycloneDX : deps runtime + arbre pub)"
  else
    echo "  ⚠  Échec de la génération du SBOM — le packaging continue sans." >&2
  fi
  rm -f "$SBOM_REFS"
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

# ── RPM (optionnel) ──────────────────────────────────────────────────────────
# Les specs (packaging/rpm/) recompilent depuis une archive source git, pas
# depuis l'archive binaire ci-dessus : on délègue à build-rpm.sh, qui pilote
# aussi les cibles conteneurisées el9/el10. Ici, cible native fedora44.
if [[ "$BUILD_RPM" == true ]]; then
  echo "▶ Génération des RPMs (scripts/build-rpm.sh --target=fedora44)…"
  "${SCRIPT_DIR}/build-rpm.sh" --target=fedora44 --package=all "$VERSION"
  echo ""

  # SBOM (CycloneDX) des RPM effectivement construits. Ne peut pas être inclus
  # dans l'archive tar.gz (les RPM sont construits à partir d'elle) : placé à
  # côté, dans dist/.
  mapfile -t _rpms < <(find "${PROJECT_DIR}/dist/rpm/fedora44" -name '*.rpm' 2>/dev/null | sort)
  if [[ "$HAVE_SBOM_GENERATOR" == true && ${#_rpms[@]} -gt 0 ]]; then
    echo "▶ Génération du SBOM des RPM construits…"
    RPM_SBOM="${PROJECT_DIR}/dist/${DIST_NAME}-rpms.cdx.json"
    RPM_LIST="$(mktemp)"
    printf '%s\n' "${_rpms[@]}" > "$RPM_LIST"
    if sbom-generator -i "$RPM_LIST" -f cyclonedx -o "$RPM_SBOM" \
         -n "${DIST_NAME}-rpms" 2>&1 | sed 's/^/  /'; then
      echo "  ✓ $(realpath --relative-to="${PROJECT_DIR}" "$RPM_SBOM")"
    else
      echo "  ⚠  Échec de la génération du SBOM RPM — le packaging continue sans." >&2
    fi
    rm -f "$RPM_LIST"
    echo ""

    echo "▶ Scan CVE du SBOM des RPM construits…"
    run_scan_report "$RPM_SBOM" \
      "${PROJECT_DIR}/dist/${DIST_NAME}-rpms-scan-report.pdf"
    echo ""
  fi
  unset _rpms
fi

# ── Installation locale (--install) ──────────────────────────
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
  echo "    └─ inclut sbom.cdx.json (SBOM CycloneDX : deps runtime + arbre pub)"
fi
if [[ "$BUILD_RPM" == true ]]; then
  find "${PROJECT_DIR}/dist/rpm/fedora44" -name "*.rpm" 2>/dev/null | sort \
    | while IFS= read -r r; do echo "  $(realpath --relative-to="${PROJECT_DIR}" "$r")"; done
  if [[ -f "${PROJECT_DIR}/dist/${DIST_NAME}-rpms.cdx.json" ]]; then
    echo "  dist/${DIST_NAME}-rpms.cdx.json (SBOM CycloneDX des RPM ci-dessus)"
  fi
  if [[ -f "${PROJECT_DIR}/dist/${DIST_NAME}-rpms-scan-report.pdf" ]]; then
    echo "  dist/${DIST_NAME}-rpms-scan-report.pdf (synthèse CVE des RPM ci-dessus)"
  fi
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
if [[ "$BUILD_RPM" == true ]]; then
  echo ""
  echo "Installation via RPM :"
  echo "  sudo dnf install dist/rpm/fedora44/rhsa-checker-${VERSION}-1.*.rpm"
  echo "  sudo dnf install dist/rpm/fedora44/rhsa-checker-gui-${VERSION}-1.*.rpm"
fi
