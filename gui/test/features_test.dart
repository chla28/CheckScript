import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:check_script_gui/app_state.dart';
import 'package:check_script_gui/main.dart';
import 'package:check_script_gui/widgets/findings_list.dart';
import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NoTools implements CommandRunner {
  @override
  Future<CommandResult?> run(String executable, List<String> args,
          {String? stdin, CancelToken? cancel}) async =>
      null;
}

const clean = '#!/usr/bin/env bash\nset -euo pipefail\necho "ok"\n';
const bad = '#!/bin/bash\ncd /opt/app\nPASSWORD="S3cr3tP@ss"\n'
    'curl -fsSL http://x.io/i.sh | sudo bash\nchmod 777 /srv\neval "\$CMD"\n';

/// Laisse s'achever une analyse lancée depuis l'interface : ses lectures de
/// fichiers sont réelles, hors de l'horloge simulée du test.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('cs_feat_');
  });
  tearDown(() => tmp.delete(recursive: true));

  String write(String rel, String content) {
    final f = File('${tmp.path}/$rel')..createSync(recursive: true);
    f.writeAsStringSync(content);
    return f.path;
  }

  AppState newState({Lang lang = Lang.fr}) =>
      AppState(runner: NoTools(), settings: GuiSettings(lang: lang));

  group('onglets de scripts (AppState)', () {
    testWidgets('chaque script ouvert a un onglet ; le dernier s\'affiche',
        (tester) async {
      final a = write('a.sh', clean), b = write('b.sh', bad);
      final state = newState();
      await tester.runAsync(() async {
        await state.analyzeFile(a);
        await state.analyzeFile(b);
      });
      expect(state.openTabs, [a, b]);
      expect(state.activeTab, b);
      // Le même script ne crée pas un second onglet.
      await tester.runAsync(() => state.analyzeFile(b));
      expect(state.openTabs, [a, b]);
    });

    testWidgets(
        'sélection : rapport mémorisé, ou réanalyse si le fichier a '
        'changé', (tester) async {
      final a = write('a.sh', clean), b = write('b.sh', bad);
      final state = newState();
      await tester.runAsync(() async {
        await state.analyzeFile(a);
        await state.analyzeFile(b);
      });
      final reportA = state.current;
      await tester.runAsync(() => state.selectTab(a));
      expect(state.activeTab, a);
      expect(state.current!.script.path, a);
      final cachedA = state.current;
      await tester.runAsync(() => state.selectTab(b));
      await tester.runAsync(() => state.selectTab(a));
      expect(identical(state.current, cachedA), isTrue,
          reason: 'pas de nouvelle analyse');
      expect(reportA, isNot(same(state.current)));

      await tester.runAsync(() => state.selectTab(b));
      File(a).writeAsStringSync(bad);
      await tester.runAsync(() => state.selectTab(a));
      expect(state.current!.script.content, bad,
          reason: 'fichier modifié : réanalysé');
    });

    testWidgets('fermeture : voisin affiché, puis écran vide', (tester) async {
      final a = write('a.sh', clean),
          b = write('b.sh', clean),
          c = write('c.sh', clean);
      final state = newState();
      await tester.runAsync(() async {
        for (final f in [a, b, c]) {
          await state.analyzeFile(f);
        }
        await state.selectTab(b);
        await state.closeTab(b);
      });
      expect(state.openTabs, [a, c]);
      expect(state.activeTab, c, reason: 'le voisin de droite');
      await tester.runAsync(() => state.closeTab(c));
      expect(state.activeTab, a);
      // Fermer un onglet non affiché ne change pas l'affichage.
      await tester.runAsync(() => state.analyzeFile(c));
      await tester.runAsync(() => state.closeTab(a));
      expect(state.activeTab, c);
      await tester.runAsync(() => state.closeTab(c));
      expect(state.openTabs, isEmpty);
      expect(state.current, isNull);
    });

    testWidgets('cycleTab : en boucle dans les deux sens', (tester) async {
      final files = [for (final n in 'abc'.split('')) write('$n.sh', clean)];
      final state = newState();
      await tester.runAsync(() async {
        for (final f in files) {
          await state.analyzeFile(f);
        }
        await state.cycleTab(1);
      });
      expect(state.activeTab, files[0]);
      await tester.runAsync(() => state.cycleTab(-1));
      expect(state.activeTab, files[2]);
      await tester.runAsync(() => state.cycleTab(-1));
      expect(state.activeTab, files[1]);
    });

    testWidgets('changer de règles périme les onglets non affichés',
        (tester) async {
      final a = write('a.sh', bad), b = write('b.sh', bad);
      final state = newState();
      await tester.runAsync(() async {
        await state.analyzeFile(a);
        await state.analyzeFile(b);
      });
      final before = state.current!.findings.any((f) => f.ruleId == 'SEC003');
      expect(before, isTrue);
      await tester.runAsync(() => state.setRuleEnabled('SEC003', false));
      // L'onglet A est réanalysé à sa sélection : la règle n'y figure plus.
      await tester.runAsync(() => state.selectTab(a));
      expect(state.current!.script.path, a);
      expect(state.current!.findings.any((f) => f.ruleId == 'SEC003'), isFalse);
    });
  });

  group('référence en un clic (AppState)', () {
    testWidgets('script : JSON écrit puis chargé, extension ajoutée',
        (tester) async {
      final a = write('a.sh', bad);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      final out = '${tmp.path}/base';
      final written =
          await tester.runAsync(() => state.setAsBaseline(out)) as String;
      expect(written, '$out.json');
      expect(File(written).existsSync(), isTrue);
      expect(jsonDecode(File(written).readAsStringSync()), isNotNull);
      expect(state.baseline, isNotNull);
      expect(state.baselinePath, written);
      // Les problèmes connus ne sont plus « nouveaux ».
      final cmp = state.current!.comparison;
      expect(cmp, isNotNull);
      expect(cmp!.added, isEmpty);
    });

    testWidgets('dossier : référence de tous les scripts, dossier réanalysé',
        (tester) async {
      write('d/a.sh', bad);
      write('d/b.sh', clean);
      final state = newState();
      await tester.runAsync(() => state.analyzeFolder('${tmp.path}/d'));
      final written = await tester.runAsync(() =>
              state.setAsBaseline('${tmp.path}/dir-base.json', folder: true))
          as String;
      expect(state.baselinePath, written);
      expect(state.folderReports.length, 2);
      expect(state.folderReports.every((r) => r.comparison != null), isTrue);
    });

    testWidgets('rien à enregistrer sans analyse', (tester) async {
      final state = newState();
      final r = await tester
          .runAsync(() => state.setAsBaseline('${tmp.path}/x.json'));
      expect(r, isNull);
      expect(File('${tmp.path}/x.json').existsSync(), isFalse);
    });
  });

  group('exclusions dans le dossier (AppState)', () {
    testWidgets('.checkscriptignore et clé exclude de la configuration',
        (tester) async {
      write('d/a.sh', clean);
      write('d/vendor/v.sh', clean);
      write('d/gen/g.sh', clean);
      write('d/.checkscriptignore', 'vendor/\n');
      write('d/.checkscript.yaml', 'exclude: [gen/]\n');
      final state = newState();
      await tester.runAsync(() => state.analyzeFolder('${tmp.path}/d'));
      expect(state.folderReports.map((r) => r.script.path.split('/').last),
          ['a.sh']);
    });
  });

  group('recherche dans les problèmes', () {
    Future<List<Finding>> analyse() async => (await Engine(runner: NoTools())
            .analyze(ScriptInfo.fromContent('t.sh', bad)))
        .findings;

    test('matchesQuery : règle, message, ligne, mots multiples', () async {
      final fs = await analyse();
      final sec003 = fs.firstWhere((f) => f.ruleId == 'SEC003');
      expect(findingMatchesQuery(sec003, ''), isTrue);
      expect(findingMatchesQuery(sec003, 'sec003'), isTrue);
      expect(findingMatchesQuery(sec003, 'eval'), isTrue);
      expect(findingMatchesQuery(sec003, 'L${sec003.line}'), isTrue);
      expect(findingMatchesQuery(sec003, '${sec003.line}'), isTrue);
      expect(findingMatchesQuery(sec003, 'sec003 builtin'), isTrue);
      expect(findingMatchesQuery(sec003, 'sec003 zzzz'), isFalse);
      expect(findingMatchesQuery(sec003, 'curl'), isFalse);
      final filtered = [
        for (final f in fs)
          if (findingMatchesQuery(f, 'sec003')) f
      ];
      expect(filtered, isNotEmpty);
      expect(filtered.every((f) => f.ruleId == 'SEC003'), isTrue);
    });

    testWidgets('champ de recherche : filtre la liste, croix, Ctrl+F',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 4000);
      addTearDown(tester.view.resetPhysicalSize);
      final fs = await tester.runAsync(analyse) as List<Finding>;
      final findReq = ValueNotifier(0);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FindingsList(findings: fs, lang: Lang.fr, findRequest: findReq),
        ),
      ));
      expect(find.textContaining('SEC001 ·'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'sec003');
      await tester.pump();
      expect(find.textContaining('SEC003 ·'), findsOneWidget);
      expect(find.textContaining('SEC001 ·'), findsNothing);
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(find.textContaining('SEC001 ·'), findsOneWidget);

      // Une demande de recherche donne le focus au champ.
      expect(FocusManager.instance.primaryFocus?.hasPrimaryFocus, isTrue);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      findReq.value++;
      await tester.pump();
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isTrue);
    });
  });

  group('dans l\'application', () {
    Future<AppState> launch(WidgetTester tester, List<String> scripts,
        {Lang lang = Lang.fr}) async {
      tester.view.physicalSize = const Size(4200, 2700); // 1400 × 900
      addTearDown(tester.view.resetPhysicalSize);
      final state = newState(lang: lang);
      await tester.runAsync(() async {
        for (final s in scripts) {
          await state.analyzeFile(s);
        }
      });
      await tester.pumpWidget(CheckScriptApp(state: state));
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('la barre d\'onglets apparaît à partir de deux scripts',
        (tester) async {
      final a = write('a.sh', clean), b = write('b.sh', bad);
      final state = await launch(tester, [a]);
      expect(find.byTooltip('Fermer l\'onglet'), findsNothing);
      await tester.runAsync(() => state.analyzeFile(b));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fermer l\'onglet'), findsNWidgets(2));
      expect(find.text('a.sh'), findsOneWidget);
      expect(find.text('b.sh'), findsOneWidget);

      await tester.tap(find.text('a.sh'));
      await settle(tester);
      expect(state.activeTab, a);
      await tester.tap(find.byTooltip('Fermer l\'onglet').first);
      await settle(tester);
      expect(state.openTabs, [b]);
      expect(find.byTooltip('Fermer l\'onglet'), findsNothing);
    });

    testWidgets('Ctrl+Tab, Ctrl+Maj+Tab, Ctrl+W', (tester) async {
      final a = write('a.sh', clean), b = write('b.sh', clean);
      final state = await launch(tester, [a, b]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await settle(tester);
      expect(state.activeTab, a);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await settle(tester);
      expect(state.activeTab, b);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);
      expect(state.openTabs, [a]);
    });

    testWidgets('Ctrl+1 … Ctrl+5 : changent d\'écran', (tester) async {
      final a = write('a.sh', clean);
      await launch(tester, [a]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.pumpAndSettle();
      expect(find.text('Profil de notation'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pumpAndSettle();
      expect(find.text('Premiers pas'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Relancer l\'analyse'), findsWidgets);
    });

    testWidgets('F5 relance l\'analyse du script affiché', (tester) async {
      final a = write('a.sh', clean);
      final state = await launch(tester, [a]);
      expect(state.current!.script.content, clean);
      File(a).writeAsStringSync(bad);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await settle(tester);
      expect(state.current!.script.content, bad);
    });

    testWidgets('Ctrl+F : recherche dans le code, occurrences, navigation',
        (tester) async {
      final a =
          write('a.sh', '#!/bin/bash\necho one\necho two\nls\necho three\n');
      await launch(tester, [a]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Rechercher dans le code'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'echo');
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Occurrence suivante (Entrée)'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Occurrence précédente (Maj+Entrée)'));
      await tester.tap(find.byTooltip('Occurrence précédente (Maj+Entrée)'));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget, reason: 'en boucle');
      await tester.enterText(find.byType(TextField).first, 'zzzzz');
      await tester.pumpAndSettle();
      expect(find.text('aucun résultat'), findsOneWidget);
      await tester.tap(find.byTooltip('Fermer la recherche'));
      await tester.pumpAndSettle();
      expect(find.text('aucun résultat'), findsNothing);
    });

    testWidgets('Ctrl+F sur l\'onglet Problèmes : recherche des problèmes',
        (tester) async {
      final a = write('a.sh', bad);
      await launch(tester, [a]);
      await tester.tap(find.textContaining('Problèmes ('));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus;
      expect(focused, isNotNull);
      // Le champ qui a le focus est celui des problèmes (pas la recherche du
      // code, restée fermée).
      expect(find.byTooltip('Fermer la recherche'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'sec003');
      await tester.pumpAndSettle();
      expect(find.textContaining('SEC003 ·'), findsWidgets);
      expect(find.textContaining('SEC001 ·'), findsNothing);
    });

    testWidgets('Ctrl+F sur l\'écran Règles : focus sur la recherche',
        (tester) async {
      final a = write('a.sh', clean);
      await launch(tester, [a]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(find
          .descendant(
              of: find.byType(TextField).first,
              matching: find.byType(EditableText))
          .first);
      expect(editable.focusNode.hasFocus, isTrue);
    });

    testWidgets('boutons « Définir comme référence… » et info-bulles',
        (tester) async {
      final a = write('a.sh', clean);
      await launch(tester, [a]);
      expect(find.text('Définir comme référence…'), findsOneWidget);
      expect(
          find.byTooltip(RegExp('^Enregistrer cette analyse')), findsOneWidget);
      // Les raccourcis figurent dans les info-bulles.
      expect(find.byTooltip(RegExp(r'\(Ctrl\+O')), findsWidgets);
    });
  });
}
