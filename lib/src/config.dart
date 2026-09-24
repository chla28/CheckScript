/// Configuration de l'analyse (fichier YAML facultatif + options CLI).
library;

import 'package:yaml/yaml.dart';

import 'model/finding.dart';
import 'rules/catalog.dart' show ExecContext;

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

/// Profils prédéfinis : point de départ de la configuration.
enum Profile {
  /// Nouveaux scripts, exigence élevée.
  strict,

  /// Réglages par défaut.
  standard,

  /// Existant ancien : style et formatage peu pénalisés.
  legacy;

  static Profile? tryParse(String s) => switch (s.toLowerCase()) {
        'strict' => strict,
        'default' || 'standard' => standard,
        'legacy' => legacy,
        _ => null,
      };
}

class CheckConfig {
  final Map<String, ToolConfig> tools;

  /// Règles désactivées (tout outil confondu : `SC2034`, `E003`, `MNT005`…).
  final Set<String> disabledRules;
  final Map<String, RuleOverride> overrides;
  final ScoringConfig scoring;
  final Thresholds thresholds;

  /// Contextes d'exécution déclarés (`--context`).
  final Set<ExecContext> contexts;

  /// Suivre les fichiers sourcés (`shellcheck -x`).
  final bool followSource;
  final Profile profile;

  /// Version minimale de Python que les scripts doivent supporter (`3.9`) :
  /// Vermin, Ruff (`--target-version`), Pylint, Pyright.
  final String pythonTarget;

  const CheckConfig({
    this.tools = defaultTools,
    this.disabledRules = const {},
    this.overrides = const {},
    this.scoring = const ScoringConfig(),
    this.thresholds = const Thresholds(),
    this.contexts = const {},
    this.followSource = false,
    this.profile = Profile.standard,
    this.pythonTarget = defaultPythonTarget,
  });

  /// Python de RHEL / Rocky 9.
  static const defaultPythonTarget = '3.9';

  /// Version cible valide : `3.N`.
  static bool isPythonTarget(String v) => RegExp(r'^3\.\d{1,2}$').hasMatch(v);

  static const defaultTools = {
    'shellcheck': ToolConfig(executable: 'shellcheck', exclude: ['SC1091']),
    'shfmt': ToolConfig(executable: 'shfmt'),
    'bashate': ToolConfig(executable: 'bashate'),
    'checkbashisms': ToolConfig(executable: 'checkbashisms'),
    'gitleaks': ToolConfig(executable: 'gitleaks'),
    'trufflehog': ToolConfig(executable: 'trufflehog'),
    'syntax': ToolConfig(executable: ''),
    'builtin': ToolConfig(executable: ''),
    // Python. PLR2004 (constantes « magiques ») et S603 / B603 / B404
    // (tout appel à subprocess) sont trop bavards pour des scripts.
    'ruff': ToolConfig(executable: 'ruff', exclude: ['PLR2004', 'S603']),
    'bandit': ToolConfig(executable: 'bandit', exclude: ['B404', 'B603']),
    'semgrep': ToolConfig(executable: 'semgrep'),
    'mypy': ToolConfig(executable: 'mypy'),
    'radon': ToolConfig(executable: 'radon'),
    'vermin': ToolConfig(executable: 'vermin'),
    // Redondants avec Ruff et mypy : activables dans la configuration.
    'pylint': ToolConfig(
        enabled: false,
        executable: 'pylint',
        exclude: ['C0103', 'C0114', 'C0115', 'C0116']),
    'pyright': ToolConfig(enabled: false, executable: 'pyright'),
  };

  /// Configuration de départ d'un profil.
  factory CheckConfig.forProfile(Profile p) => switch (p) {
        Profile.standard => const CheckConfig(),
        Profile.strict => const CheckConfig(
            profile: Profile.strict,
            scoring: ScoringConfig(weights: {
              Severity.critical: 5,
              Severity.high: 3,
              Severity.medium: 1,
              Severity.low: 0.4,
            }, referenceLines: 50),
            thresholds: Thresholds(
                maxLineLength: 100,
                maxFunctionLines: 40,
                maxNesting: 3,
                maxLinesWithoutFunction: 100),
          ),
        Profile.legacy => const CheckConfig(
            profile: Profile.legacy,
            scoring: ScoringConfig(weights: {
              Severity.critical: 4,
              Severity.high: 1.5,
              Severity.medium: 0.5,
              Severity.low: 0.1,
            }),
            thresholds: Thresholds(
                maxLineLength: 160,
                maxFunctionLines: 150,
                maxNesting: 6,
                maxLinesWithoutFunction: 400),
            disabledRules: {
              'MNT001', 'MNT004', 'MNT005', 'MNT010', 'FORMAT', //
              'E001', 'E002', 'E003', 'E005', 'E006',
              'PYMNT001', 'E501', 'W291', 'W293', 'C0301', 'C0303',
            },
          ),
      };

  ToolConfig tool(String name) =>
      tools[name] ?? defaultTools[name] ?? ToolConfig(executable: name);

  CheckConfig copyWith({
    Map<String, ToolConfig>? tools,
    Set<String>? disabledRules,
    Map<String, RuleOverride>? overrides,
    ScoringConfig? scoring,
    Thresholds? thresholds,
    Set<ExecContext>? contexts,
    bool? followSource,
    Profile? profile,
    String? pythonTarget,
  }) =>
      CheckConfig(
        tools: tools ?? this.tools,
        disabledRules: disabledRules ?? this.disabledRules,
        overrides: overrides ?? this.overrides,
        scoring: scoring ?? this.scoring,
        thresholds: thresholds ?? this.thresholds,
        contexts: contexts ?? this.contexts,
        followSource: followSource ?? this.followSource,
        profile: profile ?? this.profile,
        pythonTarget: pythonTarget ?? this.pythonTarget,
      );

  /// Copie avec certains outils activés (option `--with` : outils désactivés
  /// par défaut, comme pylint et pyright).
  CheckConfig withToolsEnabled(Iterable<String> names) {
    final t = Map<String, ToolConfig>.of(tools);
    for (final n in names) {
      t[n] = tool(n).copyWith(enabled: true);
    }
    return copyWith(tools: t);
  }

  /// Copie avec certains outils désactivés (option `--without`).
  CheckConfig withToolsDisabled(Iterable<String> names) {
    final t = Map<String, ToolConfig>.of(tools);
    for (final n in names) {
      t[n] = tool(n).copyWith(enabled: false);
    }
    return copyWith(tools: t);
  }

  /// Lit une configuration YAML. Les clés absentes gardent la valeur du
  /// profil ([profile] s'il est fourni, sinon la clé `profile:` du document,
  /// sinon `standard`). Lève [FormatException] si le document est invalide.
  static CheckConfig parse(String yamlText, {Profile? profile}) {
    final doc = loadYaml(yamlText);
    if (doc == null) return CheckConfig.forProfile(profile ?? Profile.standard);
    if (doc is! YamlMap) {
      throw const FormatException('la racine doit être un dictionnaire');
    }
    var prof = profile;
    if (prof == null && doc['profile'] != null) {
      prof = Profile.tryParse('${doc['profile']}');
      if (prof == null) {
        throw FormatException('profil inconnu : ${doc['profile']}');
      }
    }
    final base = CheckConfig.forProfile(prof ?? Profile.standard);

    final tools = Map<String, ToolConfig>.of(base.tools);
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
    final disabled = <String>{...base.disabledRules};
    final overrides = <String, RuleOverride>{...base.overrides};
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

    var scoring = base.scoring;
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

    var th = base.thresholds;
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

    final contexts = <ExecContext>{};
    final yc = doc['context'];
    for (final v in yc is YamlList ? yc : (yc == null ? const [] : [yc])) {
      final c = ExecContext.tryParse('$v');
      if (c == null) throw FormatException('contexte inconnu : $v');
      contexts.add(c);
    }

    // 3.10 sans guillemets serait lu comme le nombre 3.1.
    if (doc['pythonTarget'] is num) {
      throw const FormatException(
          'pythonTarget : écrire la version entre guillemets (ex. "3.10")');
    }
    final target = doc['pythonTarget']?.toString();
    if (target != null && !isPythonTarget(target)) {
      throw FormatException('pythonTarget invalide : $target (ex. 3.9)');
    }

    return base.copyWith(
        pythonTarget: target,
        tools: tools,
        disabledRules: disabled,
        overrides: overrides,
        scoring: scoring,
        thresholds: th,
        contexts: contexts,
        followSource: doc['followSource'] is bool
            ? doc['followSource'] as bool
            : base.followSource);
  }

  static double _toDouble(Object? v, String key) {
    if (v is num) return v.toDouble();
    throw FormatException('$key : nombre attendu');
  }
}
