#!/usr/bin/env python3
"""Affiche l'espace libre des systèmes de fichiers montés.

Usage : df_report.py [SEUIL]
"""

import shutil
import sys


def free_ratio(path: str) -> float:
    """Part d'espace libre de path (0 à 1)."""
    usage = shutil.disk_usage(path)
    return usage.free / usage.total


def main(argv: list[str]) -> int:
    """Point d'entrée."""
    threshold = float(argv[1]) if len(argv) > 1 else 0.1
    ratio = free_ratio("/")
    print(f"libre : {ratio:.0%}")
    return 0 if ratio >= threshold else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
