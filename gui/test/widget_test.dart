import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:check_script_gui/app_state.dart';
import 'package:check_script_gui/main.dart';
import 'package:check_script_gui/screens/folder_screen.dart';
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
}
