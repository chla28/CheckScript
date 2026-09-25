#!/bin/sh
# Lanceur Flatpak de l'interface : fichiers temporaires dans le cache de
# l'application (même chemin dans le bac à sable et sur l'hôte, où tournent
# les outils d'analyse).
TMPDIR="${XDG_CACHE_HOME:-$HOME/.var/app/${FLATPAK_ID}/cache}/tmp"
export TMPDIR
mkdir -p "$TMPDIR"
exec /app/lib/check_script/check_script_gui "$@"
