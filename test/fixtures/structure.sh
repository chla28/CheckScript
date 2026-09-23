#!/bin/bash
# Script de test pour l'arbre syntaxique.
long_function() {
  local f
  for f in ./*; do
    name=$(basename "$f")
    if [ -d "$f" ]; then
      while read -r line; do
        case "$line" in
          x) if true; then echo "$name"; fi ;;
        esac
      done < "$f"
    fi
  done
}
cd /tmp
cd /opt || exit 1
which ls
egrep a file
read answer
eval "$cmd"
eval echo fixe
set -x
if mkdir /tmp/x; then :; fi
mkdir /tmp/y
echo "which is only text"
long_function
