#!/bin/bash
# Vérification globale de l'état de sécurité
# Compatible RHEL 8 / RHEL 9 / RHEL 10
#
# Pas de "set -e" : ce script doit survivre à l'échec d'un contrôle
# individuel (ex: getenforce absent) et produire un rapport complet.
# La fiabilité repose sur le code de sortie final (0 = OK, 1 = alerte).
set -uo pipefail

CONFIG_FILE="/etc/security-check.conf"
if [ -f "${CONFIG_FILE}" ]; then
    # shellcheck source=security-check.conf disable=SC1091
    source "${CONFIG_FILE}"
fi
: "${ADMIN_EMAIL:=admin@example.com}"
: "${CLAMAV_SIGNATURE_MAX_AGE_DAYS:=7}"
: "${RKHUNTER_SCAN_MAX_AGE_DAYS:=2}"
: "${QUARANTINE_DIR:=/var/quarantine}"
: "${RKHUNTER_LOG:=/var/log/rkhunter.log}"
: "${SECURITY_CHECK_HISTORY_DIR:=/var/log/security/security-check}"
: "${SECURITY_CHECK_HISTORY_DAYS:=30}"
: "${NODE_EXPORTER_TEXTFILE_DIR:=}"
: "${DISK_USAGE_WARN_PERCENT:=85}"
: "${DISK_INODE_WARN_PERCENT:=85}"

LOCKFILE="/run/lock/$(basename "$0" .sh).lock"
exec 200>"${LOCKFILE}"
flock -n 200 || { echo "Une instance de $(basename "$0") est déjà en cours d'exécution." >&2; exit 1; }

HOSTNAME=$(hostname -f)
DATE=$(date '+%Y-%m-%d %H:%M:%S')
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "${SECURITY_CHECK_HISTORY_DIR}"
REPORT="${SECURITY_CHECK_HISTORY_DIR}/security_check_${TS}.txt"
ALERT=0
RHEL_MAJOR=$(rpm -E '%{rhel}' 2>/dev/null || echo inconnu)

# Détecter le nom du service ClamAV (clamd@scan sur RHEL8/9, clamav-daemon possible sur RHEL10)
if systemctl list-unit-files clamd@scan.service &>/dev/null 2>&1; then
    CLAMD_SVC="clamd@scan"
elif systemctl list-unit-files clamav-daemon.service &>/dev/null 2>&1; then
    CLAMD_SVC="clamav-daemon"
else
    CLAMD_SVC="clamd@scan"   # Valeur par défaut
fi

# ─────────────────────────────────────────
# Trace structurée (JSON) de chaque contrôle, en plus de la sortie texte,
# pour un parsing fiable côté outils tiers (voir security_check_*.json).
CURRENT_SECTION=""
CHECKS_JSON=()
OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

json_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    printf '%s' "$s"
}
add_check_json() {
    case "$1" in
        OK)   OK_COUNT=$((OK_COUNT + 1)) ;;
        WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
        FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    esac
    CHECKS_JSON+=("{\"section\":\"$(json_escape "${CURRENT_SECTION}")\",\"status\":\"$1\",\"message\":\"$(json_escape "$2")\"}")
}

header() { echo ""; echo "══════════════════════════════════════"; echo "  $1"; echo "══════════════════════════════════════"; CURRENT_SECTION=$1; }
ok()     { echo "  [OK]    $1"; add_check_json OK "$1"; }
warn()   { echo "  [WARN]  $1"; ALERT=1; add_check_json WARN "$1"; }
fail()   { echo "  [FAIL]  $1"; ALERT=1; add_check_json FAIL "$1"; }
# ─────────────────────────────────────────

{
# ATTENTION : ne pas utiliser "| tee" ici — le bloc tournerait dans un
# sous-shell (côté gauche du pipe) et les mises à jour de ALERT par
# warn()/fail() ne remonteraient jamais au shell parent. La redirection
# simple ci-dessous garde le bloc dans le shell courant.
echo "╔══════════════════════════════════════╗"
echo "║   RAPPORT DE SÉCURITÉ - ${HOSTNAME}  ║"
echo "╚══════════════════════════════════════╝"
echo "Date  : ${DATE}"
echo "RHEL  : ${RHEL_MAJOR}"
echo "ClamAV service : ${CLAMD_SVC}"

# ─────────────────────────────────────────
header "SELINUX"
MODE=$(getenforce 2>/dev/null || echo "inconnu")
case "$MODE" in
    Enforcing)  SELINUX_ENFORCING=1; ok  "SELinux en mode Enforcing" ;;
    Permissive) SELINUX_ENFORCING=0; warn "SELinux en mode Permissive (protection réduite)" ;;
    Disabled)   SELINUX_ENFORCING=0; fail "SELinux DÉSACTIVÉ" ;;
    *)          SELINUX_ENFORCING=0; fail "SELinux : état inconnu" ;;
esac

AVC_COUNT=$(ausearch -m AVC --start today 2>/dev/null | grep -c "type=AVC" || echo 0)
if [ "${AVC_COUNT}" -gt 0 ]; then warn "${AVC_COUNT} refus SELinux aujourd'hui"; else ok "Aucun refus SELinux aujourd'hui"; fi

# ─────────────────────────────────────────
header "CLAMAV"
if systemctl is-active --quiet "${CLAMD_SVC}"; then
    CLAMD_ACTIVE=1
    ok "${CLAMD_SVC} actif"
else
    CLAMD_ACTIVE=0
    fail "${CLAMD_SVC} INACTIF"
fi

# Service de mise à jour des signatures (nom différent selon la version)
FRESHCLAM_SVC="clamav-freshclam"
systemctl list-unit-files clamav-freshclam.service &>/dev/null || FRESHCLAM_SVC="clamav-update"
if systemctl is-active --quiet "${FRESHCLAM_SVC}"; then
    FRESHCLAM_ACTIVE=1
    ok "${FRESHCLAM_SVC} actif"
else
    FRESHCLAM_ACTIVE=0
    warn "${FRESHCLAM_SVC} INACTIF — signatures potentiellement obsolètes"
fi

# Vérifier l'âge des signatures
DB_AGE=$(find /var/lib/clamav -name "daily.cvd" -mtime "+${CLAMAV_SIGNATURE_MAX_AGE_DAYS}" 2>/dev/null)
if [ -n "$DB_AGE" ]; then CLAMAV_SIG_STALE=1; warn "Signatures ClamAV de plus de ${CLAMAV_SIGNATURE_MAX_AGE_DAYS} jours"; else CLAMAV_SIG_STALE=0; ok "Signatures ClamAV récentes"; fi

# Quarantaine
QUARANTINE_COUNT=$(find "${QUARANTINE_DIR}" -mindepth 1 2>/dev/null | wc -l)
if [ "${QUARANTINE_COUNT}" -gt 0 ]; then warn "${QUARANTINE_COUNT} fichier(s) en quarantaine"; else ok "Quarantaine vide"; fi

# ─────────────────────────────────────────
header "RKHUNTER"
RKH_WARN=0
if [ -f "${RKHUNTER_LOG}" ]; then
    RKH_AGE=$(find "$(dirname "${RKHUNTER_LOG}")" -name "$(basename "${RKHUNTER_LOG}")" -mtime "+${RKHUNTER_SCAN_MAX_AGE_DAYS}")
    if [ -n "$RKH_AGE" ]; then RKHUNTER_LOG_STALE=1; warn "Dernier scan rkhunter de plus de ${RKHUNTER_SCAN_MAX_AGE_DAYS} jours"; else RKHUNTER_LOG_STALE=0; ok "Scan rkhunter récent"; fi

    RKH_WARN=$(grep -c "Warning" "${RKHUNTER_LOG}" 2>/dev/null || echo 0)
    if [ "${RKH_WARN}" -gt 0 ]; then warn "${RKH_WARN} avertissement(s) dans le dernier scan rkhunter"; else ok "Aucun avertissement rkhunter"; fi
else
    RKHUNTER_LOG_STALE=1
    warn "Aucun log rkhunter trouvé — scan jamais effectué ?"
fi

# ─────────────────────────────────────────
header "FAIL2BAN"
TOTAL_BANNED=0
if systemctl is-active --quiet fail2ban; then
    FAIL2BAN_ACTIVE=1
    ok "Fail2ban actif"
    for jail in $(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*://;s/,//g' | tr -d ' ' | tr ',' ' '); do
        COUNT=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
        TOTAL_BANNED=$((TOTAL_BANNED + COUNT))
        [ "$COUNT" -gt 0 ] && echo "  [INFO]  Jail ${jail} : ${COUNT} IP(s) bannie(s)"
    done
    ok "Total IPs bannies actuellement : ${TOTAL_BANNED}"
else
    FAIL2BAN_ACTIVE=0
    fail "Fail2ban INACTIF"
fi

# ─────────────────────────────────────────
header "FIREWALL"
# Ordre de préférence : firewalld > nftables > iptables (dernier recours).
# FIREWALLD_ACTIVE : compat historique (métrique existante).
# FIREWALL_ACTIVE  : 1 dès qu'un filtrage est effectivement en place.
# FIREWALL_BACKEND : backend retenu (firewalld / nftables / iptables / none).
FIREWALLD_ACTIVE=0
FIREWALL_ACTIVE=0
FIREWALL_BACKEND="none"

nft_has_ruleset() {
    command -v nft >/dev/null 2>&1 || return 1
    [ -n "$(nft list ruleset 2>/dev/null | tr -d '[:space:]')" ]
}
iptables_has_rules() {
    command -v iptables >/dev/null 2>&1 || return 1
    # Règles autres que les politiques par défaut (-P) et la création de chaînes (-N)
    iptables -S 2>/dev/null | grep -qvE '^-(P|N) '
}

if systemctl is-active --quiet firewalld; then
    FIREWALLD_ACTIVE=1
    FIREWALL_ACTIVE=1
    FIREWALL_BACKEND="firewalld"
    ok "firewalld actif"
    ZONE=$(firewall-cmd --get-default-zone 2>/dev/null)
    ok "Zone par défaut : ${ZONE}"
elif systemctl is-active --quiet nftables || nft_has_ruleset; then
    FIREWALL_ACTIVE=1
    FIREWALL_BACKEND="nftables"
    if systemctl is-active --quiet nftables; then
        ok "Pare-feu assuré par nftables (service actif ; firewalld inactif)"
    else
        ok "Pare-feu assuré par nftables (ruleset chargé, service inactif ; firewalld inactif)"
    fi
elif systemctl is-active --quiet iptables || iptables_has_rules; then
    FIREWALL_ACTIVE=1
    FIREWALL_BACKEND="iptables"
    warn "firewalld et nftables INACTIFS — filtrage résiduel via iptables (hérité, à migrer)"
else
    fail "Aucun pare-feu actif (firewalld / nftables / iptables)"
fi

# ─────────────────────────────────────────
header "MISES À JOUR DE SÉCURITÉ"
SEC_UPDATES_COUNT=0
if command -v dnf &>/dev/null; then
    SEC_UPDATES_COUNT=$(dnf updateinfo list security --quiet 2>/dev/null | grep -cE '^[A-Za-z0-9]+-[0-9]' || echo 0)
    if [ "${SEC_UPDATES_COUNT}" -gt 0 ]; then
        warn "${SEC_UPDATES_COUNT} mise(s) à jour de sécurité en attente"
    else
        ok "Aucune mise à jour de sécurité en attente"
    fi
else
    warn "dnf introuvable — impossible de vérifier les mises à jour de sécurité"
fi

# ─────────────────────────────────────────
header "AUDITD"
if systemctl is-active --quiet auditd; then
    AUDITD_ACTIVE=1
    ok "auditd actif"
    AUDITD_RULES_COUNT=$(auditctl -l 2>/dev/null | grep -cv '^No rules' || echo 0)
    if [ "${AUDITD_RULES_COUNT}" -gt 0 ]; then
        ok "${AUDITD_RULES_COUNT} règle(s) auditd chargée(s)"
    else
        warn "auditd actif mais aucune règle chargée"
    fi
else
    AUDITD_ACTIVE=0
    AUDITD_RULES_COUNT=0
    fail "auditd INACTIF"
fi

# ─────────────────────────────────────────
header "DURCISSEMENT SSHD"
SSHD_ROOT_LOGIN_PWD=0
if command -v sshd &>/dev/null; then
    PERMIT_ROOT_LOGIN=$(sshd -T 2>/dev/null | awk '/^permitrootlogin/ {print $2}')
    case "${PERMIT_ROOT_LOGIN}" in
        yes)
            SSHD_ROOT_LOGIN_PWD=1
            fail "PermitRootLogin=yes — connexion root SSH par mot de passe autorisée"
            ;;
        no|prohibit-password|without-password)
            ok "PermitRootLogin=${PERMIT_ROOT_LOGIN}"
            ;;
        "")
            warn "Impossible de déterminer PermitRootLogin (sshd -T a échoué)"
            ;;
        *)
            warn "PermitRootLogin=${PERMIT_ROOT_LOGIN} (valeur inattendue)"
            ;;
    esac
else
    warn "sshd introuvable — contrôle ignoré"
fi

UID0_EXTRA=$(awk -F: '$3==0 && $1!="root" {print $1}' /etc/passwd 2>/dev/null)
UID0_EXTRA_COUNT=$(printf '%s\n' "${UID0_EXTRA}" | grep -c . || echo 0)
if [ "${UID0_EXTRA_COUNT}" -gt 0 ]; then
    fail "${UID0_EXTRA_COUNT} compte(s) UID 0 autre(s) que root : $(echo "${UID0_EXTRA}" | tr '\n' ' ')"
else
    ok "Aucun compte UID 0 hors root"
fi

PASSWORDLESS=$(awk -F: '$2=="" {print $1}' /etc/shadow 2>/dev/null)
PASSWORDLESS_COUNT=$(printf '%s\n' "${PASSWORDLESS}" | grep -c . || echo 0)
if [ "${PASSWORDLESS_COUNT}" -gt 0 ]; then
    warn "${PASSWORDLESS_COUNT} compte(s) sans mot de passe dans /etc/shadow : $(echo "${PASSWORDLESS}" | tr '\n' ' ')"
else
    ok "Aucun compte sans mot de passe"
fi

# ─────────────────────────────────────────
header "ESPACE DISQUE"
DISK_USAGE_ALERT=0
while read -r _fs _size _used _avail pcent _mount; do
    pct=${pcent%%%}
    if [ -n "${pct}" ] && [ "${pct}" -ge "${DISK_USAGE_WARN_PERCENT}" ] 2>/dev/null; then
        DISK_USAGE_ALERT=1
        warn "Partition ${_mount} : ${pct}% d'espace utilisé (seuil ${DISK_USAGE_WARN_PERCENT}%)"
    fi
done < <(df -P -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | tail -n +2)

while read -r _fs _inodes _iused _ifree ipcent _mount; do
    pct=${ipcent%%%}
    if [ -n "${pct}" ] && [ "${pct}" -ge "${DISK_INODE_WARN_PERCENT}" ] 2>/dev/null; then
        DISK_USAGE_ALERT=1
        warn "Partition ${_mount} : ${pct}% d'inodes utilisés (seuil ${DISK_INODE_WARN_PERCENT}%)"
    fi
done < <(df -iP -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | tail -n +2)

if [ "${DISK_USAGE_ALERT}" -eq 0 ]; then
    ok "Espace disque et inodes sous les seuils configurés"
fi

# ─────────────────────────────────────────
header "CONNEXIONS ACTIVES"
echo "  Sessions SSH actives :"
who | while read -r line; do echo "    $line"; done
echo "  Ports en écoute (non loopback) :"
ss -tlnp | grep -v '127.0.0.1' | grep -v '::1' | tail -n +2 | while read -r line; do echo "    $line"; done

# ─────────────────────────────────────────
header "RÉSUMÉ"
if [ "${ALERT}" -eq 0 ]; then
    echo "  ✔ Tous les contrôles sont OK"
else
    echo "  ✘ Des problèmes ont été détectés — voir les WARN/FAIL ci-dessus"
fi

} > "${REPORT}" 2>&1
cat "${REPORT}"

# Envoyer par email si des alertes
if [ "${ALERT}" -eq 1 ]; then
    mail -s "[SÉCURITÉ] Alertes détectées sur ${HOSTNAME}" "${ADMIN_EMAIL}" < "${REPORT}"
fi

# Le rapport est conservé (historique) ; purge au-delà de la rétention configurée
find "${SECURITY_CHECK_HISTORY_DIR}" -name 'security_check_*.txt' -mtime "+${SECURITY_CHECK_HISTORY_DAYS}" -delete 2>/dev/null || true

# Rapport JSON structuré (toujours généré, même horodatage que le .txt) :
# permet un parsing fiable côté outils tiers (GUI CheckPlatform notamment)
# sans dépendre du format texte destiné à la lecture humaine.
JSON_REPORT="${SECURITY_CHECK_HISTORY_DIR}/security_check_${TS}.json"
{
    printf '{\n'
    printf '  "hostname": "%s",\n' "$(json_escape "${HOSTNAME}")"
    printf '  "date": "%s",\n' "$(json_escape "${DATE}")"
    printf '  "rhel_major": "%s",\n' "$(json_escape "${RHEL_MAJOR}")"
    printf '  "alert": %s,\n' "${ALERT}"
    printf '  "ok_count": %s,\n' "${OK_COUNT}"
    printf '  "warn_count": %s,\n' "${WARN_COUNT}"
    printf '  "fail_count": %s,\n' "${FAIL_COUNT}"
    printf '  "checks": [\n'
    last=$((${#CHECKS_JSON[@]} - 1))
    for i in "${!CHECKS_JSON[@]}"; do
        sep=","
        [ "$i" -eq "${last}" ] && sep=""
        printf '    %s%s\n' "${CHECKS_JSON[$i]}" "${sep}"
    done
    printf '  ]\n'
    printf '}\n'
} > "${JSON_REPORT}"
find "${SECURITY_CHECK_HISTORY_DIR}" -name 'security_check_*.json' -mtime "+${SECURITY_CHECK_HISTORY_DAYS}" -delete 2>/dev/null || true

# Métriques Prometheus (node_exporter --collector.textfile), désactivées si
# NODE_EXPORTER_TEXTFILE_DIR est vide. Écriture atomique via fichier temporaire + mv.
if [ -n "${NODE_EXPORTER_TEXTFILE_DIR}" ]; then
    PROM_TMP=$(mktemp "${NODE_EXPORTER_TEXTFILE_DIR}/.security_check.prom.XXXXXX")
    {
        echo "# HELP security_check_alert État global de security-check.sh (0=OK, 1=alerte)"
        echo "# TYPE security_check_alert gauge"
        echo "security_check_alert ${ALERT}"
        echo "# HELP security_check_last_run_timestamp_seconds Horodatage Unix de la dernière exécution"
        echo "# TYPE security_check_last_run_timestamp_seconds gauge"
        echo "security_check_last_run_timestamp_seconds $(date +%s)"
        echo "# HELP security_check_selinux_enforcing SELinux en mode Enforcing (1) ou non (0)"
        echo "# TYPE security_check_selinux_enforcing gauge"
        echo "security_check_selinux_enforcing ${SELINUX_ENFORCING}"
        echo "# HELP security_check_selinux_avc_denials_today Nombre de refus SELinux (AVC) aujourd'hui"
        echo "# TYPE security_check_selinux_avc_denials_today gauge"
        echo "security_check_selinux_avc_denials_today ${AVC_COUNT}"
        echo "# HELP security_check_clamd_active Service ClamAV actif (1) ou non (0)"
        echo "# TYPE security_check_clamd_active gauge"
        echo "security_check_clamd_active ${CLAMD_ACTIVE}"
        echo "# HELP security_check_freshclam_active Service freshclam actif (1) ou non (0)"
        echo "# TYPE security_check_freshclam_active gauge"
        echo "security_check_freshclam_active ${FRESHCLAM_ACTIVE}"
        echo "# HELP security_check_clamav_signatures_stale Signatures ClamAV trop anciennes (1) ou récentes (0)"
        echo "# TYPE security_check_clamav_signatures_stale gauge"
        echo "security_check_clamav_signatures_stale ${CLAMAV_SIG_STALE}"
        echo "# HELP security_check_quarantine_files Nombre de fichiers en quarantaine"
        echo "# TYPE security_check_quarantine_files gauge"
        echo "security_check_quarantine_files ${QUARANTINE_COUNT}"
        echo "# HELP security_check_rkhunter_log_stale Dernier scan rkhunter trop ancien (1) ou récent (0)"
        echo "# TYPE security_check_rkhunter_log_stale gauge"
        echo "security_check_rkhunter_log_stale ${RKHUNTER_LOG_STALE}"
        echo "# HELP security_check_rkhunter_warnings Avertissements du dernier scan rkhunter"
        echo "# TYPE security_check_rkhunter_warnings gauge"
        echo "security_check_rkhunter_warnings ${RKH_WARN}"
        echo "# HELP security_check_fail2ban_active Service fail2ban actif (1) ou non (0)"
        echo "# TYPE security_check_fail2ban_active gauge"
        echo "security_check_fail2ban_active ${FAIL2BAN_ACTIVE}"
        echo "# HELP security_check_fail2ban_banned_total IPs actuellement bannies (toutes jails confondues)"
        echo "# TYPE security_check_fail2ban_banned_total gauge"
        echo "security_check_fail2ban_banned_total ${TOTAL_BANNED}"
        echo "# HELP security_check_firewalld_active Service firewalld actif (1) ou non (0)"
        echo "# TYPE security_check_firewalld_active gauge"
        echo "security_check_firewalld_active ${FIREWALLD_ACTIVE}"
        echo "# HELP security_check_firewall_active Un pare-feu filtre effectivement le trafic (1) ou aucun (0)"
        echo "# TYPE security_check_firewall_active gauge"
        echo "security_check_firewall_active ${FIREWALL_ACTIVE}"
        echo "# HELP security_check_firewall_backend_info Backend de pare-feu retenu (label backend=firewalld|nftables|iptables|none)"
        echo "# TYPE security_check_firewall_backend_info gauge"
        echo "security_check_firewall_backend_info{backend=\"${FIREWALL_BACKEND}\"} 1"
        echo "# HELP security_check_pending_security_updates Mises à jour de sécurité en attente (dnf updateinfo)"
        echo "# TYPE security_check_pending_security_updates gauge"
        echo "security_check_pending_security_updates ${SEC_UPDATES_COUNT}"
        echo "# HELP security_check_auditd_active Service auditd actif (1) ou non (0)"
        echo "# TYPE security_check_auditd_active gauge"
        echo "security_check_auditd_active ${AUDITD_ACTIVE}"
        echo "# HELP security_check_auditd_rules Nombre de règles auditd chargées"
        echo "# TYPE security_check_auditd_rules gauge"
        echo "security_check_auditd_rules ${AUDITD_RULES_COUNT}"
        echo "# HELP security_check_sshd_root_login_password_allowed sshd autorise la connexion root par mot de passe (1) ou non (0)"
        echo "# TYPE security_check_sshd_root_login_password_allowed gauge"
        echo "security_check_sshd_root_login_password_allowed ${SSHD_ROOT_LOGIN_PWD}"
        echo "# HELP security_check_uid0_extra_accounts Nombre de comptes UID 0 autres que root"
        echo "# TYPE security_check_uid0_extra_accounts gauge"
        echo "security_check_uid0_extra_accounts ${UID0_EXTRA_COUNT}"
        echo "# HELP security_check_passwordless_accounts Nombre de comptes sans mot de passe dans /etc/shadow"
        echo "# TYPE security_check_passwordless_accounts gauge"
        echo "security_check_passwordless_accounts ${PASSWORDLESS_COUNT}"
        echo "# HELP security_check_disk_usage_alert Une partition dépasse le seuil d'espace/inodes configuré (1) ou non (0)"
        echo "# TYPE security_check_disk_usage_alert gauge"
        echo "security_check_disk_usage_alert ${DISK_USAGE_ALERT}"
    } > "${PROM_TMP}"
    mv -f "${PROM_TMP}" "${NODE_EXPORTER_TEXTFILE_DIR}/security_check.prom"
fi

exit "${ALERT}"
