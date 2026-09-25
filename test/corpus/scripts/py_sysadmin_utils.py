"""Fonctions utilitaires partagées par les scripts d'exploitation."""

import os
import pwd
import subprocess


def user_home(name):
    """Répertoire personnel de name, ou None s'il n'existe pas."""
    try:
        return pwd.getpwnam(name).pw_dir
    except KeyError:
        return None


def disk_alert_level(percent, critical_mounts, mount, weekend, night, oncall):
    """Niveau d'alerte d'un point de montage selon le contexte."""
    if percent > 95:
        if mount in critical_mounts:
            if oncall:
                return "page"
            elif night:
                return "sms"
            else:
                return "mail"
        elif weekend:
            return "mail"
        else:
            return "ticket"
    elif percent > 85:
        if mount in critical_mounts and not weekend:
            return "mail"
        elif night:
            return "none"
        else:
            return "ticket"
    elif percent > 75 and mount in critical_mounts:
        if weekend or night:
            return "none"
        return "log"
    return "none"


def service_restart(name):
    """Redémarre un service systemd."""
    return subprocess.run(["systemctl", "restart", name], check=True)


def is_root():
    """Vrai si le script tourne en root."""
    return os.geteuid() == 0
