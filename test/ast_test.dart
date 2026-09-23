import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Arbre produit par le vrai shfmt (3.7) : test/fixtures/outputs/.
void main() {
  late AstFacts ast;
  setUpAll(() =>
      ast = AstFacts.fromJson(readFixture('outputs/shfmt_ast_structure.json')));

  test('fonctions : nom et étendue', () {
    expect(ast.functions.single.name, 'long_function');
    expect(ast.functions.single.startLine, 3);
    expect(ast.functions.single.endLine, 15);
  });

  test('imbrication : profondeur maximale et franchissement du seuil', () {
    expect(ast.maxDepth, 5);
    expect(ast.deepNodes(4).single.line, 10);
    expect(ast.deepNodes(5), isEmpty);
  });

  CommandFact cmd(String name, [int? line]) => ast.commands
      .firstWhere((c) => c.name == name && (line == null || c.line == line));

  test('commandes : contrôle du code de retour', () {
    expect(cmd('cd', 16).checked, isFalse);
    expect(cmd('cd', 17).checked, isTrue); // cd … || exit 1
    expect(cmd('mkdir', 24).checked, isTrue); // condition de if
    expect(cmd('mkdir', 25).checked, isFalse);
  });

  test('commandes : boucle et substitution', () {
    final b = cmd('basename');
    expect(b.inLoop, isTrue);
    expect(b.inSubstitution, isTrue);
    expect(cmd('which').inLoop, isFalse);
  });

  test('arguments littéraux et expansions', () {
    expect(
        ast.commands.where((c) => c.name == 'eval').map((c) => c.hasExpansion),
        [true, false]);
    expect(cmd('set').args, ['-x']);
    expect(cmd('read', 20).args, ['answer']);
  });

  test('un mot-clé dans une chaîne n\'est pas une commande', () {
    expect(ast.commands.where((c) => c.name == 'which'), hasLength(1));
  });

  test('JSON invalide', () {
    expect(() => AstFacts.fromJson('[1]'), throwsFormatException);
  });

  group('règles intégrées sur l\'arbre', () {
    List<Finding> run() => runBuiltinRules(
        script(readFixture('structure.sh')), const CheckConfig(), Lang.en,
        ast: ast);

    test('commandes signalées aux bonnes lignes', () {
      final byRule = <String, List<int>>{};
      for (final f in run()) {
        (byRule[f.ruleId] ??= []).add(f.line);
      }
      expect(byRule['SEC003'], [21]); // eval "$cmd", pas eval echo fixe
      expect(byRule['ROB005'], [16]);
      expect(byRule['POR004'], [18]);
      expect(byRule['POR005'], [19]);
      expect(byRule['ROB007'], [20]);
      expect(byRule['SEC012'], [23]);
      expect(byRule['PERF004'], [6]);
      expect(byRule['MNT003'], [10]);
      expect(byRule['ROB011'], [25]);
    });

    test('les règles de commande du lexer sont remplacées', () {
      // Sans arbre, le lexer signalerait aussi eval echo fixe (non).
      final lexer = runBuiltinRules(
          script(readFixture('structure.sh')), const CheckConfig(), Lang.en);
      expect(lexer.where((f) => f.ruleId == 'SEC003').map((f) => f.line), [21]);
    });
  });

  test('loadAst : shfmt reçoit le script sur l\'entrée standard', () async {
    final runner = FakeRunner({
      'shfmt': (_) =>
          CommandResult(0, readFixture('outputs/shfmt_ast_structure.json'), ''),
    });
    final ctx = AnalysisContext(
        script: script(readFixture('structure.sh')),
        filePath: 'x',
        config: const CheckConfig(),
        lang: Lang.fr,
        runner: runner);
    final a = await loadAst(ctx);
    expect(a, isNotNull);
    expect(runner.calls.single.$2, containsAll(['--to-json', '-ln=bash']));
    expect(runner.stdins.single, contains('long_function'));
  });

  test('loadAst : repli bash pour un script /bin/sh non POSIX', () async {
    final runner = FakeRunner({
      'shfmt': (args) => args.contains('-ln=posix')
          ? const CommandResult(1, '', 'erreur')
          : CommandResult(
              0, readFixture('outputs/shfmt_ast_structure.json'), ''),
    });
    final ctx = AnalysisContext(
        script: script('#!/bin/sh\nfunction f { :; }\n'),
        filePath: 'x',
        config: const CheckConfig(),
        lang: Lang.fr,
        runner: runner);
    expect(await loadAst(ctx), isNotNull);
    expect(runner.calls, hasLength(2));
  });

  test('loadAst : null sans shfmt', () async {
    final ctx = AnalysisContext(
        script: script('echo a\n'),
        filePath: 'x',
        config: const CheckConfig(),
        lang: Lang.fr,
        runner: noTools());
    expect(await loadAst(ctx), isNull);
  });
}
