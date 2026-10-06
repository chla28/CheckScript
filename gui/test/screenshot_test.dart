/// Captures d'écran hors affichage (contrôle visuel) : lancé seulement si
/// SCREENSHOT_DIR est défini, avec les polices système réelles.
///
///   SCREENSHOT_DIR=/tmp/shots flutter test test/screenshot_test.dart
///
/// Les captures françaises sont écrites dans SCREENSHOT_DIR, les anglaises
/// dans SCREENSHOT_DIR/en.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:check_script/check_script.dart';
import 'package:check_script_gui/app_state.dart';
import 'package:check_script_gui/main.dart';
import 'package:check_script_gui/screens/compare_dialog.dart';
import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _dir = Platform.environment['SCREENSHOT_DIR'];

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    if (File(f).existsSync()) {
      loader.addFont(
          Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
  }
  await loader.load();
}

Lang _lang = Lang.fr;

/// Affiche l'écran Analyse (entrée de navigation sélectionnée ou non).
Future<void> _goAnalysis(WidgetTester t) async {
  await t.tap(find
      .descendant(
          of: find.byType(NavigationRail),
          matching: find.byWidgetPredicate((w) =>
              w is Icon &&
              (w.icon == Icons.description ||
                  w.icon == Icons.description_outlined)))
      .first);
  await t.pumpAndSettle();
}

/// Ferme les dialogues restés ouverts par la capture précédente.
Future<void> _closeDialogs(WidgetTester t) async {
  while (find.byType(Dialog).evaluate().isNotEmpty) {
    Navigator.of(t.element(find.byType(Dialog).first)).pop();
    await t.pumpAndSettle();
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  final bytes = await tester
      .runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  final dir = _lang == Lang.fr ? _dir : '$_dir/en';
  Directory(dir!).createSync(recursive: true);
  File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/devel/flutter';

  setUpAll(() async {
    if (_dir == null) return;
    await _font('Roboto',
        ['/usr/share/fonts/adwaita-sans-fonts/AdwaitaSans-Regular.ttf']);
    await _font('monospace',
        ['/usr/share/fonts/adwaita-mono-fonts/AdwaitaMono-Regular.ttf']);
    await _font('JetBrains Mono', [
      for (final v in ['Regular', 'Bold', 'Italic', 'BoldItalic'])
        'fonts/JetBrainsMono/JetBrainsMonoNL-$v.ttf'
    ]);
    await _font('MaterialIcons', [
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
    ]);
  });

  Future<void> run(WidgetTester tester, String name, Brightness b,
      Future<void> Function(AppState) prepare,
      {int tab = 0,
      bool openIssues = false,
      Future<void> Function(WidgetTester)? after}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState(
        settings: GuiSettings(
            lang: _lang,
            theme: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light));
    await tester.runAsync(() => prepare(state));
    await tester.pumpWidget(RepaintBoundary(
        key: const Key('shot'), child: CheckScriptApp(state: state)));
    if (tab != 0) {
      await tester.tap(find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byIcon(const [
            Icons.folder_outlined,
            Icons.rule_outlined,
            Icons.settings_outlined,
            Icons.help_outline,
          ][tab - 1])));
    }
    await tester.pumpAndSettle();
    if (openIssues) {
      await tester.tap(
          find.textContaining(_lang == Lang.fr ? 'Problèmes (' : 'Issues ('));
      await tester.pumpAndSettle();
    }
    await after?.call(tester);
    await _shot(tester, name);
  }

  const bad = '../test/fixtures/bad.sh';
  for (final lang in Lang.values) {
    testWidgets('captures ${lang.name}', (tester) async {
      _lang = lang;
      await run(
          tester, 'analyse-clair', Brightness.light, (s) => s.analyzeFile(bad));
      await run(
          tester, 'analyse-sombre', Brightness.dark, (s) => s.analyzeFile(bad));
      await run(tester, 'problemes', Brightness.light, (s) async {
        await s.analyzeFile(bad);
      }, openIssues: true);
      const badPy = '../test/fixtures/bad.py';
      await run(tester, 'analyse-python', Brightness.light,
          (s) => s.analyzeFile(badPy));
      await run(tester, 'problemes-python', Brightness.dark,
          (s) => s.analyzeFile(badPy),
          openIssues: true);
      await run(tester, 'dossier', Brightness.light,
          (s) => s.analyzeFolder('../test/corpus/scripts'),
          tab: 1);
      await run(tester, 'regles', Brightness.light, (s) async {
        await s.analyzeFile(badPy);
        await s.setRuleEnabled('SC2086', false);
      }, tab: 2);
      await run(tester, 'reglages', Brightness.light, (s) async {}, tab: 3);
      await run(tester, 'aide', Brightness.light, (s) async {}, tab: 4);
      // Comparaison : « avant » = bad.sh, « après » = une version corrigée.
      late AppState compared;
      final tmp = Directory.systemTemp.createTempSync('cs_shot');
      final original = File('../test/fixtures/bad.sh').readAsStringSync();
      final improved = original
          .split('\n')
          .where((l) => !l.contains('eval ') && !l.contains('sudo bash'))
          .join('\n')
          .replaceAll('chmod 777', 'chmod 750')
          .replaceAll(
              'DB_PASSWORD="S3cr3tP@ss"', 'DB_PASSWORD="\${DB_PASSWORD:?}"');
      final deploy = File('${tmp.path}/deploy.sh')..writeAsStringSync(improved);
      await run(tester, 'comparaison', Brightness.light, (s) async {
        compared = s;
        await s.analyzeFile(deploy.path);
      }, after: (t) async {
        final beforeJson = await t.runAsync(() async => renderJson([
              await Engine(runner: const ProcessCommandRunner(), lang: _lang)
                  .analyze(ScriptInfo.fromContent('deploy.sh', original))
            ]));
        final ctx = t.element(find.byType(Scaffold).first);
        showCompareDialog(ctx, compared,
            before: (name: 'avant.json', json: beforeJson!));
        await t.pumpAndSettle();
      });
      await run(tester, 'regle-detail', Brightness.light, (s) async {
        await s.analyzeFile(bad);
      }, after: (t) async {
        await _closeDialogs(t);
        await t.tap(find.descendant(
            of: find.byType(NavigationRail),
            matching: find.byIcon(Icons.rule_outlined)));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).first, 'SEC003');
        await t.pumpAndSettle();
        await t.tap(find.byIcon(Icons.info_outline).first);
        await t.pumpAndSettle();
      });
      await run(tester, 'editeur', Brightness.light, (s) async {
        await s.analyzeFile(bad);
      }, after: (t) async {
        await _closeDialogs(t);
        await _goAnalysis(t);
        await t.pumpAndSettle();
        await t.tap(find.byIcon(Icons.edit_outlined));
        await t.pumpAndSettle();
        final field = find.byType(TextField).first;
        final text = t.widget<TextField>(field).controller!.text;
        await t.enterText(field, text.replaceAll('chmod 777', 'chmod 750'));
        await t.pumpAndSettle();
      });
      await run(tester, 'onglets', Brightness.light, (s) async {
        await s.analyzeFile('../test/fixtures/bad.py');
        await s.analyzeFile(bad);
      }, after: (t) async {
        await _closeDialogs(t);
        // L'écran d'aide du test précédent reste affiché : retour à l'analyse.
        await _goAnalysis(t);
        await t.pumpAndSettle();
        await t.tap(find.byIcon(Icons.search).first);
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).first, 'echo');
        await t.pumpAndSettle();
      });
      // Laisse expirer les minuteurs d'animation (info-bulles, défilement).
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }, skip: _dir == null);
  }
}
