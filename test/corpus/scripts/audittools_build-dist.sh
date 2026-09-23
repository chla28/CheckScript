#!/usr/bin/env bash
# build-dist.sh — Construit (et installe) les livrables de tous les sous-projets
# AuditTools.
#
# Parcourt chaque sous-dossier de la racine AuditTools qui expose un
# scripts/build-dist.sh (ou scripts/builddist.sh) et l'execute. Les archives
# restent dans le dist/ de chaque projet ; ce script se contente d'orchestrer
# et de recapituler.
#
# Usage : ./scripts/build-dist.sh [--pull|--pull-only] [--push] [--rpm] [--install] [--uninstall] [--list] [PROJET...]
#   --pull       avant toute construction, execute `git pull --ff-only` dans la
#                racine AuditTools puis dans chaque sous-dossier qui est un
#                depot git (les symlinks sont suivis). Un depot en echec (arbre
#                sale, divergence, pas d'upstream) est signale au recap sans
#                interrompre les autres. Restreint par PROJET... si fourni
#                (la racine n'est alors pas mise a jour).
#   --pull-only  fait uniquement le `git pull --ff-only` ci-dessus (meme
#                perimetre, meme recap) puis quitte : aucun build, aucune
#                installation, aucun push. Incompatible avec --push, --rpm,
#                --install, --uninstall et --list.
#   --push       en fin d'execution (apres le build et --install), execute
#                `git push` dans la racine AuditTools et chaque sous-depot dont
#                la branche courante est en avance sur son upstream. Jamais de
#                --force ; ne commit rien (les modifs non commitees sont juste
#                signalees). Meme perimetre et meme filtre que --pull.
#   --rpm        transmis aux seuls scripts qui savent le gerer ; les autres
#                sont appeles sans (detection automatique).
#   --install    apres chaque build reussi, execute dist/<paquet>/install.sh
#                (installation utilisateur dans ~/.local).
#   --uninstall  n'installe et ne construit rien : execute le uninstall.sh de
#                chaque projet (dist/<paquet>/ sinon scripts/) puis quitte.
#   --list       affiche les projets detectes puis quitte.
#   PROJET...    restreint l'action aux dossiers nommes (ex. MainGUI GenCVEDoc).
#
# Toutes les etapes sont tentees ; le script sort en code non nul si l'une
# d'elles a echoue.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

WITH_RPM=false
LIST_ONLY=false
DO_INSTALL=false
DO_UNINSTALL=false
DO_PULL=false
DO_PULL_ONLY=false
DO_PUSH=false
declare -a FILTER=()

for arg in "$@"; do
  case "$arg" in
    --pull)      DO_PULL=true ;;
    --pull-only) DO_PULL=true; DO_PULL_ONLY=true ;;
    --push)      DO_PUSH=true ;;
    --rpm)       WITH_RPM=true ;;
    --install)   DO_INSTALL=true ;;
    --uninstall) DO_UNINSTALL=true ;;
    --list)      LIST_ONLY=true ;;
    --help|-h)
      awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"
      exit 0 ;;
    -*)          echo "Option inconnue : $arg" >&2; exit 1 ;;
    *)           FILTER+=("$arg") ;;
  esac
done

if $DO_INSTALL && $DO_UNINSTALL; then
  echo "Options incompatibles : --install et --uninstall." >&2
  exit 1
fi

if $DO_PULL_ONLY && { $DO_PUSH || $WITH_RPM || $DO_INSTALL || $DO_UNINSTALL || $LIST_ONLY; }; then
  echo "Option --pull-only incompatible avec --push/--rpm/--install/--uninstall/--list." >&2
  exit 1
fi

_in_filter() {
  [[ ${#FILTER[@]} -eq 0 ]] && return 0
  local needle="$1" f
  for f in "${FILTER[@]}"; do [[ "$f" == "$needle" ]] && return 0; done
  return 1
}

# Un script accepte --rpm s'il le mentionne dans son analyse d'options.
_supports_rpm() { grep -qE -- '--rpm' "$1"; }

# Vrai si $1 est la racine de son propre depot git (et pas un sous-dossier
# rattache au depot AuditTools parent, ni un lien casse).
_is_repo_root() {
  local real top
  real="$(realpath "$1" 2>/dev/null)" || return 1
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ -n "$top" && "$real" == "$top" ]]
}

# Applique la fonction $1 (label, chemin) a la racine AuditTools (sauf si un
# filtre PROJET... est actif) puis a chaque sous-dossier de la racine qui est
# la racine de son propre depot git (symlinks suivis, respecte le filtre).
_for_each_repo() {
  local cb="$1" dir name
  [[ ${#FILTER[@]} -eq 0 ]] && "$cb" "AuditTools" "$ROOT_DIR"
  while IFS= read -r dir; do
    name="$(basename "$dir")"
    [[ "$name" == .* || "$name" == "scripts" ]] && continue
    _in_filter "$name" || continue
    _is_repo_root "$dir" || continue
    "$cb" "$name" "$dir"
  done < <(find -L "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
}

# install.sh fraichement construit (a le payload gui/ bin/ a cote).
_find_install() {
  find -L "${ROOT_DIR}/$1/dist" -maxdepth 2 -type f -name 'install.sh' 2>/dev/null \
    | sort | tail -1
}

# uninstall.sh : celui du paquet si present, sinon celui des sources.
_find_uninstall() {
  local f
  f="$(find -L "${ROOT_DIR}/$1/dist" -maxdepth 2 -type f -name 'uninstall.sh' 2>/dev/null | sort | tail -1)"
  [[ -n "$f" ]] && { echo "$f"; return 0; }
  [[ -f "${ROOT_DIR}/$1/scripts/uninstall.sh" ]] && { echo "${ROOT_DIR}/$1/scripts/uninstall.sh"; return 0; }
  return 1
}

# ── Detection des projets ──────────────────────────────────────────────────
declare -a NAMES=() SCRIPTS=() SKIPPED=()

while IFS= read -r dir; do
  name="$(basename "$dir")"
  [[ "$name" == "scripts" ]] && continue

  script=""
  if   [[ -f "$dir/scripts/build-dist.sh" ]]; then script="$dir/scripts/build-dist.sh"
  elif [[ -f "$dir/scripts/builddist.sh"  ]]; then script="$dir/scripts/builddist.sh"
  fi

  if [[ -z "$script" ]]; then
    # Projet Flutter/Dart sans script de build : on le signale.
    [[ -f "$dir/pubspec.yaml" ]] && _in_filter "$name" && SKIPPED+=("$name")
    continue
  fi

  _in_filter "$name" || continue
  NAMES+=("$name")
  SCRIPTS+=("$script")
done < <(find -L "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

# MainGUI (l'agregateur) traite en dernier s'il est present.
for i in "${!NAMES[@]}"; do
  if [[ "${NAMES[$i]}" == "MainGUI" ]]; then
    NAMES+=("${NAMES[$i]}"); SCRIPTS+=("${SCRIPTS[$i]}")
    unset 'NAMES[i]' 'SCRIPTS[i]'
    NAMES=("${NAMES[@]}"); SCRIPTS=("${SCRIPTS[@]}")
    break
  fi
done

OVERALL=0

# ── Mise a jour des depots (--pull) ───────────────────────────────────────
if $DO_PULL; then
  echo "╔══════════════════════════════════════════╗"
  echo "║  AuditTools — git pull des depots         ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""

  declare -a P_NAME=() P_STATUS=()

  _pull_one() {
    local label="$1" path="$2" st br
    br="$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || echo 'HEAD detache')"
    echo "────────────────────────────────────────────────────────────"
    echo "▶ ${label}   ($(realpath "$path") @ ${br})"
    echo "────────────────────────────────────────────────────────────"
    if git -C "$path" pull --ff-only; then
      st="OK (${br})"
    else
      st="ECHEC (${br})"
      OVERALL=1
    fi
    P_NAME+=("$label"); P_STATUS+=("$st")
    echo ""
  }

  _for_each_repo _pull_one

  echo "╔══════════════════════════════════════════╗"
  echo "║  Recapitulatif git pull                   ║"
  echo "╚══════════════════════════════════════════╝"
  for i in "${!P_NAME[@]}"; do
    printf '  %-16s %s\n' "${P_NAME[$i]}" "${P_STATUS[$i]}"
  done
  echo ""

  if $DO_PULL_ONLY; then
    [[ "$OVERALL" -eq 0 ]] && echo "✅ Pull termine." || echo "❌ Au moins un pull a echoue."
    exit "$OVERALL"
  fi
fi

if [[ ${#NAMES[@]} -eq 0 ]]; then
  echo "Aucun sous-projet avec scripts/build-dist.sh trouve sous ${ROOT_DIR}." >&2
  exit 1
fi

# ── Liste seule ────────────────────────────────────────────────────────────
if $LIST_ONLY; then
  echo "Projets detectes (${#NAMES[@]}) :"
  for i in "${!NAMES[@]}"; do
    rpm="non"; _supports_rpm "${SCRIPTS[$i]}" && rpm="oui"
    printf '  %-16s %-28s (--rpm: %s)\n' \
      "${NAMES[$i]}" "${NAMES[$i]}/scripts/$(basename "${SCRIPTS[$i]}")" "$rpm"
  done
  if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo ""
    echo "Ignores (pas de script de build) : ${SKIPPED[*]}"
  fi
  exit 0
fi

# ── Mode desinstallation ──────────────────────────────────────────────────
if $DO_UNINSTALL; then
  echo "╔══════════════════════════════════════════╗"
  echo "║  AuditTools — Desinstallation             ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""
  declare -a U_NAME=() U_STATUS=()
  for name in "${NAMES[@]}"; do
    echo "────────────────────────────────────────────────────────────"
    if script="$(_find_uninstall "$name")"; then
      echo "▶ ${name}   ($(realpath --relative-to="$ROOT_DIR" "$script"))"
      echo "────────────────────────────────────────────────────────────"
      if bash "$script"; then st="OK"; else st="ECHEC"; OVERALL=1; fi
    else
      echo "▶ ${name}   (aucun uninstall.sh)"
      echo "────────────────────────────────────────────────────────────"
      st="n/a"
    fi
    U_NAME+=("$name"); U_STATUS+=("$st")
    echo ""
  done

  echo "╔══════════════════════════════════════════╗"
  echo "║  Recapitulatif desinstallation           ║"
  echo "╚══════════════════════════════════════════╝"
  for i in "${!U_NAME[@]}"; do
    printf '  %-16s %s\n' "${U_NAME[$i]}" "${U_STATUS[$i]}"
  done
  echo ""
  [[ "$OVERALL" -eq 0 ]] && echo "✅ Termine." || echo "❌ Au moins un uninstall.sh a echoue."
  exit "$OVERALL"
fi

# ── Build (+ install optionnel) ───────────────────────────────────────────
MARKER="$(mktemp)"; trap 'rm -f "$MARKER"' EXIT

echo "╔══════════════════════════════════════════╗"
echo "║  AuditTools — Build de tous les livrables ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Racine   : ${ROOT_DIR}"
echo "Projets  : ${NAMES[*]}"
echo "Pull     : $($DO_PULL && echo 'oui (git pull --ff-only, effectue)' || echo 'non')"
echo "RPM      : $($WITH_RPM && echo 'oui (si supporte)' || echo 'non')"
echo "Install  : $($DO_INSTALL && echo 'oui (~/.local, apres chaque build reussi)' || echo 'non')"
echo "Push     : $($DO_PUSH && echo 'oui (git push en fin de run)' || echo 'non')"
[[ ${#SKIPPED[@]} -gt 0 ]] && echo "Ignores  : ${SKIPPED[*]} (pas de script de build)"
echo ""

declare -a R_NAME=() R_STATUS=() R_DUR=() R_RPM=() R_INSTALL=()

for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"
  script="${SCRIPTS[$i]}"

  declare -a call_args=()
  rpm_note="-"
  if $WITH_RPM && _supports_rpm "$script"; then
    call_args+=(--rpm)
    rpm_note="--rpm"
  fi

  echo "────────────────────────────────────────────────────────────"
  echo "▶ ${name}   (${name}/scripts/$(basename "$script") ${call_args[*]})"
  echo "────────────────────────────────────────────────────────────"

  start=$SECONDS
  if bash "$script" ${call_args[@]+"${call_args[@]}"}; then
    status="OK"
  else
    status="ECHEC"
    OVERALL=1
  fi
  dur=$(( SECONDS - start ))

  install_note="-"
  if $DO_INSTALL; then
    if [[ "$status" != "OK" ]]; then
      install_note="ignore (build KO)"
    elif inst="$(_find_install "$name")" && [[ -n "$inst" ]]; then
      echo ""
      echo "▶ Installation : $(realpath --relative-to="$ROOT_DIR" "$inst")"
      if bash "$inst"; then install_note="installe"; else install_note="ECHEC"; OVERALL=1; fi
    else
      install_note="pas d'install.sh"
    fi
  fi

  R_NAME+=("$name"); R_STATUS+=("$status"); R_DUR+=("${dur}s")
  R_RPM+=("$rpm_note"); R_INSTALL+=("$install_note")
  echo ""
done

# ── Recapitulatif ──────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════╗"
echo "║  Recapitulatif                           ║"
echo "╚══════════════════════════════════════════╝"
if $DO_INSTALL; then
  printf '  %-16s %-8s %8s  %-7s  %s\n' "PROJET" "STATUT" "DUREE" "RPM" "INSTALL"
  for i in "${!R_NAME[@]}"; do
    printf '  %-16s %-8s %8s  %-7s  %s\n' \
      "${R_NAME[$i]}" "${R_STATUS[$i]}" "${R_DUR[$i]}" "${R_RPM[$i]}" "${R_INSTALL[$i]}"
  done
else
  printf '  %-16s %-8s %8s  %s\n' "PROJET" "STATUT" "DUREE" "RPM"
  for i in "${!R_NAME[@]}"; do
    printf '  %-16s %-8s %8s  %s\n' \
      "${R_NAME[$i]}" "${R_STATUS[$i]}" "${R_DUR[$i]}" "${R_RPM[$i]}"
  done
fi
echo ""

echo "Archives produites :"
found=0
for name in "${NAMES[@]}"; do
  dist="${ROOT_DIR}/${name}/dist"
  [[ -d "$dist" ]] || continue
  while IFS= read -r f; do
    printf '  %s\n' "$(realpath --relative-to="$ROOT_DIR" "$f")"
    found=1
  done < <(find -L "$dist" -newer "$MARKER" \( -name '*.tar.gz' -o -name '*.rpm' \) 2>/dev/null | sort)
done
[[ "$found" -eq 0 ]] && echo "  (aucune archive datee de cette execution)"
echo ""

# ── Push des depots (--push) ─────────────────────────────────────────────────
if $DO_PUSH; then
  echo "╔══════════════════════════════════════════╗"
  echo "║  AuditTools — git push des depots         ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""

  declare -a PUSH_NAME=() PUSH_STATUS=()

  _push_one() {
    local label="$1" path="$2" st br upstream ahead dirty=""
    br="$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || echo '')"
    echo "────────────────────────────────────────────────────────────"
    echo "▶ ${label}   ($(realpath "$path") @ ${br:-HEAD detache})"
    echo "────────────────────────────────────────────────────────────"

    [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]] \
      && dirty=" [modifs non commitees ignorees]"

    if [[ -z "$br" ]]; then
      echo "HEAD detache — rien a pousser."
      st="ECHEC (HEAD detache)"; OVERALL=1
    elif ! upstream="$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"; then
      echo "Pas d'upstream configure pour '${br}'."
      st="ECHEC (pas d'upstream)"; OVERALL=1
    else
      ahead="$(git -C "$path" rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)"
      if [[ "${ahead:-0}" -eq 0 ]]; then
        echo "Deja a jour avec ${upstream}."
        st="a jour"
      elif git -C "$path" push; then
        st="OK (${ahead} commit(s) -> ${upstream})"
      else
        st="ECHEC (push rejete)"; OVERALL=1
      fi
    fi
    PUSH_NAME+=("$label"); PUSH_STATUS+=("${st}${dirty}")
    echo ""
  }

  _for_each_repo _push_one

  echo "╔══════════════════════════════════════════╗"
  echo "║  Recapitulatif git push                   ║"
  echo "╚══════════════════════════════════════════╝"
  for i in "${!PUSH_NAME[@]}"; do
    printf '  %-16s %s\n' "${PUSH_NAME[$i]}" "${PUSH_STATUS[$i]}"
  done
  echo ""
fi

if [[ "$OVERALL" -eq 0 ]]; then
  echo "✅ Toutes les etapes ont reussi."
else
  echo "❌ Au moins une etape a echoue (voir le recapitulatif)."
fi
exit "$OVERALL"
