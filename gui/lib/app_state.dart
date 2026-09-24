/// État de l'application : réglages persistés, analyse du script courant,
/// analyse d'un dossier, référence (baseline), progression et annulation.
library;

import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:flutter/material.dart' hide Baseline;
import 'package:shared_preferences/shared_preferences.dart';

import 'widgets/split_view.dart';

/// Réglages de l'interface (persistés dans shared_preferences).
class GuiSettings {
  final Lang? lang; // null : langue du système
  final ThemeMode theme;
  final Profile profile;
  final Set<ExecContext> contexts;
  final Set<String> disabledTools;

  /// Outils désactivés par défaut (pylint, pyright) que l'utilisateur active.
  final Set<String> enabledTools;
  final bool followSource;
  final String? configPath;

  /// Version minimale de Python ; null : celle de la configuration (3.9).
  final String? pythonTarget;

  /// Répartition code / résultats de l'écran d'analyse, en disposition
  /// large (côte à côte) et étroite (l'un au-dessus de l'autre).
  final SplitState wideSplit;
  final SplitState narrowSplit;

  static const defaultWideSplit = SplitState(0.66);
  static const defaultNarrowSplit = SplitState(0.35);

  const GuiSettings({
    this.lang,
    this.theme = ThemeMode.system,
    this.profile = Profile.standard,
    this.contexts = const {},
    this.disabledTools = const {},
    this.enabledTools = const {},
    this.followSource = false,
    this.configPath,
    this.pythonTarget,
    this.wideSplit = defaultWideSplit,
    this.narrowSplit = defaultNarrowSplit,
  });

  /// Outil actif selon ces réglages (sa valeur par défaut, sauf choix
  /// contraire de l'utilisateur).
  bool toolEnabled(String tool) {
    if (disabledTools.contains(tool)) return false;
    return enabledTools.contains(tool) ||
        (CheckConfig.defaultTools[tool]?.enabled ?? true);
  }

  /// Réglages après activation / désactivation d'un outil.
  GuiSettings withTool(String tool, bool on) => copyWith(
        disabledTools:
            on ? ({...disabledTools}..remove(tool)) : {...disabledTools, tool},
        enabledTools:
            on ? {...enabledTools, tool} : ({...enabledTools}..remove(tool)),
      );

  GuiSettings copyWith({
    Lang? Function()? lang,
    ThemeMode? theme,
    Profile? profile,
    Set<ExecContext>? contexts,
    Set<String>? disabledTools,
    Set<String>? enabledTools,
    bool? followSource,
    String? Function()? configPath,
    String? Function()? pythonTarget,
    SplitState? wideSplit,
    SplitState? narrowSplit,
  }) =>
      GuiSettings(
        lang: lang == null ? this.lang : lang(),
        theme: theme ?? this.theme,
        profile: profile ?? this.profile,
        contexts: contexts ?? this.contexts,
        disabledTools: disabledTools ?? this.disabledTools,
        enabledTools: enabledTools ?? this.enabledTools,
        followSource: followSource ?? this.followSource,
        configPath: configPath == null ? this.configPath : configPath(),
        pythonTarget: pythonTarget == null ? this.pythonTarget : pythonTarget(),
        wideSplit: wideSplit ?? this.wideSplit,
        narrowSplit: narrowSplit ?? this.narrowSplit,
      );

  static Future<GuiSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return GuiSettings(
      lang: Lang.tryParse(p.getString('lang') ?? ''),
      theme: ThemeMode.values.firstWhere((t) => t.name == p.getString('theme'),
          orElse: () => ThemeMode.system),
      profile:
          Profile.tryParse(p.getString('profile') ?? '') ?? Profile.standard,
      contexts: {
        for (final c in p.getStringList('contexts') ?? const <String>[])
          if (ExecContext.tryParse(c) != null) ExecContext.tryParse(c)!
      },
      disabledTools:
          (p.getStringList('disabledTools') ?? const <String>[]).toSet(),
      enabledTools:
          (p.getStringList('enabledTools') ?? const <String>[]).toSet(),
      followSource: p.getBool('followSource') ?? false,
      configPath: p.getString('configPath'),
      pythonTarget: p.getString('pythonTarget'),
      wideSplit: SplitState.decode(p.getString('wideSplit'), defaultWideSplit),
      narrowSplit:
          SplitState.decode(p.getString('narrowSplit'), defaultNarrowSplit),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    if (lang == null) {
      await p.remove('lang');
    } else {
      await p.setString('lang', lang!.name);
    }
    await p.setString('theme', theme.name);
    await p.setString('profile', profile.name);
    await p.setStringList('contexts', [for (final c in contexts) c.name]);
    await p.setStringList('disabledTools', disabledTools.toList());
    await p.setStringList('enabledTools', enabledTools.toList());
    await p.setBool('followSource', followSource);
    if (configPath == null) {
      await p.remove('configPath');
    } else {
      await p.setString('configPath', configPath!);
    }
    if (pythonTarget == null) {
      await p.remove('pythonTarget');
    } else {
      await p.setString('pythonTarget', pythonTarget!);
    }
    await p.setString('wideSplit', wideSplit.encode());
    await p.setString('narrowSplit', narrowSplit.encode());
  }
}

/// Progression affichée pendant une analyse.
class ProgressInfo {
  final String label;
  final double fraction;
  const ProgressInfo(this.label, this.fraction);
}

class AppState extends ChangeNotifier {
  AppState({CommandRunner? runner, GuiSettings? settings})
      : runner = runner ?? const ProcessCommandRunner(),
        _settings = settings ?? const GuiSettings();

  final CommandRunner runner;
  GuiSettings _settings;
  GuiSettings get settings => _settings;

  Lang get lang => _settings.lang ?? Lang.fromEnvironment(Platform.environment);

  ScriptReport? current;
  List<ScriptReport> folderReports = [];
  String? folderPath;
  Baseline? baseline;
  String? baselinePath;

  ProgressInfo? progress;
  String? message;
  CancelToken? _cancel;
  bool get busy => _cancel != null;

  /// Outils détectés : nom → version (null : absent).
  Map<String, String?> toolVersions = {};

  Future<void> updateSettings(GuiSettings s) async {
    _settings = s;
    notifyListeners();
    await s.save();
  }

  /// Configuration effective : fichier YAML éventuel, profil, contextes,
  /// outils désactivés.
  Future<CheckConfig> buildConfig() async {
    var c = CheckConfig.forProfile(_settings.profile);
    final path = _settings.configPath;
    if (path != null && await File(path).exists()) {
      c = CheckConfig.parse(await File(path).readAsString(),
          profile: _settings.profile);
    }
    return c
        .withToolsEnabled(_settings.enabledTools)
        .withToolsDisabled(_settings.disabledTools)
        .copyWith(
          contexts: _settings.contexts,
          followSource: _settings.followSource,
          pythonTarget: _settings.pythonTarget,
        );
  }

  Future<Engine> _engine() async => Engine(
        config: await buildConfig(),
        lang: lang,
        runner: runner,
        baseline: baseline,
      );

  void _start() {
    _cancel = CancelToken();
    message = null;
    progress = const ProgressInfo('', 0);
    notifyListeners();
  }

  void _finish([String? msg]) {
    _cancel = null;
    progress = null;
    message = msg;
    notifyListeners();
  }

  void cancel() => _cancel?.cancel();

  /// Analyse un script ; le résultat devient le script courant.
  Future<void> analyzeFile(String path) async {
    if (busy) return;
    _start();
    final token = _cancel!;
    try {
      final engine = await _engine();
      current = await engine.analyzeFile(path, cancel: token, onProgress: (p) {
        progress = ProgressInfo(p.tool ?? '', p.fraction);
        notifyListeners();
      });
      _finish();
    } on AnalysisCancelled {
      _finish('cancelled');
    } catch (e) {
      _finish('error:$e');
    }
  }

  /// Analyse tous les scripts d'un dossier.
  Future<void> analyzeFolder(String path) async {
    if (busy) return;
    _start();
    final token = _cancel!;
    folderPath = path;
    try {
      final files = await collectScripts(path) ?? const [];
      final engine = await _engine();
      final out = <ScriptReport>[];
      for (var i = 0; i < files.length; i++) {
        token.check();
        progress = ProgressInfo(
            '${i + 1}/${files.length}  ${files[i]}', i / files.length);
        notifyListeners();
        try {
          out.add(await engine.analyzeFile(files[i], cancel: token));
        } on FileSystemException {
          // Fichier illisible : ignoré.
        } on FormatException {
          // Fichier non textuel : ignoré.
        }
      }
      folderReports = out;
      _finish(files.isEmpty ? 'noScripts' : null);
    } on AnalysisCancelled {
      _finish('cancelled');
    } catch (e) {
      _finish('error:$e');
    }
  }

  /// Relance l'analyse du script courant (après correction ou réglages).
  Future<void> reanalyze() async {
    final c = current;
    if (c != null && c.script.path != '<stdin>') {
      await analyzeFile(c.script.path);
    }
  }

  Future<void> loadBaseline(String path) async {
    try {
      baseline = Baseline.parse(await File(path).readAsString());
      baselinePath = path;
      message = null;
    } on Object catch (e) {
      message = 'error:$e';
    }
    notifyListeners();
    await reanalyze();
  }

  Future<void> clearBaseline() async {
    baseline = null;
    baselinePath = null;
    notifyListeners();
    await reanalyze();
  }

  /// Calcule les corrections du script courant (sans rien écrire).
  Future<FixResult?> proposeFix() async {
    final c = current;
    if (c == null) return null;
    final script = ScriptInfo.fromContent(
        c.script.path, await File(c.script.path).readAsString());
    return fixScript(script, config: await buildConfig(), runner: runner);
  }

  /// Scripts déjà sauvegardés en .orig depuis le lancement.
  final _backedUp = <String>{};

  /// Écrit la copie .orig à la première correction de [path] depuis le
  /// lancement ; les corrections suivantes la conservent : elle garde le
  /// script d'avant la première correction.
  Future<void> _backup(String path, String original) async {
    if (_backedUp.add(path)) await File('$path.orig').writeAsString(original);
  }

  /// Écrit la version corrigée (avec copie .orig) et relance l'analyse.
  Future<void> applyFix(FixResult r) async {
    final c = current;
    if (c == null || !r.changed) return;
    await _backup(c.script.path, r.original);
    await File(c.script.path).writeAsString(r.fixed);
    await analyzeFile(c.script.path);
  }

  /// Applique au script courant la seule correction de [f] (copie .orig),
  /// puis relance l'analyse. Renvoie null en cas de succès, sinon la raison
  /// du refus : [staleFix] si le fichier a changé depuis l'analyse, ou le
  /// message de l'interpréteur si la syntaxe ne serait plus valide.
  Future<String?> applyFindingFix(Finding f) async {
    final c = current;
    if (c == null || busy || f.edits.isEmpty) return staleFix;
    final raw = await File(c.script.path).readAsString();
    final script = ScriptInfo.fromContent(c.script.path, raw);
    if (script.content != c.script.content) return staleFix;
    final (fixed, _) = applyEdits(script.content, f.edits);
    if (fixed == script.content) return staleFix;
    final broken = await syntaxRegression(script, fixed,
        config: await buildConfig(), runner: runner);
    if (broken != null) return broken;
    await _backup(c.script.path, raw);
    // Les fins de ligne d'origine sont conservées (seul --fix les convertit).
    await File(c.script.path)
        .writeAsString(script.hasCrlf ? fixed.replaceAll('\n', '\r\n') : fixed);
    await analyzeFile(c.script.path);
    return null;
  }

  static const staleFix = 'stale';

  /// Exporte les rapports affichés dans [path] (format selon l'extension).
  Future<void> export(String path, List<ScriptReport> reports) async {
    final fmt = OutputFormat.fromPath(path) ?? OutputFormat.markdown;
    await File(path)
        .writeAsString(render(reports, fmt, RenderOptions(lang: lang)));
  }

  /// Détecte les outils externes et leur version.
  Future<void> detectTools() async {
    final config = await buildConfig();
    final out = <String, String?>{};
    for (final a in defaultAnalyzers()) {
      if (a.name == 'builtin' || a.name == 'syntax') continue;
      out[a.name] = await a.version(
          runner, config.copyWith(tools: CheckConfig.defaultTools));
    }
    toolVersions = out;
    notifyListeners();
  }
}
