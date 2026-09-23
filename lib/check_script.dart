/// Bibliothèque check_script : évaluation de scripts shell selon cinq axes
/// (Sécurité, Robustesse, Maintenabilité, Portabilité, Performance).
///
/// Point d'entrée commun au CLI (`bin/check_script.dart`) et à la future
/// interface Flutter.
library;

export 'src/analyzers/analyzer.dart';
export 'src/analyzers/builtin_rules.dart'
    show allBuiltinRules, RuleInfo, runBuiltinRules;
export 'src/analyzers/external_tools.dart';
export 'src/analyzers/shellcheck.dart';
export 'src/config.dart';
export 'src/engine.dart';
export 'src/i18n.dart';
export 'src/model/finding.dart';
export 'src/model/report.dart';
export 'src/reporters/reporters.dart';
export 'src/scoring.dart';
export 'src/script_info.dart';
export 'src/version.dart';
