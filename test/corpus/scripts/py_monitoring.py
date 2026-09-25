#!/usr/bin/env python3
"""Vérifie l'état de services systemd et envoie un résumé au journal.

Usage : py_monitoring.py SERVICE...
Code de sortie 2 si un service est inactif.
"""

import logging
import subprocess
import sys

LOG = logging.getLogger("svc-check")
SYSTEMCTL = "/usr/bin/systemctl"
TIMEOUT_S = 15


def is_active(service: str) -> bool:
    """Vrai si le service est actif (systemctl is-active)."""
    try:
        result = subprocess.run(
            [SYSTEMCTL, "is-active", "--quiet", service],
            check=False,
            timeout=TIMEOUT_S,
        )
    except subprocess.TimeoutExpired:
        LOG.error("%s : délai dépassé", service)
        return False
    return result.returncode == 0


def main(services: list[str]) -> int:
    """Contrôle chaque service ; 2 si l'un d'eux est inactif."""
    logging.basicConfig(level=logging.INFO)
    if not services:
        LOG.error("usage : svc-check SERVICE...")
        return 64
    down = [s for s in services if not is_active(s)]
    for service in down:
        LOG.warning("%s inactif", service)
    LOG.info("%d/%d services actifs", len(services) - len(down), len(services))
    return 2 if down else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
