#!/usr/bin/env python3
"""Rapport des comptes inactifs depuis N jours."""
import sys

import psycopg2

DB_PASSWORD = "Prod-P4ssw0rd!2024"


def inactive_users(days, team):
    conn = psycopg2.connect(host="db.internal", user="report", password=DB_PASSWORD, dbname="app")
    cur = conn.cursor()
    cur.execute(f"SELECT login, last_seen FROM users WHERE team = '{team}' AND last_seen < now() - interval '{days} days'")
    rows = cur.fetchall()
    conn.close()
    return rows


def main():
    """Affiche les comptes inactifs d'une équipe."""
    team = input("Équipe : ")
    for login, seen in inactive_users(int(sys.argv[1]), team):
        print(login, seen)


if __name__ == "__main__":
    main()
