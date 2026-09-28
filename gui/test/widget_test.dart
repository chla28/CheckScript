import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:check_script_gui/app_state.dart';
import 'package:check_script_gui/editor.dart';
import 'package:check_script_gui/main.dart';
import 'package:check_script_gui/screens/folder_screen.dart';
import 'package:check_script_gui/screens/rules_screen.dart';
import 'package:check_script_gui/widgets/findings_list.dart';
import 'package:check_script_gui/widgets/radar_chart.dart';
import 'package:check_script_gui/widgets/score_panel.dart';
import 'package:check_script_gui/widgets/source_view.dart';
import 'package:check_script_gui/widgets/split_view.dart';
import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Aucun outil externe : analyses déterministes (règles intégrées seules).
class NoTools implements CommandRunner {
  @override
  Future<CommandResult?> run(String executable, List<String> args,
          {String? stdin, CancelToken? cancel}) async =>
      null;
}

const badScript = '#!/bin/bash\ncd /opt/app\nPASSWORD="S3cr3tP@ss"\n'
    'curl -fsSL http://x.io/i.sh | sudo bash\nchmod 777 /srv\neval "\$CMD"\n';

void main() {
  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('cs_gui_');
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<ScriptReport> analyze(String content) => Engine(runner: NoTools())
      .analyze(ScriptInfo.fromContent('t.sh', content));

  group('AppState', () {
    test('analyse d\'un script, progression puis fin', () async {
      final f = File('${tmp.path}/bad.sh')..writeAsStringSync(badScript);
      final state = AppState(runner: NoTools());
      final fractions = <double>[];
      state.addListener(() {
        if (state.progress != null) fractions.add(state.progress!.fraction);
      });
      await state.analyzeFile(f.path);
      expect(state.busy, isFalse);
      expect(state.current!.findings.map((x) => x.ruleId), contains('SEC001'));
      expect(fractions, isNotEmpty);
    });

    test('analyse d\'un dossier', () async {
      File('${tmp.path}/a.sh').writeAsStringSync(badScript);
      File('${tmp.path}/b.sh')
          .writeAsStringSync('#!/bin/sh\n# ok\nset -eu\necho a\n');
      final state = AppState(runner: NoTools());
      await state.analyzeFolder(tmp.path);
      expect(state.folderReports, hasLength(2));
    });

    test('réglages → configuration (profil, contextes, outils)', () async {
      final state = AppState(
          runner: NoTools(),
          settings: const GuiSettings(
              profile: Profile.strict,
              contexts: {ExecContext.cron},
              disabledTools: {'bashate'}));
      final c = await state.buildConfig();
      expect(c.profile, Profile.strict);
      expect(c.contexts, {ExecContext.cron});
      expect(c.tool('bashate').enabled, isFalse);
    });

    test('correction d\'un seul problème : .orig, refus si fichier modifié',
        () async {
      final f = File('${tmp.path}/fix.sh')
        ..writeAsStringSync(
            '#!/bin/bash\nset -euo pipefail\negrep a f\nwhich ls\nread x\n');
      final state = AppState(runner: NoTools());
      await state.analyzeFile(f.path);
      Finding rule(String id) =>
          state.current!.findings.firstWhere((x) => x.ruleId == id);
      expect(await state.applyFindingFix(rule('POR005')), isNull);
      expect(f.readAsStringSync(),
          '#!/bin/bash\nset -euo pipefail\ngrep -E a f\nwhich ls\nread x\n');
      expect(File('${f.path}.orig').readAsStringSync(), contains('egrep'));
      expect(state.current!.findings.map((x) => x.ruleId),
          isNot(contains('POR005')));
      // Deuxième correction : le .orig garde le script d'avant la première.
      expect(await state.applyFindingFix(rule('POR004')), isNull);
      expect(f.readAsStringSync(), contains('command -v ls'));
      expect(File('${f.path}.orig').readAsStringSync(), contains('egrep'));
      final sc = rule('ROB007');
      f.writeAsStringSync('${f.readAsStringSync()}echo modifié\n');
      expect(await state.applyFindingFix(sc), AppState.staleFix);
    });

    test('outils Python : pylint activable, version cible transmise', () async {
      const g = GuiSettings();
      expect(g.toolEnabled('ruff'), isTrue);
      expect(g.toolEnabled('pylint'), isFalse);
      final on = g.withTool('pylint', true).withTool('ruff', false);
      expect(on.toolEnabled('pylint'), isTrue);
      expect(on.toolEnabled('ruff'), isFalse);
      final state = AppState(
          runner: NoTools(),
          settings: GuiSettings(
              enabledTools: on.enabledTools,
              disabledTools: on.disabledTools,
              pythonTarget: '3.11'));
      final c = await state.buildConfig();
      expect(c.tool('pylint').enabled, isTrue);
      expect(c.tool('ruff').enabled, isFalse);
      expect(c.pythonTarget, '3.11');
      await on.copyWith(pythonTarget: () => '3.12').save();
      final loaded = await GuiSettings.load();
      expect(loaded.pythonTarget, '3.12');
      expect(loaded.toolEnabled('pylint'), isTrue);
    });

    test('analyse d\'un script Python (sans outils : règles intégrées)',
        () async {
      final f = File('${tmp.path}/tool.py')
        ..writeAsStringSync('#!/usr/bin/python\nimport os\n\n'
            'def main():\n    os.getcwd()\n\nmain()\n');
      final state = AppState(runner: NoTools());
      await state.analyzeFile(f.path);
      final r = state.current!;
      expect(r.script.dialect, Dialect.python);
      expect(r.tools.map((t) => t.tool), isNot(contains('shellcheck')));
      expect(r.findings.map((x) => x.ruleId),
          containsAll(['PYPOR001', 'PYMNT002']));
    });

    test('réglages persistés', () async {
      await const GuiSettings(
              lang: Lang.en, profile: Profile.legacy, followSource: true)
          .save();
      final g = await GuiSettings.load();
      expect(g.lang, Lang.en);
      expect(g.profile, Profile.legacy);
      expect(g.followSource, isTrue);
    });

    test('référence puis correction appliquée avec copie .orig', () async {
      final f = File('${tmp.path}/fix.sh')
        ..writeAsStringSync('#!/bin/bash\n# t\negrep a f\n');
      final state = AppState(runner: NoTools());
      await state.analyzeFile(f.path);
      final base = File('${tmp.path}/base.json');
      await state.export(base.path, [state.current!]);
      await state.loadBaseline(base.path);
      expect(state.current!.comparison, isNotNull);
      final r = (await state.proposeFix())!;
      expect(r.changed, isTrue);
      await state.applyFix(r);
      expect(f.readAsStringSync(), contains('grep -E'));
      expect(File('${f.path}.orig').existsSync(), isTrue);
      expect(state.current!.comparison!.fixed, greaterThanOrEqualTo(1));
    });
  });

  test('tri du tableau du dossier', () async {
    final a = await analyze(badScript);
    final b = await analyze('#!/bin/bash\n# t\nset -euo pipefail\necho a\n');
    expect(sortReports([a, b], -1, true).first, a);
    expect(sortReports([a, b], -1, false).first, b);
  });

  test('radar : sommets', () {
    final c = RadarPainter.vertex(Offset.zero, 100, 0, 5, 10);
    expect(c.dx, closeTo(0, 1e-9));
    expect(c.dy, closeTo(-100, 1e-9));
    expect(
        RadarPainter.vertex(Offset.zero, 100, 0, 5, 5).dy, closeTo(-50, 1e-9));
  });

  testWidgets('écran d\'accueil : navigation et invitation à déposer',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    final state =
        AppState(runner: NoTools(), settings: const GuiSettings(lang: Lang.fr));
    await tester.pumpWidget(CheckScriptApp(state: state));
    expect(find.text('Analyse'), findsWidgets);
    expect(find.text('Dossier'), findsOneWidget);
    expect(find.textContaining('Déposez un script'), findsOneWidget);
    // Fenêtre basse : la barre de navigation défile jusqu'à l'entrée.
    await tester.ensureVisible(find.text('Réglages'));
    await tester.tap(find.text('Réglages'));
    await tester.pumpAndSettle();
    expect(find.text('Police du code'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Profil de notation'), 200,
        scrollable: find
            .descendant(
                of: find.byType(IndexedStack),
                matching: find.byType(Scrollable))
            .last);
    expect(find.text('Profil de notation'), findsOneWidget);
  });

  testWidgets('panneau des notes et source annotée', (tester) async {
    final report = await tester.runAsync(() => analyze(badScript));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          Expanded(
              child: SourceView(
                  lines: report!.script.lines, findings: report.findings)),
          SizedBox(
              width: 460,
              child: SingleChildScrollView(
                  child: ScorePanel(report: report, lang: Lang.en))),
        ]),
      ),
    ));
    expect(find.text('Security'), findsWidgets);
    expect(find.text(report.grade), findsOneWidget);
    expect(find.textContaining('PASSWORD'), findsOneWidget);
  });

  testWidgets('clic sur un problème : code de correction déplié',
      (tester) async {
    final report = await tester.runAsync(() => analyze(
        '#!/bin/bash\nset -euo pipefail\n# en-tête\negrep a f\neval "\$CMD"\n'));
    final applied = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FindingsList(
          findings: report!.findings,
          lang: Lang.fr,
          lines: report.script.lines,
          onApplyFix: (f) => applied.add(f.ruleId),
        ),
      ),
    ));
    expect(find.text('Correction proposée'), findsNothing);
    await tester.tap(find.textContaining('egrep'));
    await tester.pumpAndSettle();
    expect(find.text('Correction proposée'), findsOneWidget);
    expect(find.text('grep -E a f'), findsOneWidget);
    await tester.tap(find.text('Appliquer cette correction'));
    expect(applied, ['POR005']);

    // Règle sans correction automatique : exemple générique.
    await tester.tap(find.textContaining('SEC003'));
    await tester.pumpAndSettle();
    expect(find.text('Correction proposée'), findsNothing);
    expect(find.text('Exemple de correction'), findsOneWidget);
    expect(find.text('À écrire'), findsOneWidget);
    expect(find.text('Appliquer cette correction'), findsNothing);
    expect(find.text('Copier'), findsOneWidget);
  });

  group('séparateur code / résultats', () {
    test('sérialisation et valeurs invalides', () {
      const st = SplitState(0.4, SplitCollapse.second);
      expect(SplitState.decode(st.encode(), const SplitState(0.5)), st);
      expect(SplitState.decode(null, const SplitState(0.5)),
          const SplitState(0.5));
      expect(SplitState.decode('1.7;none', const SplitState(0.5)),
          const SplitState(0.5));
      expect(SplitState.decode('0.3;inconnu', const SplitState(0.5)),
          const SplitState(0.3));
    });

    /// Barre horizontale de 1010 px : 1000 px utiles.
    Future<List<SplitState>> pumpSplit(WidgetTester tester, SplitState st,
        {Axis axis = Axis.horizontal}) async {
      final changes = <SplitState>[];
      var current = st;
      await tester.pumpWidget(MaterialApp(
        home: Center(
            child: StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 1000 + SplitView.handle,
            height: 1000 + SplitView.handle,
            child: SplitView(
              axis: axis,
              first: const _Counter(key: Key('first')),
              second: const ColoredBox(
                  key: Key('second'), color: Colors.transparent),
              state: current,
              defaultState: const SplitState(0.5),
              minFirst: 100,
              minSecond: 200,
              onChanged: (v) => setState(() {
                changes.add(v);
                current = v;
              }),
            ),
          ),
        )),
      ));
      return changes;
    }

    double width(WidgetTester t, String key) =>
        t.getSize(find.byKey(Key(key))).width;

    /// Point de la barre éloigné des boutons (placés en son centre).
    Offset grip(WidgetTester t) =>
        t.getTopLeft(find.byKey(const Key('split-handle'))) +
        const Offset(SplitView.handle / 2, SplitView.handle / 2 + 20);

    testWidgets('glisser, bornes, double-clic', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final changes = await pumpSplit(tester, const SplitState(0.5));
      expect(width(tester, 'first'), 500);
      await tester.dragFrom(grip(tester), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(width(tester, 'first'), closeTo(300, 25));
      // Une seule notification, en fin de glissement.
      expect(changes, hasLength(1));
      // Au-delà de la taille minimale du second panneau (200 px) : bornée.
      await tester.dragFrom(grip(tester), const Offset(900, 0));
      await tester.pumpAndSettle();
      expect(width(tester, 'second'), closeTo(200, 1));
      await tester.tapAt(grip(tester));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(grip(tester));
      await tester.pumpAndSettle();
      expect(changes.last, const SplitState(0.5));
      expect(width(tester, 'first'), 500);
    });

    testWidgets('replier puis rétablir sans perdre l\'état', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpSplit(tester, const SplitState(0.5));
      await tester.tap(find.text('0'));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_left)); // replier le 1er
      await tester.pumpAndSettle();
      expect(find.text('1'), findsNothing); // hors écran
      expect(width(tester, 'second'), 1000);
      await tester.tap(find.byIcon(Icons.chevron_right)); // rétablir
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget); // compteur conservé
      await tester.tap(find.byIcon(Icons.chevron_right)); // replier le 2nd
      await tester.pumpAndSettle();
      expect(width(tester, 'first'), 1000);
    });

    testWidgets('disposition verticale', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpSplit(tester, const SplitState(0.35), axis: Axis.vertical);
      expect(tester.getSize(find.byKey(const Key('first'))).height, 350);
      final top = tester.getTopLeft(find.byKey(const Key('split-handle')));
      await tester.dragFrom(
          top + const Offset(20, SplitView.handle / 2), const Offset(0, 150));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const Key('first'))).height,
          closeTo(500, 25));
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });

    testWidgets('écran d\'analyse : répartition mémorisée', (tester) async {
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = File('${tmp.path}/split.sh')..writeAsStringSync(badScript);
      // Langue fixée : sinon elle dépend de LANG (anglais en CI).
      final state = AppState(
          runner: NoTools(), settings: const GuiSettings(lang: Lang.fr));
      await tester.runAsync(() => state.analyzeFile(f.path));
      await tester.pumpWidget(CheckScriptApp(state: state));
      await tester.pumpAndSettle();
      expect(state.settings.wideSplit, GuiSettings.defaultWideSplit);
      await tester.dragFrom(grip(tester), const Offset(-300, 0));
      await tester.pumpAndSettle();
      final r = state.settings.wideSplit.ratio;
      expect(r, lessThan(GuiSettings.defaultWideSplit.ratio));
      final loaded = await tester.runAsync(GuiSettings.load);
      expect(loaded!.wideSplit.ratio, closeTo(r, 1e-4));
      await tester.tap(find.byTooltip('Masquer le code'));
      await tester.pumpAndSettle();
      expect(state.settings.wideSplit.collapsed, SplitCollapse.first);
    });
  });

  group('corriger toutes les occurrences d\'une règle', () {
    const src = '#!/bin/bash\nset -euo pipefail\n# en-tête\n'
        'egrep a f\nwhich ls\negrep b g\negrep c h\n';

    test('AppState : toutes les occurrences en une fois', () async {
      final f = File('${tmp.path}/multi.sh')..writeAsStringSync(src);
      final state = AppState(runner: NoTools());
      await state.analyzeFile(f.path);
      final first =
          state.current!.findings.firstWhere((x) => x.ruleId == 'POR005');
      expect(state.fixableOfRule(first), hasLength(3));
      expect(await state.applyRuleFixes(first), isNull);
      final text = f.readAsStringSync();
      expect(text, isNot(contains('egrep')));
      expect(text, contains('which ls')); // autre règle : inchangée
      expect(File('${f.path}.orig').readAsStringSync(), src);
      expect(state.current!.findings.map((x) => x.ruleId),
          isNot(contains('POR005')));
    });

    testWidgets('bouton affiché seulement s\'il y a plusieurs occurrences',
        (tester) async {
      final report = await tester.runAsync(() => analyze(src));
      final fixed = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FindingsList(
            findings: report!.findings,
            lang: Lang.fr,
            lines: report.script.lines,
            onApplyFix: (_) {},
            onApplyRule: (f) => fixed.add(f.ruleId),
          ),
        ),
      ));
      await tester.tap(find.textContaining('POR005').first);
      await tester.pumpAndSettle();
      final button = find.text('Corriger les 3 occurrences (POR005)');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      expect(fixed, ['POR005']);
      // Une seule occurrence (which) : pas de bouton groupé.
      await tester.ensureVisible(find.textContaining('POR004').first);
      await tester.tap(find.textContaining('POR004').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('occurrences (POR004)'), findsNothing);
    });
  });

  group('v0.8 : historique, surveillance, éditeur, explication', () {
    test('historique d\'un dossier : une entrée par analyse', () async {
      File('${tmp.path}/a.sh').writeAsStringSync(badScript);
      final hist = FolderHistory(Directory('${tmp.path}/.hist'));
      final state = AppState(runner: NoTools(), history: hist);
      await state.analyzeFolder(tmp.path);
      await state.analyzeFolder(tmp.path);
      expect(state.folderHistory, hasLength(2));
      expect(state.folderHistory.last.scripts, 1);
      expect(state.folderHistory.last.scores.keys, ['a.sh']);
      final reloaded = await hist.load(tmp.path);
      expect(reloaded.last.average, state.folderHistory.last.average);
    });

    testWidgets('écran Dossier : courbe d\'historique', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      File('${tmp.path}/a.sh').writeAsStringSync(badScript);
      final hist = FolderHistory(Directory('${tmp.path}/.hist'));
      final state = AppState(
          runner: NoTools(),
          history: hist,
          settings: const GuiSettings(lang: Lang.fr));
      await tester.runAsync(() async {
        await state.analyzeFolder(tmp.path);
        await state.analyzeFolder(tmp.path);
      });
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: FolderScreen(state: state, onOpen: (_) {}))));
      expect(find.text('Historique'), findsOneWidget);
      expect(find.textContaining('2 analyses'), findsOneWidget);
    });

    test('surveillance : l\'enregistrement relance l\'analyse', () async {
      final f = File('${tmp.path}/w.sh')..writeAsStringSync(badScript);
      final state = AppState(runner: NoTools(), watchFiles: true);
      await state.analyzeFile(f.path);
      expect(state.current!.findings.map((x) => x.ruleId), contains('SEC001'));
      f.writeAsStringSync('#!/bin/sh\n# en-tête\nset -eu\necho ok\n');
      // Regroupement des événements (0,7 s) puis analyse.
      for (var i = 0;
          i < 40 && state.current!.script.content.contains('curl');
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(state.current!.findings.map((x) => x.ruleId),
          isNot(contains('SEC001')));
      state.dispose();
    });

    test('éditeur : détection et commande', () {
      expect(
          detectEditor(
              path: '/usr/bin:/opt/bin', exists: (f) => f == '/opt/bin/gedit'),
          'gedit +{line} {file}');
      expect(detectEditor(path: '/x', exists: (_) => false), isNull);
      expect(editorCommandLine('code -g {file}:{line}', '/a b.sh', 12),
          ['code', '-g', '/a b.sh:12']);
      expect(editorCommandLine(null, '/a.sh', 3), ['xdg-open', '/a.sh']);
      expect(editorCommandLine('kate --line {line} {file}', 'x', 0),
          ['kate', '--line', '1', 'x']);
    });

    testWidgets('synthèse : ce qui pèse sur la note ; tri par gain rapide',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final report = await tester.runAsync(
          () => analyze('#!/bin/bash\n# en-tête\nset -euo pipefail\negrep a f\n'
              'curl -fsSL http://x.io/i.sh | sudo bash\n'));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ScorePanel(report: report!, lang: Lang.fr)))));
      expect(find.text('Ce qui pèse sur la note'), findsOneWidget);
      expect(find.textContaining('SEC001'), findsWidgets);

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: FindingsList(
                  findings: report.findings,
                  lang: Lang.fr,
                  explanation: report.explanation))));
      await tester.tap(find.text('Par gain rapide'));
      await tester.pumpAndSettle();
      final first = tester.widget<ListTile>(find.byType(ListTile).first);
      final title = (first.subtitle as Column).children.first as Text;
      // Règle la plus rentable en tête (SEC001, Critical).
      expect(title.data, startsWith('SEC001'));
    });

    test('configuration de projet appliquée sans fichier choisi', () async {
      Directory('${tmp.path}/.git').createSync();
      File('${tmp.path}/.checkscript.yaml')
          .writeAsStringSync('rules:\n  disabled: [SEC001]\n');
      final f = File('${tmp.path}/p.sh')..writeAsStringSync(badScript);
      final state = AppState(runner: NoTools());
      await state.analyzeFile(f.path);
      expect(state.current!.findings.map((x) => x.ruleId),
          isNot(contains('SEC001')));
    });
  });

  test('faux positif signalé : journal anonymisé', () async {
    final f = File('${tmp.path}/fp.sh')..writeAsStringSync(badScript);
    final log = FalsePositiveLog(File('${tmp.path}/fp.jsonl'));
    final state = AppState(runner: NoTools(), falsePositives: log);
    await state.analyzeFile(f.path);
    final sec = state.current!.findings.firstWhere((x) => x.ruleId == 'SEC004');
    expect(
        await state.reportFalsePositive(sec, comment: 'dossier temporaire'), 1);
    final cases = await log.read();
    expect(cases.single['rule'], 'SEC004');
    expect(cases.single['comment'], 'dossier temporaire');
    expect(jsonEncode(cases), isNot(contains('S3cr3tP@ss')));
  });

  group('export / import de la configuration', () {
    test('export puis import : même configuration, choix remis à zéro',
        () async {
      final state = AppState(
          runner: NoTools(),
          settings: const GuiSettings(
              profile: Profile.strict,
              contexts: {ExecContext.cron},
              enabledTools: {'pylint'},
              disabledTools: {'bashate'},
              pythonTarget: '3.11',
              disabledRules: {'SEC001', 'B602'}));
      final path = '${tmp.path}/.checkscript.yaml';
      await state.exportConfig(path);
      final text = File(path).readAsStringSync();
      expect(text, contains('pythonTarget: "3.11"'));
      expect(text, contains('check-script --config'));

      final other = AppState(runner: NoTools());
      await other.importConfig(path);
      final a = await state.buildConfig(), b = await other.buildConfig();
      expect(b.profile, Profile.strict);
      expect(b.contexts, {ExecContext.cron});
      expect(b.pythonTarget, '3.11');
      expect(b.tool('pylint').enabled, isTrue);
      expect(b.tool('bashate').enabled, isFalse);
      expect(b.disabledRules, a.disabledRules);
      // Le fichier fait foi : pas de choix propres à l'interface.
      expect(other.settings.disabledRules, isEmpty);
      expect(other.settings.enabledTools, isEmpty);
      expect(other.settings.configPath, path);
    });

    test('fichier invalide : refusé, réglages inchangés', () async {
      final path = '${tmp.path}/bad.yaml';
      File(path).writeAsStringSync('profile: inconnu\n');
      final state = AppState(runner: NoTools());
      await expectLater(state.importConfig(path), throwsFormatException);
      expect(state.settings.configPath, isNull);
    });
  });

  group('règles de détection', () {
    test('désactivation effective à l\'analyse suivante, mémorisation',
        () async {
      final f = File('${tmp.path}/r.sh')..writeAsStringSync(badScript);
      final state = AppState(runner: NoTools());
      await state.analyzeFile(f.path);
      expect(state.current!.findings.map((x) => x.ruleId), contains('SEC001'));
      // Règles rencontrées mémorisées.
      expect(state.seenRules.keys, contains('SEC001'));
      expect((await AppState.loadSeenRules()).keys, contains('SEC001'));
      await state.setRuleEnabled('sec001', false);
      expect(state.settings.disabledRules, {'SEC001'});
      // Le rapport courant n'est pas modifié avant la prochaine analyse.
      expect(state.current!.findings.map((x) => x.ruleId), contains('SEC001'));
      expect((await state.buildConfig()).disabledRules, contains('SEC001'));
      await state.reanalyze();
      expect(state.current!.findings.map((x) => x.ruleId),
          isNot(contains('SEC001')));
      expect((await GuiSettings.load()).disabledRules, {'SEC001'});
      await state.enableAllRules();
      expect(state.settings.disabledRules, isEmpty);
    });

    test('règles du profil : conservées, non réactivables ici', () async {
      final state = AppState(
          runner: NoTools(),
          settings: const GuiSettings(
              profile: Profile.legacy, disabledRules: {'SC2086'}));
      final c = await state.buildConfig();
      expect(c.disabledRules, containsAll(['MNT001', 'SC2086']));
      expect(
          (await state.baseConfig()).disabledRules, isNot(contains('SC2086')));
    });

    testWidgets('onglet Règles : recherche, case à cocher, saisie, verrou',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState(
          runner: NoTools(),
          settings: const GuiSettings(lang: Lang.fr, profile: Profile.legacy),
          seenRules: {
            'ARG-TYPE': const RuleEntry(
                id: 'arg-type',
                tool: 'mypy',
                language: ToolLanguage.python,
                category: Category.robustness,
                severity: Severity.medium,
                title: 'Argument has incompatible type'),
          });
      // Comme dans l'application : reconstruit à chaque changement d'état.
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ListenableBuilder(
                  listenable: state,
                  builder: (_, __) => RulesScreen(state: state)))));
      await tester.pumpAndSettle();
      final total = RulesScreenTestAccess.count(state);
      expect(find.textContaining('/ $total règles'), findsOneWidget);

      // La recherche porte sur des sous-chaînes : SEC001 et PYSEC001.
      await tester.enterText(find.byType(TextField).first, 'SEC001');
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('SEC001')),
          matching: find.byType(Checkbox)));
      await tester.pumpAndSettle();
      expect(state.settings.disabledRules, {'SEC001'});
      expect(find.text('Tout réactiver (1)'), findsOneWidget);

      // Règle rencontrée lors d'une analyse.
      await tester.enterText(find.byType(TextField).first, 'arg-type');
      await tester.pumpAndSettle();
      expect(find.textContaining('rencontrée'), findsOneWidget);

      // Règle désactivée par le profil legacy : case grisée.
      await tester.enterText(find.byType(TextField).first, 'MNT001');
      await tester.pumpAndSettle();
      final box =
          tester.widget<CheckboxListTile>(find.byKey(const ValueKey('MNT001')));
      expect(box.value, isFalse);
      expect(box.onChanged, isNull);

      // Code saisi librement.
      await tester.enterText(find.byType(TextField).at(1), 'sc9999');
      await tester.tap(find.text('Désactiver'));
      await tester.pumpAndSettle();
      expect(state.settings.disabledRules, containsAll(['SEC001', 'SC9999']));
      await tester.enterText(find.byType(TextField).first, 'SC9999');
      await tester.pumpAndSettle();
      expect(find.textContaining('code saisi'), findsOneWidget);
    });

    testWidgets('problème : « Ne plus signaler »', (tester) async {
      final report = await tester.runAsync(() => analyze(badScript));
      final disabled = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FindingsList(
            findings: report!.findings,
            lang: Lang.fr,
            lines: report.script.lines,
            onDisableRule: (f) => disabled.add(f.ruleId),
          ),
        ),
      ));
      expect(find.textContaining('Ne plus signaler'), findsNothing);
      await tester.tap(find.textContaining('SEC003'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Ne plus signaler SEC003'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ne plus signaler SEC003'));
      expect(disabled, ['SEC003']);
    });
  });
}

/// Nombre total de règles affichées par l'onglet (connues + rencontrées +
/// saisies), pour vérifier le compteur.
class RulesScreenTestAccess {
  static int count(AppState state) =>
      knownRules(state.lang).length +
      state.seenRules.keys
          .where((k) => !knownRules(state.lang).any((e) => e.key == k))
          .length;
}

/// Compteur à état local : vérifie qu'un panneau replié n'est pas recréé.
class _Counter extends StatefulWidget {
  const _Counter({super.key});
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _n = 0;
  @override
  Widget build(BuildContext context) => Center(
      child: TextButton(
          onPressed: () => setState(() => _n++), child: Text('$_n')));
}
