#!/usr/bin/env bash
# build-flatpak.sh — Construit le Flatpak de CheckScript (interface + CLI).
#
# Usage : ./scripts/build-flatpak.sh [--install] [--skip-build]
#   --install      installe aussi le Flatpak pour l'utilisateur
#   --skip-build   réutilise le bundle Flutter de gui/build
#
# Sortie : dist/CheckScript-VERSION-ARCH.flatpak
#
# Prérequis : flutter, dart, et flatpak-builder (dnf install flatpak-builder,
# ou flatpak install flathub org.flatpak.Builder). Le runtime
# org.gnome.Platform et son SDK (voir packaging/flatpak/*.yml) sont installés
# au besoin depuis Flathub, pour l'utilisateur.
#
# Dans le Flatpak, les outils d'analyse sont ceux de l'hôte (flatpak-spawn
# --host) : les installer sur le système comme pour la version native.
set -euo pipefail
# shellcheck source=scripts/package-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/package-common.sh"

INSTALL=false
SKIP_BUILD=0
for arg in "$@"; do
  case "$arg" in
  --install) INSTALL=true ;;
  --skip-build) SKIP_BUILD=1 ;;
  --help | -h) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Option inconnue : $arg" >&2; exit 1 ;;
  esac
done

MANIFEST="$PROJECT_DIR/packaging/flatpak/$APP_ID.yml"
WORK="$PROJECT_DIR/build/flatpak"
STAGING="$WORK/staging"
OUT="$PROJECT_DIR/dist/CheckScript-${VERSION}-${ARCH}.flatpak"

if command -v flatpak-builder >/dev/null; then
  FB=(flatpak-builder)
elif flatpak info org.flatpak.Builder >/dev/null 2>&1; then
  FB=(flatpak run org.flatpak.Builder)
else
  echo "flatpak-builder introuvable : dnf install flatpak-builder" >&2
  echo "  (ou : flatpak install flathub org.flatpak.Builder)" >&2
  exit 1
fi

echo "CheckScript $VERSION — Flatpak $APP_ID ($ARCH)"
build_binaries "$STAGING"
cp "$PROJECT_DIR/packaging/flatpak/check-script-gui.sh" \
  "$PROJECT_DIR/packaging/flatpak/check-script.sh" \
  "$PROJECT_DIR/packaging/linux/$APP_ID.desktop" \
  "$PROJECT_DIR/packaging/linux/$APP_ID.metainfo.xml" \
  "$PROJECT_DIR/assets/check_script.svg" "$STAGING/"
glibc_report "$STAGING"

# Dépôt Flathub pour l'utilisateur (runtime et SDK).
flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo

echo "→ flatpak-builder"
"${FB[@]}" --user --install-deps-from=flathub --force-clean --disable-rofiles-fuse \
  --repo="$WORK/repo" "$WORK/build" "$MANIFEST"

mkdir -p "$(dirname "$OUT")"
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  "$WORK/repo" "$OUT" "$APP_ID"
echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"

if $INSTALL; then
  flatpak install --user -y --reinstall "$OUT"
  echo "✓ installé : flatpak run $APP_ID"
  echo "  CLI : flatpak run --command=check-script $APP_ID script.sh"
fi
