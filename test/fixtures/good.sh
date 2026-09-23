#!/usr/bin/env bash
# Sauvegarde les fichiers de configuration dans une archive horodatée.
# Usage : good.sh <dossier-source> <dossier-destination>
set -euo pipefail

usage() {
  echo "Usage: ${0##*/} <source> <destination>" >&2
  exit 2
}

main() {
  [[ $# -eq 2 ]] || usage
  local src="$1" dest="$2" tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf -- "${tmp:?}"' EXIT

  # Archive dans un dossier temporaire puis déplacement atomique.
  tar -czf "$tmp/backup.tar.gz" -C "$src" .
  mv -- "$tmp/backup.tar.gz" "$dest/backup-$(date +%Y%m%d).tar.gz"
}

main "$@"
