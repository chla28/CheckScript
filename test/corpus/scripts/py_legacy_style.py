#!/usr/bin/python
# -*- coding: utf-8 -*-
# Nettoyage des vieux fichiers d'export
import os, sys, time, string

EXPORT_DIR = "/data/exports"
MAX_AGE = 30


def old_files(dir, age=MAX_AGE, found=[]):
    now = time.time()
    for f in os.listdir(dir):
        p = os.path.join(dir, f)
        if os.path.isfile(p) and now - os.path.getmtime(p) > age * 86400:
            found.append(p)
    return found


def main():
    if len(sys.argv) > 1:
        dir = sys.argv[1]
    else:
        dir = EXPORT_DIR
    files = old_files(dir)
    print("%d fichiers à supprimer" % len(files))
    for f in files:
        try:
            os.remove(f)
        except:
            print("impossible de supprimer %s" % f)
    if len(files) == 0:
        return 0
    else:
        return 1


main()
