#!/bin/sh
# Démarre ou arrête le service démo.
set -eu

function start {
  local pid
  if [[ -f /run/demo.pid ]]; then
    echo -e "déjà démarré\n"
    return 0
  fi
  /usr/local/bin/demo &> /var/log/demo.log &
  echo $! > /run/demo.pid
}

stop() {
  kill "$(cat /run/demo.pid)" && rm -f /run/demo.pid
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  *) echo "usage: $0 start|stop" >&2; exit 2 ;;
esac
