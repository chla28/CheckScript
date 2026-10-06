import 'package:check_script/check_script.dart';
import 'package:check_script_gui/app_state.dart';
import 'package:check_script_gui/help/help_content.dart';
import 'package:check_script_gui/help/help_screen.dart';
import 'package:check_script_gui/help/tips.dart';
import 'package:check_script_gui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NoTools implements CommandRunner {
  @override
  Future<CommandResult?> run(String executable, List<String> args,
          {String? stdin, CancelToken? cancel}) async =>
      null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('contenu de l\'aide', () {
    test('une page par sujet, dans l\'ordre, dans les deux langues', () {
      for (final lang in Lang.values) {
        final pages = helpPages(lang);
        expect(pages.map((p) => p.topic), HelpTopic.values);
        expect(pages.map((p) => p.title).toSet().length, pages.length,
            reason: 'titres uniques ($lang)');
        for (final p in pages) {
          expect(p.title, isNotEmpty);
          expect(p.quick, isNotEmpty);
          expect(p.blocks, isNotEmpty, reason: p.title);
        }
      }
    });

    test('mêmes pages et mêmes blocs en français et en anglais', () {
      final fr = helpPages(Lang.fr);
      final en = helpPages(Lang.en);
      for (var i = 0; i < fr.length; i++) {
        expect(en[i].blocks.length, fr[i].blocks.length, reason: fr[i].title);
        for (var j = 0; j < fr[i].blocks.length; j++) {
          expect(en[i].blocks[j].runtimeType, fr[i].blocks[j].runtimeType);
          if (fr[i].blocks[j] case HelpBullets(:final items)) {
            expect((en[i].blocks[j] as HelpBullets).items.length, items.length,
                reason: fr[i].title);
          }
        }
        // Les pages ne sont pas des copies l'une de l'autre.
        expect(en[i].quick == fr[i].quick, isFalse,
            reason: 'résumé traduit : ${fr[i].title}');
      }
    });

    test('mise en forme équilibrée (** et `)', () {
      for (final lang in Lang.values) {
        for (final p in helpPages(lang)) {
          final texts = [
            p.quick,
            for (final b in p.blocks)
              switch (b) {
                HelpPara(:final text) => text,
                HelpBullets(:final items) => items.join('\n'),
                _ => '',
              }
          ];
          for (final t in texts) {
            expect('**'.allMatches(t).length.isEven, isTrue, reason: t);
            expect('`'.allMatches(t).length.isEven, isTrue, reason: t);
          }
        }
      }
    });

    test('numéro de version et licence à jour dans « À propos »', () {
      final about =
          helpPages(Lang.en).firstWhere((p) => p.topic == HelpTopic.about);
      expect(about.searchText, contains(appVersion));
      expect(about.searchText, contains('lgpl'));
    });
  });

  group('info-bulles', () {
    test('tout est renseigné dans les deux langues', () {
      for (final lang in Lang.values) {
        final tp = Tips(lang);
        final all = <String>[
          tp.navAnalysis,
          tp.navFolder,
          tp.navRules,
          tp.navSettings,
          tp.navHelp,
          tp.recentMenu,
          tp.openScript,
          tp.openFolder,
          tp.reanalyze,
          tp.fix,
          tp.export,
          tp.openInEditor,
          tp.loadBaseline,
          tp.baselineChip,
          tp.cancelAnalysis,
          tp.globalScore,
          tp.grade,
          tp.delta,
          tp.radar,
          tp.categoryColumn,
          tp.scoreColumn,
          tp.totalColumn,
          tp.explainTitle,
          tp.pointsColumn,
          tp.gainColumn,
          tp.suppressed,
          tp.categoryChip,
          tp.severityChip,
          tp.sortCategory,
          tp.sortQuickWin,
          tp.selectAllFixable,
          tp.fixSelection,
          tp.fixCheckbox,
          tp.lineBadge,
          tp.documentation,
          tp.copyCode,
          tp.applyThisFix,
          tp.applyRuleFixes,
          tp.reportFalsePositive,
          tp.doNotReport('SEC001'),
          tp.codeFont,
          tp.codeMargin,
          tp.folderSort,
          tp.trend,
          tp.history,
          tp.searchRules,
          tp.enableAll,
          tp.disableOther,
          tp.ruleCheckbox,
          tp.lockedRule,
          tp.languageFilter,
          tp.toolFilter,
          tp.categoryFilter,
          tp.language,
          tp.theme,
          tp.codeFontField,
          tp.codeFontSize,
          tp.profile,
          tp.contexts,
          tp.profileStrict,
          tp.profileStandard,
          tp.profileLegacy,
          tp.ruffProjectConfig,
          tp.pythonTarget,
          tp.useCache,
          tp.watchFile,
          tp.editorCommand,
          tp.followSource,
          tp.detect,
          tp.importConfig,
          tp.exportConfig,
          tp.removeConfig,
          tp.tabSummary,
          tp.tabIssues,
          tp.searchIssues,
          tp.searchCode,
          tp.setBaseline,
          tp.tab,
          tp.compare,
          tp.pickReport,
          tp.useBaseline,
          tp.copyDiff,
          tp.editScript,
          tp.saveScript,
          tp.discardChanges,
          tp.editor,
          tp.ruleDetails,
          for (final s in Severity.values) tp.severity(s),
          for (final c in ExecContext.values) tp.context(c),
          for (final t in [
            'shellcheck',
            'shfmt',
            'bashate',
            'checkbashisms',
            'ruff',
            'bandit',
            'semgrep',
            'mypy',
            'radon',
            'vermin',
            'pydeps',
            'pip-audit',
            'pylint',
            'pyright',
            'gitleaks',
            'trufflehog',
            'syntax',
            'hadolint',
            'actionlint',
            'zizmor'
          ])
            tp.tool(t),
        ];
        for (final t in all) {
          expect(t.trim(), isNotEmpty);
        }
        // Un outil inconnu n'a pas de texte inventé : son nom.
        expect(tp.tool('inconnu'), 'inconnu');
      }
      expect(Tips(Lang.fr).openScript, isNot(Tips(Lang.en).openScript));
    });

    test('tip() n\'ajoute pas d\'info-bulle sans message', () {
      const child = SizedBox();
      expect(tip(null, child), same(child));
      expect(tip('', child), same(child));
      expect(tip('aide', child), isA<Tooltip>());
    });
  });

  group('écran d\'aide', () {
    test('filtre : titre, résumé et corps', () {
      final pages = helpPages(Lang.fr);
      expect(filterHelpPages(pages, ''), pages);
      expect(filterHelpPages(pages, 'Sarif').map((p) => p.topic),
          contains(HelpTopic.export));
      expect(filterHelpPages(pages, 'xyzzy-introuvable'), isEmpty);
      // Insensible à la casse et aux espaces autour.
      expect(filterHelpPages(pages, '  BASELINE '), isNotEmpty);
    });

    testWidgets('liste des sujets, choix d\'un sujet, recherche',
        (tester) async {
      tester.view.physicalSize = const Size(2400, 1800);
      addTearDown(tester.view.resetPhysicalSize);
      final topic = ValueNotifier(HelpTopic.start);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: HelpScreen(lang: Lang.fr, topic: topic))));
      expect(find.text('Premiers pas'), findsWidgets);
      await tester.tap(find.text('Comprendre la note').first);
      await tester.pumpAndSettle();
      expect(topic.value, HelpTopic.score);
      expect(find.textContaining('plafonnée'), findsWidgets);

      await tester.enterText(find.byType(TextField), 'sarif');
      await tester.pumpAndSettle();
      expect(find.text('Exports'), findsWidgets);
      expect(find.text('Réglages'), findsNothing);

      await tester.enterText(find.byType(TextField), 'xyzzy-introuvable');
      await tester.pumpAndSettle();
      expect(find.text('Aucun sujet ne correspond.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.text('Aucun sujet ne correspond.'), findsNothing);
    });

    testWidgets('fenêtre étroite : aucune erreur de mise en page',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1500); // 400 × 500 px
      addTearDown(tester.view.resetPhysicalSize);
      for (final lang in Lang.values) {
        for (final t in HelpTopic.values) {
          await tester.pumpWidget(MaterialApp(
              home: Scaffold(
                  body: HelpScreen(lang: lang, topic: ValueNotifier(t)))));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$lang $t');
        }
      }
    });

    testWidgets('bouton « ? » : résumé puis aide complète', (tester) async {
      HelpTopic? opened;
      await tester.pumpWidget(MaterialApp(
        home: HelpScope(
          openHelp: (t) => opened = t,
          child:
              const Scaffold(body: HelpButton(HelpTopic.rules, lang: Lang.fr)),
        ),
      ));
      await tester.tap(find.byIcon(Icons.help_outline));
      await tester.pumpAndSettle();
      expect(find.text('Écran Règles'), findsOneWidget);
      expect(find.textContaining('prochaine analyse'), findsOneWidget);
      await tester.tap(find.text('Aide complète'));
      await tester.pumpAndSettle();
      expect(opened, HelpTopic.rules);
      expect(find.text('Écran Règles'), findsNothing);
    });

    testWidgets('bouton « ? » : absent hors de l\'application', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: HelpButton(HelpTopic.rules, lang: Lang.fr))));
      expect(find.byIcon(Icons.help_outline), findsNothing);
    });
  });

  group('dans l\'application', () {
    Future<void> launch(WidgetTester tester, Lang lang) async {
      tester.view.physicalSize = const Size(4200, 2700); // 1400 × 900
      addTearDown(tester.view.resetPhysicalSize);
      final state =
          AppState(runner: NoTools(), settings: GuiSettings(lang: lang));
      await tester.pumpWidget(CheckScriptApp(state: state));
    }

    testWidgets('entrée « Aide » dans la navigation', (tester) async {
      await launch(tester, Lang.fr);
      await tester.tap(find.text('Aide'));
      await tester.pumpAndSettle();
      expect(find.text('Premiers pas'), findsWidgets);
      expect(find.text('Les écrans'), findsOneWidget);
    });

    testWidgets('page d\'aide alignée en haut de l\'écran', (tester) async {
      await launch(tester, Lang.fr);
      await tester.tap(find.text('Aide'));
      await tester.pumpAndSettle();
      expect(
          tester.getTopLeft(find.text('Premiers pas').last).dy, lessThan(80));
    });

    testWidgets('F1 ouvre l\'aide de l\'écran en cours', (tester) async {
      await launch(tester, Lang.fr);
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.text('Barre d\'outils'), findsOneWidget); // page Analyse

      await tester.tap(find.text('Règles').first);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.text('Écran Règles'), findsWidgets);
    });

    testWidgets('« ? » de l\'écran Réglages mène à l\'aide du profil',
        (tester) async {
      await launch(tester, Lang.fr);
      await tester.tap(find.text('Réglages'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithIcon(IconButton, Icons.help_outline).first);
      await tester.pumpAndSettle();
      expect(find.text('Aide complète'), findsOneWidget);
      await tester.tap(find.text('Aide complète'));
      await tester.pumpAndSettle();
      expect(find.text('Réglages'), findsWidgets);
    });

    testWidgets('info-bulles de la barre d\'outils', (tester) async {
      await launch(tester, Lang.fr);
      final tp = Tips(Lang.fr);
      for (final m in [tp.openScript, tp.reanalyze, tp.fix, tp.export]) {
        expect(find.byTooltip(m), findsOneWidget, reason: m);
      }
      await tester.tap(find.text('Dossier'));
      await tester.pumpAndSettle();
      expect(find.byTooltip(tp.openFolder), findsOneWidget);
    });

    testWidgets('anglais : aide et info-bulles dans la langue', (tester) async {
      await launch(tester, Lang.en);
      expect(find.byTooltip(Tips(Lang.en).openScript), findsOneWidget);
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      expect(find.text('Getting started'), findsWidgets);
    });
  });

  group('mise en forme', () {
    testWidgets('gras, code et italique', (tester) async {
      late TextSpan span;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          span = inlineSpans('un **gras**, du `code` et *italique*',
              const TextStyle(fontSize: 14), context);
          return const SizedBox();
        }),
      ));
      final parts = span.children!.cast<TextSpan>();
      expect(parts.map((p) => p.text).join(), 'un gras, du code et italique');
      expect(parts.firstWhere((p) => p.text == 'gras').style?.fontWeight,
          FontWeight.w700);
      expect(parts.firstWhere((p) => p.text == 'italique').style?.fontStyle,
          FontStyle.italic);
      expect(parts.firstWhere((p) => p.text == 'code').style?.backgroundColor,
          isNotNull);
    });
  });
}
