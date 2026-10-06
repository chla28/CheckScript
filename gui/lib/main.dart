// Copyright (C) 2026 Christophe Lafaille
// SPDX-License-Identifier: LGPL-3.0-or-later

/// Interface graphique de check-script.
///
/// Réutilise directement la bibliothèque check_script (même moteur, mêmes
/// règles et mêmes rapports que le CLI).
library;

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'code_style.dart';
import 'screens/analysis_screen.dart'
    show AnalysisScreen, exportReports, requestCloseTab;
import 'screens/folder_screen.dart';
import 'screens/rules_screen.dart';
import 'screens/settings_screen.dart';
import 'help/help_content.dart';
import 'help/help_screen.dart';
import 'help/tips.dart';
import 'strings.dart';
import 'widgets/recent_menu.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(
      settings: await GuiSettings.load(),
      seenRules: await AppState.loadSeenRules());
  runApp(CheckScriptApp(state: state));
  // Un chemin passé en argument est analysé au démarrage.
  if (args.isNotEmpty) {
    final target = args.first;
    if (await FileSystemEntity.isDirectory(target)) {
      await state.analyzeFolder(target);
    } else if (await File(target).exists()) {
      await state.analyzeFile(target);
    }
  }
}

class CheckScriptApp extends StatelessWidget {
  const CheckScriptApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        ThemeData theme(Brightness b) => ThemeData(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF3C6E71), brightness: b),
              useMaterial3: true,
            );
        // Au-dessus du navigateur : les dialogues (diff…) en profitent.
        return CodeFont(
          family: state.settings.codeFont,
          size: state.settings.codeFontSize,
          child: MaterialApp(
            title: 'CheckScript',
            debugShowCheckedModeBanner: false,
            theme: theme(Brightness.light),
            darkTheme: theme(Brightness.dark),
            themeMode: state.settings.theme,
            home: HomeScreen(state: state),
          ),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});
  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  bool _dragging = false;

  /// Demandes de recherche (Ctrl+F), une par écran qui en a une.
  final _findAnalysis = ValueNotifier(0);
  final _findRules = ValueNotifier(0);
  final _findHelp = ValueNotifier(0);

  /// Sujet affiché par l'écran d'aide (dernière entrée de la navigation).
  final _helpTopic = ValueNotifier(HelpTopic.start);
  static const _helpIndex = 4;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.addListener(_onState);
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    _helpTopic.dispose();
    _findAnalysis.dispose();
    _findRules.dispose();
    _findHelp.dispose();
    super.dispose();
  }

  void _onState() {
    final msg = state.message;
    if (msg == null || !mounted) return;
    final s = S(state.lang);
    final text = switch (msg) {
      'cancelled' => s.cancelled,
      'noScripts' => s.noScripts,
      'fileChanged' => s.fileChanged,
      'folderChanged' => s.folderChanged,
      _ when msg.startsWith('error:') => s.error(msg.substring(6)),
      _ => msg,
    };
    state.message = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(text)));
      }
    });
  }

  /// Ouvre l'écran d'aide sur [topic] (aide contextuelle).
  void _openHelp(HelpTopic topic) {
    _helpTopic.value = topic;
    setState(() => _index = _helpIndex);
  }

  /// Sujet d'aide de l'écran affiché (touche F1).
  HelpTopic _topicOfScreen() => switch (_index) {
        0 => HelpTopic.analysis,
        1 => HelpTopic.folder,
        2 => HelpTopic.rules,
        3 => HelpTopic.settings,
        _ => _helpTopic.value,
      };

  Future<void> _openRecent(String path, bool directory) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = S(state.lang);
    setState(() => _index = directory ? 1 : 0);
    if (!await state.openRecent(path)) {
      messenger.showSnackBar(SnackBar(content: Text(s.recentMissing(path))));
    }
  }

  Future<void> _drop(DropDoneDetails d) async {
    if (d.files.isEmpty) return;
    final first = d.files.first.path;
    if (await FileSystemEntity.isDirectory(first)) {
      setState(() => _index = 1);
      await state.analyzeFolder(first);
      return;
    }
    // Plusieurs scripts déposés : un onglet chacun (le dernier s'affiche).
    setState(() => _index = 0);
    for (final f in d.files) {
      if (!await FileSystemEntity.isDirectory(f.path)) {
        await state.analyzeFile(f.path);
      }
    }
  }

  // ── Raccourcis clavier ────────────────────────────────────────────────────

  /// Ctrl+O : choisir un ou plusieurs scripts.
  Future<void> _openScripts() async {
    if (state.busy) return;
    final r = await FilePicker.pickFiles(
        dialogTitle: S(state.lang).openScript, allowMultiple: true);
    if (r == null || !mounted) return;
    setState(() => _index = 0);
    for (final f in r.files) {
      final path = f.path;
      if (path != null) await state.analyzeFile(path);
    }
  }

  /// Ctrl+Maj+O : choisir un dossier.
  Future<void> _openFolder() async {
    if (state.busy) return;
    final dir = await FilePicker.getDirectoryPath(
        dialogTitle: S(state.lang).openFolder);
    if (dir == null || !mounted) return;
    setState(() => _index = 1);
    await state.analyzeFolder(dir);
  }

  /// F5 / Ctrl+R : relancer l'analyse du dossier (écran Dossier) ou du
  /// script affiché.
  Future<void> _reanalyze() async {
    if (state.busy) return;
    final dir = state.folderPath;
    if (_index == 1 && dir != null) {
      await state.analyzeFolder(dir);
    } else {
      await state.reanalyze();
    }
  }

  /// Ctrl+E : exporter le rapport du dossier (écran Dossier) ou du script.
  Future<void> _export() async {
    final reports = _index == 1
        ? state.folderReports
        : [if (state.current != null) state.current!];
    if (reports.isNotEmpty) await exportReports(context, state, reports);
  }

  /// Ctrl+F : recherche dans l'écran affiché.
  void _find() {
    switch (_index) {
      case 0:
        _findAnalysis.value++;
      case 2:
        _findRules.value++;
      case _helpIndex:
        _findHelp.value++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S(state.lang);
    final progress = state.progress;
    final screens = [
      AnalysisScreen(state: state, findRequest: _findAnalysis),
      FolderScreen(
          state: state,
          onOpen: (path) {
            setState(() => _index = 0);
            state.analyzeFile(path);
          }),
      RulesScreen(state: state, findRequest: _findRules),
      SettingsScreen(state: state),
      HelpScreen(lang: state.lang, topic: _helpTopic, findRequest: _findHelp),
    ];
    // Ctrl+plus / Ctrl+moins / Ctrl+0 : taille du code, depuis tout l'écran.
    void zoom(double? d) => state.updateSettings(state.settings.zoomCode(d));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): () =>
            _openHelp(_topicOfScreen()),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            _openScripts,
        const SingleActivator(LogicalKeyboardKey.keyO,
            control: true, shift: true): _openFolder,
        const SingleActivator(LogicalKeyboardKey.f5): _reanalyze,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true):
            _reanalyze,
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): _export,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _find,
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
          final tab = state.activeTab;
          if (_index == 0 && tab != null) requestCloseTab(context, state, tab);
        },
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
            state.cycleTab(1),
        const SingleActivator(LogicalKeyboardKey.tab,
            control: true, shift: true): () => state.cycleTab(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown, control: true): () =>
            state.cycleTab(1),
        const SingleActivator(LogicalKeyboardKey.pageUp, control: true): () =>
            state.cycleTab(-1),
        for (var i = 0; i < 5; i++)
          SingleActivator(
              [
                LogicalKeyboardKey.digit1,
                LogicalKeyboardKey.digit2,
                LogicalKeyboardKey.digit3,
                LogicalKeyboardKey.digit4,
                LogicalKeyboardKey.digit5,
              ][i],
              control: true): () => setState(() => _index = i),
        for (final k in [
          LogicalKeyboardKey.equal,
          LogicalKeyboardKey.add,
          LogicalKeyboardKey.numpadAdd,
        ])
          SingleActivator(k, control: true): () => zoom(1),
        for (final k in [
          LogicalKeyboardKey.minus,
          LogicalKeyboardKey.numpadSubtract,
        ])
          SingleActivator(k, control: true): () => zoom(-1),
        for (final k in [LogicalKeyboardKey.digit0, LogicalKeyboardKey.numpad0])
          SingleActivator(k, control: true): () => zoom(null),
      },
      child: HelpScope(
        openHelp: _openHelp,
        child: Focus(
            autofocus: true, child: _scaffold(context, s, screens, progress)),
      ),
    );
  }

  NavigationRailDestination _destination(
          IconData icon, IconData selected, String label, String help) =>
      NavigationRailDestination(
          icon: Icon(icon),
          selectedIcon: Icon(selected),
          label: tip(help, Text(label)));

  Widget _scaffold(
      BuildContext context, S s, List<Widget> screens, ProgressInfo? progress) {
    final tp = Tips(state.lang);
    return Scaffold(
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (d) {
          setState(() => _dragging = false);
          _drop(d);
        },
        child: Row(children: [
          // Barre défilante quand la fenêtre est trop basse pour ses entrées.
          LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    labelType: NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Icon(Icons.fact_check,
                          size: 32,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    trailing: RecentMenu(state: state, onOpen: _openRecent),
                    destinations: [
                      _destination(Icons.description_outlined,
                          Icons.description, s.analysis, tp.navAnalysis),
                      _destination(Icons.folder_outlined, Icons.folder,
                          s.folder, tp.navFolder),
                      _destination(Icons.rule_outlined, Icons.rule, s.rules,
                          tp.navRules),
                      _destination(Icons.settings_outlined, Icons.settings,
                          s.settings, tp.navSettings),
                      _destination(
                          Icons.help_outline, Icons.help, s.help, tp.navHelp),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(children: [
              if (progress != null)
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.analyzing(progress.label),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(value: progress.fraction),
                            ]),
                      ),
                      tip(
                          tp.cancelAnalysis,
                          TextButton(
                              onPressed: state.cancel, child: Text(s.cancel))),
                    ]),
                  ),
                ),
              Expanded(
                child: Stack(children: [
                  IndexedStack(index: _index, children: screens),
                  if (_dragging)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.08),
                          alignment: Alignment.center,
                          child: Icon(Icons.file_download,
                              size: 64,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
