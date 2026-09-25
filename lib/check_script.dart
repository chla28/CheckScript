// Copyright (C) 2026 Christophe Lafaille
// SPDX-License-Identifier: LGPL-3.0-or-later

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
    show
        runBuiltinRules,
        lineRules,
        shannonEntropy,
        looksLikeSecret,
        lineHasSecret,
        BuiltinAnalyzer;
export 'src/analyzers/external_tools.dart';
export 'src/analyzers/python_deps.dart';
export 'src/analyzers/python_rules.dart';
export 'src/analyzers/python_tools.dart';
export 'src/analyzers/secrets.dart';
export 'src/analyzers/shellcheck.dart';
export 'src/baseline.dart';
export 'src/config.dart';
export 'src/config_discovery.dart';
export 'src/diff.dart';
export 'src/discovery.dart';
export 'src/embedded.dart';
export 'src/engine.dart';
export 'src/explain.dart';
export 'src/feedback.dart';
export 'src/git.dart';
export 'src/history.dart';
export 'src/fixer.dart';
export 'src/i18n.dart';
export 'src/model/finding.dart';
export 'src/model/report.dart';
export 'src/reporters/codeclimate.dart';
export 'src/reporters/dashboard.dart';
export 'src/reporters/html.dart';
export 'src/reporters/junit.dart';
export 'src/reporters/reporters.dart';
export 'src/reporters/sarif.dart';
export 'src/result_cache.dart';
export 'src/rules/catalog.dart';
export 'src/rules/custom_rules.dart';
export 'src/rules/examples.dart';
export 'src/rules/registry.dart';
export 'src/rules/same_rules.dart';
export 'src/scoring.dart';
export 'src/script_info.dart';
export 'src/suppressions.dart';
export 'src/version.dart';
export 'src/watch.dart';
