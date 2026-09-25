/// Interface graphique de check-script.
///
/// Réutilise directement la bibliothèque check_script (même moteur, mêmes
/// règles et mêmes rapports que le CLI).
library;

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/analysis_screen.dart';
import 'screens/folder_screen.dart';
import 'screens/rules_screen.dart';
import 'screens/settings_screen.dart';
import 'strings.dart';

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
        return MaterialApp(
          title: 'CheckScript',
          debugShowCheckedModeBanner: false,
          theme: theme(Brightness.light),
          darkTheme: theme(Brightness.dark),
          themeMode: state.settings.theme,
          home: HomeScreen(state: state),
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

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.addListener(_onState);
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    final msg = state.message;
    if (msg == null || !mounted) return;
    final s = S(state.lang);
    final text = switch (msg) {
      'cancelled' => s.cancelled,
      'noScripts' => s.noScripts,
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

  Future<void> _drop(DropDoneDetails d) async {
    if (d.files.isEmpty) return;
    final path = d.files.first.path;
    if (await FileSystemEntity.isDirectory(path)) {
      setState(() => _index = 1);
      await state.analyzeFolder(path);
    } else {
      setState(() => _index = 0);
      await state.analyzeFile(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S(state.lang);
    final progress = state.progress;
    final screens = [
      AnalysisScreen(state: state),
      FolderScreen(
          state: state,
          onOpen: (path) {
            setState(() => _index = 0);
            state.analyzeFile(path);
          }),
      RulesScreen(state: state),
      SettingsScreen(state: state),
    ];
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
                    destinations: [
                      NavigationRailDestination(
                          icon: const Icon(Icons.description_outlined),
                          selectedIcon: const Icon(Icons.description),
                          label: Text(s.analysis)),
                      NavigationRailDestination(
                          icon: const Icon(Icons.folder_outlined),
                          selectedIcon: const Icon(Icons.folder),
                          label: Text(s.folder)),
                      NavigationRailDestination(
                          icon: const Icon(Icons.rule_outlined),
                          selectedIcon: const Icon(Icons.rule),
                          label: Text(s.rules)),
                      NavigationRailDestination(
                          icon: const Icon(Icons.settings_outlined),
                          selectedIcon: const Icon(Icons.settings),
                          label: Text(s.settings)),
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
                      TextButton(
                          onPressed: state.cancel, child: Text(s.cancel)),
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
