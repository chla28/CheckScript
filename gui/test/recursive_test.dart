import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:check_script_gui/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoTools implements CommandRunner {
  @override
  Future<CommandResult?> run(String executable, List<String> args,
          {String? stdin, CancelToken? cancel}) async =>
      null;
}

void main() {
  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('cs_gui_rec_');
    for (final f in ['a.sh', 'sub/b.sh']) {
      File('${tmp.path}/$f')
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/bash\necho x\n');
    }
  });
  tearDown(() => tmp.delete(recursive: true));

  test('dossier : sous-dossiers ignorés par défaut, analysés avec le réglage',
      () async {
    final state = AppState(runner: _NoTools(), settings: const GuiSettings());
    await state.analyzeFolder(tmp.path);
    expect(state.folderReports, hasLength(1));

    await state.updateSettings(state.settings.copyWith(recursive: true));
    await state.analyzeFolder(tmp.path);
    expect(state.folderReports, hasLength(2));
  });

  test('réglage conservé entre deux sessions', () async {
    final state = AppState(runner: _NoTools(), settings: const GuiSettings());
    await state.updateSettings(state.settings.copyWith(recursive: true));
    expect((await GuiSettings.load()).recursive, isTrue);
    expect(const GuiSettings().recursive, isFalse);
  });
}
