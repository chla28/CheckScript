#!/bin/sh
# Lanceur Flatpak de la ligne de commande :
#   flatpak run --command=check-script fr.chla28.check_script_gui script.sh
TMPDIR="${XDG_CACHE_HOME:-$HOME/.var/app/${FLATPAK_ID}/cache}/tmp"
export TMPDIR
mkdir -p "$TMPDIR"
exec /app/lib/check_script/check-script-cli "$@"
