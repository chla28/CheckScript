/// Configuration de l'analyse (fichier YAML facultatif + options CLI).
library;

import 'package:yaml/yaml.dart';

import 'model/finding.dart';

/// Reclassement d'une règle (catégorie et/ou sévérité).
class RuleOverride {
  final Category? category;
  final Severity? severity;
  const RuleOverride({this.category, this.severity});
}

class ToolConfig {
  final bool enabled;

  /// Exécutable (nom dans le PATH ou chemin absolu).
  final String executable;

  /// Règles de l'outil à ne pas exécuter (transmises à l'outil quand il le
  /// permet : `shellcheck -e`, `bashate -i`).
  final List<String> exclude;

  const ToolConfig(
      {this.enabled = true, required this.executable, this.exclude = const []});

  ToolConfig copyWith({bool? enabled}) => ToolConfig(
      enabled: enabled ?? this.enabled,
      executable: executable,
      exclude: exclude);
}

class ScoringConfig {
  final Map<Severity, double> weights;

  /// Taille (lignes de code) en deçà de laquelle les pénalités Medium/Low ne
  /// sont pas atténuées.
  final int referenceLines;

  /// Poids des catégories dans la note globale.
  final Map<Category, double> categoryWeights;

  const ScoringConfig({
    this.weights = const {
      Severity.critical: 4,
      Severity.high: 2,
      Severity.medium: 0.75,
      Severity.low: 0.25,
    },
    this.referenceLines = 100,
    this.categoryWeights = const {
      Category.security: 1.5,
      Category.robustness: 1.25,
      Category.maintainability: 1,
      Category.portability: 0.75,
      Category.performance: 0.5,
    },
  });
}

class Thresholds {
  final int maxLineLength;
  final int maxFunctionLines;
  final int maxNesting;

  /// Taille (lignes de code) au-delà de laquelle un script sans fonction est
  /// signalé.
  final int maxLinesWithoutFunction;

  const Thresholds({
    this.maxLineLength = 120,
    this.maxFunctionLines = 60,
    this.maxNesting = 4,
    this.maxLinesWithoutFunction = 150,
  });
}

class CheckConfig {
  final Map<String, ToolConfig> tools;

  /// Règles désactivées (tout outil confondu : `SC2034`, `E003`, `MNT005`…).
  final Set<String> disabledRules;
  final Map<String, RuleOverride> overrides;
  final ScoringConfig scoring;
  final Thresholds thresholds;

  const CheckConfig({
    this.tools = defaultTools,
    this.disabledRules = const {},
    this.overrides = const {},
    this.scoring = const ScoringConfig(),
    this.thresholds = const Thresholds(),
  });

  static const defaultTools = {
    'shellcheck': ToolConfig(executable: 'shellcheck', exclude: ['SC1091']),
    'shfmt': ToolConfig(executable: 'shfmt'),
    'bashate': ToolConfig(executable: 'bashate'),
    'checkbashisms': ToolConfig(executable: 'checkbashisms'),
    'syntax': ToolConfig(executable: ''),
    'builtin': ToolConfig(executable: ''),
  };

  ToolConfig tool(String name) =>
      tools[name] ?? defaultTools[name] ?? ToolConfig(executable: name);

  /// Copie avec certains outils désactivés (option `--without`).
  CheckConfig withToolsDisabled(Iterable<String> names) {
    final t = Map<String, ToolConfig>.of(tools);
    for (final n in names) {
      t[n] = tool(n).copyWith(enabled: false);
    }
    return CheckConfig(
        tools: t,
        disabledRules: disabledRules,
        overrides: overrides,
        scoring: scoring,
        thresholds: thresholds);
  }

  /// Lit une configuration YAML. Les clés absentes gardent leur valeur par
  /// défaut. Lève [FormatException] si le document est invalide.
  static CheckConfig parse(String yamlText) {
    final doc = loadYaml(yamlText);
    if (doc == null) return const CheckConfig();
    if (doc is! YamlMap) {
      throw const FormatException('la racine doit être un dictionnaire');
    }

    final tools = Map<String, ToolConfig>.of(defaultTools);
    final yTools = doc['tools'];
    if (yTools is YamlMap) {
      yTools.forEach((k, v) {
        final name = '$k';
        final base = tools[name] ?? ToolConfig(executable: name);
        if (v is YamlMap) {
          tools[name] = ToolConfig(
            enabled: v['enabled'] is bool ? v['enabled'] as bool : base.enabled,
            executable:
                v['path'] is String ? v['path'] as String : base.executable,
            exclude: v['exclude'] is YamlList
                ? [for (final e in v['exclude'] as YamlList) '$e']
                : base.exclude,
          );
        } else if (v is bool) {
          tools[name] = base.copyWith(enabled: v);
        }
      });
    }

    final rules = doc['rules'];
    final disabled = <String>{};
    final overrides = <String, RuleOverride>{};
    if (rules is YamlMap) {
      if (rules['disabled'] is YamlList) {
        for (final r in rules['disabled'] as YamlList) {
          disabled.add('$r'.toUpperCase());
        }
      }
      if (rules['overrides'] is YamlMap) {
        (rules['overrides'] as YamlMap).forEach((k, v) {
          if (v is! YamlMap) return;
          final cat = v['category'] == null
              ? null
              : Category.tryParse('${v['category']}');
          final sev = v['severity'] == null
              ? null
              : Severity.tryParse('${v['severity']}');
          if (v['category'] != null && cat == null) {
            throw FormatException('catégorie inconnue : ${v['category']}');
          }
          if (v['severity'] != null && sev == null) {
            throw FormatException('sévérité inconnue : ${v['severity']}');
          }
          overrides['$k'.toUpperCase()] =
              RuleOverride(category: cat, severity: sev);
        });
      }
    }

    var scoring = const ScoringConfig();
    final ys = doc['scoring'];
    if (ys is YamlMap) {
      final weights = Map<Severity, double>.of(scoring.weights);
      if (ys['weights'] is YamlMap) {
        (ys['weights'] as YamlMap).forEach((k, v) {
          final s = Severity.tryParse('$k');
          if (s == null) throw FormatException('sévérité inconnue : $k');
          weights[s] = _toDouble(v, 'scoring.weights.$k');
        });
      }
      final catWeights = Map<Category, double>.of(scoring.categoryWeights);
      if (ys['categoryWeights'] is YamlMap) {
        (ys['categoryWeights'] as YamlMap).forEach((k, v) {
          final c = Category.tryParse('$k');
          if (c == null) throw FormatException('catégorie inconnue : $k');
          catWeights[c] = _toDouble(v, 'scoring.categoryWeights.$k');
        });
      }
      scoring = ScoringConfig(
        weights: weights,
        categoryWeights: catWeights,
        referenceLines: ys['referenceLines'] is int
            ? ys['referenceLines'] as int
            : scoring.referenceLines,
      );
    }

    var th = const Thresholds();
    final yt = doc['thresholds'];
    if (yt is YamlMap) {
      int pick(String key, int def) => yt[key] is int ? yt[key] as int : def;
      th = Thresholds(
        maxLineLength: pick('maxLineLength', th.maxLineLength),
        maxFunctionLines: pick('maxFunctionLines', th.maxFunctionLines),
        maxNesting: pick('maxNesting', th.maxNesting),
        maxLinesWithoutFunction:
            pick('maxLinesWithoutFunction', th.maxLinesWithoutFunction),
      );
    }

    return CheckConfig(
        tools: tools,
        disabledRules: disabled,
        overrides: overrides,
        scoring: scoring,
        thresholds: th);
  }

  static double _toDouble(Object? v, String key) {
    if (v is num) return v.toDouble();
    throw FormatException('$key : nombre attendu');
  }
}
