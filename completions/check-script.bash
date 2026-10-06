# Bash completion for check-script.
#
# Installation:
#   sudo cp completions/check-script.bash /etc/bash_completion.d/check-script
# or, for the current user:
#   mkdir -p ~/.local/share/bash-completion/completions
#   cp completions/check-script.bash ~/.local/share/bash-completion/completions/check-script

_check_script() {
  local cur prev opts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  opts="--output -o --format -f --lang -l --shell -s --python-target --profile -p --context \
--follow-source --config -c --with --without --no-external --ref --embedded --no-embedded --watch -w --jobs -j --exclude --all --changed-since --dashboard --history-dir --cache --no-cache --explain --sort --baseline -b --baseline-update --fail-on-new \
--fix --interactive -i --dry-run --backup --details --summary --source --no-source --color --no-color --quiet -q \
--fail-under --list-tools --list-rules --version -v --help -h"

  case "$prev" in
    --format | -f)
      mapfile -t COMPREPLY < <(compgen -W "terminal md adoc html pdf json sarif codeclimate gitlab junit github" -- "$cur")
      return 0
      ;;
    --lang | -l)
      mapfile -t COMPREPLY < <(compgen -W "fr en" -- "$cur")
      return 0
      ;;
    --shell | -s)
      mapfile -t COMPREPLY < <(compgen -W "sh bash dash ksh zsh python" -- "$cur")
      return 0
      ;;
    --profile | -p)
      mapfile -t COMPREPLY < <(compgen -W "strict default legacy" -- "$cur")
      return 0
      ;;
    --context)
      mapfile -t COMPREPLY < <(compgen -W "root cron systemd interactive" -- "$cur")
      return 0
      ;;
    --with | --without)
      mapfile -t COMPREPLY < <(compgen -W "shellcheck shfmt bashate checkbashisms ruff bandit semgrep mypy pyright pylint radon vermin pydeps pip-audit hadolint actionlint zizmor commands gitleaks trufflehog syntax builtin custom" -- "$cur")
      return 0
      ;;
    --sort)
      mapfile -t COMPREPLY < <(compgen -W "category impact" -- "$cur")
      return 0
      ;;
    --python-target)
      mapfile -t COMPREPLY < <(compgen -W "3.6 3.7 3.8 3.9 3.10 3.11 3.12 3.13 3.14" -- "$cur")
      return 0
      ;;
    --fail-on-new)
      mapfile -t COMPREPLY < <(compgen -W "low medium high critical" -- "$cur")
      return 0
      ;;
    --fail-under)
      mapfile -t COMPREPLY < <(compgen -W "security= robustness= maintainability= portability= performance=" -- "$cur")
      compopt -o nospace 2>/dev/null
      return 0
      ;;
    --output | -o | --config | -c | --baseline | -b)
      mapfile -t COMPREPLY < <(compgen -f -- "$cur")
      return 0
      ;;
  esac

  # Sous-commandes : explain RÈGLE, init [DOSSIER], lsp.
  if [[ $COMP_CWORD -eq 1 && "$cur" != -* ]]; then
    mapfile -t COMPREPLY < <(compgen -W "explain init diff lsp" -- "$cur"; compgen -f -- "$cur")
    return 0
  fi
  if [[ "${COMP_WORDS[1]}" == init ]]; then
    mapfile -t COMPREPLY < <(compgen -W "--profile -p --context --exclude --baseline --no-analysis --no-external --force -f --stdout --lang -l --help -h" -- "$cur"; compgen -d -- "$cur")
    return 0
  fi
  if [[ "${COMP_WORDS[1]}" == diff ]]; then
    if [[ "$prev" == --format || "$prev" == -f ]]; then
      mapfile -t COMPREPLY < <(compgen -W "text md json" -- "$cur")
    elif [[ "$cur" == -* ]]; then
      mapfile -t COMPREPLY < <(compgen -W "--format -f --summary --fail-on-new --fail-on-worse --lang -l --help -h" -- "$cur")
    else
      mapfile -t COMPREPLY < <(compgen -f -- "$cur")
    fi
    return 0
  fi
  if [[ "${COMP_WORDS[1]}" == explain ]]; then
    mapfile -t COMPREPLY < <(compgen -W "--lang -l --config -c --help -h" -- "$cur")
    return 0
  fi

  if [[ "$cur" == -* ]]; then
    mapfile -t COMPREPLY < <(compgen -W "$opts" -- "$cur")
  else
    mapfile -t COMPREPLY < <(compgen -f -- "$cur")
  fi
}
complete -o filenames -F _check_script check-script
