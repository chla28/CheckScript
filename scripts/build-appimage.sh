#!/usr/bin/env bash
# build-appimage.sh — Construit l'AppImage de CheckScript (interface + CLI).
#
# Usage : ./scripts/build-appimage.sh [--skip-build]
#   --skip-build   réutilise le bundle Flutter de gui/build
#
# Sortie : dist/CheckScript-VERSION-ARCH.AppImage
#   ./CheckScript-….AppImage [FICHIER]      interface graphique
#   ./CheckScript-….AppImage --cli …        ligne de commande
#
# Prérequis : flutter, dart ; appimagetool (dans le PATH, variable
# APPIMAGETOOL, ou téléchargé dans build/appimage/). GTK 3 et les outils
# d'analyse sont ceux du système qui exécute l'AppImage. Pour une large
# compatibilité, construire sur la distribution la plus ancienne visée : la
# glibc minimale requise est affichée.
set -euo pipefail
# shellcheck source=scripts/package-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/package-common.sh"

SKIP_BUILD=0
for arg in "$@"; do
  case "$arg" in
  --skip-build) SKIP_BUILD=1 ;;
  --help | -h) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Option inconnue : $arg" >&2; exit 1 ;;
  esac
done

WORK="$PROJECT_DIR/build/appimage"
APPDIR="$WORK/CheckScript.AppDir"
OUT="$PROJECT_DIR/dist/CheckScript-${VERSION}-${ARCH}.AppImage"

TOOL="${APPIMAGETOOL:-$(command -v appimagetool || true)}"
if [[ -z "$TOOL" ]]; then
  TOOL="$WORK/appimagetool-${ARCH}.AppImage"
  if [[ ! -x "$TOOL" ]]; then
    echo "→ téléchargement d'appimagetool"
    mkdir -p "$WORK"
    curl -fsSL -o "$TOOL.part" \
      "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage"
    mv "$TOOL.part" "$TOOL"
    chmod +x "$TOOL"
  fi
fi

echo "CheckScript $VERSION — AppImage ($ARCH)"
build_binaries "$WORK/staging"

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/lib" "$APPDIR/usr/bin" \
  "$APPDIR/usr/share/applications" "$APPDIR/usr/share/metainfo" \
  "$APPDIR/usr/share/icons/hicolor/scalable/apps"
cp -r "$WORK/staging/bundle" "$APPDIR/usr/lib/check_script"
install -m755 "$WORK/staging/check-script-cli" "$APPDIR/usr/bin/check-script"
install -m755 "$PROJECT_DIR/packaging/appimage/AppRun" "$APPDIR/AppRun"
install -m644 "$PROJECT_DIR/packaging/linux/$APP_ID.desktop" "$APPDIR/$APP_ID.desktop"
install -m644 "$PROJECT_DIR/packaging/linux/$APP_ID.desktop" "$APPDIR/usr/share/applications/"
install -m644 "$PROJECT_DIR/packaging/linux/$APP_ID.metainfo.xml" \
  "$APPDIR/usr/share/metainfo/$APP_ID.appdata.xml"
install -m644 "$PROJECT_DIR/assets/check_script.svg" "$APPDIR/$APP_ID.svg"
install -m644 "$PROJECT_DIR/assets/check_script.svg" \
  "$APPDIR/usr/share/icons/hicolor/scalable/apps/$APP_ID.svg"
ln -sf "$APP_ID.svg" "$APPDIR/.DirIcon"
install -Dm644 "$PROJECT_DIR/LICENSE" "$APPDIR/usr/share/licenses/$APP_ID/LICENSE"
glibc_report "$APPDIR"

echo "→ appimagetool"
mkdir -p "$(dirname "$OUT")"
# Sans FUSE (conteneur, CI) : appimagetool s'extrait puis s'exécute.
if ! ARCH="$ARCH" APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" --no-appstream "$APPDIR" "$OUT" \
  >"$WORK/appimagetool.log" 2>&1; then
  cat "$WORK/appimagetool.log" >&2
  exit 1
fi
echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
echo "  interface : $OUT    ligne de commande : $OUT --cli --help"
