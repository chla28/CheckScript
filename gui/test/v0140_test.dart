import 'dart:async';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:check_script_gui/app_state.dart';
import 'package:check_script_gui/widgets/findings_list.dart';
import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NoTools implements CommandRunner {
  @override
  Future<CommandResult?> run(String executable, List<String> args,
          {String? stdin, CancelToken? cancel}) async =>
      null;
}

const fixable = '#!/bin/bash\nset -euo pipefail\negrep a f\nwhich ls\n';

void main() {
  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('cs_gui14_');
  });
  tearDown(() => tmp.delete(recursive: true));

  group('récents', () {
    test('mémorisés, sans doublon, limités, entrée disparue retirée', () async {
      final f = File('${tmp.path}/a.sh')..writeAsStringSync(fixable);
      final state = AppState(runner: NoTools(), settings: const GuiSettings());
      await state.analyzeFile(f.path);
      await state.analyzeFolder(tmp.path);
      await state.analyzeFile(f.path);
      expect(state.settings.recent, [f.absolute.path, tmp.absolute.path]);
      expect((await GuiSettings.load()).recent, state.settings.recent);

      var g = const GuiSettings();
      for (var i = 0; i < 15; i++) {
        g = g.withRecent('/x/$i');
      }
      expect(g.recent, hasLength(GuiSettings.maxRecent));
      expect(g.recent.first, '/x/14');

      f.deleteSync();
      expect(await state.openRecent(f.absolute.path), isFalse);
      expect(state.settings.recent, [tmp.absolute.path]);
      await state.clearRecent();
      expect(state.settings.recent, isEmpty);
    });
  });

  group('correction de la sélection', () {
    test('aperçu global puis application', () async {
      final f = File('${tmp.path}/fix.sh')..writeAsStringSync(fixable);
      final state = AppState(runner: NoTools());
      await state.analyzeFile(f.path);
      final chosen = [
        for (final x in state.current!.findings)
          if (x.ruleId == 'POR005' || x.ruleId == 'POR004') x
      ];
      expect(chosen, hasLength(2));
      final (before, after) = (await state.previewFixes(chosen))!;
      expect(before, fixable);
      expect(after, contains('grep -E a f'));
      expect(after, contains('command -v ls'));
      expect(await state.applySelectedFixes(chosen), isNull);
      expect(f.readAsStringSync(), after);
      // Fichier modifié depuis l'analyse : pas d'aperçu.
      f.writeAsStringSync('${f.readAsStringSync()}echo x\n');
      expect(await state.previewFixes(state.current!.findings), isNull);
    });

    testWidgets('cases à cocher et bouton de la liste', (tester) async {
      final report = await tester.runAsync(() => Engine(runner: NoTools())
          .analyze(ScriptInfo.fromContent('t.sh', fixable)));
      List<Finding>? selected;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FindingsList(
            findings: report!.findings,
            lang: Lang.fr,
            lines: report.script.lines,
            onApplySelection: (fs) => selected = fs,
          ),
        ),
      ));
      final button = find.textContaining('Corriger la sélection');
      expect(
          tester
              .widget<FilledButton>(find.ancestor(
                  of: button,
                  matching: find.byWidgetPredicate((w) => w is FilledButton)))
              .onPressed,
          isNull);
      // Tout cocher (case à trois états de la barre).
      await tester
          .tap(find.byWidgetPredicate((w) => w is Checkbox && w.tristate));
      await tester.pump();
      expect(find.text('Corriger la sélection (2)…'), findsOneWidget);
      await tester.tap(button);
      expect(selected!.map((f) => f.ruleId).toSet(), {'POR004', 'POR005'});
    });
  });

  test('vue Dossier : un script enregistré est réanalysé', () async {
    final f = File('${tmp.path}/a.sh')
      ..writeAsStringSync('#!/bin/sh\necho a\n');
    final state = AppState(runner: NoTools(), watchFiles: true);
    await state.analyzeFolder(tmp.path);
    expect(state.folderReports.single.findings.map((x) => x.ruleId),
        isNot(contains('POR005')));
    final changed = Completer<void>();
    state.addListener(() {
      if (state.message == 'folderChanged' && !changed.isCompleted) {
        changed.complete();
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    f.writeAsStringSync('#!/bin/sh\negrep a f\n');
    File('${tmp.path}/b.sh').writeAsStringSync('#!/bin/sh\necho b\n');
    await changed.future.timeout(const Duration(seconds: 10));
    expect(state.folderReports, hasLength(2));
    expect(state.folderReports.first.findings.map((x) => x.ruleId),
        contains('POR005'));
    state.dispose();
  });
}
