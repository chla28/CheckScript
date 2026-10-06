import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:check_script_gui/app_state.dart';
import 'package:check_script_gui/main.dart';
import 'package:check_script_gui/screens/compare_dialog.dart';
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

/// Laisse s'achever les lectures de fichiers lancées depuis l'interface.
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
    tmp = await Directory.systemTemp.createTemp('cs_edit_');
  });
  tearDown(() => tmp.delete(recursive: true));

  String write(String name, String content) {
    final f = File('${tmp.path}/$name')..writeAsStringSync(content);
    return f.path;
  }

  AppState newState() =>
      AppState(runner: NoTools(), settings: const GuiSettings(lang: Lang.fr));

  group('brouillons (AppState)', () {
    testWidgets('présence, retour au contenu d\'origine, notifications',
        (tester) async {
      final a = write('a.sh', clean);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      var n = 0;
      state.addListener(() => n++);
      expect(state.hasDraft(a), isFalse);
      expect(state.textForEdit(a), clean);
      state.setDraft(a, '$clean# plus\n');
      expect(state.hasDraft(a), isTrue);
      expect(n, 1);
      state.setDraft(a, '$clean# plus encore\n');
      expect(n, 1, reason: 'pas de notification à chaque frappe');
      expect(state.textForEdit(a), '$clean# plus encore\n');
      // Revenir au texte d'origine supprime le brouillon.
      state.setDraft(a, clean);
      expect(state.hasDraft(a), isFalse);
      expect(n, 2);
      state.setDraft(a, 'x');
      state.discardDraft(a);
      expect(state.hasDraft(a), isFalse);
    });

    testWidgets('enregistrement : fichier écrit, .orig, réanalyse',
        (tester) async {
      final a = write('a.sh', clean);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      state.setDraft(a, bad);
      final why = await tester.runAsync(() => state.saveDraft(a));
      expect(why, isNull);
      expect(File(a).readAsStringSync(), bad);
      expect(File('$a.orig').readAsStringSync(), clean);
      expect(state.current!.script.content, bad);
      expect(state.hasDraft(a), isFalse);
      // Deuxième enregistrement : la copie .orig garde la première version.
      state.setDraft(a, clean);
      await tester.runAsync(() => state.saveDraft(a));
      expect(File('$a.orig').readAsStringSync(), clean,
          reason: 'copie faite à la première écriture seulement');
    });

    testWidgets('fins de ligne CRLF conservées', (tester) async {
      final a = write('a.sh', clean.replaceAll('\n', '\r\n'));
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      state.setDraft(a, '$clean# fin\n');
      await tester.runAsync(() => state.saveDraft(a));
      expect(
          File(a).readAsStringSync(), '$clean# fin\n'.replaceAll('\n', '\r\n'));
    });

    testWidgets('fichier modifié sur le disque : enregistrement refusé',
        (tester) async {
      final a = write('a.sh', clean);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      state.setDraft(a, bad);
      File(a).writeAsStringSync('#!/bin/sh\necho autre\n');
      final why = await tester.runAsync(() => state.saveDraft(a));
      expect(why, AppState.staleFix);
      expect(File(a).readAsStringSync(), '#!/bin/sh\necho autre\n');
      expect(state.hasDraft(a), isTrue, reason: 'le brouillon est conservé');
    });

    testWidgets(
        'le brouillon survit au changement d\'onglet, pas à la '
        'fermeture', (tester) async {
      final a = write('a.sh', clean), b = write('b.sh', clean);
      final state = newState();
      await tester.runAsync(() async {
        await state.analyzeFile(a);
        await state.analyzeFile(b);
      });
      state.setDraft(b, bad);
      await tester.runAsync(() => state.selectTab(a));
      expect(state.hasDraft(b), isTrue);
      await tester.runAsync(() => state.selectTab(b));
      expect(state.textForEdit(b), bad);
      await tester.runAsync(() => state.closeTab(b));
      expect(state.hasDraft(b), isFalse);
    });
  });

  group('éditeur (interface)', () {
    Future<AppState> launch(WidgetTester tester, List<String> scripts) async {
      tester.view.physicalSize = const Size(4200, 2700); // 1400 × 900
      addTearDown(tester.view.resetPhysicalSize);
      final state = newState();
      await tester.runAsync(() async {
        for (final s in scripts) {
          await state.analyzeFile(s);
        }
      });
      await tester.pumpWidget(CheckScriptApp(state: state));
      await tester.pumpAndSettle();
      return state;
    }

    Finder editButton() => find.byIcon(Icons.edit_outlined);

    testWidgets('modifier puis enregistrer par le bouton', (tester) async {
      final a = write('a.sh', clean);
      final state = await launch(tester, [a]);
      await tester.tap(editButton());
      await tester.pumpAndSettle();
      final field =
          find.byKey(const ValueKey('editor:/dummy'), skipOffstage: false);
      expect(field, findsNothing);
      final editor = find.byType(TextField).first;
      expect(tester.widget<TextField>(editor).controller!.text, clean);
      await tester.enterText(editor, '$clean# note\n');
      await tester.pumpAndSettle();
      expect(find.text('● Modifications non enregistrées'), findsOneWidget);
      expect(state.hasDraft(a), isTrue);
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await settle(tester);
      expect(File(a).readAsStringSync(), '$clean# note\n');
      expect(state.hasDraft(a), isFalse);
      expect(find.text('● Modifications non enregistrées'), findsNothing);
      // Retour à la vue annotée.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('Ctrl+S enregistre depuis l\'éditeur', (tester) async {
      final a = write('a.sh', clean);
      await launch(tester, [a]);
      await tester.tap(editButton());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '$clean# ctrl-s\n');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);
      expect(File(a).readAsStringSync(), '$clean# ctrl-s\n');
    });

    testWidgets('abandonner : brouillon supprimé, fichier intact',
        (tester) async {
      final a = write('a.sh', clean);
      final state = await launch(tester, [a]);
      await tester.tap(editButton());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'autre chose');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Abandonner'));
      await tester.pumpAndSettle();
      expect(state.hasDraft(a), isFalse);
      expect(File(a).readAsStringSync(), clean);
    });

    testWidgets('onglet modifié : pastille, confirmation à la fermeture',
        (tester) async {
      final a = write('a.sh', clean), b = write('b.sh', clean);
      final state = await launch(tester, [a, b]);
      state.setDraft(b, bad);
      await tester.pumpAndSettle();
      expect(find.text('● b.sh'), findsOneWidget);
      expect(find.text('a.sh'), findsOneWidget);
      // Fermer b : confirmation ; Annuler garde l'onglet et le brouillon.
      await tester.tap(find.byTooltip('Fermer l\'onglet').last);
      await tester.pumpAndSettle();
      expect(find.text('Fermer b.sh sans enregistrer ?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
      await tester.pumpAndSettle();
      expect(state.openTabs, [a, b]);
      expect(state.hasDraft(b), isTrue);
      // Confirmer ferme l'onglet et perd le brouillon.
      await tester.tap(find.byTooltip('Fermer l\'onglet').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fermer sans enregistrer'));
      await settle(tester);
      expect(state.openTabs, [a]);
      expect(state.hasDraft(b), isFalse);
    });

    testWidgets('onglet sans modification : fermeture directe', (tester) async {
      final a = write('a.sh', clean), b = write('b.sh', clean);
      final state = await launch(tester, [a, b]);
      await tester.tap(find.byTooltip('Fermer l\'onglet').last);
      await settle(tester);
      expect(find.textContaining('sans enregistrer ?'), findsNothing);
      expect(state.openTabs, [a]);
    });
  });

  group('détail d\'une règle', () {
    testWidgets('dialogue : exemple, références, occurrences, activation',
        (tester) async {
      tester.view.physicalSize = const Size(4200, 2700);
      addTearDown(tester.view.resetPhysicalSize);
      final a = write('a.sh', bad);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      await tester.pumpWidget(CheckScriptApp(state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byIcon(Icons.rule_outlined)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'SEC003');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(RegExp('^Détail de la règle')).first);
      await tester.pumpAndSettle();
      expect(find.text('Exemple'), findsOneWidget);
      expect(find.text('À éviter'), findsOneWidget);
      expect(find.text('À écrire'), findsOneWidget);
      expect(find.textContaining('CWE-95'), findsWidgets);
      expect(find.textContaining('dans le script affiché (lignes 6)'),
          findsOneWidget);
      expect(find.text('# check-script disable=SEC003'), findsOneWidget);
      expect(find.text('check-script explain SEC003'), findsOneWidget);
      // L'interrupteur désactive la règle (effet à la prochaine analyse).
      expect(state.settings.disabledRules, isEmpty);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(state.settings.disabledRules, contains('SEC003'));
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text('Exemple'), findsNothing);
    });

    testWidgets('règle désactivée par la configuration : interrupteur gelé',
        (tester) async {
      tester.view.physicalSize = const Size(4200, 2700);
      addTearDown(tester.view.resetPhysicalSize);
      final state = AppState(
          runner: NoTools(),
          settings: const GuiSettings(lang: Lang.fr, profile: Profile.legacy));
      await tester.pumpWidget(CheckScriptApp(state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byIcon(Icons.rule_outlined)));
      await tester.pumpAndSettle();
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'MNT005');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(RegExp('^Détail de la règle')).first);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(find.textContaining('désactivée par le profil'), findsWidgets);
    });
  });

  group('comparaison de deux analyses', () {
    Future<PickedReport> report(
        WidgetTester tester, String name, Map<String, String> scripts) async {
      final reports = await tester.runAsync(() async => [
            for (final e in scripts.entries)
              await Engine(runner: NoTools(), lang: Lang.fr)
                  .analyze(ScriptInfo.fromContent(e.key, e.value))
          ]);
      return (name: name, json: renderJson(reports!));
    }

    Future<void> pumpCompare(
        WidgetTester tester, PickedReport before, PickedReport after) async {
      tester.view.physicalSize = const Size(4200, 2700);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(
        home: CompareView(
            state: newState(), initialBefore: before, initialAfter: after),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('amélioration : problèmes corrigés à gauche, note en hausse',
        (tester) async {
      await pumpCompare(
          tester,
          await report(tester, 'avant.json', {'a.sh': bad}),
          await report(tester, 'apres.json', {'a.sh': clean}));
      expect(find.textContaining('Note moyenne'), findsOneWidget);
      expect(find.textContaining('0 nouveaux'), findsOneWidget);
      expect(find.textContaining('corrigés'), findsWidgets);
      expect(find.byIcon(Icons.check_circle_outline), findsWidgets);
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      expect(find.text('Avant — 1,5'), findsOneWidget);
      expect(find.textContaining('Après —'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up), findsWidgets);
    });

    testWidgets('régression : problèmes nouveaux à droite', (tester) async {
      await pumpCompare(
          tester,
          await report(tester, 'avant.json', {'a.sh': clean, 'b.sh': clean}),
          await report(tester, 'apres.json', {'a.sh': bad, 'b.sh': clean}));
      expect(find.byIcon(Icons.add_circle_outline), findsWidgets);
      expect(find.byIcon(Icons.trending_down), findsWidgets);
      // Le script en régression est affiché en premier et sélectionné.
      expect(find.text('a.sh'), findsWidgets);
      expect(find.textContaining('Après —'), findsOneWidget);
      // Les inchangés sont masqués, puis affichables.
      expect(find.textContaining('Inchangés ('), findsOneWidget);
    });

    testWidgets('aucune différence', (tester) async {
      final r = await report(tester, 'x.json', {'a.sh': clean});
      await pumpCompare(tester, r, (name: 'y.json', json: r.json));
      expect(find.text('Aucune différence.'), findsOneWidget);
    });

    testWidgets('rapport invalide : message d\'erreur', (tester) async {
      final good = await report(tester, 'x.json', {'a.sh': clean});
      await pumpCompare(
          tester, (name: 'cassé.json', json: 'pas du json'), good);
      expect(find.textContaining('invalid JSON'), findsOneWidget);
    });

    testWidgets('sans « avant » : invitation à en choisir un', (tester) async {
      tester.view.physicalSize = const Size(4200, 2700);
      addTearDown(tester.view.resetPhysicalSize);
      await tester
          .pumpWidget(MaterialApp(home: CompareView(state: newState())));
      await tester.pumpAndSettle();
      expect(find.textContaining('Choisissez le rapport'), findsOneWidget);
    });

    testWidgets('bouton « Comparer… » de la barre d\'outils', (tester) async {
      tester.view.physicalSize = const Size(4200, 2700);
      addTearDown(tester.view.resetPhysicalSize);
      final a = write('a.sh', bad);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      await tester.pumpWidget(CheckScriptApp(state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comparer…'));
      await tester.pumpAndSettle();
      expect(find.text('Comparer deux analyses'), findsOneWidget);
      expect(find.text('Analyse affichée'), findsOneWidget);
      await tester.tap(find.byTooltip('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text('Comparer deux analyses'), findsNothing);
    });
  });
}
