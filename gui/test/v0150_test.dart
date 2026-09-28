import 'package:check_script/check_script.dart';
import 'package:check_script_gui/app_state.dart';
import 'package:check_script_gui/code_style.dart';
import 'package:check_script_gui/main.dart';
import 'package:check_script_gui/widgets/source_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('taille du code : pas, bornes, défaut, mémorisation', () async {
    const g = GuiSettings();
    expect(g.codeFontSize, defaultCodeFontSize);
    expect(g.codeFont, isNull);
    expect(g.zoomCode(2).codeFontSize, defaultCodeFontSize + 2);
    expect(g.zoomCode(100).codeFontSize, maxCodeFontSize);
    expect(g.zoomCode(-100).codeFontSize, minCodeFontSize);
    expect(g.zoomCode(3).zoomCode(null).codeFontSize, defaultCodeFontSize);
    await g.zoomCode(4).copyWith(codeFont: () => 'Noto Sans Mono').save();
    final loaded = await GuiSettings.load();
    expect(loaded.codeFontSize, defaultCodeFontSize + 4);
    expect(loaded.codeFont, 'Noto Sans Mono');
    expect(codeLineHeight(13), 20);
  });

  testWidgets('source colorée, police et taille appliquées', (tester) async {
    const lines = ['#!/bin/bash', 'echo "\$HOME" # fin'];
    final zooms = <double>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SourceView(
          lines: lines,
          findings: const [],
          language: HighlightLanguage.shell,
          fontFamily: 'Noto Sans Mono',
          fontSize: 16,
          onZoom: zooms.add,
        ),
      ),
    ));
    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((r) => r.text.toPlainText() == lines[1]);
    // Text.rich place le texte sous le style par défaut.
    final span = (rich.text as TextSpan).children!.single as TextSpan;
    expect(span.style!.fontFamily, 'Noto Sans Mono');
    expect(span.style!.fontSize, 16);
    final colored = <String>{
      for (final c in span.children!.cast<TextSpan>())
        if (c.style?.color != null) c.text!,
    };
    expect(colored, containsAll(['echo', r'$HOME', '# fin']));

    // Ctrl+molette : zoom (la molette seule fait défiler).
    final at = tester.getCenter(find.textContaining('echo'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(at));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -20)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
    expect(zooms, [1]);
  });

  testWidgets('Ctrl+plus / Ctrl+moins / Ctrl+0 dans l\'application',
      (tester) async {
    final state = AppState(
        runner: _NoTools(), settings: const GuiSettings(lang: Lang.fr));
    await tester.pumpWidget(CheckScriptApp(state: state));
    await tester.pump();
    Future<void> ctrl(LogicalKeyboardKey k) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(k);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await ctrl(LogicalKeyboardKey.equal);
    await ctrl(LogicalKeyboardKey.equal);
    expect(state.settings.codeFontSize, defaultCodeFontSize + 2);
    await ctrl(LogicalKeyboardKey.minus);
    expect(state.settings.codeFontSize, defaultCodeFontSize + 1);
    await ctrl(LogicalKeyboardKey.digit0);
    expect(state.settings.codeFontSize, defaultCodeFontSize);
    // Laisse expirer les minuteurs (info-bulles, animations).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('police du code transmise aux blocs de code', (tester) async {
    late TextStyle style;
    await tester.pumpWidget(CodeFont(
      family: 'Noto Sans Mono',
      size: 18,
      child: Builder(builder: (context) {
        style = CodeFont.styleOf(context);
        return const SizedBox();
      }),
    ));
    expect(style.fontFamily, 'Noto Sans Mono');
    expect(style.fontSize, 18);
    expect(style.fontFamilyFallback, contains(defaultCodeFont));
  });
}

class _NoTools implements CommandRunner {
  @override
  Future<CommandResult?> run(String executable, List<String> args,
          {String? stdin, CancelToken? cancel}) async =>
      null;
}
