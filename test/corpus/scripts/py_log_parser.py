#!/usr/bin/env python3
"""Compte les codes HTTP d'un journal d'accès au format combined.

Usage : py_log_parser.py FICHIER
"""

import re
import sys
from collections import Counter

LINE = re.compile(r'"\w+ \S+ \S+" (\d{3}) ')


def status_codes(path):
    """Liste des codes HTTP trouvés dans le fichier."""
    codes = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = LINE.search(line)
            if m:
                codes.append(m.group(1))
    return codes


def summary(codes):
    """Occurrences par code, triées."""
    counts = {}
    for code in codes:
        if code in counts:
            counts[code] = counts[code] + 1
        else:
            counts[code] = 1
    result = []
    for code in sorted(counts.keys()):
        result.append((code, counts[code]))
    return result


def main():
    """Affiche le résumé du fichier passé en argument."""
    if len(sys.argv) != 2:
        print("usage : py_log_parser.py FICHIER", file=sys.stderr)
        return 64
    for code, n in summary(status_codes(sys.argv[1])):
        print(code, n)
    print("total", sum(Counter(status_codes(sys.argv[1])).values()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
