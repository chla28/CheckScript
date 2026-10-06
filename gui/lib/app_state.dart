/// État de l'application : réglages persistés, analyse du script courant,
/// analyse d'un dossier, référence (baseline), progression et annulation.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:flutter/material.dart' hide Baseline;
import 'package:shared_preferences/shared_preferences.dart';

import 'code_style.dart';
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

  /// Règles désactivées depuis l'interface (clés en majuscules), ajoutées
  /// à `rules.disabled` de la configuration.
  final Set<String> disabledRules;

  /// Réutiliser les résultats d'un script inchangé (cache).
  final bool useCache;

  /// Relancer l'analyse quand le script ouvert est enregistré.
  final bool watchFile;

  /// Ruff suit la configuration du projet du script (ruff.toml,
  /// pyproject.toml) plutôt que les réglages de check-script.
  final bool ruffProjectConfig;

  /// Commande d'ouverture dans l'éditeur ({file}, {line}) ; null :
  /// détection automatique.
  final String? editorCommand;

  /// Scripts et dossiers analysés récemment, du plus récent au plus ancien.
  final List<String> recent;

  /// Police du code (null : JetBrains Mono, embarquée).
  final String? codeFont;

  /// Taille de la police du code, en points.
  final double codeFontSize;

  /// Nombre d'entrées conservées dans [recent].
  static const maxRecent = 10;

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
    this.disabledRules = const {},
    this.useCache = true,
    this.watchFile = true,
    this.editorCommand,
    this.ruffProjectConfig = false,
    this.recent = const [],
    this.codeFont,
    this.codeFontSize = defaultCodeFontSize,
  });

  /// Réglages avec la taille du code changée de [delta] points (bornée) ;
  /// null : taille par défaut.
  GuiSettings zoomCode(double? delta) => copyWith(
      codeFontSize: delta == null
          ? defaultCodeFontSize
          : (codeFontSize + delta).clamp(minCodeFontSize, maxCodeFontSize));

  /// Réglages avec [path] en tête des récents (sans doublon).
  GuiSettings withRecent(String path) => copyWith(
          recent: [
        path,
        for (final r in recent)
          if (r != path) r,
      ].take(maxRecent).toList());

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
    Set<String>? disabledRules,
    bool? useCache,
    bool? watchFile,
    String? Function()? editorCommand,
    bool? ruffProjectConfig,
    List<String>? recent,
    String? Function()? codeFont,
    double? codeFontSize,
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
        disabledRules: disabledRules ?? this.disabledRules,
        useCache: useCache ?? this.useCache,
        watchFile: watchFile ?? this.watchFile,
        editorCommand:
            editorCommand == null ? this.editorCommand : editorCommand(),
        ruffProjectConfig: ruffProjectConfig ?? this.ruffProjectConfig,
        recent: recent ?? this.recent,
        codeFont: codeFont == null ? this.codeFont : codeFont(),
        codeFontSize: codeFontSize ?? this.codeFontSize,
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
      disabledRules:
          (p.getStringList('disabledRules') ?? const <String>[]).toSet(),
      useCache: p.getBool('useCache') ?? true,
      watchFile: p.getBool('watchFile') ?? true,
      editorCommand: p.getString('editorCommand'),
      ruffProjectConfig: p.getBool('ruffProjectConfig') ?? false,
      recent: p.getStringList('recent') ?? const [],
      codeFont: p.getString('codeFont'),
      codeFontSize: (p.getDouble('codeFontSize') ?? defaultCodeFontSize)
          .clamp(minCodeFontSize, maxCodeFontSize),
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
    await p.setStringList('disabledRules', disabledRules.toList()..sort());
    await p.setBool('useCache', useCache);
    await p.setBool('watchFile', watchFile);
    await p.setBool('ruffProjectConfig', ruffProjectConfig);
    await p.setStringList('recent', recent);
    if (codeFont == null) {
      await p.remove('codeFont');
    } else {
      await p.setString('codeFont', codeFont!);
    }
    await p.setDouble('codeFontSize', codeFontSize);
    if (editorCommand == null) {
      await p.remove('editorCommand');
    } else {
      await p.setString('editorCommand', editorCommand!);
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
  AppState(
      {CommandRunner? runner,
      GuiSettings? settings,
      Map<String, RuleEntry>? seenRules,
      FolderHistory? history,
      bool? watchFiles,
      FalsePositiveLog? falsePositives})
      : runner = runner ?? const ProcessCommandRunner(),
        _settings = settings ?? const GuiSettings(),
        seenRules = seenRules ?? {},
        // Historique et surveillance : par défaut seulement avec les vrais
        // outils (les tests les activent explicitement).
        history = history ??
            (runner == null || runner is ProcessCommandRunner
                ? FolderHistory.standard()
                : null),
        watchFiles =
            watchFiles ?? (runner == null || runner is ProcessCommandRunner),
        falsePositives = falsePositives ??
            (runner == null || runner is ProcessCommandRunner
                ? FalsePositiveLog.standard()
                : null);

  /// Journal des faux positifs signalés (null : signalement indisponible).
  final FalsePositiveLog? falsePositives;

  /// Enregistre [f] (script courant) comme faux positif ; renvoie le nombre
  /// de cas du journal, ou null si le signalement est indisponible.
  Future<int?> reportFalsePositive(Finding f, {String comment = ''}) async {
    final c = current;
    final log = falsePositives;
    if (c == null || log == null) return null;
    return log.append(FalsePositive.of(f, c, comment: comment));
  }

  /// Historique des analyses de dossier (null : pas d'historique).
  final FolderHistory? history;

  /// Analyses du dossier courant, de la plus ancienne à la plus récente.
  List<HistoryEntry> folderHistory = [];

  /// Surveillance du script ouvert autorisée (voir [GuiSettings.watchFile]).
  final bool watchFiles;
  StreamSubscription<FileSystemEvent>? _watchSub;
  Timer? _debounce;
  StreamSubscription<Set<String>>? _folderSub;

  /// Délai de regroupement des événements d'un même enregistrement.
  static const watchDelay = Duration(milliseconds: 700);

  /// Surveille [path] : à chaque enregistrement (contenu réellement
  /// modifié), l'analyse est relancée. Le dossier est surveillé plutôt que
  /// le fichier, car beaucoup d'éditeurs enregistrent par renommage.
  void _watch(String path) {
    _unwatch();
    if (!watchFiles || !_settings.watchFile || path == '<stdin>') return;
    final target = File(path).absolute.path;
    try {
      _watchSub = File(target).parent.watch().listen((e) {
        final hit = e.path == target ||
            (e is FileSystemMoveEvent && e.destination == target);
        if (!hit) return;
        _debounce?.cancel();
        _debounce = Timer(watchDelay, () => _onWatched(path));
      });
    } on FileSystemException {
      // Surveillance impossible (système de fichiers) : ignorée.
    }
  }

  void _unwatch() {
    _debounce?.cancel();
    _watchSub?.cancel();
    _watchSub = null;
  }

  /// Surveille le dossier [path] : les scripts enregistrés (ou créés) sont
  /// réanalysés et leur rapport remplacé dans [folderReports].
  void _watchFolder(String path) {
    _unwatchFolder();
    if (!watchFiles || !_settings.watchFile) return;
    _folderSub = watchTargets([path], debounce: watchDelay)
        .listen((changed) => _onFolderChanged(path, changed));
  }

  void _unwatchFolder() {
    _folderSub?.cancel();
    _folderSub = null;
  }

  Future<void> _onFolderChanged(String path, Set<String> changed) async {
    if (folderPath != path) return;
    if (busy) {
      Timer(watchDelay, () => _onFolderChanged(path, changed));
      return;
    }
    final scripts = [
      for (final f in changed)
        if (File(f).existsSync() && await isScriptFile(f)) f
    ];
    if (scripts.isEmpty) return;
    try {
      final engine = await _engine(near: path);
      final fresh = await engine.analyzeFiles(scripts);
      if (folderPath != path) return;
      String key(String f) => File(f).absolute.path;
      final byPath = {for (final r in folderReports) key(r.script.path): r};
      for (final r in fresh) {
        byPath[key(r.script.path)] = r;
      }
      folderReports = byPath.values.toList()
        ..sort((a, b) => a.script.path.compareTo(b.script.path));
      await _recordSeen(fresh);
      message = 'folderChanged';
      notifyListeners();
    } on Object {
      // Fichier en cours d'écriture : le prochain enregistrement relancera.
    }
  }

  Future<void> _onWatched(String path) async {
    final c = current;
    if (c == null || c.script.path != path) return;
    if (busy) {
      _debounce = Timer(watchDelay, () => _onWatched(path));
      return;
    }
    try {
      final now = ScriptInfo.fromContent(path, await File(path).readAsString());
      if (now.content == c.script.content) return;
    } on FileSystemException {
      return; // enregistrement en cours ou fichier supprimé
    }
    await analyzeFile(path);
    message = 'fileChanged';
    notifyListeners();
  }

  @override
  void dispose() {
    _unwatch();
    _unwatchFolder();
    super.dispose();
  }

  /// Règles rencontrées lors des analyses (clé → règle), pour l'onglet
  /// Règles : elles complètent le registre des règles connues.
  final Map<String, RuleEntry> seenRules;

  final CommandRunner runner;
  GuiSettings _settings;
  GuiSettings get settings => _settings;

  Lang get lang => _settings.lang ?? Lang.fromEnvironment(Platform.environment);

  ScriptReport? current;

  /// Scripts ouverts en onglets (chemins, dans l'ordre d'ouverture) ; le
  /// script affiché est [current]. Les rapports des autres onglets sont
  /// gardés dans [_tabReports] tant qu'ils sont à jour.
  final List<String> openTabs = [];
  final Map<String, ScriptReport> _tabReports = {};

  /// Chemin du script de l'onglet affiché.
  String? get activeTab => current?.script.path;

  /// Oublie les rapports des onglets non affichés (périmés) : ils seront
  /// réanalysés à leur sélection.
  void _dropStaleTabs() {
    final keep = activeTab;
    _tabReports.removeWhere((path, _) => path != keep);
  }

  /// Affiche l'onglet [path] : son rapport mémorisé, ou une nouvelle analyse
  /// si le fichier a changé depuis ou si le rapport est périmé.
  Future<void> selectTab(String path) async {
    if (busy || path == activeTab || !openTabs.contains(path)) return;
    final cached = _tabReports[path];
    if (cached == null) {
      await analyzeFile(path);
      return;
    }
    try {
      final now = ScriptInfo.fromContent(path, await File(path).readAsString());
      if (now.content != cached.script.content) {
        await analyzeFile(path);
        return;
      }
    } on Object {
      // Illisible : le rapport mémorisé reste affiché.
    }
    current = cached;
    _watch(path);
    notifyListeners();
  }

  /// Passe à l'onglet suivant ([step] 1) ou précédent (-1), en boucle.
  Future<void> cycleTab(int step) async {
    if (openTabs.length < 2) return;
    final i = openTabs.indexOf(activeTab ?? '');
    final next = openTabs[((i < 0 ? 0 : i) + step) % openTabs.length];
    await selectTab(next);
  }

  /// Ferme l'onglet [path] ; s'il était affiché, un voisin le remplace (ou
  /// l'écran se vide s'il n'en reste aucun).
  Future<void> closeTab(String path) async {
    if (busy) return;
    final i = openTabs.indexOf(path);
    if (i < 0) return;
    openTabs.removeAt(i);
    _tabReports.remove(path);
    if (path != activeTab) {
      notifyListeners();
    } else if (openTabs.isEmpty) {
      current = null;
      _unwatch();
      notifyListeners();
    } else {
      current = null; // selectTab affiche le voisin
      await selectTab(openTabs[i < openTabs.length ? i : openTabs.length - 1]);
    }
  }

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

  /// Réglages qui changent le résultat d'une analyse : s'ils changent, les
  /// rapports des onglets non affichés sont périmés.
  static String _analysisKey(GuiSettings s) => [
        s.profile.name,
        (s.contexts.map((c) => c.name).toList()..sort()).join(','),
        (s.disabledTools.toList()..sort()).join(','),
        (s.enabledTools.toList()..sort()).join(','),
        (s.disabledRules.toList()..sort()).join(','),
        s.followSource,
        s.configPath,
        s.pythonTarget,
        s.ruffProjectConfig,
      ].join('|');

  Future<void> updateSettings(GuiSettings s) async {
    final watchChanged = s.watchFile != _settings.watchFile;
    if (_analysisKey(s) != _analysisKey(_settings)) _dropStaleTabs();
    _settings = s;
    if (watchChanged) {
      final c = current;
      if (c != null && s.watchFile) {
        _watch(c.script.path);
      } else {
        _unwatch();
      }
      final f = folderPath;
      if (f != null && s.watchFile) {
        _watchFolder(f);
      } else {
        _unwatchFolder();
      }
    }
    notifyListeners();
    await s.save();
  }

  /// Configuration effective : fichier YAML éventuel, profil, contextes,
  /// outils désactivés.
  /// [near] : script ou dossier analysé ; sans fichier de configuration
  /// choisi, son `.checkscript.yaml` de projet s'applique.
  Future<CheckConfig> buildConfig({String? near}) async {
    var c = await baseConfig(near: near);
    if (_settings.ruffProjectConfig && c.tool('ruff').config == null) {
      c = c.copyWith(tools: {
        ...c.tools,
        'ruff': c.tool('ruff').copyWith(config: () => 'project'),
      });
    }
    return c
        .withToolsEnabled(_settings.enabledTools)
        .withToolsDisabled(_settings.disabledTools)
        .copyWith(
      contexts: _settings.contexts,
      followSource: _settings.followSource,
      pythonTarget: _settings.pythonTarget,
      disabledRules: {...c.disabledRules, ..._settings.disabledRules},
    );
  }

  /// Configuration du profil et du fichier YAML, sans les choix faits dans
  /// l'interface : ses règles désactivées ne se réactivent pas ici.
  Future<CheckConfig> baseConfig({String? near}) async {
    final path =
        _settings.configPath ?? (near == null ? null : findProjectConfig(near));
    if (path != null && await File(path).exists()) {
      return CheckConfig.parse(await File(path).readAsString(),
          profile: _settings.profile);
    }
    return CheckConfig.forProfile(_settings.profile);
  }

  /// Écrit la configuration effective (fichier YAML éventuel et choix de
  /// l'interface) dans [path], relisible par la CLI (`--config`).
  Future<void> exportConfig(String path) async {
    final c = await buildConfig();
    await File(path).writeAsString(c.toYaml(
        header: 'check-script configuration exported by the interface '
            '(check-script $appVersion).\n'
            'CLI: check-script --config ${path.split('/').last} … '
            '(or name the file .checkscript.yaml).'));
  }

  /// Adopte [path] comme configuration : son profil, ses contextes, le suivi
  /// des sources et sa version de Python passent dans les réglages, et les
  /// choix propres à l'interface (règles, outils) sont remis à zéro, pour
  /// que le fichier fasse foi. Lève [FormatException] si le fichier est
  /// invalide.
  Future<void> importConfig(String path) async {
    final c = CheckConfig.parse(await File(path).readAsString());
    await updateSettings(GuiSettings(
      lang: _settings.lang,
      theme: _settings.theme,
      wideSplit: _settings.wideSplit,
      narrowSplit: _settings.narrowSplit,
      useCache: _settings.useCache,
      watchFile: _settings.watchFile,
      editorCommand: _settings.editorCommand,
      ruffProjectConfig: _settings.ruffProjectConfig,
      configPath: path,
      profile: c.profile,
      contexts: c.contexts,
      followSource: c.followSource,
    ));
  }

  /// Active ou désactive une règle (clé en majuscules) à partir de la
  /// prochaine analyse.
  Future<void> setRuleEnabled(String id, bool enabled) {
    final key = id.trim().toUpperCase();
    return updateSettings(_settings.copyWith(
        disabledRules: enabled
            ? ({..._settings.disabledRules}..remove(key))
            : {..._settings.disabledRules, key}));
  }

  /// Réactive toutes les règles désactivées depuis l'interface.
  Future<void> enableAllRules() =>
      updateSettings(_settings.copyWith(disabledRules: const {}));

  /// Nombre maximal de règles rencontrées mémorisées.
  static const maxSeenRules = 2000;

  /// Mémorise les règles des problèmes de [reports] non encore vues.
  Future<void> _recordSeen(Iterable<ScriptReport> reports) async {
    var changed = false;
    for (final r in reports) {
      for (final f in r.findings) {
        final key = f.ruleId.toUpperCase();
        if (seenRules.containsKey(key) || seenRules.length >= maxSeenRules) {
          continue;
        }
        seenRules[key] =
            RuleEntry.fromFinding(f, python: r.script.dialect.isPython);
        changed = true;
      }
    }
    if (changed) await saveSeenRules(seenRules);
  }

  static const _seenKey = 'seenRules';

  /// Règles rencontrées, mémorisées d'une session à l'autre.
  static Future<Map<String, RuleEntry>> loadSeenRules() async {
    final p = await SharedPreferences.getInstance();
    try {
      final list = jsonDecode(p.getString(_seenKey) ?? '[]');
      return {
        for (final j in list is List ? list : const [])
          if (RuleEntry.fromJson(j) case final e?) e.key: e
      };
    } on FormatException {
      return {};
    }
  }

  static Future<void> saveSeenRules(Map<String, RuleEntry> rules) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _seenKey, jsonEncode([for (final e in rules.values) e.toJson()]));
  }

  Future<Engine> _engine({String? near}) async => Engine(
        config: await buildConfig(near: near),
        lang: lang,
        runner: runner,
        baseline: baseline,
        // Cache seulement avec les vrais outils (pas avec un exécuteur de
        // test), et si le réglage l'autorise.
        cache: _settings.useCache && runner is ProcessCommandRunner
            ? ResultCache.standard()
            : null,
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
      final engine = await _engine(near: path);
      current = await engine.analyzeFile(path, cancel: token, onProgress: (p) {
        progress = ProgressInfo(p.tool ?? '', p.fraction);
        notifyListeners();
      });
      await _recordSeen([current!]);
      if (!openTabs.contains(path)) openTabs.add(path);
      _tabReports[path] = current!;
      _watch(path);
      await _remember(path);
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
    folderHistory = await history?.load(path) ?? [];
    try {
      final config = await buildConfig(near: path);
      final files = await collectScripts(path, exclude: config.exclude) ??
          const <String>[];
      final engine = await _engine(near: path);
      // Plusieurs scripts à la fois ; fichiers illisibles ou non textuels
      // ignorés.
      final out = await engine.analyzeFiles(files, cancel: token,
          onDone: (done, total, file) {
        progress = ProgressInfo('$done/$total  $file', done / total);
        notifyListeners();
      });
      folderReports = out;
      await _recordSeen(out);
      _watchFolder(path);
      await _remember(path);
      if (history != null && out.isNotEmpty) {
        folderHistory = await history!.append(path, HistoryEntry.of(path, out));
      }
      _finish(files.isEmpty ? 'noScripts' : null);
    } on AnalysisCancelled {
      _finish('cancelled');
    } catch (e) {
      _finish('error:$e');
    }
  }

  /// Place [path] en tête des récents (enregistrés avec les réglages).
  Future<void> _remember(String path) async {
    if (path == '<stdin>') return;
    final abs = File(path).absolute.path;
    if (_settings.recent.isNotEmpty && _settings.recent.first == abs) return;
    _settings = _settings.withRecent(abs);
    try {
      await _settings.save();
    } on Object {
      // Préférences indisponibles : la liste reste en mémoire.
    }
  }

  /// Oublie les récents.
  Future<void> clearRecent() => updateSettings(_settings.copyWith(recent: []));

  /// Ouvre une entrée des récents : dossier ou script selon ce qu'elle est
  /// devenue ; renvoie false si elle n'existe plus (elle est alors retirée).
  Future<bool> openRecent(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) {
      await updateSettings(_settings.copyWith(recent: [
        for (final r in _settings.recent)
          if (r != path) r
      ]));
      return false;
    }
    if (type == FileSystemEntityType.directory) {
      await analyzeFolder(path);
    } else {
      await analyzeFile(path);
    }
    return true;
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
    _dropStaleTabs();
    notifyListeners();
    await reanalyze();
  }

  Future<void> clearBaseline() async {
    baseline = null;
    baselinePath = null;
    _dropStaleTabs();
    notifyListeners();
    await reanalyze();
  }

  /// Définit l'analyse affichée comme référence : écrit son rapport JSON dans
  /// [path] (extension .json ajoutée au besoin), puis le charge comme
  /// référence. [folder] : le dossier analysé plutôt que le script courant
  /// (il est alors réanalysé pour afficher la tendance). Renvoie le chemin
  /// écrit, ou null s'il n'y a rien à enregistrer.
  Future<String?> setAsBaseline(String path, {bool folder = false}) async {
    final reports = folder ? folderReports : [if (current != null) current!];
    if (reports.isEmpty) return null;
    final file = path.toLowerCase().endsWith('.json') ? path : '$path.json';
    await export(file, reports);
    await loadBaseline(file);
    final dir = folderPath;
    if (folder && dir != null) await analyzeFolder(dir);
    return file;
  }

  /// Calcule les corrections du script courant (sans rien écrire).
  Future<FixResult?> proposeFix() async {
    final c = current;
    if (c == null) return null;
    final script = ScriptInfo.fromContent(
        c.script.path, await File(c.script.path).readAsString());
    return fixScript(script,
        config: await buildConfig(near: c.script.path), runner: runner);
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
  Future<String?> applyFindingFix(Finding f) => _applyFixes([f]);

  /// Problèmes corrigeables de la même règle que [f] dans le script courant.
  List<Finding> fixableOfRule(Finding f) => [
        for (final x in current?.findings ?? const <Finding>[])
          if (x.ruleId.toUpperCase() == f.ruleId.toUpperCase() &&
              x.edits.isNotEmpty)
            x
      ];

  /// Corrige toutes les occurrences de la règle de [f] en une fois (mêmes
  /// garde-fous que [applyFindingFix]).
  Future<String?> applyRuleFixes(Finding f) => _applyFixes(fixableOfRule(f));

  Future<String?> _applyFixes(List<Finding> findings) async {
    final c = current;
    final edits = [for (final f in findings) ...f.edits];
    if (c == null || busy || edits.isEmpty) return staleFix;
    final raw = await File(c.script.path).readAsString();
    final script = ScriptInfo.fromContent(c.script.path, raw);
    if (script.content != c.script.content) return staleFix;
    // Les éditions en conflit sont écartées par applyEdits.
    final (fixed, _) = applyEdits(script.content, edits);
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

  /// Aperçu des corrections de [findings] sur le script courant : (texte
  /// actuel, texte corrigé), ou null si rien ne change ou si le fichier a
  /// été modifié depuis l'analyse.
  Future<(String, String)?> previewFixes(List<Finding> findings) async {
    final c = current;
    final edits = [for (final f in findings) ...f.edits];
    if (c == null || edits.isEmpty) return null;
    final String raw;
    try {
      raw = await File(c.script.path).readAsString();
    } on FileSystemException {
      return null;
    }
    final script = ScriptInfo.fromContent(c.script.path, raw);
    if (script.content != c.script.content) return null;
    final (fixed, _) = applyEdits(script.content, edits);
    return fixed == script.content ? null : (script.content, fixed);
  }

  /// Applique ensemble les corrections des problèmes sélectionnés (mêmes
  /// garde-fous que [applyFindingFix]).
  Future<String?> applySelectedFixes(List<Finding> findings) =>
      _applyFixes(findings);

  /// Exporte les rapports affichés dans [path] (format selon l'extension).
  Future<void> export(String path, List<ScriptReport> reports) async {
    final fmt = OutputFormat.fromPath(path) ?? OutputFormat.markdown;
    await File(path).writeAsBytes(
        await renderBytes(reports, fmt, RenderOptions(lang: lang)));
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
