#!/usr/bin/env python3
"""Sauvegarde nocturne de /srv vers le NAS (lancée par cron)."""

import datetime
import os
import subprocess
import sys

DEST = "backup@nas.example:/volume1/srv"
EXCLUDES = ["*.tmp", "cache/"]


def rsync(src, dest):
    args = ["rsync", "-a", "--delete"]
    for e in EXCLUDES:
        args += ["--exclude", e]
    args += [src, dest]
    return subprocess.call(args)


def rotate_logs(directory, keep=7):
    files = sorted(os.listdir(directory))
    for name in files[:-keep]:
        os.remove(os.path.join(directory, name))


def main():
    stamp = datetime.datetime.now().strftime("%Y%m%d")
    log = open("/var/log/backup-%s.log" % stamp, "a")
    log.write("début %s\n" % datetime.datetime.now())
    rc = rsync("/srv/", DEST)
    if rc != 0:
        log.write("échec rsync : %d\n" % rc)
        sys.exit(1)
    rotate_logs("/var/log/backups")
    log.write("fin\n")
    log.close()


if __name__ == "__main__":
    main()
