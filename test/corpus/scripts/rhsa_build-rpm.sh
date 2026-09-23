#!/usr/bin/env bash
# build-rpm.sh — Génère les RPMs CLI et/ou GUI de RHSA Checker
#
# Usage : ./scripts/build-rpm.sh [--target=fedora44|el9|el10] [--package=cli|gui|all] [VERSION]
#
#   --target=fedora44   Build natif sur cette machine (rpmbuild local, dart/flutter du PATH)
#   --target=el9        Build dans un conteneur podman UBI9  (glibc/GTK compatibles RHEL 9)
#   --target=el10       Build dans un conteneur podman UBI10 (glibc/GTK compatibles RHEL 10)
#   --package=cli        Ne construire que le CLI  (rhsa-checker)
#   --package=gui        Ne construire que le GUI  (rhsa-checker-gui)
#   --package=all         Construire les deux (défaut)
#   VERSION               Numéro de version (défaut : lu depuis pubspec.yaml)
#
# Sorties : dist/rpm/<target>/*.rpm
#
# Pourquoi des cibles séparées : Fedora 44 a une glibc/GTK plus récente que
# RHEL 9/10. Un binaire compilé sur Fedora 44 n'a aucune garantie de
# fonctionner sur RHEL 9/10 (compatibilité glibc à sens unique : un binaire
# lié à une glibc récente ne tourne pas sur une glibc plus ancienne). Les
# cibles el9/el10 compilent donc entièrement à l'intérieur d'un conteneur
# basé sur l'image UBI (Universal Base Image) correspondante, garantissant
# la compatibilité binaire réelle avec RHEL 9/10.
#
# ⚠ Les cibles el9/el10 nécessitent podman et un accès réseau (image UBI +
#   téléchargement du SDK Flutter dans le conteneur, ~1 Go, résolu
#   dynamiquement depuis releases_linux.json). Elles n'ont PAS été
#   exécutées/validées dans le cadre du développement de ce script — seule
#   la cible fedora44 (native, cette machine) l'a été. À valider avant tout
#   usage en production.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SPEC_DIR="${PROJECT_DIR}/packaging/rpm"

TARGET="fedora44"
PACKAGE="all"
VERSION=""

for arg in "$@"; do
  case "$arg" in
    --target=*)  TARGET="${arg#--target=}" ;;
    --package=*) PACKAGE="${arg#--package=}" ;;
    --help|-h)
      sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      if [[ -z "$VERSION" ]]; then VERSION="$arg";
      else echo "Argument inconnu : $arg" >&2; exit 1; fi
      ;;
  esac
done

case "$TARGET" in
  fedora44|el9|el10) ;;
  *) echo "Cible inconnue : $TARGET (attendu : fedora44, el9, el10)" >&2; exit 1 ;;
esac
case "$PACKAGE" in
  cli|gui|all) ;;
  *) echo "Paquet inconnu : $PACKAGE (attendu : cli, gui, all)" >&2; exit 1 ;;
esac

if [[ -z "$VERSION" ]]; then
  VERSION="$(grep -m1 '^version:' "${PROJECT_DIR}/pubspec.yaml" | awk '{print $2}')"
fi

echo "╔══════════════════════════════════════════╗"
echo "║  RHSA Checker — Build RPM               ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Version : ${VERSION}"
echo "Cible   : ${TARGET}"
echo "Paquet  : ${PACKAGE}"
echo ""

# Chaque cible utilise son propre topdir pour éviter qu'un build el9 ne
# ramasse par erreur des RPMs .fc44 laissés par un run précédent.
TOPDIR="${PROJECT_DIR}/dist/rpmbuild-${TARGET}"
OUTDIR="${PROJECT_DIR}/dist/rpm/${TARGET}"
# Nettoyage complet du topdir : sans cela, un RPMS/ d'un run précédent à une
# autre version reste sur le disque et se ferait ramasser avec la copie
# finale (glob sur RPMS/*/*.rpm), livrant deux versions à la fois.
rm -rf "$OUTDIR" "$TOPDIR"
mkdir -p "${TOPDIR}"/{SOURCES,SPECS,BUILD,BUILDROOT,RPMS,SRPMS} "$OUTDIR"

# ── Archive source (git archive HEAD) ────────────────────────────────────────
echo "▶ Archive source (git archive HEAD)…"
cd "$PROJECT_DIR"
if ! git rev-parse HEAD &>/dev/null; then
  echo "Erreur : pas un dépôt git (ou aucun commit) — impossible de créer l'archive source." >&2
  exit 1
fi
SRC_TARBALL="${TOPDIR}/SOURCES/rhsa_checker-${VERSION}.tar.gz"
git archive --format=tar.gz --prefix="rhsa_checker-${VERSION}/" HEAD -o "$SRC_TARBALL"
echo "  ✓ ${SRC_TARBALL}  (contenu suivi par git au commit courant — les"
echo "    modifications non committées ne sont pas incluses)"
echo ""

SPECS=()
[[ "$PACKAGE" == "cli" || "$PACKAGE" == "all" ]] && SPECS+=("rhsa-checker.spec")
[[ "$PACKAGE" == "gui" || "$PACKAGE" == "all" ]] && SPECS+=("rhsa-checker-gui.spec")

build_native() {
  for spec in "${SPECS[@]}"; do
    echo "▶ rpmbuild : ${spec}"
    rpmbuild -bb \
      --define "_topdir ${TOPDIR}" \
      --define "version ${VERSION}" \
      "${SPEC_DIR}/${spec}"
    echo ""
  done
}

build_in_container() {
  local image="$1"
  echo "▶ Build dans un conteneur podman : ${image}"
  echo "  (accès réseau requis — SDK Dart et/ou Flutter téléchargés dans le conteneur)"
  echo ""

  local specs_csv
  specs_csv="$(IFS=,; echo "${SPECS[*]}")"

  # N'installer/télécharger que ce que le paquet demandé requiert : le GUI
  # (gtk3-devel, libsecret-devel, cmake, ninja-build, clang, SDK Flutter
  # complet ~1 Go) n'a pas de raison de bloquer ou ralentir un
  # --package=cli. Voir aussi le même principe pour --target=fedora44.
  #
  # IMPORTANT : gtk3-devel n'est PAS disponible dans les dépôts UBI publics
  # non authentifiés (BaseOS/AppStream/CodeReady Builder) ni via EPEL —
  # confirmé empiriquement (`dnf list available gtk3-devel` → aucune
  # correspondance dans les trois dépôts UBI9/UBI10, EPEL ne le fournit pas
  # non plus, ce paquet RHEL "plein" nécessitant un abonnement RHEL
  # authentifié via `subscription-manager register`, hors de portée d'un
  # script de build générique). **Le build GUI --target=el9/el10 échoue donc
  # systématiquement** avec cette image de base ; seul --package=cli
  # fonctionne. Voir doc/developer.adoc, section Packaging RPM.
  local need_cli=0 need_gui=0
  [[ "$PACKAGE" == "cli" || "$PACKAGE" == "all" ]] && need_cli=1
  [[ "$PACKAGE" == "gui" || "$PACKAGE" == "all" ]] && need_gui=1

  local pkgs="rpm-build rpmdevtools git tar xz"
  [[ "$need_gui" -eq 1 ]] && pkgs+=" gtk3-devel libsecret-devel cmake ninja-build clang pkgconf-pkg-config"

  podman run --rm \
    -v "${TOPDIR}:/rpmbuild:Z" \
    -v "${SPEC_DIR}:/specs:Z,ro" \
    -e "VERSION=${VERSION}" \
    -e "SPECS_CSV=${specs_csv}" \
    -e "NEED_CLI=${need_cli}" \
    -e "NEED_GUI=${need_gui}" \
    -e "PKGS=${pkgs}" \
    "$image" bash -euo pipefail -c '
      dnf install -y $PKGS

      cd /opt
      if [[ "$NEED_GUI" -eq 1 ]]; then
        # SDK Flutter (fournit aussi `dart` via flutter/bin/) — resolu
        # dynamiquement depuis le flux officiel des releases stable Linux.
        curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json \
          -o releases_linux.json
        ARCHIVE="$(grep -o "\"archive\":\"stable/linux/flutter_linux_[^\"]*\.tar\.xz\"" releases_linux.json \
          | head -1 | cut -d\" -f4)"
        if [[ -z "$ARCHIVE" ]]; then
          echo "Erreur : impossible de déterminer larchive Flutter stable depuis releases_linux.json" >&2
          exit 1
        fi
        curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/${ARCHIVE}" -o flutter.tar.xz
        tar xf flutter.tar.xz
        export PATH="/opt/flutter/bin:${PATH}"
        flutter config --enable-linux-desktop --no-analytics
        flutter --version
      elif [[ "$NEED_CLI" -eq 1 ]]; then
        # SDK Dart seul (sans Flutter) : suffisant et bien plus léger pour
        # un build --package=cli isolé.
        curl -fsSL https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-x64-release.zip \
          -o dartsdk.zip
        dnf install -y unzip
        unzip -q dartsdk.zip
        export PATH="/opt/dart-sdk/bin:${PATH}"
        dart --version
      fi

      git config --global --add safe.directory "*"

      IFS="," read -ra SPECS_ARR <<< "${SPECS_CSV}"
      for spec in "${SPECS_ARR[@]}"; do
        echo "▶ rpmbuild : ${spec}"
        rpmbuild -bb \
          --define "_topdir /rpmbuild" \
          --define "version ${VERSION}" \
          "/specs/${spec}"
      done
    '
}

case "$TARGET" in
  fedora44)
    # `dart` n'est requis que pour le CLI et `flutter` que pour le GUI : ne pas
    # exiger flutter pour un build --package=cli isolé (ex: job CI léger qui
    # ne teste que le RPM CLI, sans installer le SDK Flutter).
    tools=(rpmbuild git)
    [[ "$PACKAGE" == "cli" || "$PACKAGE" == "all" ]] && tools+=(dart)
    [[ "$PACKAGE" == "gui" || "$PACKAGE" == "all" ]] && tools+=(flutter)
    for tool in "${tools[@]}"; do
      command -v "$tool" &>/dev/null || { echo "Erreur : '$tool' introuvable dans PATH." >&2; exit 1; }
    done
    build_native
    ;;
  el9)
    command -v podman &>/dev/null || { echo "Erreur : podman introuvable (requis pour --target=el9)." >&2; exit 1; }
    build_in_container "registry.access.redhat.com/ubi9/ubi:latest"
    ;;
  el10)
    command -v podman &>/dev/null || { echo "Erreur : podman introuvable (requis pour --target=el10)." >&2; exit 1; }
    build_in_container "registry.access.redhat.com/ubi10/ubi:latest"
    ;;
esac

# ── Collecte des RPMs produits ──────────────────────────────────────────────
echo "▶ Copie des RPMs vers ${OUTDIR}…"
shopt -s nullglob
RPMS=("${TOPDIR}"/RPMS/*/*.rpm)
shopt -u nullglob
if [[ ${#RPMS[@]} -eq 0 ]]; then
  echo "Erreur : aucun RPM produit dans ${TOPDIR}/RPMS/" >&2
  exit 1
fi
cp -v "${RPMS[@]}" "$OUTDIR/"
echo ""
echo "✅ RPMs disponibles dans dist/rpm/${TARGET}/"
ls -la "$OUTDIR"
