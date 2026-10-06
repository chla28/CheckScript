# fish completion for check-script.
#
# Installation:
#   cp completions/check-script.fish ~/.config/fish/completions/
# or system-wide:
#   sudo cp completions/check-script.fish /usr/share/fish/vendor_completions.d/

set -l subcommands explain init diff lsp

# Sous-commandes (premier argument seulement).
complete -c check-script -f -n "not __fish_seen_subcommand_from $subcommands" -a explain -d 'Describe a rule (example, references)'
complete -c check-script -f -n "not __fish_seen_subcommand_from $subcommands" -a init -d 'Write a .checkscript.yaml'
complete -c check-script -f -n "not __fish_seen_subcommand_from $subcommands" -a diff -d 'Compare two JSON reports'
complete -c check-script -f -n "not __fish_seen_subcommand_from $subcommands" -a lsp -d 'LSP server for editors'

# Options communes.
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -s o -l output -r -F -d 'Report file (repeatable)'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -s f -l format -x -a 'terminal md adoc html pdf json sarif codeclimate gitlab junit github' -d 'Output format'
complete -c check-script -s l -l lang -x -a 'fr en' -d 'Language'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -s s -l shell -x -a 'sh bash dash ksh zsh python' -d 'Force the dialect'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l python-target -x -a '3.6 3.7 3.8 3.9 3.10 3.11 3.12 3.13 3.14' -d 'Minimum Python version'
complete -c check-script -s p -l profile -x -a 'strict default legacy' -d 'Scoring profile'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l context -x -a 'root cron systemd interactive' -d 'Execution context'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l follow-source -d 'Follow sourced files'
complete -c check-script -s c -l config -r -F -d 'YAML configuration'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l with -x -a 'pylint pyright' -d 'Enable a tool'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l without -x -a 'shellcheck shfmt bashate checkbashisms ruff bandit semgrep mypy pyright pylint radon vermin pydeps pip-audit hadolint actionlint zizmor commands gitleaks trufflehog syntax builtin custom' -d 'Disable a tool'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l no-external -d 'Built-in rules only'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l ref -x -d 'CWE, OWASP or ANSSI reference'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l exclude -x -d 'Ignore matching paths (.gitignore syntax)'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l embedded -d 'Analyse embedded scripts (default)'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l no-embedded -d 'Skip embedded scripts'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -s w -l watch -d 'Re-analyse on every save'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -s j -l jobs -x -d 'Scripts analysed concurrently'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l changed-since -x -d 'Only scripts changed since a git reference'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l dashboard -r -F -d 'Team dashboard (HTML)'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l history-dir -r -a '(__fish_complete_directories)' -d 'History of analysed folders'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l cache -d 'Reuse results (default)'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l no-cache -d 'Re-analyse everything'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l explain -d 'Cost of each rule on the score'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l sort -x -a 'category impact' -d 'Order of issues'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -s b -l baseline -r -F -d 'Baseline JSON report'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l baseline-update -d 'Rewrite the baseline without the fixed issues'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l fail-on-new -x -a 'low medium high critical' -d 'Fail on a new issue'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l fix -d 'Fix safe defects'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -s i -l interactive -d 'With --fix: confirm each fix'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l dry-run -d 'Print the diff without writing'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l backup -d 'Keep FILE.orig'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l details -d 'All issues'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l summary -d 'Summary only'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l source -d 'Code line under each issue (default)'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l no-source -d 'Without the code line'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l color -d 'Force color'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l no-color -d 'No color'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -s q -l quiet -d 'Nothing on standard output'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l fail-under -x -d 'Score threshold (7 or security=8)'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l list-tools -d 'Detected tools'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l list-rules -d 'Built-in rules'
complete -c check-script -n "not __fish_seen_subcommand_from $subcommands" -l all -d 'With --list-rules: tool codes too'
complete -c check-script -s v -l version -d 'Version'
complete -c check-script -s h -l help -d 'Help'

# check-script explain RULE
complete -c check-script -n '__fish_seen_subcommand_from explain' -s c -l config -r -F -d 'YAML configuration (custom rules)'

# check-script init [DIR]
complete -c check-script -n '__fish_seen_subcommand_from init' -s p -l profile -x -a 'strict default legacy' -d 'Force the profile'
complete -c check-script -n '__fish_seen_subcommand_from init' -l context -x -a 'root cron systemd' -d 'Execution context'
complete -c check-script -n '__fish_seen_subcommand_from init' -l exclude -x -d 'Ignored path (.gitignore syntax)'
complete -c check-script -n '__fish_seen_subcommand_from init' -l baseline -r -F -d 'Also write the baseline report'
complete -c check-script -n '__fish_seen_subcommand_from init' -l no-analysis -d 'Analyse nothing'
complete -c check-script -n '__fish_seen_subcommand_from init' -l no-external -d 'Built-in rules only'
complete -c check-script -n '__fish_seen_subcommand_from init' -s f -l force -d 'Replace an existing file'
complete -c check-script -n '__fish_seen_subcommand_from init' -l stdout -d 'Write to standard output'
complete -c check-script -n '__fish_seen_subcommand_from init' -a '(__fish_complete_directories)'

# check-script diff BEFORE.json AFTER.json
complete -c check-script -n '__fish_seen_subcommand_from diff' -s f -l format -x -a 'text md json' -d 'Output format'
complete -c check-script -n '__fish_seen_subcommand_from diff' -l summary -d 'Without the issue details'
complete -c check-script -n '__fish_seen_subcommand_from diff' -l fail-on-new -x -a 'low medium high critical' -d 'Fail on a new issue'
complete -c check-script -n '__fish_seen_subcommand_from diff' -l fail-on-worse -d 'Fail if a score dropped'
complete -c check-script -n '__fish_seen_subcommand_from diff' -F
