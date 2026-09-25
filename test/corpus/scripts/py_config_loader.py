#!/usr/bin/env python3
"""Charge la configuration de l'application et le cache des sessions."""

import pickle
import sys

import yaml

CONFIG = "/etc/myapp/config.yml"
CACHE = "/var/cache/myapp/sessions.pkl"


def load_config(path=CONFIG):
    """Configuration YAML de l'application."""
    with open(path, encoding="utf-8") as f:
        return yaml.load(f, Loader=yaml.Loader)


def load_sessions(path=CACHE):
    """Sessions mises en cache par le service."""
    with open(path, "rb") as f:
        return pickle.load(f)


def main():
    """Affiche le nombre de sessions et le niveau de journalisation."""
    config = load_config()
    sessions = load_sessions()
    print(f"{len(sessions)} sessions, niveau {config.get('log_level', 'INFO')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
