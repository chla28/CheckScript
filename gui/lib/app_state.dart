/// État de l'application : réglages persistés, analyse du script courant,
/// analyse d'un dossier, référence (baseline), progression et annulation.
library;

import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:flutter/material.dart' hide Baseline;
import 'package:shared_preferences/shared_preferences.dart';

/// Réglages de l'interface (persistés dans shared_preferences).
class GuiSettings {
  final Lang? lang; // null : langue du système
  final ThemeMode theme;
  final Profile profile;
  final Set<ExecContext> contexts;
  final Set<String> disabledTools;
  final bool followSource;
  final String? configPath;

  const GuiSettings({
    this.lang,
    this.theme = ThemeMode.system,
    this.profile = Profile.standard,
    this.contexts = const {},
    this.disabledTools = const {},
    this.followSource = false,
    this.configPath,
  });

  GuiSettings copyWith({
    Lang? Function()? lang,
    ThemeMode? theme,
    Profile? profile,
    Set<ExecContext>? contexts,
    Set<String>? disabledTools,
    bool? followSource,
    String? Function()? configPath,
  }) =>
      GuiSettings(
        lang: lang == null ? this.lang : lang(),
        theme: theme ?? this.theme,
        profile: profile ?? this.profile,
        contexts: contexts ?? this.contexts,
        disabledTools: disabledTools ?? this.disabledTools,
        followSource: followSource ?? this.followSource,
        configPath: configPath == null ? this.configPath : configPath(),
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
      followSource: p.getBool('followSource') ?? false,
      configPath: p.getString('configPath'),
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
    await p.setBool('followSource', followSource);
    if (configPath == null) {
      await p.remove('configPath');
    } else {
      await p.setString('configPath', configPath!);
    }
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
    return c.withToolsDisabled(_settings.disabledTools).copyWith(
          contexts: _settings.contexts,
          followSource: _settings.followSource,
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

  /// Écrit la version corrigée (avec copie .orig) et relance l'analyse.
  Future<void> applyFix(FixResult r) async {
    final c = current;
    if (c == null || !r.changed) return;
    await File('${c.script.path}.orig').writeAsString(r.original);
    await File(c.script.path).writeAsString(r.fixed);
    await analyzeFile(c.script.path);
  }

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
