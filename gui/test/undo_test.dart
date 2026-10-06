import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:check_script_gui/app_state.dart';
import 'package:check_script_gui/main.dart';
import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NoTools implements CommandRunner {
  @override
  Future<CommandResult?> run(String executable, List<String> args,
          {String? stdin, CancelToken? cancel}) async =>
      null;
}

/// Trois défauts à corriger automatiquement : backticks, read, which.
const fixable =
    '#!/bin/bash\nset -u\nd=`date`\nread name\nwhich ls\necho "\$d \$name"\n';

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
    tmp = await Directory.systemTemp.createTemp('cs_undo_');
  });
  tearDown(() => tmp.delete(recursive: true));

  String write(String name, String content) {
    final f = File('${tmp.path}/$name')..writeAsStringSync(content);
    return f.path;
  }

  AppState newState() =>
      AppState(runner: NoTools(), settings: const GuiSettings(lang: Lang.fr));

  /// Première correction automatique disponible du script affiché.
  Finding firstFixable(AppState s) =>
      s.current!.findings.firstWhere((f) => f.edits.isNotEmpty);

  group('historique et annulation (AppState)', () {
    testWidgets('une correction est enregistrée puis annulée', (tester) async {
      final a = write('a.sh', fixable);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      expect(state.fixHistory, isEmpty);
      expect(state.lastFixOf(a), isNull);
      final f = firstFixable(state);
      expect(await tester.runAsync(() => state.applyFindingFix(f)), isNull);
      final fixed = File(a).readAsStringSync();
      expect(fixed, isNot(fixable));
      final r = state.lastFixOf(a)!;
      expect(r.kind, FixKind.fix);
      expect(r.detail, f.ruleId);
      expect(r.before, fixable);
      expect(r.after, fixed);

      expect(await tester.runAsync(() => state.undoFix(r)), isNull);
      expect(File(a).readAsStringSync(), fixable);
      expect(state.fixHistory, isEmpty);
      // Le script est réanalysé : le problème corrigé est revenu.
      expect(state.current!.script.content, fixable);
      expect(state.current!.findings.any((x) => x.ruleId == f.ruleId), isTrue);
    });

    testWidgets('fins de ligne CRLF : octets d\'origine restitués',
        (tester) async {
      final original = fixable.replaceAll('\n', '\r\n');
      final a = write('a.sh', original);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      await tester.runAsync(() => state.applyFindingFix(firstFixable(state)));
      expect(File(a).readAsStringSync(), contains('\r\n'));
      await tester.runAsync(() => state.undoFix(state.lastFixOf(a)!));
      expect(File(a).readAsStringSync(), original);
    });

    testWidgets('seule la plus récente modification d\'un script s\'annule',
        (tester) async {
      final a = write('a.sh', fixable);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      await tester.runAsync(() => state.applyFindingFix(firstFixable(state)));
      final first = state.lastFixOf(a)!;
      await tester.runAsync(() => state.applyFindingFix(firstFixable(state)));
      final second = state.lastFixOf(a)!;
      expect(second, isNot(same(first)));
      expect(state.fixHistory, hasLength(2));
      // La plus ancienne ne s'annule pas avant la plus récente.
      expect(
          await tester.runAsync(() => state.undoFix(first)), AppState.staleFix);
      expect(await tester.runAsync(() => state.undoFix(second)), isNull);
      expect(await tester.runAsync(() => state.undoFix(first)), isNull);
      expect(File(a).readAsStringSync(), fixable);
      expect(state.fixHistory, isEmpty);
    });

    testWidgets('fichier modifié depuis : annulation refusée', (tester) async {
      final a = write('a.sh', fixable);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      await tester.runAsync(() => state.applyFindingFix(firstFixable(state)));
      final r = state.lastFixOf(a)!;
      File(a).writeAsStringSync('#!/bin/sh\necho changé ailleurs\n');
      expect(await tester.runAsync(() => state.undoFix(r)), AppState.staleFix);
      expect(File(a).readAsStringSync(), '#!/bin/sh\necho changé ailleurs\n');
      expect(state.fixHistory, [r], reason: 'l\'entrée est conservée');
    });

    testWidgets('restauration de l\'original (.orig), elle-même annulable',
        (tester) async {
      final a = write('a.sh', fixable);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      expect(state.hasOriginalBackup(a), isFalse);
      await tester.runAsync(() => state.applyFindingFix(firstFixable(state)));
      await tester.runAsync(() => state.applyFindingFix(firstFixable(state)));
      expect(state.hasOriginalBackup(a), isTrue);
      final afterTwo = File(a).readAsStringSync();

      expect(await tester.runAsync(() => state.restoreOriginal(a)), isNull);
      expect(File(a).readAsStringSync(), fixable);
      final restore = state.lastFixOf(a)!;
      expect(restore.kind, FixKind.restore);
      expect(state.current!.script.content, fixable);
      // Annuler la restauration remet les deux corrections.
      expect(await tester.runAsync(() => state.undoFix(restore)), isNull);
      expect(File(a).readAsStringSync(), afterTwo);
    });

    testWidgets('restauration sans copie .orig : erreur, rien d\'écrit',
        (tester) async {
      final a = write('a.sh', fixable);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      final why = await tester.runAsync(() => state.restoreOriginal(a));
      expect(why, isNotNull);
      expect(why, isNot(AppState.staleFix));
      expect(File(a).readAsStringSync(), fixable);
      expect(state.fixHistory, isEmpty);
    });

    testWidgets('une édition manuelle enregistrée est annulable',
        (tester) async {
      final a = write('a.sh', fixable);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      state.setDraft(a, '$fixable# note\n');
      await tester.runAsync(() => state.saveDraft(a));
      final r = state.lastFixOf(a)!;
      expect(r.kind, FixKind.edit);
      await tester.runAsync(() => state.undoFix(r));
      expect(File(a).readAsStringSync(), fixable);
    });

    testWidgets(
        'annulation sur un onglet non affiché : réanalysé à la '
        'sélection', (tester) async {
      final a = write('a.sh', fixable), b = write('b.sh', '#!/bin/sh\n:\n');
      final state = newState();
      await tester.runAsync(() async {
        await state.analyzeFile(a);
        await state.applyFindingFix(firstFixable(state));
        await state.analyzeFile(b);
      });
      final r = state.lastFixOf(a)!;
      expect(await tester.runAsync(() => state.undoFix(r)), isNull);
      expect(state.activeTab, b, reason: 'l\'onglet affiché ne change pas');
      await tester.runAsync(() => state.selectTab(a));
      expect(state.current!.script.content, fixable);
    });

    testWidgets('historique borné', (tester) async {
      final a = write('a.sh', fixable);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      await tester.runAsync(() async {
        for (var i = 0; i < AppState.maxFixHistory + 5; i++) {
          state.setDraft(a, '$fixable# $i\n');
          await state.saveDraft(a);
        }
      });
      expect(state.fixHistory, hasLength(AppState.maxFixHistory));
    });

    testWidgets('rien n\'est enregistré si le contenu ne change pas',
        (tester) async {
      final a = write('a.sh', fixable);
      final state = newState();
      await tester.runAsync(() => state.analyzeFile(a));
      await tester.runAsync(() => state.restoreOriginal(a));
      expect(state.fixHistory, isEmpty);
    });
  });

  group('annulation (interface)', () {
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

    Finder undoButton() => find.widgetWithText(OutlinedButton, 'Annuler');

    testWidgets('le bouton « Annuler » suit la dernière modification',
        (tester) async {
      final a = write('a.sh', fixable);
      final state = await launch(tester, [a]);
      expect(tester.widget<OutlinedButton>(undoButton()).onPressed, isNull);
      await tester.runAsync(() => state.applyFindingFix(firstFixable(state)));
      await settle(tester);
      expect(tester.widget<OutlinedButton>(undoButton()).onPressed, isNotNull);
      expect(find.byTooltip(RegExp('^Annuler la dernière modification')),
          findsOneWidget);
      final fixed = File(a).readAsStringSync();
      expect(fixed, isNot(fixable));

      await tester.tap(undoButton());
      await settle(tester);
      expect(File(a).readAsStringSync(), fixable);
      expect(find.textContaining('Annulé : Correction'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(undoButton()).onPressed, isNull);
    });

    testWidgets('historique : liste, annulation de la plus récente seulement',
        (tester) async {
      final a = write('a.sh', fixable);
      final state = await launch(tester, [a]);
      await tester.runAsync(() async {
        await state.applyFindingFix(firstFixable(state));
        await state.applyFindingFix(firstFixable(state));
      });
      await settle(tester);
      await tester.tap(find.text('Historique…'));
      await tester.pumpAndSettle();
      expect(find.text('Modifications du script'), findsOneWidget);
      expect(find.textContaining('a.sh — Correction'), findsNWidgets(2));
      final buttons = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Annuler'));
      expect(buttons, findsNWidgets(2));
      // Ligne du haut = la plus récente : seule annulable.
      expect(tester.widget<TextButton>(buttons.at(0)).onPressed, isNotNull);
      expect(tester.widget<TextButton>(buttons.at(1)).onPressed, isNull);
      await tester.tap(buttons.at(0));
      await settle(tester);
      expect(state.fixHistory, hasLength(1));
      expect(find.textContaining('a.sh — Correction'), findsOneWidget);
    });

    testWidgets(
        'historique vide, puis restauration de l\'original avec '
        'confirmation', (tester) async {
      final a = write('a.sh', fixable);
      final state = await launch(tester, [a]);
      await tester.tap(find.text('Historique…'));
      await tester.pumpAndSettle();
      expect(find.text('Aucune modification depuis le lancement.'),
          findsOneWidget);
      // Sans copie .orig : bouton grisé.
      final restore = find.widgetWithText(TextButton, 'Restaurer l\'original');
      expect(tester.widget<TextButton>(restore).onPressed, isNull);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await state.applyFindingFix(firstFixable(state));
        await state.applyFindingFix(firstFixable(state));
      });
      await settle(tester);
      await tester.tap(find.text('Historique…'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(restore).onPressed, isNotNull);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(find.text('Restaurer l\'original de a.sh ?'), findsOneWidget);
      // Annuler la confirmation : rien ne change.
      await tester.tap(find.widgetWithText(TextButton, 'Annuler').last);
      await tester.pumpAndSettle();
      expect(File(a).readAsStringSync(), isNot(fixable));
      // Confirmer : le fichier retrouve l'original.
      await tester.tap(restore);
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(FilledButton, 'Restaurer l\'original'));
      await settle(tester);
      expect(File(a).readAsStringSync(), fixable);
      expect(find.textContaining('Restauration de l\'original'), findsWidgets);
    });
  });
}
