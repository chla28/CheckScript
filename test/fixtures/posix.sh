#!/bin/sh
# Affiche les utilisateurs dont le shell est bash.
set -eu

function show {
  local name=$1
  if [[ $name == root ]]; then
    echo -e "admin:\t$name"
  fi
}

while IFS=: read -r user _ _ _ _ _ shell; do
  [ "$shell" = /bin/bash ] && show "$user"
done < /etc/passwd
