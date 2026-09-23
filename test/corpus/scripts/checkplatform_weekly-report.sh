#!/bin/bash
# Génère un rapport HTML hebdomadaire de sécurité
# Compatible RHEL 8 / RHEL 9 / RHEL 10
#
# Pas de "set -e" : un indicateur manquant (ex: fail2ban absent) ne doit
# pas empêcher la génération du reste du rapport.
set -uo pipefail

CONFIG_FILE="/etc/security-check.conf"
if [ -f "${CONFIG_FILE}" ]; then
    # shellcheck source=security-check.conf disable=SC1091
    source "${CONFIG_FILE}"
fi
: "${ADMIN_EMAIL:=admin@example.com}"
: "${QUARANTINE_DIR:=/var/quarantine}"
: "${RKHUNTER_LOG:=/var/log/rkhunter.log}"

LOCKFILE="/run/lock/$(basename "$0" .sh).lock"
exec 200>"${LOCKFILE}"
flock -n 200 || { echo "Une instance de $(basename "$0") est déjà en cours d'exécution." >&2; exit 1; }

HOSTNAME=$(hostname -f)
SEMAINE=$(date '+%Y-S%V')
REPORT="/tmp/security_weekly_${SEMAINE}.html"
RHEL_MAJOR=$(rpm -E '%{rhel}' 2>/dev/null || echo inconnu)

# Détecter le service ClamAV
CLAMD_SVC="clamd@scan"
systemctl list-unit-files clamav-daemon.service &>/dev/null 2>&1 && \
  ! systemctl list-unit-files clamd@scan.service &>/dev/null 2>&1 && \
  CLAMD_SVC="clamav-daemon"

cat > "${REPORT}" << HTML
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Rapport Sécurité - ${HOSTNAME} - Semaine ${SEMAINE}</title>
<style>
  body { font-family: Arial, sans-serif; margin: 20px; color: #333; }
  h1   { color: #c00; }
  h2   { color: #333; border-bottom: 2px solid #c00; }
  table { border-collapse: collapse; width: 100%; margin: 10px 0; }
  th   { background: #c00; color: white; padding: 8px; }
  td   { border: 1px solid #ddd; padding: 8px; }
  tr:nth-child(even) { background: #f5f5f5; }
  .ok   { color: green; font-weight: bold; }
  .warn { color: orange; font-weight: bold; }
  .fail { color: red; font-weight: bold; }
</style>
</head>
<body>
<h1>Rapport de Sécurité Hebdomadaire</h1>
<p><b>Hôte :</b> ${HOSTNAME} &nbsp;|&nbsp; <b>Semaine :</b> ${SEMAINE} &nbsp;|&nbsp; <b>RHEL :</b> ${RHEL_MAJOR} &nbsp;|&nbsp; <b>Généré le :</b> $(date)</p>

<h2>ClamAV</h2>
<table>
<tr><th>Indicateur</th><th>Valeur</th></tr>
<tr><td>Service clamd (${CLAMD_SVC})</td><td class="$(systemctl is-active ${CLAMD_SVC} &>/dev/null && echo ok || echo fail)">$(systemctl is-active ${CLAMD_SVC} 2>/dev/null)</td></tr>
<tr><td>Service freshclam</td><td>$(systemctl is-active clamav-freshclam 2>/dev/null)</td></tr>
<tr><td>Fichiers en quarantaine</td><td>$(find "${QUARANTINE_DIR}" -mindepth 1 2>/dev/null | wc -l)</td></tr>
<tr><td>Dernière mise à jour signatures</td><td>$(stat -c %y /var/lib/clamav/daily.cvd 2>/dev/null | cut -d. -f1)</td></tr>
</table>

<h2>Fail2ban — Bans de la semaine</h2>
<table>
<tr><th>Jail</th><th>Total bans</th><th>Actuellement bannis</th></tr>
HTML

for jail in $(fail2ban-client status 2>/dev/null | grep "Jail list" | \
              sed 's/.*://;s/,//g' | tr -d ' ' | tr ',' ' '); do
    total=$(fail2ban-client status "$jail" 2>/dev/null | grep "Total banned" | awk '{print $NF}')
    current=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
    echo "<tr><td>${jail}</td><td>${total}</td><td>${current}</td></tr>" >> "${REPORT}"
done

cat >> "${REPORT}" << HTML
</table>

<h2>rkhunter — Derniers avertissements</h2>
<pre>$(grep "Warning" "${RKHUNTER_LOG}" 2>/dev/null | tail -20 || echo "Aucun avertissement")</pre>

<h2>Connexions SSH (dernière semaine)</h2>
<pre>$(last | head -20)</pre>

<h2>Top 10 IPs bannies par Fail2ban</h2>
<pre>$(grep "Ban" /var/log/fail2ban.log 2>/dev/null | \
  grep -oP '(\d{1,3}\.){3}\d{1,3}' | sort | uniq -c | sort -rn | head -10)</pre>

</body>
</html>
HTML

# Envoyer par email
echo "Voir le rapport en pièce jointe." | \
    mail -s "[Sécurité] Rapport hebdomadaire - ${HOSTNAME} - ${SEMAINE}" \
         -a "Content-Type: text/html" \
         -A "${REPORT}" \
         "${ADMIN_EMAIL}"

rm -f "${REPORT}"

# Planifier chaque lundi à 8h00 (ajout idempotent, le script étant lui-même lancé par ce cron)
CRON_LINE="0 8 * * 1 root /usr/local/sbin/weekly-security-report.sh"
grep -qF "${CRON_LINE}" /etc/cron.d/security 2>/dev/null || echo "${CRON_LINE}" >> /etc/cron.d/security
