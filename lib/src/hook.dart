/// Hook git `pre-commit` généré par `check-script install-hook` : analyse la
/// version indexée des scripts modifiés (`check-script --staged`).
library;

/// Repère placé dans le hook : seuls les hooks portant ce repère sont
/// remplacés ou retirés sans `--force`.
const hookMarker = '# check-script-hook';

/// Contenu du hook : bloque le commit sous la note [failUnder].
String preCommitHook({required String failUnder}) => '''#!/bin/sh
$hookMarker — généré par « check-script install-hook » (relancer la commande
# pour le régénérer ; « check-script install-hook --uninstall » le retire).
# CHECK_SCRIPT_SKIP=1 git commit …   ignore le contrôle (une fois)
# CHECK_SCRIPT_ARGS="--profile strict"   ajoute des options
[ -n "\$CHECK_SCRIPT_SKIP" ] && exit 0
if ! command -v check-script >/dev/null 2>&1; then
  echo "pre-commit : check-script introuvable, contrôle ignoré." >&2
  exit 0
fi
# shellcheck disable=SC2086
exec check-script --staged --summary --no-color --fail-under $failUnder \$CHECK_SCRIPT_ARGS
''';

/// Le contenu est un hook généré par check-script.
bool isCheckScriptHook(String content) => content.contains(hookMarker);
