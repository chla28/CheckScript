#!/usr/bin/env bash
# Bibliothèque de fonctions de journalisation et de vérification.
# À sourcer : . lib/log.sh
set -euo pipefail

# Affiche un message horodaté sur la sortie d'erreur.
log() {
  local level="$1"
  shift
  printf '%s [%s] %s\n' "$(date '+%F %T')" "$level" "$*" >&2
}

# Vérifie qu'une commande est disponible, sinon arrête le script.
require() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log ERROR "commande requise absente : $cmd"
      exit 1
    fi
  done
}

# Exécute une commande en journalisant son code de retour.
run() {
  log INFO "exécution : $*"
  if "$@"; then
    log INFO "succès : $1"
  else
    local rc=$?
    log ERROR "échec ($rc) : $1"
    return "$rc"
  fi
}
