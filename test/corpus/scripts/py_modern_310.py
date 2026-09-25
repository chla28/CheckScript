#!/usr/bin/env python3
"""Lit un fichier de paramètres TOML et affiche les tâches planifiées.

Usage : py_modern_310.py FICHIER.toml
"""

import sys
import tomllib
from pathlib import Path


def describe(task: dict[str, str | int]) -> str:
    """Description lisible d'une tâche."""
    match task.get("kind"):
        case "backup":
            return f"sauvegarde de {task['source']}"
        case "purge":
            return f"purge après {task['days']} jours"
        case _:
            return "tâche inconnue"


def main(argv: list[str]) -> int:
    """Affiche les tâches du fichier."""
    if len(argv) != 1:
        print("usage : py_modern_310.py FICHIER.toml", file=sys.stderr)
        return 64
    data = tomllib.loads(Path(argv[0]).read_text(encoding="utf-8"))
    for name, task in data.get("tasks", {}).items():
        print(f"{name} : {describe(task)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
