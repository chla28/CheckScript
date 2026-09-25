# Complétion bash pour check-script.
#
# Installation :
#   sudo cp completions/check-script.bash /etc/bash_completion.d/check-script
# ou, pour l'utilisateur courant :
#   mkdir -p ~/.local/share/bash-completion/completions
#   cp completions/check-script.bash ~/.local/share/bash-completion/completions/check-script

_check_script() {
  local cur prev opts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  opts="--output -o --format -f --lang -l --shell -s --python-target --profile -p --context \
--follow-source --config -c --with --without --no-external --jobs -j --all --baseline -b --fail-on-new \
--fix --dry-run --backup --details --summary --source --no-source --color --no-color --quiet -q \
--fail-under --list-tools --list-rules --version -v --help -h"

  case "$prev" in
    --format | -f)
      mapfile -t COMPREPLY < <(compgen -W "terminal md adoc html json sarif codeclimate" -- "$cur")
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
      mapfile -t COMPREPLY < <(compgen -W "shellcheck shfmt bashate checkbashisms ruff bandit semgrep mypy pyright pylint radon vermin gitleaks trufflehog syntax builtin" -- "$cur")
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

  if [[ "$cur" == -* ]]; then
    mapfile -t COMPREPLY < <(compgen -W "$opts" -- "$cur")
  else
    mapfile -t COMPREPLY < <(compgen -f -- "$cur")
  fi
}
complete -o filenames -F _check_script check-script
