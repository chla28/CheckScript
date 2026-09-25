/// Configuration de l'analyse (fichier YAML facultatif + options CLI).
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'model/finding.dart';
import 'rules/catalog.dart' show ExecContext;
import 'rules/custom_rules.dart';
import 'rules/same_rules.dart';

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

  /// Règles de l'outil (Semgrep : fichier ou dossier local, ou jeu du
  /// registre) ; null : valeur par défaut de l'outil.
  final String? config;

  const ToolConfig(
      {this.enabled = true,
      required this.executable,
      this.exclude = const [],
      this.config});

  ToolConfig copyWith({bool? enabled, String? Function()? config}) =>
      ToolConfig(
          enabled: enabled ?? this.enabled,
          executable: executable,
          exclude: exclude,
          config: config == null ? this.config : config());
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

  /// Règles personnalisées du projet (`rules.custom`).
  final List<CustomRule> customRules;

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
    this.customRules = const [],
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
    'custom': ToolConfig(executable: ''),
    // Python. PLR2004 (constantes « magiques ») et S603 / B603 / B404
    // (tout appel à subprocess) sont trop bavards pour des scripts.
    'ruff': ToolConfig(executable: 'ruff', exclude: ['PLR2004', 'S603']),
    'bandit': ToolConfig(executable: 'bandit', exclude: ['B404', 'B603']),
    'semgrep': ToolConfig(executable: 'semgrep'),
    'mypy': ToolConfig(executable: 'mypy'),
    'radon': ToolConfig(executable: 'radon'),
    'vermin': ToolConfig(executable: 'vermin'),
    // Interpréteur des dépendances : '' → VIRTUAL_ENV, sinon python3.
    'pydeps': ToolConfig(executable: ''),
    'pip-audit': ToolConfig(executable: 'pip-audit'),
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

  /// Règle désactivée (`rules.disabled`), directement ou sous le code de la
  /// même règle dans un autre outil ([sameRuleIds]).
  bool isRuleDisabled(String id) {
    final k = id.toUpperCase();
    return disabledRules.contains(k) ||
        sameRuleIds(k).any(disabledRules.contains);
  }

  /// Format des codes qu'un outil accepte sans erreur dans ses exclusions
  /// (ShellCheck et mypy refusent un code inconnu, Ruff aussi, Pylint le
  /// signale comme un problème : ils ne reçoivent pas les règles désactivées).
  static final Map<String, RegExp> _excludable = {
    'shellcheck': RegExp(r'^SC\d{4}$'),
    'bashate': RegExp(r'^[EW]\d{3}$'),
    'bandit': RegExp(r'^B[1-7]\d\d$'),
  };

  /// Exclusions à transmettre à [name] : les siennes, plus les règles
  /// désactivées qu'il reconnaît à coup sûr (il ne les calcule alors pas).
  List<String> excludedFor(String name) {
    final own = tool(name).exclude;
    final pattern = _excludable[name];
    if (pattern == null) return own;
    return {
      ...own,
      for (final r in disabledRules)
        if (pattern.hasMatch(r)) r,
      for (final r in disabledRules)
        for (final same in sameRuleIds(r))
          if (pattern.hasMatch(same)) same,
    }.toList();
  }

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
    List<CustomRule>? customRules,
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
        customRules: customRules ?? this.customRules,
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
            config: v['config'] is String ? v['config'] as String : base.config,
          );
        } else if (v is bool) {
          tools[name] = base.copyWith(enabled: v);
        }
      });
    }

    final rules = doc['rules'];
    final disabled = <String>{...base.disabledRules};
    final overrides = <String, RuleOverride>{...base.overrides};
    final custom = <CustomRule>[];
    if (rules is YamlMap) {
      final c = rules['custom'];
      if (c != null && c is! YamlList) {
        throw const FormatException('rules.custom : liste de règles attendue');
      }
      for (final y in c is YamlList ? c : const []) {
        final r = CustomRule.fromYaml(y);
        if (custom.any((x) => x.id == r.id)) {
          throw FormatException('rules.custom : ${r.id} déclarée deux fois');
        }
        custom.add(r);
      }
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
        customRules: custom,
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

  /// Configuration au format YAML, relisible par [parse] : seul ce qui
  /// diffère du profil est écrit (exportée par l'interface, ou partagée avec
  /// la CI par `.checkscript.yaml`).
  String toYaml({String? header}) {
    final base = CheckConfig.forProfile(profile);
    String q(String v) => jsonEncode(v); // chaîne YAML entre guillemets
    String list(Iterable<String> v) => '[${v.map(q).join(', ')}]';
    String num(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    final b = StringBuffer();
    if (header != null) {
      for (final l in header.split('\n')) {
        b.writeln('# $l');
      }
    }
    b.writeln(
        'profile: ${profile == Profile.standard ? 'default' : profile.name}');
    if (contexts.isNotEmpty) {
      b.writeln('context: ${list([for (final c in contexts) c.name])}');
    }
    if (followSource) b.writeln('followSource: true');
    if (pythonTarget != defaultPythonTarget) {
      b.writeln('pythonTarget: ${q(pythonTarget)}');
    }

    final names = {...defaultTools.keys, ...tools.keys}.toList()..sort();
    final toolLines = <String>[];
    for (final n in names) {
      final t = tool(n), d = base.tool(n);
      final lines = [
        if (t.enabled != d.enabled) 'enabled: ${t.enabled}',
        if (t.executable != d.executable) 'path: ${q(t.executable)}',
        if (t.exclude.join(',') != d.exclude.join(','))
          'exclude: ${list(t.exclude)}',
        if (t.config != d.config && t.config != null) 'config: ${q(t.config!)}',
      ];
      if (lines.isEmpty) continue;
      toolLines.add('  $n:');
      toolLines.addAll([for (final l in lines) '    $l']);
    }
    if (toolLines.isNotEmpty) {
      b.writeln('tools:');
      toolLines.forEach(b.writeln);
    }

    final disabled = disabledRules.difference(base.disabledRules).toList()
      ..sort();
    if (disabled.isNotEmpty || overrides.isNotEmpty || customRules.isNotEmpty) {
      b.writeln('rules:');
      if (disabled.isNotEmpty) b.writeln('  disabled: ${list(disabled)}');
      if (customRules.isNotEmpty) {
        b.writeln('  custom:');
        for (final r in customRules) {
          for (final l in r.toYaml()) {
            b.writeln('    $l');
          }
        }
      }
      if (overrides.isNotEmpty) {
        b.writeln('  overrides:');
        for (final e in overrides.entries) {
          final o = e.value;
          b.writeln('    ${q(e.key)}: {'
              '${[
            if (o.category != null) 'category: ${o.category!.name}',
            if (o.severity != null) 'severity: ${o.severity!.name}',
          ].join(', ')}}');
        }
      }
    }

    final sc = scoring, sb = base.scoring;
    String weights(Map<Enum, double> m) => '{${[
          for (final e in m.entries) '${e.key.name}: ${num(e.value)}'
        ].join(', ')}}';
    final scoringLines = [
      if (weights(sc.weights) != weights(sb.weights))
        'weights: ${weights(sc.weights)}',
      if (sc.referenceLines != sb.referenceLines)
        'referenceLines: ${sc.referenceLines}',
      if (weights(sc.categoryWeights) != weights(sb.categoryWeights))
        'categoryWeights: ${weights(sc.categoryWeights)}',
    ];
    if (scoringLines.isNotEmpty) {
      b.writeln('scoring:');
      for (final l in scoringLines) {
        b.writeln('  $l');
      }
    }

    final th = thresholds, tb = base.thresholds;
    final thLines = [
      if (th.maxLineLength != tb.maxLineLength)
        'maxLineLength: ${th.maxLineLength}',
      if (th.maxFunctionLines != tb.maxFunctionLines)
        'maxFunctionLines: ${th.maxFunctionLines}',
      if (th.maxNesting != tb.maxNesting) 'maxNesting: ${th.maxNesting}',
      if (th.maxLinesWithoutFunction != tb.maxLinesWithoutFunction)
        'maxLinesWithoutFunction: ${th.maxLinesWithoutFunction}',
    ];
    if (thLines.isNotEmpty) {
      b.writeln('thresholds:');
      for (final l in thLines) {
        b.writeln('  $l');
      }
    }
    return b.toString();
  }

  static double _toDouble(Object? v, String key) {
    if (v is num) return v.toDouble();
    throw FormatException('$key : nombre attendu');
  }
}
