/// Exemples de correction « à éviter / à écrire » par règle : règles
/// intégrées et codes ShellCheck les plus fréquents. Ils sont affichés quand
/// aucune correction automatique ne s'applique au problème lui-même.
library;

import '../i18n.dart';

class CodeExample {
  /// Code fautif, puis code corrigé.
  final String bad, good;

  /// Variantes anglaises, quand le code contient du texte (commentaires,
  /// messages) ; à défaut, le même code sert dans les deux langues.
  final String? badEn, goodEn;

  const CodeExample(this.bad, this.good, {this.badEn, this.goodEn});

  String badOf(Lang lang) => lang == Lang.en ? badEn ?? bad : bad;
  String goodOf(Lang lang) => lang == Lang.en ? goodEn ?? good : good;
}

/// Exemple de correction d'une règle, ou null si aucun n'est rédigé.
CodeExample? exampleFor(String ruleId) =>
    ruleExamples[_aliases[ruleId] ?? _banditToRuff(ruleId) ?? ruleId];

/// Code Bandit → code Ruff de même numéro (`B602` → `S602`).
String? _banditToRuff(String id) {
  final m = RegExp(r'^B([1-7]\d\d)$').firstMatch(id);
  return m == null ? null : 'S${m[1]}';
}

/// Codes ShellCheck couverts par l'exemple d'une règle intégrée.
const Map<String, String> _aliases = {
  'SC2164': 'ROB005',
  'SC2162': 'ROB007',
  'SC2045': 'ROB008',
  'SC2115': 'SEC007',
  'SC2114': 'SEC008',
  'SC2006': 'MNT007',
  'SC2148': 'POR001',
  'SC2230': 'POR004',
  'SC2196': 'POR005',
  'SC2002': 'PERF001',
  'SC2126': 'PERF002',
  'SC2003': 'PERF003',
  'SC2009': 'PERF006',
  'SC2116': 'PERF008',
  // Pylint → code Ruff équivalent.
  'W0702': 'E722',
  'W0102': 'B006',
  'W0611': 'F401',
  'W0612': 'F841',
  'W0123': 'S307',
  'W0707': 'B904',
  'W1510': 'PLW1510',
  'W1514': 'PLW1514',
  'R1732': 'SIM115',
  'C0114': 'PYMNT001',
  'D100': 'PYMNT001',
  'EXE003': 'PYPOR001',
  'R0912': 'CC',
  'PLR0912': 'CC',
  'C901': 'CC',
};

const Map<String, CodeExample> ruleExamples = {
  // ── Sécurité ──────────────────────────────────────────────────────────────
  'SEC001': CodeExample(
      r'''curl -fsSL https://example.com/install.sh | sh''', r'''tmp=$(mktemp)
trap 'rm -f -- "$tmp"' EXIT
curl -fsSL -o "$tmp" https://example.com/install.sh
echo "<sha256>  $tmp" | sha256sum -c -
sh "$tmp"'''),
  'SEC002': CodeExample(r'''PASSWORD="…"''',
      r'''# Fichier protégé : chmod 600, propriétaire du service
IFS= read -r PASSWORD < /etc/myapp/db.pass''',
      goodEn: r'''# Protected file: chmod 600, owned by the service
IFS= read -r PASSWORD < /etc/myapp/db.pass'''),
  'SEC003': CodeExample(r'''eval "rsync -a $opts $src $dst"''',
      r'''cmd=(rsync -a "${opts[@]}" -- "$src" "$dst")
"${cmd[@]}"'''),
  'SEC004': CodeExample(r'''chmod 777 /srv/app''', r'''chmod 750 /srv/app
chmod 640 /srv/app/app.conf'''),
  'SEC005': CodeExample(r'''curl -k https://intranet.example/api''',
      r'''curl --cacert /etc/pki/intranet-ca.pem https://intranet.example/api'''),
  'SEC006': CodeExample(r'''wget http://example.com/tool.tar.gz''',
      r'''wget https://example.com/tool.tar.gz
sha256sum -c tool.tar.gz.sha256'''),
  'SEC007': CodeExample(
      r'''rm -rf $BUILD_DIR/*''', r'''rm -rf -- "${BUILD_DIR:?}"/*'''),
  'SEC008': CodeExample(r'''rm -rf /usr/local''', r'''target=/opt/myapp/cache
[ -d "$target" ] && rm -rf -- "$target"'''),
  'SEC009': CodeExample(r'''tmp=/tmp/myscript.$$
echo "$data" > "$tmp"''', r'''tmp=$(mktemp)
trap 'rm -f -- "$tmp"' EXIT
echo "$data" > "$tmp"'''),
  'SEC010': CodeExample(r'''mysql -u admin -p"$PASSWORD" appdb''',
      r'''# my.cnf (chmod 600) : [client] user=… password=…
mysql --defaults-extra-file=/etc/myapp/my.cnf appdb''',
      goodEn: r'''# my.cnf (chmod 600): [client] user=… password=…
mysql --defaults-extra-file=/etc/myapp/my.cnf appdb'''),
  'SEC011':
      CodeExample(r'''. /tmp/settings.sh''', r'''. /etc/myapp/settings.sh'''),
  'SEC012': CodeExample(r'''set -x''', r'''[ -n "${DEBUG:-}" ] && set -x'''),
  'SEC013': CodeExample(r'''chmod u+s /usr/local/bin/tool''',
      r'''setcap cap_net_bind_service=+ep /usr/local/bin/tool'''),
  'SEC014': CodeExample(r'''read -r -p "Mot de passe : " pass''',
      r'''read -rs -p "Mot de passe : " pass
echo''',
      badEn: r'''read -r -p "Password: " pass''',
      goodEn: r'''read -rs -p "Password: " pass
echo'''),
  'SEC015': CodeExample(r'''sudo systemctl restart app''',
      r'''sudo /usr/bin/systemctl restart app'''),
  'SEC016': CodeExample(r'''PATH=.:$PATH''', r'''PATH=/usr/local/bin:$PATH'''),
  'SEC017': CodeExample(r'''#!/bin/bash
systemctl restart app''', r'''#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
systemctl restart app'''),
  'SEC018': CodeExample(
      r'''echo "deploy ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers''',
      r'''tmp=$(mktemp)
echo "deploy ALL=(root) /usr/bin/systemctl restart app" > "$tmp"
visudo -cf "$tmp" && install -m 440 "$tmp" /etc/sudoers.d/deploy'''),
  'SEC019': CodeExample(
      r'''curl -fsSL https://example.com/app.tar.gz | tar xz''',
      r'''curl -fsSLO https://example.com/app.tar.gz
sha256sum -c app.tar.gz.sha256
tar xzf app.tar.gz'''),
  'SEC020':
      CodeExample(r'''ssh -A bastion ssh app01''', r'''ssh -J bastion app01'''),
  'SEC021': CodeExample(r'''export API_TOKEN="$token"
./deploy.sh''', r'''API_TOKEN="$token" ./deploy.sh'''),
  'SEC022': CodeExample(
      r'''KEY="9f86d081…"''', r'''IFS= read -r KEY < /etc/myapp/api.key'''),

  // ── Robustesse ────────────────────────────────────────────────────────────
  'ROB001': CodeExample(r'''#!/bin/bash
cp "$src" "$dst"''', r'''#!/bin/bash
set -euo pipefail
cp "$src" "$dst"'''),
  'ROB002': CodeExample(r'''set -e
curl -fsS "$url" | tar xz''', r'''set -eo pipefail
curl -fsS "$url" | tar xz'''),
  'ROB003': CodeExample(r'''set -e
level=$LOG_LEVEL''', r'''set -eu
level=${LOG_LEVEL:-info}'''),
  'ROB004': CodeExample(r'''tmp=$(mktemp)''', r'''tmp=$(mktemp)
trap 'rm -f -- "$tmp"' EXIT'''),
  'ROB005': CodeExample(r'''cd /opt/app''', r'''cd /opt/app || exit 1'''),
  'ROB006': CodeExample(
      r'''if [ $answer = yes ]; then''', r'''if [ "$answer" = yes ]; then'''),
  'ROB007': CodeExample(
      r'''while read line; do''', r'''while IFS= read -r line; do'''),
  'ROB008': CodeExample(r'''for f in $(ls *.log); do
  gzip $f
done''', r'''for f in ./*.log; do
  [ -e "$f" ] || continue
  gzip -- "$f"
done'''),
  'ROB009': CodeExample(r'''#!/bin/bash^M
echo ok^M''', r'''sed -i 's/\r$//' script.sh   # ou : dos2unix script.sh''',
      goodEn: r'''sed -i 's/\r$//' script.sh   # or: dos2unix script.sh'''),
  'ROB010': CodeExample(r'''cp $@ /backup/''', r'''cp -- "$@" /backup/'''),
  'ROB011': CodeExample(r'''tar czf "$archive" /data
rm -rf /data/old''', r'''tar czf "$archive" /data || exit 1
rm -rf /data/old'''),
  'ROB012': CodeExample(r'''IFS=:
read -r user pass uid < "$f"''', r'''IFS=: read -r user pass uid < "$f"'''),
  'ROB013': CodeExample(r'''trap 'rm -f -- "$tmp"' INT TERM''',
      r'''trap 'rm -f -- "$tmp"' EXIT'''),
  'ROB014': CodeExample(r'''#!/bin/sh
/usr/local/bin/sync-data''', r'''#!/bin/sh
exec 9>/run/lock/sync-data.lock
flock -n 9 || exit 0
/usr/local/bin/sync-data'''),
  'ROB015': CodeExample(r'''read -r -p "Continuer ? " answer''',
      r'''[ "${FORCE:-no}" = yes ] || exit 0''',
      badEn: r'''read -r -p "Continue? " answer'''),
  'ROB016': CodeExample(r'''#!/bin/sh
rsync -a /data/ backup:/data/''', r'''#!/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
export PATH
rsync -a /data/ backup:/data/'''),

  // ── Maintenabilité ────────────────────────────────────────────────────────
  'MNT001': CodeExample(
      r'''rsync -a --delete --exclude=.git --exclude=node_modules --exclude=build "$src/" "$dst/"''',
      r'''rsync -a --delete \
  --exclude=.git --exclude=node_modules --exclude=build \
  "$src/" "$dst/"'''),
  'MNT002': CodeExample(r'''deploy() {
  # … 150 lignes …
}''', r'''deploy() {
  build
  upload
  restart_service
}''', badEn: r'''deploy() {
  # … 150 lines …
}'''),
  'MNT003': CodeExample(r'''for f in ./*; do
  if [ -f "$f" ]; then
    if [ -r "$f" ]; then
      if grep -q x "$f"; then
        process "$f"
      fi
    fi
  fi
done''', r'''for f in ./*; do
  [ -f "$f" ] && [ -r "$f" ] || continue
  grep -q x "$f" || continue
  process "$f"
done'''),
  'MNT004': CodeExample(r'''#!/bin/bash
set -euo pipefail''', r'''#!/bin/bash
# Sauvegarde quotidienne de /srv vers le NAS.
# Usage : backup.sh [-n] DESTINATION
# Prérequis : rsync, accès SSH au NAS.
set -euo pipefail''', goodEn: r'''#!/bin/bash
# Daily backup of /srv to the NAS.
# Usage: backup.sh [-n] DESTINATION
# Requires: rsync, SSH access to the NAS.
set -euo pipefail'''),
  'MNT005': CodeExample(r'''find "$logs" -mtime +30 -delete''',
      r'''# Purge des journaux de plus de 30 jours (durée de rétention).
find "$logs" -mtime +30 -delete''',
      goodEn: r'''# Purge logs older than 30 days (retention period).
find "$logs" -mtime +30 -delete'''),
  'MNT006': CodeExample(r'''# TODO : gérer l'erreur réseau
curl -fsS "$url"''',
      r'''curl -fsS "$url" || { echo "réseau indisponible" >&2; exit 1; }''',
      badEn: r'''# TODO: handle network errors
curl -fsS "$url"''',
      goodEn:
          r'''curl -fsS "$url" || { echo "network unavailable" >&2; exit 1; }'''),
  'MNT007': CodeExample(r'''day=`date +%F`''', r'''day=$(date +%F)'''),
  'MNT008': CodeExample(r'''#!/bin/bash
# … 200 lignes de commandes …''', r'''#!/bin/bash
parse_args() { …; }
backup() { …; }

main() {
  parse_args "$@"
  backup
}
main "$@"''', badEn: r'''#!/bin/bash
# … 200 lines of commands …'''),
  'MNT009': CodeExample('if true; then\n\techo a\n    echo b\nfi',
      'if true; then\n  echo a\n  echo b\nfi'),
  'MNT010': CodeExample('echo ok   ', 'echo ok'),

  // ── Portabilité ───────────────────────────────────────────────────────────
  'POR001': CodeExample(r'''set -eu
echo ok''', r'''#!/bin/sh
set -eu
echo ok'''),
  'POR002':
      CodeExample(r'''#!/usr/local/bin/bash''', r'''#!/usr/bin/env bash'''),
  'POR003': CodeExample(r'''#!/bin/sh
if [[ $x == y* ]]; then
  echo match
fi''', r'''#!/bin/sh
case $x in
  y*) echo match ;;
esac'''),
  'POR004': CodeExample(r'''if which jq >/dev/null; then''',
      r'''if command -v jq >/dev/null; then'''),
  'POR005': CodeExample(
      r'''egrep 'error|fatal' app.log''', r'''grep -E 'error|fatal' app.log'''),
  'POR006': CodeExample(
      r'''apt-get install -y jq''', r'''if command -v dnf >/dev/null; then
  dnf install -y jq
elif command -v apt-get >/dev/null; then
  apt-get install -y jq
fi'''),
  'POR007': CodeExample(r'''ifconfig eth0
netstat -tlnp''', r'''ip addr show eth0
ss -tlnp'''),

  // ── Performance ───────────────────────────────────────────────────────────
  'PERF001':
      CodeExample(r'''cat access.log | grep 404''', r'''grep 404 access.log'''),
  'PERF002': CodeExample(r'''n=$(grep ERROR app.log | wc -l)''',
      r'''n=$(grep -c ERROR app.log)'''),
  'PERF003': CodeExample(r'''i=$(expr $i + 1)''', r'''i=$((i + 1))'''),
  'PERF004': CodeExample(r'''for f in ./*; do
  name=$(basename "$f")
done''', r'''for f in ./*; do
  name=${f##*/}
done'''),
  'PERF005': CodeExample(
      r"grep error app.log | grep -v debug | awk '{print $1}'",
      r'''awk '/error/ && !/debug/ {print $1}' app.log'''),
  'PERF006': CodeExample(r"ps aux | grep '[n]ginx'", r'''pgrep -x nginx'''),
  'PERF007': CodeExample(r'''for i in $(seq 1 100); do''',
      r'''for ((i = 1; i <= 100; i++)); do'''),
  'PERF008': CodeExample(r'''x=$(echo "$y")''', r'''x=$y'''),
  'PERF009':
      CodeExample(r'''conf=$(cat app.conf)''', r'''conf=$(< app.conf)'''),

  // ── ShellCheck ────────────────────────────────────────────────────────────
  'SC2086': CodeExample(r'''rm $file''', r'''rm -- "$file"'''),
  'SC2046':
      CodeExample(r'''ls -l $(dirname "$f")''', r'''ls -l "$(dirname "$f")"'''),
  'SC2068': CodeExample(r'''for a in $@; do''', r'''for a in "$@"; do'''),
  'SC2044': CodeExample(r'''for f in $(find . -name '*.log'); do
  gzip "$f"
done''', r'''find . -name '*.log' -exec gzip -- {} +'''),
  'SC2064': CodeExample(
      r'''trap "rm -f $tmp" EXIT''', r'''trap 'rm -f -- "$tmp"' EXIT'''),
  'SC2069': CodeExample(r'''cmd 2>&1 >/dev/null''', r'''cmd >/dev/null 2>&1'''),
  'SC2154': CodeExample(
      r'''echo "Bonjour $name"''', r'''name=${1:?"usage : $0 NOM"}
echo "Bonjour $name"''',
      badEn: r'''echo "Hello $name"''', goodEn: r'''name=${1:?"usage: $0 NAME"}
echo "Hello $name"'''),
  'SC2155': CodeExample(r'''local out=$(cmd)''', r'''local out
out=$(cmd)'''),
  'SC2015': CodeExample(r'''[ -f "$f" ] && rm -- "$f" || echo "absent"''',
      r'''if [ -f "$f" ]; then
  rm -- "$f"
else
  echo "absent"
fi''',
      badEn: r'''[ -f "$f" ] && rm -- "$f" || echo "missing"''',
      goodEn: r'''if [ -f "$f" ]; then
  rm -- "$f"
else
  echo "missing"
fi'''),
  'SC2012': CodeExample(r'''newest=$(ls -t | head -n 1)''',
      r'''newest=$(find . -maxdepth 1 -type f -printf '%T@ %p\n' | sort -n | tail -n 1 | cut -d' ' -f2-)'''),
  'SC2034': CodeExample(r'''dir=/var/tmp/app
mkdir -p /var/tmp/app''', r'''dir=/var/tmp/app
mkdir -p -- "$dir"'''),
  'SC2004': CodeExample(r'''echo $(($n + 1))''', r'''echo $((n + 1))'''),
  'SC2181': CodeExample(r'''make
if [ $? -ne 0 ]; then
  exit 1
fi''', r'''if ! make; then
  exit 1
fi'''),
  'SC2094': CodeExample(r'''grep -v '^#' app.conf > app.conf''',
      r'''grep -v '^#' app.conf > app.conf.tmp && mv app.conf.tmp app.conf'''),
  'SC2156': CodeExample(
      r'''find . -name '*.sh' -exec sh -c 'shellcheck {}' \;''',
      r'''find . -name '*.sh' -exec sh -c 'shellcheck "$1"' sh {} \;'''),
  'SC2059': CodeExample(r'''printf "$msg\n"''', r'''printf '%s\n' "$msg"'''),
  'SC2035': CodeExample(r'''rm *.log''', r'''rm -- ./*.log'''),
  'SC2166': CodeExample(
      r'''[ "$a" = x -a "$b" = y ]''', r'''[ "$a" = x ] && [ "$b" = y ]'''),
  'SC2197':
      CodeExample(r'''fgrep 'a.b' notes.txt''', r'''grep -F 'a.b' notes.txt'''),
  'SC2010': CodeExample(r"ls | grep '\.log$'", r'''printf '%s\n' ./*.log'''),
  'SC2005': CodeExample(r'''echo $(date +%F)''', r'''date +%F'''),
  'SC2001': CodeExample(
      r'''new=$(echo "$v" | sed 's/foo/bar/g')''', r'''new=${v//foo/bar}'''),
  'SC2143': CodeExample(r'''if [ -n "$(grep x app.log)" ]; then''',
      r'''if grep -q x app.log; then'''),
  'SC2219': CodeExample(r'''let i=i+1''', r'''i=$((i + 1))'''),
  'SC2112': CodeExample(r'''function cleanup() {''', r'''cleanup() {'''),
  'SC3010':
      CodeExample(r'''if [[ -n $x ]]; then''', r'''if [ -n "$x" ]; then'''),
  'SC3011':
      CodeExample(r'''grep x <<< "$v"''', r'''printf '%s\n' "$v" | grep x'''),
  'SC3020': CodeExample(r'''cmd &> out.log''', r'''cmd > out.log 2>&1'''),
  'SC3006':
      CodeExample(r'''if (( n > 3 )); then''', r'''if [ "$n" -gt 3 ]; then'''),
  'SC3018': CodeExample(r''': $((i++))''', r'''i=$((i + 1))'''),

  // ── Python : règles intégrées ─────────────────────────────────────────────
  'PYSEC001': CodeExample(
      r'''API_KEY = "9f86d081…"''', r'''API_KEY = os.environ["API_KEY"]'''),
  'PYROB001': CodeExample(
      r'''subprocess.run(["rsync", "-a", src, dst], check=True)''',
      r'''subprocess.run(["rsync", "-a", src, dst], check=True, timeout=600)'''),
  'PYROB002': CodeExample(r'''answer = input("Continuer ? ")''',
      r'''parser = argparse.ArgumentParser()
parser.add_argument("--force", action="store_true")
args = parser.parse_args()''',
      badEn: r'''answer = input("Continue? ")'''),
  'PYROB003': CodeExample(r'''def main():
    sync()''', r'''import fcntl


def main():
    with open("/run/lock/sync.lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0  # exécution précédente encore en cours
        sync()''', goodEn: r'''import fcntl


def main():
    with open("/run/lock/sync.lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0  # previous run still in progress
        sync()'''),
  'PYROB004': CodeExample(r'''if __name__ == "__main__":
    main()''', r'''if __name__ == "__main__":
    sys.exit(main())'''),
  'PYMNT001': CodeExample(
      r'''import sys''', r'''"""Sauvegarde quotidienne de /srv vers le NAS.

Usage : backup.py [-n] DESTINATION
"""
import sys''',
      goodEn: r'''"""Daily backup of /srv to the NAS.

Usage: backup.py [-n] DESTINATION
"""
import sys'''),
  'PYMNT002': CodeExample(r'''def main():
    ...

main()''', r'''def main():
    ...


if __name__ == "__main__":
    main()'''),
  'PYPOR001':
      CodeExample(r'''#!/usr/bin/python''', r'''#!/usr/bin/env python3'''),

  // ── Python : Ruff (et Bandit, Pylint par alias) ──────────────────────────
  'S602': CodeExample(
      r'''subprocess.call(f"tar czf {archive} {src}", shell=True)''',
      r'''subprocess.call(["tar", "czf", archive, src])'''),
  'S605': CodeExample(
      r'''os.system("rm -rf " + path)''', r'''shutil.rmtree(path)'''),
  'S307': CodeExample(
      r'''value = eval(text)''', r'''value = ast.literal_eval(text)'''),
  'S301': CodeExample(r'''data = pickle.load(f)''', r'''data = json.load(f)'''),
  'S506':
      CodeExample(r'''conf = yaml.load(f)''', r'''conf = yaml.safe_load(f)'''),
  'S501': CodeExample(r'''requests.get(url, verify=False)''',
      r'''requests.get(url, verify="/etc/pki/tls/certs/ca-bundle.crt", timeout=30)'''),
  'S113': CodeExample(
      r'''requests.get(url)''', r'''requests.get(url, timeout=30)'''),
  'S108': CodeExample(r'''path = "/tmp/report.txt"''',
      r'''fd, path = tempfile.mkstemp(suffix=".txt")'''),
  'S105': CodeExample(
      r'''password = "…"''', r'''password = os.environ["DB_PASSWORD"]'''),
  'S106': CodeExample(r'''connect(user="admin", password="…")''',
      r'''connect(user="admin", password=os.environ["DB_PASSWORD"])'''),
  'S110': CodeExample(r'''try:
    os.remove(path)
except Exception:
    pass''', r'''with contextlib.suppress(FileNotFoundError):
    os.remove(path)'''),
  'S324': CodeExample(r'''digest = hashlib.md5(data).hexdigest()''',
      r'''digest = hashlib.sha256(data).hexdigest()'''),
  'S311': CodeExample(r'''token = "".join(random.choices(chars, k=32))''',
      r'''token = secrets.token_urlsafe(32)'''),
  'S608': CodeExample(
      r'''cur.execute(f"SELECT * FROM users WHERE name = '{name}'")''',
      r'''cur.execute("SELECT * FROM users WHERE name = %s", (name,))'''),
  'S101': CodeExample(r'''assert user.is_admin''', r'''if not user.is_admin:
    raise PermissionError("droits administrateur requis")''',
      goodEn: r'''if not user.is_admin:
    raise PermissionError("administrator rights required")'''),
  'E722': CodeExample(r'''try:
    run()
except:
    log.error("échec")''', r'''try:
    run()
except Exception:
    log.exception("échec")''', badEn: r'''try:
    run()
except:
    log.error("failed")''', goodEn: r'''try:
    run()
except Exception:
    log.exception("failed")'''),
  'BLE001': CodeExample(r'''except Exception:
    return None''', r'''except OSError as e:
    log.error("lecture impossible : %s", e)
    return None''', goodEn: r'''except OSError as e:
    log.error("cannot read: %s", e)
    return None'''),
  'B006': CodeExample(r'''def add(item, items=[]):
    items.append(item)''', r'''def add(item, items=None):
    if items is None:
        items = []
    items.append(item)'''),
  'B904': CodeExample(r'''except KeyError:
    raise ValueError("clé absente")''', r'''except KeyError as e:
    raise ValueError("clé absente") from e''', badEn: r'''except KeyError:
    raise ValueError("missing key")''', goodEn: r'''except KeyError as e:
    raise ValueError("missing key") from e'''),
  'F401': CodeExample(r'''import os
import sys

print(sys.argv)''', r'''import sys

print(sys.argv)'''),
  'F841': CodeExample(r'''result = compute()''', r'''compute()'''),
  'F821': CodeExample(r'''total = 0
print(totl)''', r'''total = 0
print(total)'''),
  'PLW1510': CodeExample(
      r'''subprocess.run(cmd)''', r'''subprocess.run(cmd, check=True)'''),
  'PLW1514': CodeExample(r'''with open(path) as f:''',
      r'''with open(path, encoding="utf-8") as f:'''),
  'SIM115': CodeExample(r'''f = open(path, encoding="utf-8")
data = f.read()''', r'''with open(path, encoding="utf-8") as f:
    data = f.read()'''),
  'PERF401': CodeExample(r'''result = []
for x in items:
    if x > 0:
        result.append(x)''', r'''result = [x for x in items if x > 0]'''),
  'E501': CodeExample(
      r'''subprocess.run(["rsync", "-a", "--delete", "--exclude=.git", "--exclude=build", src, dst], check=True, timeout=600)''',
      r'''subprocess.run(
    ["rsync", "-a", "--delete", "--exclude=.git", "--exclude=build", src, dst],
    check=True,
    timeout=600,
)'''),
  'VERMIN': CodeExample(r'''match cmd:
    case "start":
        start()
    case _:
        usage()''', r'''if cmd == "start":
    start()
else:
    usage()'''),
  'CC': CodeExample(r'''def process(path):
    if os.path.isfile(path):
        if os.access(path, os.R_OK):
            for line in open(path, encoding="utf-8"):
                if line.strip():
                    handle(line)''', r'''def process(path):
    if not os.path.isfile(path) or not os.access(path, os.R_OK):
        return
    with open(path, encoding="utf-8") as f:
        for line in filter(str.strip, f):
            handle(line)'''),
};
