#!/bin/bash
## master_audit_cible.sh — Orchestre les scripts sur_cible_root/ et sur_cible_user/
## en séquence, dans l'ordre décrit dans fr/audit.adoc (section « Poursuivre l'audit
## sur la cible »). À exécuter directement sur la machine cible, après connexion SSH.
##
## Usage : ./master_audit_cible.sh [--quick|--full] [--json] [--forensics] [--sudo|--su]
##             [--from=N] [--to=N] [--only=N[,M…]] [--resume=DIR|--resume-last]
##             [--list-phases] [--dry-run] [--debug] [-h|--help]
##   --quick      (défaut) Phases 5, 6, 7, 8, 9 + vérifications rapides — cœur de
##                l'audit cible (~15-20 min).
##   --full       --quick, puis les ~25 audits complémentaires (Podman, PAM, TLS,
##                bases de données, DNS, mail, FreeIPA, etc. — voir sur_cible_root/).
##   --json       ajoute --json aux scripts qui le supportent, pour l'intégration
##                ultérieure dans generate_json_summary.sh / generate_score_report.sh.
##   --forensics  lance phase10_forensics_collect.sh EN PREMIER, avant tout le reste
##                (système potentiellement compromis — voir fr/audit.adoc §6).
##                N'est jamais inclus dans --quick/--full : à demander explicitement.
##   --dry-run    affiche la séquence de scripts qui serait exécutée (avec le mode,
##                --json et --forensics choisis) sans rien lancer, sans sudo, sans
##                créer OUTDIR — pour prévisualiser avant d'agir sur une vraie cible.
##   --sudo       force l'élévation des scripts sur_cible_root/ via `sudo`.
##   --su         force l'élévation via `su` (mot de passe root demandé une
##                fois, ou préchargé via SU_ROOT_PASSWORD) — pour les cibles
##                durcies sans sudo pour le compte d'audit. Nécessite `setsid`.
##                Sans --sudo ni --su : détection automatique (sudo s'il est
##                utilisable, sinon su).
##   --debug      trace d'exécution détaillée (`set -x`) de l'orchestrateur et de
##                chaque script lancé, écrite dans <OUTDIR>/debug_xtrace.log (jamais
##                sur la console). Sans effet avec --dry-run.
##
## Reprise par phase (tester une phase sans rejouer les précédentes) :
##   --from=N        exécute la phase N puis toutes les suivantes
##   --to=N          s'arrête après la phase N (combinable avec --from)
##   --only=N[,M…]   exécute uniquement la/les phase(s) indiquée(s)
##   --list-phases   affiche la liste numérotée des phases (5 à 11) et quitte
##   --resume=DIR    rejoue la/les phase(s) dans un OUTDIR existant (au lieu d'en
##   --resume-last   créer un neuf) ; --resume-last = le plus récent de ce compte.
##                Une phase rejouée écrase ses fichiers ; le résumé final est
##                toujours recalculé sur les fichiers présents. Quand une sélection
##                est donnée, elle l'emporte sur --quick/--full.
##
## Élévation de privilèges :
##   - à lancer de préférence en tant qu'utilisateur normal : les scripts de
##     sur_cible_root/ sont élevés script par script (via `sudo` ou `su`, voir
##     --sudo/--su) ; ceux de sur_cible_user/ (Phase 7) restent non privilégiés,
##     condition nécessaire à la pertinence de leurs résultats (énumération
##     SUID/sudo/PATH du point de vue d'un utilisateur normal).
##   - en mode `su`, `setsid` détache l'appel de tout terminal de contrôle pour
##     que `su` lise le mot de passe depuis stdin (jamais en argument, jamais
##     dans `ps`). Les fichiers de sortie sont alors créés par root en 0644 —
##     lisibles par le compte d'audit.
##   - si ce script est lui-même lancé via `sudo`/en root, aucune élévation :
##     les scripts de sur_cible_user/ sont ré-exécutés en tant que $SUDO_USER
##     quand cette variable est disponible ; sinon un avertissement est affiché
##     (résultats non représentatifs d'un utilisateur non privilégié).
##
## Sortie centralisée dans OUTDIR (${OUTDIR:-$HOME/audit_cible_<hostname>_<horodatage>}) :
## un fichier .txt (ou .json si le script le supporte et --json est demandé) par
## script exécuté, préfixé par son numéro d'ordre.
##
## remediation_reference.sh n'est pas un audit exécutable — voir fr/audit.adoc.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

## ============================================================
## Options
## ============================================================
MODE="quick"
JSON_MODE=0
FORENSICS=0
DRY_RUN=0
DEBUG_MODE=0
## Reprise par phase (voir l'en-tête). Vides = séquence complète (--quick/--full).
PHASE_FROM=""
PHASE_TO=""
PHASE_ONLY=""
RESUME_DIR=""
RESUME_LAST=0
LIST_PHASES=0
## Méthode d'élévation : auto (défaut) | sudo | su | none (déjà root).
ELEVATE="auto"
for arg in "$@"; do
    case "$arg" in
        --quick)          MODE="quick" ;;
        --full)           MODE="full" ;;
        --json)           JSON_MODE=1 ;;
        --forensics)      FORENSICS=1 ;;
        --dry-run)        DRY_RUN=1 ;;
        --debug|--verbose) DEBUG_MODE=1 ;;
        --sudo)           ELEVATE="sudo" ;;
        --su)             ELEVATE="su" ;;
        --from=*)         PHASE_FROM="${arg#*=}" ;;
        --to=*)           PHASE_TO="${arg#*=}" ;;
        --only=*)         PHASE_ONLY="${arg#*=}" ;;
        --resume=*)       RESUME_DIR="${arg#*=}" ;;
        --resume-last)    RESUME_LAST=1 ;;
        --list-phases)    LIST_PHASES=1 ;;
        -h|--help)
            sed -n '2,61p' "$0" | sed 's/^## \{0,1\}//'
            exit 0
            ;;
        *)
            echo "[!] Option inconnue : $arg (voir --help)" >&2
            exit 1
            ;;
    esac
done

## ============================================================
## Sélection des phases (--from / --to / --only / --list-phases)
## ============================================================
## Registre ordonné : "numéro|libellé". La forensique (--forensics) reste
## indépendante : elle passe toujours en premier, hors de cette plage.
_PHASE_LIST=(
    "5|Configuration système (phase5_config_audit.sh)"
    "6|SELinux et contrôle d'accès (phase6_selinux_audit.sh)"
    "7|Élévation de privilèges — non privilégié (phase7_privesc_check.sh, phase5_linpeas_local.sh)"
    "8|Journaux et auditd (phase8_logs_audit.sh)"
    "9|Persistance et backdoors (phase9_persistence_check.sh)"
    "10|Vérifications rapides (check_auditd.sh, check_fedora44_specifics.sh)"
    "11|Audits complémentaires — ~25 scripts audit_*.sh"
)
_PHASE_MIN=5
_PHASE_MAX=11

list_phases() {
    echo "Phases de master_audit_cible.sh :"
    local _e
    for _e in "${_PHASE_LIST[@]}"; do
        printf '  %-3s %s\n' "${_e%%|*}" "${_e#*|}"
    done
    echo
    echo "  --from=N        exécute la phase N puis les suivantes"
    echo "  --to=N          s'arrête après la phase N"
    echo "  --only=N[,M…]   exécute uniquement ces phases"
    echo "  Sans sélection : --quick = 5-10, --full = 5-11."
    echo "  Le résumé final est toujours recalculé. --forensics reste indépendant."
}

_phase_valid() {  # <numéro>
    case "$1" in
        ''|*[!0-9]*) echo "[!] Numéro de phase invalide : '$1'" >&2; exit 2 ;;
    esac
    { [ "$1" -ge "$_PHASE_MIN" ] && [ "$1" -le "$_PHASE_MAX" ]; } \
        || { echo "[!] Phase hors plage : $1 (${_PHASE_MIN}-${_PHASE_MAX}, voir --list-phases)" >&2; exit 2; }
}

## PHASES_ENABLED (" 5 7 9 ") : sélection explicite si donnée, sinon la
## séquence normale du mode (--quick 5-10 / --full 5-11).
PHASES_ENABLED=""
_compute_phases() {
    local _n
    if [ -n "$PHASE_ONLY" ]; then
        [ -z "$PHASE_FROM" ] && [ -z "$PHASE_TO" ] \
            || { echo "[!] --only est incompatible avec --from / --to" >&2; exit 2; }
        local _old_ifs="$IFS"; IFS=','
        for _n in $PHASE_ONLY; do IFS="$_old_ifs"; _phase_valid "$_n"; PHASES_ENABLED+=" $_n "; done
        IFS="$_old_ifs"
    elif [ -n "$PHASE_FROM" ] || [ -n "$PHASE_TO" ]; then
        local _seq_max=10; [ "$MODE" = "full" ] && _seq_max=11
        local _from="${PHASE_FROM:-$_PHASE_MIN}" _to="${PHASE_TO:-$_seq_max}"
        _phase_valid "$_from"; _phase_valid "$_to"
        [ "$_from" -le "$_to" ] || { echo "[!] --from=$_from est postérieur à --to=$_to" >&2; exit 2; }
        for (( _n = _from; _n <= _to; _n++ )); do PHASES_ENABLED+=" $_n "; done
    else
        local _seq_max=10; [ "$MODE" = "full" ] && _seq_max=11
        for (( _n = _PHASE_MIN; _n <= _seq_max; _n++ )); do PHASES_ENABLED+=" $_n "; done
    fi
}

phase_enabled() {  # <numéro> → 0 si la phase doit s'exécuter
    case "$PHASES_ENABLED" in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

if [ "$LIST_PHASES" = "1" ]; then list_phases; exit 0; fi
_compute_phases

## ============================================================
## Répertoire de sortie (neuf, ou repris avec --resume* / OUTDIR)
## ============================================================
RESUMING=0
if [ "$DRY_RUN" = "1" ]; then
    OUTDIR="(dry-run — aucun répertoire créé)"
elif [ -n "$RESUME_DIR" ]; then
    [ -d "$RESUME_DIR" ] || { echo "[!] --resume : répertoire introuvable : $RESUME_DIR" >&2; exit 2; }
    OUTDIR="${RESUME_DIR%/}"; RESUMING=1
    mkdir -p "$OUTDIR"
elif [ "$RESUME_LAST" = "1" ]; then
    ## Motif = hostname + horodatage : `ls` est sûr ici. `|| true` : `ls` sort
    ## en non nul si aucun résultat, ce qui tuerait le script sous `pipefail`.
    # shellcheck disable=SC2012
    OUTDIR="$( { ls -dt "$HOME/audit_cible_$(hostname -s 2>/dev/null || hostname)_"*/ 2>/dev/null || true; } | head -1)"
    OUTDIR="${OUTDIR%/}"
    { [ -n "$OUTDIR" ] && [ -d "$OUTDIR" ]; } \
        || { echo "[!] --resume-last : aucun audit_cible précédent dans $HOME/" >&2; exit 2; }
    RESUMING=1
    mkdir -p "$OUTDIR"
else
    OUTDIR="${OUTDIR:-$HOME/audit_cible_$(hostname -s 2>/dev/null || hostname)_$(date +%Y%m%d_%H%M%S)}"
    mkdir -p "$OUTDIR"
fi
LOG_FILE="$OUTDIR/master_audit_cible.log"
STEP=1

## Mode debug (--debug) : trace d'exécution détaillée de l'orchestrateur et de
## chaque script lancé, dans <OUTDIR>/debug_xtrace.log (pas sur la console).
## Sans objet en --dry-run (aucun OUTDIR).
if [ "$DEBUG_MODE" = "1" ] && [ "$DRY_RUN" != "1" ]; then
    export AUDIT_DEBUG=1
    export AUDIT_XTRACE_FILE="$OUTDIR/debug_xtrace.log"
fi
# shellcheck source=lib_audit_debug.sh
[ -f "$SCRIPT_DIR/lib_audit_debug.sh" ] && source "$SCRIPT_DIR/lib_audit_debug.sh"

## ============================================================
## Affichage
## ============================================================
RED='\033[0;31m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

_out() {
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "$*"
    else
        echo -e "$*" | tee -a "$LOG_FILE"
    fi
}
log()  { _out "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { _out "${GREEN}[OK]${NC} $*"; }
warn() { _out "${ORANGE}[!]${NC} $*"; }
err()  { _out "${RED}[!!!]${NC} $*"; }

banner() {
    local content
    content="$(cat <<EOF
╔══════════════════════════════════════════════════════════╗
║       AUDIT SUR CIBLE — sur_cible_root / sur_cible_user  ║
║  Hôte  : $(hostname)
║  Mode  : $MODE$( [ "$JSON_MODE" = "1" ] && echo " + json" )$( [ "$FORENSICS" = "1" ] && echo " + forensics" )$( [ "$DRY_RUN" = "1" ] && echo " + dry-run" )$( [ "${AUDIT_DEBUG:-0}" = "1" ] && echo " + debug" )$( [ "$ELEVATE" = "sudo" ] || [ "$ELEVATE" = "su" ] && echo " + $ELEVATE" )
║  Date  : $(date)
╚══════════════════════════════════════════════════════════╝
EOF
)"
    _out "$content"
}

## ============================================================
## Prérequis et élévation de privilèges
## ============================================================
SUDO_REFRESH_PID=""
SU_ROOT_PASSWORD="${SU_ROOT_PASSWORD:-}"

cleanup() {
    [ -n "$SUDO_REFRESH_PID" ] && kill "$SUDO_REFRESH_PID" 2>/dev/null || true
    SU_ROOT_PASSWORD=""
}
trap cleanup EXIT

## Exécute une commande shell en root via `su`. `setsid -w` détache l'appel de
## tout terminal de contrôle : `su` lit alors le mot de passe (SU_ROOT_PASSWORD)
## depuis stdin — jamais en argument, jamais visible dans `ps` — et non depuis
## /dev/tty. L'invite « Password: » de `su` part sur stderr (jetée par l'appelant).
_su_root() {
    setsid -w su -c "$1" <<<"$SU_ROOT_PASSWORD"
}

check_prerequisites() {
    if [ "$DRY_RUN" = "1" ]; then
        log "(dry-run : élévation de privilèges ignorée)"
        return
    fi

    if [ "$EUID" -eq 0 ]; then
        ELEVATE="none"
        if [ -z "${SUDO_USER:-}" ]; then
            warn "Lancé directement en root (SUDO_USER non défini) — les résultats de"
            warn "phase7_privesc_check.sh / phase5_linpeas_local.sh ne refléteront pas la"
            warn "perspective d'un utilisateur non privilégié. Préférer un lancement depuis"
            warn "un compte normal (ce script élève lui-même les scripts root)."
        fi
        return
    fi

    ## Résolution du mode auto : sudo s'il est réellement utilisable, sinon su.
    if [ "$ELEVATE" = "auto" ]; then
        if command -v sudo &>/dev/null && sudo -v 2>/dev/null; then
            ELEVATE="sudo"
            log "Élévation : sudo (détecté)"
        else
            ELEVATE="su"
            log "Élévation : su (sudo indisponible ou non autorisé pour ce compte)"
        fi
    fi

    case "$ELEVATE" in
        sudo)
            command -v sudo &>/dev/null || { err "--sudo demandé mais 'sudo' est introuvable"; exit 1; }
            log "Vérification des privilèges sudo (mot de passe demandé si nécessaire)..."
            sudo -v || { err "Échec de l'authentification sudo"; exit 1; }
            ## Rafraîchit le cache d'identifiants sudo toutes les 60s, pour
            ## enchaîner les phases sans nouvelle demande de mot de passe.
            ( while true; do sudo -n -v 2>/dev/null; sleep 60; done ) &
            SUDO_REFRESH_PID=$!
            ;;
        su)
            command -v su &>/dev/null || { err "'su' est introuvable"; exit 1; }
            command -v setsid &>/dev/null || {
                err "'setsid' (util-linux) est requis pour l'élévation via su."
                err "Installer util-linux, ou relancer avec --sudo, ou en tant que root."
                exit 1
            }
            if [ -z "$SU_ROOT_PASSWORD" ]; then
                read -rsp "Mot de passe root (su) sur $(hostname -s 2>/dev/null || hostname) : " SU_ROOT_PASSWORD
                echo ""
            fi
            ## Valide le mot de passe tout de suite (évite ~30 échecs en série).
            if ! _su_root "true" >/dev/null 2>&1; then
                err "Échec de 'su' vers root — mot de passe incorrect, ou su restreint"
                err "(groupe wheel / pam_wheel dans /etc/pam.d/su)."
                exit 1
            fi
            log "Élévation : su — mot de passe root validé"
            ;;
    esac
}

## ============================================================
## Exécution d'un script, capture de sa sortie, gestion des privilèges
## ============================================================
JSON_CAPABLE=" audit_aide_integrity audit_clamav audit_container_escape audit_disk_encryption audit_firewall_rules audit_grub_security audit_mfa audit_pam_config audit_rsyslog_remote audit_timesync audit_wireguard "

is_json_capable() {
    case "$JSON_CAPABLE" in
        *" $1 "*) return 0 ;;
        *)        return 1 ;;
    esac
}

## run_step <root|user> <chemin relatif depuis scripts/> [args...]
run_step() {
    local ctx="$1" rel="$2"; shift 2
    local script="$SCRIPT_DIR/$rel"
    local name; name="$(basename "$rel" .sh)"
    local ext="txt"
    local args=("$@")

    if [ "$JSON_MODE" = "1" ] && is_json_capable "$name"; then
        args+=(--json)
        ext="json"
    fi

    if [ ! -f "$script" ]; then
        warn "Script introuvable : $rel — ignoré"
        return
    fi

    if [ "$DRY_RUN" = "1" ]; then
        log "$(printf '%02d' "$STEP") [$ctx] $rel${args[*]:+ ${args[*]}}"
        STEP=$((STEP + 1))
        return
    fi

    ## En reprise (--resume*), retirer une éventuelle sortie précédente de CE
    ## script (quel que soit son ancien numéro d'ordre) pour ne pas la compter
    ## deux fois dans le résumé / le scoring.
    if [ "${RESUMING:-0}" = "1" ]; then
        rm -f "$OUTDIR"/[0-9][0-9]_"$name".txt "$OUTDIR"/[0-9][0-9]_"$name".json 2>/dev/null || true
    fi

    local out
    out="$(printf '%s/%02d_%s.%s' "$OUTDIR" "$STEP" "$name" "$ext")"
    STEP=$((STEP + 1))

    log "-> $rel${args[*]:+ ${args[*]}}"
    ## En mode --debug, propager la trace à l'environnement du script élevé
    ## (sudo réinitialise l'environnement ; su aussi) : il écrit alors dans le
    ## même debug_xtrace.log.
    local -a dbg_env=()
    if [ "${AUDIT_DEBUG:-0}" = "1" ]; then
        dbg_env=("AUDIT_DEBUG=1" "AUDIT_XTRACE_FILE=$AUDIT_XTRACE_FILE")
    fi
    local rc=0
    case "$ctx" in
        root)
            case "$ELEVATE" in
                none)
                    env ${dbg_env[@]+"${dbg_env[@]}"} bash "$script" "${args[@]}" > "$out" 2>&1 || rc=$?
                    ;;
                sudo)
                    # shellcheck disable=SC2024 # redirect ouvert par le shell courant
                    # (non privilégié) avant l'exec de sudo : $out reste possédé par
                    # l'utilisateur invoquant, dans $OUTDIR sous son $HOME — voulu.
                    sudo ${dbg_env[@]+"${dbg_env[@]}"} bash "$script" "${args[@]}" > "$out" 2>&1 || rc=$?
                    ;;
                su)
                    ## La redirection est faite DANS la commande su (root) : $out
                    ## est donc créé par root, en 0644. L'invite « Password: » de
                    ## su (stderr, hors su -c) est jetée.
                    local _inner
                    _inner="export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; "
                    _inner+="$(printf '%q ' env ${dbg_env[@]+"${dbg_env[@]}"} bash "$script" "${args[@]}")"
                    _inner+="> $(printf '%q' "$out") 2>&1; __rc=\$?; chmod 0644 $(printf '%q' "$out") 2>/dev/null || true; exit \$__rc"
                    _su_root "$_inner" >/dev/null 2>&1 || rc=$?
                    ;;
            esac
            ;;
        user)
            if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
                if command -v sudo &>/dev/null; then
                    # shellcheck disable=SC2024 # voir commentaire ci-dessus
                    sudo -u "$SUDO_USER" ${dbg_env[@]+"${dbg_env[@]}"} bash "$script" "${args[@]}" > "$out" 2>&1 || rc=$?
                else
                    ## Pas de sudo : redescendre vers l'utilisateur via `su`
                    ## (aucun mot de passe requis quand on part de root).
                    su -c "$(printf '%q ' env ${dbg_env[@]+"${dbg_env[@]}"} bash "$script" "${args[@]}")" "$SUDO_USER" > "$out" 2>&1 || rc=$?
                fi
            else
                env ${dbg_env[@]+"${dbg_env[@]}"} bash "$script" "${args[@]}" > "$out" 2>&1 || rc=$?
            fi
            ;;
    esac

    if [ "$rc" -eq 0 ]; then
        ok "   $(basename "$out")"
    else
        warn "   $rel : code retour $rc — voir $(basename "$out")"
    fi
}

## ============================================================
## Séquence — Phase 10 (forensique, optionnelle, toujours en premier)
## ============================================================
run_forensics() {
    log "=== FORENSIQUE : SNAPSHOT PRÉ-INTERVENTION ==="
    run_step root sur_cible_root/phase10_forensics_collect.sh
}

## ============================================================
## Séquence — cœur (--quick) : Phases 5, 6, 7, 8, 9 + vérifications rapides
## ============================================================
## Chaque bloc est encadré par `phase_enabled N` : --from/--to/--only ne jouent
## que ceux-là. Sans sélection, PHASES_ENABLED contient toute la séquence du mode.
run_core() {
    if phase_enabled 5; then
        log "=== PHASE 5 : CONFIGURATION SYSTÈME ==="
        run_step root sur_cible_root/phase5_config_audit.sh
    fi

    if phase_enabled 6; then
        log "=== PHASE 6 : SELINUX ET CONTRÔLE D'ACCÈS ==="
        run_step root sur_cible_root/phase6_selinux_audit.sh
    fi

    if phase_enabled 7; then
        log "=== PHASE 7 : ÉLÉVATION DE PRIVILÈGES (utilisateur normal) ==="
        run_step user sur_cible_user/phase7_privesc_check.sh
        run_step user sur_cible_user/phase5_linpeas_local.sh
    fi

    if phase_enabled 8; then
        log "=== PHASE 8 : JOURNAUX ET AUDITD ==="
        run_step root sur_cible_root/phase8_logs_audit.sh
    fi

    if phase_enabled 9; then
        log "=== PHASE 9 : PERSISTANCE ET BACKDOORS ==="
        run_step root sur_cible_root/phase9_persistence_check.sh
    fi

    if phase_enabled 10; then
        log "=== VÉRIFICATIONS RAPIDES ==="
        run_step root sur_cible_root/check_auditd.sh
        run_step root sur_cible_root/check_fedora44_specifics.sh
    fi
}

## ============================================================
## Séquence — audits complémentaires (--full uniquement)
## ============================================================
run_complementary() {
    phase_enabled 11 || return 0
    log "=== AUDITS COMPLÉMENTAIRES ==="
    local scripts=(
        audit_podman.sh
        audit_container_escape.sh
        audit_crypto_policy.sh
        audit_pam_config.sh
        audit_mfa.sh
        audit_ssh_keys.sh
        audit_tls_certs.sh
        audit_firewall_rules.sh
        audit_kernel_hardening.sh
        audit_grub_security.sh
        audit_disk_encryption.sh
        audit_systemd_credentials.sh
        audit_rsyslog_remote.sh
        audit_timesync.sh
        audit_wireguard.sh
        audit_clamav.sh
        audit_aide_integrity.sh
        audit_web_apps.sh
        audit_databases.sh
        audit_nfs_smb.sh
        audit_dns_server.sh
        audit_mail_server.sh
        audit_freeipa.sh
        audit_sssd_ad.sh
        audit_supply_chain.sh
    )
    local s
    for s in "${scripts[@]}"; do
        run_step root "sur_cible_root/$s"
    done
}

## ============================================================
## Résumé final
## ============================================================
summarize() {
    if [ "$DRY_RUN" = "1" ]; then
        log "=== RÉSUMÉ (dry-run) ==="
        log "$((STEP - 1)) script(s) seraient exécutés — aucune action réalisée."
        log "Relancer sans --dry-run pour un audit réel."
        return
    fi

    log "=== RÉSUMÉ ==="
    local crit high nok
    ## `|| true` : `grep` sort en 1 quand un marqueur est absent (fréquent —
    ## p. ex. aucun `[!!!]` critique), ce qui, sous `set -o pipefail` + `set -e`,
    ## tuerait la substitution et donc tout le résumé.
    crit=$(grep -rhF "[!!!]" "$OUTDIR" 2>/dev/null | wc -l || true)
    high=$(grep -rhF "[!]" "$OUTDIR" 2>/dev/null | wc -l || true)
    nok=$(grep -rhF "[NOK]" "$OUTDIR" 2>/dev/null | wc -l || true)
    log "Findings : $crit critique(s) / $high alerte(s) / $nok non conforme(s)"
    log "Résultats complets dans : $OUTDIR/"
    [ "${AUDIT_DEBUG:-0}" = "1" ] && [ -f "${AUDIT_XTRACE_FILE:-}" ] \
        && log "Trace debug : $AUDIT_XTRACE_FILE ($(wc -l < "$AUDIT_XTRACE_FILE") lignes)"
    log ""
    log "Prochaine étape (depuis Kali, après rapatriement de $OUTDIR/) :"
    log "  bash depuis_kali/generate_json_summary.sh  $OUTDIR <IP_CIBLE> <AUDITEUR>"
    log "  bash depuis_kali/generate_score_report.sh  $OUTDIR <IP_CIBLE> <AUDITEUR>"
}

## ============================================================
## MAIN
## ============================================================
main() {
    banner
    if [ "$RESUMING" = "1" ]; then
        log "Reprise dans le répertoire existant : $OUTDIR"
    fi
    log "Phases exécutées :$PHASES_ENABLED — résumé toujours recalculé"
    check_prerequisites

    if [ "$FORENSICS" = "1" ]; then run_forensics; fi

    run_core
    run_complementary   ## no-op si la phase 11 n'est pas dans la sélection

    summarize
}

main
