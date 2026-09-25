#!/usr/bin/env python3
"""Rapport d'occupation des systèmes de fichiers.

Usage : py_clean_cli.py [--threshold PCT] [--json] [MOUNT...]
Affiche les points de montage dont l'occupation dépasse le seuil.
"""

from __future__ import annotations

import argparse
import json
import logging
import shutil
import sys
from dataclasses import asdict, dataclass

log = logging.getLogger("df_report")


@dataclass(frozen=True)
class Usage:
    """Occupation d'un point de montage."""

    mount: str
    total: int
    used: int

    @property
    def percent(self) -> float:
        """Pourcentage utilisé (0 à 100)."""
        return 100.0 * self.used / self.total if self.total else 0.0


def measure(mount: str) -> Usage | None:
    """Mesure l'occupation de mount ; None s'il est inaccessible."""
    try:
        du = shutil.disk_usage(mount)
    except OSError as exc:
        log.warning("%s inaccessible : %s", mount, exc)
        return None
    return Usage(mount, du.total, du.used)


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Options de la ligne de commande."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--threshold", type=float, default=80.0)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("mounts", nargs="*", default=["/"])
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    """Point d'entrée : 1 si un point de montage dépasse le seuil."""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = parse_args(argv)
    usages = [u for u in map(measure, args.mounts) if u is not None]
    over = [u for u in usages if u.percent >= args.threshold]
    if args.json:
        print(json.dumps([asdict(u) for u in over], indent=2))
    else:
        for u in over:
            print(f"{u.mount}\t{u.percent:.1f} %")
    return 1 if over else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
