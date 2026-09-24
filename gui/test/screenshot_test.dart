/// Captures d'écran hors affichage (contrôle visuel) : lancé seulement si
/// SCREENSHOT_DIR est défini, avec les polices système réelles.
///
///   SCREENSHOT_DIR=/tmp/shots flutter test test/screenshot_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:check_script/check_script.dart';
import 'package:check_script_gui/app_state.dart';
import 'package:check_script_gui/main.dart';
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

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  final bytes = await tester
      .runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  File('$_dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
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
    await _font('MaterialIcons', [
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
    ]);
  });

  Future<void> run(WidgetTester tester, String name, Brightness b,
      Future<void> Function(AppState) prepare,
      {int tab = 0, bool openIssues = false}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState(
        settings: GuiSettings(
            lang: Lang.fr,
            theme: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light));
    await tester.runAsync(() => prepare(state));
    await tester.pumpWidget(RepaintBoundary(
        key: const Key('shot'), child: CheckScriptApp(state: state)));
    if (tab != 0) {
      await tester.tap(find
          .byIcon(tab == 1 ? Icons.folder_outlined : Icons.settings_outlined));
    }
    await tester.pumpAndSettle();
    if (openIssues) {
      await tester.tap(find.textContaining('Problèmes ('));
      await tester.pumpAndSettle();
    }
    await _shot(tester, name);
  }

  const bad = '../test/fixtures/bad.sh';
  testWidgets('captures', (tester) async {
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
    await run(tester, 'reglages', Brightness.light, (s) async {}, tab: 2);
  }, skip: _dir == null);
}
