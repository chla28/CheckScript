import 'dart:io';

import 'package:check_script/check_script.dart';

/// Chemin d'une fixture.
String fixture(String name) => 'test/fixtures/$name';

String readFixture(String name) => File(fixture(name)).readAsStringSync();

/// Faux exécuteur : renvoie des résultats préenregistrés par exécutable.
/// Un exécutable absent de [responses] est considéré comme non installé.
class FakeRunner implements CommandRunner {
  final Map<String, CommandResult Function(List<String> args)> responses;
  final calls = <(String, List<String>)>[];
  final stdins = <String?>[];

  FakeRunner(this.responses);

  @override
  Future<CommandResult?> run(String executable, List<String> args,
      {String? stdin, CancelToken? cancel}) async {
    calls.add((executable, args));
    stdins.add(stdin);
    final r = responses[executable];
    return r?.call(args);
  }
}

/// Aucun outil externe installé (pas même bash).
FakeRunner noTools() => FakeRunner({});

ScriptInfo script(String content,
        {String path = 'test.sh', Dialect? dialect}) =>
    ScriptInfo.fromContent(path, content, forcedDialect: dialect);

/// Règles intégrées seules, en anglais.
List<Finding> builtin(String content,
        {CheckConfig config = const CheckConfig(), Dialect? dialect}) =>
    runBuiltinRules(script(content, dialect: dialect), config, Lang.en);

Set<String> ids(List<Finding> fs) => {for (final f in fs) f.ruleId};
