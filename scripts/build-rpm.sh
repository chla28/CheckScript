#!/usr/bin/env bash
# build-rpm.sh — Génère les RPM de CheckScript (build natif sur cette machine)
#
# Usage : ./scripts/build-rpm.sh [--package=cli|gui|all] [VERSION]
#
#   --package=cli   check-script (CLI)
#   --package=gui   check-script-gui (interface Flutter)
#   --package=all   les deux (défaut)
#   VERSION         défaut : version de pubspec.yaml
#
# Sorties : dist/rpm/<distribution>/*.rpm
#
# Les specs (packaging/rpm/) recompilent depuis une archive `git archive HEAD` :
# seules les modifications commitées sont incluses. Prérequis : rpm-build,
# SDK Dart (CLI), SDK Flutter + gtk3-devel, cmake, ninja-build, clang (GUI),
# asciidoctor (page de manuel).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SPEC_DIR="${PROJECT_DIR}/packaging/rpm"

PACKAGE="all"
VERSION=""
for arg in "$@"; do
  case "$arg" in
  --package=*) PACKAGE="${arg#--package=}" ;;
  --help | -h)
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  -*)
    echo "Option inconnue : $arg" >&2
    exit 1
    ;;
  *)
    if [[ -z "$VERSION" ]]; then
      VERSION="$arg"
    else
      echo "Argument inconnu : $arg" >&2
      exit 1
    fi
    ;;
  esac
done
case "$PACKAGE" in
cli | gui | all) ;;
*)
  echo "Paquet inconnu : $PACKAGE (attendu : cli, gui, all)" >&2
  exit 1
  ;;
esac
[[ -z "$VERSION" ]] && VERSION="$(awk '/^version:/ {print $2; exit}' "${PROJECT_DIR}/pubspec.yaml")"
VERSION="${VERSION%%+*}"

command -v rpmbuild &>/dev/null || {
  echo "Error: rpmbuild not found (sudo dnf install rpm-build)." >&2
  exit 1
}
DIST_TAG="$(rpm --eval '%{?dist}' | sed 's/^\.//')"
DIST_TAG="${DIST_TAG:-native}"

echo "╔══════════════════════════════════════════╗"
echo "║  CheckScript — Build RPM                 ║"
echo "╚══════════════════════════════════════════╝"
echo "Version: ${VERSION}"
echo "Paquet  : ${PACKAGE}"
echo "Distrib : ${DIST_TAG}"
echo ""

TOPDIR="${PROJECT_DIR}/dist/rpmbuild"
OUTDIR="${PROJECT_DIR}/dist/rpm/${DIST_TAG}"
rm -rf "${TOPDIR:?}" "${OUTDIR:?}"
mkdir -p "${TOPDIR}"/{SOURCES,SPECS,BUILD,BUILDROOT,RPMS,SRPMS} "$OUTDIR"

echo "▶ Source archive (git archive HEAD)…"
cd "$PROJECT_DIR" || exit 1
git rev-parse HEAD &>/dev/null || {
  echo "Error: no commit — cannot create the source archive." >&2
  exit 1
}
git archive --format=tar.gz --prefix="check_script-${VERSION}/" HEAD \
  -o "${TOPDIR}/SOURCES/check_script-${VERSION}.tar.gz"
echo "  ✓ SOURCES/check_script-${VERSION}.tar.gz (committed content only)"
echo ""

specs=()
[[ "$PACKAGE" == "cli" || "$PACKAGE" == "all" ]] && specs+=("check-script.spec")
[[ "$PACKAGE" == "gui" || "$PACKAGE" == "all" ]] && specs+=("check-script-gui.spec")

for spec in "${specs[@]}"; do
  echo "▶ rpmbuild : ${spec}"
  log="${TOPDIR}/${spec%.spec}.log"
  # LC_ALL=C : messages en anglais (filtrage fiable) ; journal complet conservé.
  if ! LC_ALL=C rpmbuild -bb --define "_topdir ${TOPDIR}" --define "version ${VERSION}" \
    "${SPEC_DIR}/${spec}" >"$log" 2>&1; then
    echo "  ✗ failed — last lines of ${log#"${PROJECT_DIR}"/} :" >&2
    tail -n 20 "$log" | sed 's/^/    /' >&2
    exit 1
  fi
  grep -E '^Wrote:' "$log" | sed 's|^Wrote: .*/|  ✓ |'
done
find "${TOPDIR}/RPMS" -name '*.rpm' -exec cp {} "$OUTDIR/" \;
echo ""
echo "✅ RPM :"
find "$OUTDIR" -name '*.rpm' | sort | sed "s|^${PROJECT_DIR}/|  |"
