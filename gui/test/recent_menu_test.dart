import 'dart:io';

import 'package:check_script/check_script.dart' show Lang;
import 'package:check_script_gui/app_state.dart';
import 'package:check_script_gui/editor.dart';
import 'package:check_script_gui/widgets/recent_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('cs_gui_recent_');
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<void> pump(
          WidgetTester t, AppState state, void Function(String, bool) onOpen) =>
      t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(child: RecentMenu(state: state, onOpen: onOpen)),
        ),
      ));

  group('RecentMenu', () {
    testWidgets('liste vide : message « aucun élément »', (t) async {
      final state = AppState(settings: const GuiSettings(lang: Lang.en));
      await pump(t, state, (_, __) {});
      await t.tap(find.byType(RecentMenu));
      await t.pumpAndSettle();
      expect(find.text('No recent item'), findsOneWidget);
      expect(find.text('Clear the list'), findsNothing);
    });

    testWidgets('fichier et dossier : ouverture avec le bon type', (t) async {
      final f = File('${tmp.path}/a.sh')..writeAsStringSync('echo a\n');
      final state = AppState(
          settings: GuiSettings(lang: Lang.en, recent: [f.path, tmp.path]));
      final opened = <(String, bool)>[];
      await pump(t, state, (p, d) => opened.add((p, d)));

      await t.tap(find.byType(RecentMenu));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
      await t.tap(find.text('a.sh'));
      await t.pumpAndSettle();
      expect(opened, [(f.path, false)]);

      await t.tap(find.byType(RecentMenu));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.folder_outlined));
      await t.pumpAndSettle();
      expect(opened.last, (tmp.path, true));
    });

    testWidgets('« Vider la liste » efface les récents', (t) async {
      final state = AppState(
          settings: GuiSettings(lang: Lang.en, recent: ['${tmp.path}/x.sh']));
      await pump(t, state, (_, __) {});
      await t.tap(find.byType(RecentMenu));
      await t.pumpAndSettle();
      await t.tap(find.text('Clear the list'));
      await t.pumpAndSettle();
      expect(state.settings.recent, isEmpty);
    });
  });

  group('éditeur externe', () {
    test('detectEditor : premier éditeur connu trouvé dans le PATH', () {
      expect(
          detectEditor(
              path: '/a:/b', exists: (f) => f == '/b/kate' || f == '/a/xed'),
          startsWith('kate '));
      expect(detectEditor(path: '', exists: (_) => true), isNull);
    });

    test('editorCommandLine : modèle vide ou ligne < 1', () {
      expect(editorCommandLine('  ', '/a.sh', 3), ['xdg-open', '/a.sh']);
      expect(editorCommandLine('gedit +{line} {file}', '/a.sh', -4),
          ['gedit', '+1', '/a.sh']);
    });

    test('openInEditor : exécutable introuvable → message d\'erreur', () async {
      final msg = await openInEditor('cs-no-such-editor {file}', '/x.sh', 1);
      expect(msg, isNotNull);
      expect(msg, startsWith('cs-no-such-editor'));
    });

    test('openInEditor : commande valide → null', () async {
      expect(await openInEditor('true {file}', '/x.sh', 1), isNull);
    });
  });
}
