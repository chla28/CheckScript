/// Bibliothèque check_script : évaluation de scripts shell selon cinq axes
/// (Sécurité, Robustesse, Maintenabilité, Portabilité, Performance).
///
/// Point d'entrée commun au CLI (`bin/check_script.dart`) et à l'interface
/// Flutter (`gui/`).
library;

export 'src/analyzers/analyzer.dart';
export 'src/analyzers/ast.dart'
    show AstFacts, CommandFact, FunctionFact, NestingFact, loadAst;
export 'src/analyzers/builtin_rules.dart'
    show runBuiltinRules, lineRules, shannonEntropy, looksLikeSecret;
export 'src/analyzers/external_tools.dart';
export 'src/analyzers/secrets.dart';
export 'src/analyzers/shellcheck.dart';
export 'src/baseline.dart';
export 'src/config.dart';
export 'src/diff.dart';
export 'src/discovery.dart';
export 'src/engine.dart';
export 'src/fixer.dart';
export 'src/i18n.dart';
export 'src/model/finding.dart';
export 'src/model/report.dart';
export 'src/reporters/codeclimate.dart';
export 'src/reporters/html.dart';
export 'src/reporters/reporters.dart';
export 'src/reporters/sarif.dart';
export 'src/rules/catalog.dart';
export 'src/scoring.dart';
export 'src/script_info.dart';
export 'src/suppressions.dart';
export 'src/version.dart';
