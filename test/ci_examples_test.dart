/// Les exemples d'intégration continue (doc/ci/*, doc/ci.adoc, doc/ci.fr.adoc)
/// restent valides : chaque ligne de commande `check-script …` est acceptée
/// par l'analyseur d'options réel, les entrées de l'action GitHub existent,
/// les hooks pre-commit existent, et les versions citées sont celles de
/// l'outil.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:check_script/check_script.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../bin/check_script.dart' as cli;

/// Découpe une ligne de commande façon shell (guillemets simples et doubles,
/// antislash) ; les variables (`$VAR`, `${VAR}`, `$(…)`) deviennent « x » ; la
/// commande s'arrête au premier opérateur (`|`, `&&`, `;`, `>`, `<`…).
List<String> shellWords(String line) {
  final out = <String>[];
  final cur = StringBuffer();
  var inWord = false;
  void flush() {
    if (inWord) out.add(cur.toString());
    cur.clear();
    inWord = false;
  }

  var i = 0;
  while (i < line.length) {
    final c = line[i];
    if (c == "'") {
      inWord = true;
      final end = line.indexOf("'", i + 1);
      cur.write(line.substring(i + 1, end < 0 ? line.length : end));
      i = end < 0 ? line.length : end + 1;
    } else if (c == '"') {
      inWord = true;
      i++;
      while (i < line.length && line[i] != '"') {
        if (line[i] == r'\' && i + 1 < line.length) {
          cur.write(line[i + 1]);
          i += 2;
        } else if (line[i] == r'$') {
          i = _skipVariable(line, i);
          cur.write('x');
        } else {
          cur.write(line[i]);
          i++;
        }
      }
      i++;
    } else if (c == r'\' && i + 1 < line.length) {
      inWord = true;
      cur.write(line[i + 1]);
      i += 2;
    } else if (c == r'$') {
      inWord = true;
      i = _skipVariable(line, i);
      cur.write('x');
    } else if (' \t'.contains(c)) {
      flush();
      i++;
    } else if ('|&;<>'.contains(c) || (c == '2' && line.startsWith('2>', i))) {
      // Redirection ou enchaînement : fin de la commande (un « 2 » collé à
      // un mot reste un caractère ordinaire).
      if (c == '2' && inWord) {
        cur.write(c);
        i++;
      } else {
        flush();
        break;
      }
    } else {
      inWord = true;
      cur.write(c);
      i++;
    }
  }
  flush();
  return out;
}

/// Position après la variable ou la substitution qui commence en [i].
int _skipVariable(String s, int i) {
  if (i + 1 < s.length && (s[i + 1] == '{' || s[i + 1] == '(')) {
    final close = s[i + 1] == '{' ? '}' : ')';
    final end = s.indexOf(close, i + 2);
    return end < 0 ? s.length : end + 1;
  }
  var j = i + 1;
  while (j < s.length && RegExp(r'[A-Za-z0-9_]').hasMatch(s[j])) {
    j++;
  }
  return j;
}

/// Lignes de commande `check-script …` d'un texte : continuations par
/// antislash recollées, exécutable éventuellement sous la forme
/// `"$RUNNER_TEMP/check-script"`, préfixes de liste YAML ou d'invite retirés.
List<String> commandsIn(String text) {
  final lines = <String>[];
  final buf = StringBuffer();
  for (final raw in text.split('\n')) {
    final line = raw.trimRight();
    if (line.endsWith(r'\')) {
      buf.write('${line.substring(0, line.length - 1)} ');
    } else {
      buf.write(line);
      lines.add(buf.toString());
      buf.clear();
    }
  }
  final out = <String>[];
  final exe = RegExp(
      r'''(?:^|[\s;&|(])(?:"\$RUNNER_TEMP/check-script"|check-script)(?=\s|$)''');
  for (final l in lines) {
    final t = l.trimLeft();
    if (t.startsWith('#') || t.startsWith('//')) continue;
    final m = exe.firstMatch(l);
    if (m == null) continue;
    // Seulement les vraies commandes : pas de prose (« check-script est… »).
    final after = l.substring(m.end).trimLeft();
    if (after.isEmpty) {
      out.add('');
      continue;
    }
    if (RegExp(r'^[a-zàâçéèêëîïôûùü]+\s+[a-zàâçéèêëîïôûùü]+\b')
            .hasMatch(after) &&
        !const {'diff', 'init', 'explain', 'lsp'}
            .contains(after.split(' ').first)) {
      continue;
    }
    out.add(after);
  }
  return out;
}

/// Toutes les chaînes d'un document YAML.
Iterable<String> yamlStrings(Object? n) sync* {
  if (n is String) yield n;
  if (n is YamlMap) {
    for (final v in n.values) {
      yield* yamlStrings(v);
    }
  }
  if (n is YamlList) {
    for (final v in n) {
      yield* yamlStrings(v);
    }
  }
}

/// Blocs de code d'un fichier AsciiDoc (entre lignes `----`).
List<String> adocBlocks(String text) {
  final blocks = <String>[];
  StringBuffer? cur;
  for (final line in text.split('\n')) {
    if (line == '----') {
      if (cur == null) {
        cur = StringBuffer();
      } else {
        blocks.add(cur.toString());
        cur = null;
      }
    } else {
      cur?.writeln(line);
    }
  }
  return blocks;
}

/// Valide les arguments d'une commande avec l'analyseur d'options réel ;
/// renvoie un message d'erreur, ou null.
String? validate(String command) {
  final words = shellWords(command);
  if (words.isEmpty) return null;
  try {
    switch (words.first) {
      case 'diff':
        cli.buildDiffParser().parse(words.skip(1));
      case 'init':
        cli.buildInitParser().parse(words.skip(1));
      case 'explain':
        cli.buildExplainParser().parse(words.skip(1));
      case 'lsp':
        break;
      default:
        cli.buildParser(Lang.en).parse(words);
    }
  } on FormatException catch (e) {
    return '${e.message} dans « check-script $command »';
  }
  return null;
}

void main() {
  final files = [
    for (final f in Directory('doc/ci').listSync().whereType<File>()) f.path,
    'doc/ci.adoc',
    'doc/ci.fr.adoc',
  ]..sort();

  group('shellWords / commandsIn (outillage du test)', () {
    test('découpage façon shell', () {
      expect(shellWords("--fail-under 6 --lang 'en us' -o \"a b.json\" x"),
          ['--fail-under', '6', '--lang', 'en us', '-o', 'a b.json', 'x']);
      expect(shellWords(r'-b "$BASE" --fail-on-new high | tee out'),
          ['-b', 'x', '--fail-on-new', 'high']);
      expect(shellWords('scripts > out.txt 2>&1'), ['scripts']);
      expect(shellWords(r'a${X}b $(date) c'), ['axb', 'x', 'c']);
      expect(shellWords('-j 2'), ['-j', '2']);
    });

    test('continuations et préfixes', () {
      final c =
          commandsIn('check-script --summary -o a.json \\\n  --fail-under 6 .\n'
              '- check-script --lang en .\n'
              r'"$RUNNER_TEMP/check-script" diff a.json b.json'
              '\n'
              '# check-script ignoré\n'
              'check-script est un outil\n');
      expect(c.map((x) => x.replaceAll(RegExp(r'\s+'), ' ')).toList(), [
        '--summary -o a.json --fail-under 6 .',
        '--lang en .',
        'diff a.json b.json',
      ]);
    });

    test('validation : options inconnues refusées', () {
      expect(validate('--fail-under 6 scripts'), isNull);
      expect(validate('--nope scripts'), contains('nope'));
      expect(validate('diff a.json b.json --fail-on-new high'), isNull);
      expect(validate('diff a.json b.json --zzz'), contains('zzz'));
      expect(validate('init --baseline b.json'), isNull);
      expect(validate('explain SEC003'), isNull);
    });
  });

  group('exemples d\'intégration continue', () {
    test('les fichiers attendus existent', () {
      for (final n in [
        'github-actions.yml',
        'github-pr-diff.yml',
        'github-baseline.yml',
        'gitlab-ci.yml',
        'gitlab-baseline.yml',
        'Jenkinsfile',
        'pre-commit-config.yaml',
      ]) {
        expect(File('doc/ci/$n').existsSync(), isTrue, reason: n);
      }
    });

    test('chaque commande check-script est acceptée par l\'analyseur', () {
      var count = 0;
      for (final path in files) {
        final text = File(path).readAsStringSync();
        final texts = <String>[];
        if (path.endsWith('.adoc')) {
          texts.addAll(adocBlocks(text));
        } else if (path.endsWith('.yml') || path.endsWith('.yaml')) {
          texts.addAll(yamlStrings(loadYaml(text)));
        } else {
          texts.add(text);
        }
        for (final t in texts) {
          for (final c in commandsIn(t)) {
            count++;
            expect(validate(c), isNull, reason: '$path : $c');
          }
        }
      }
      // Garde-fou : l'extraction ne doit pas être devenue muette.
      expect(count, greaterThanOrEqualTo(25));
    });

    test('les fichiers YAML sont du YAML valide', () {
      for (final path
          in files.where((f) => f.endsWith('.yml') || f.endsWith('.yaml'))) {
        expect(() => loadYaml(File(path).readAsStringSync()), returnsNormally,
            reason: path);
      }
    });

    test('l\'action GitHub : entrées utilisées déclarées dans action.yml', () {
      final inputs = ((loadYaml(File('action.yml').readAsStringSync())
              as YamlMap)['inputs'] as YamlMap)
          .keys
          .cast<String>()
          .toSet();
      var steps = 0;
      for (final path in files.where((f) => f.endsWith('.yml'))) {
        final doc = loadYaml(File(path).readAsStringSync());
        if (doc is! YamlMap || doc['jobs'] is! YamlMap) continue;
        for (final job in (doc['jobs'] as YamlMap).values) {
          for (final step
              in (job as YamlMap)['steps'] as YamlList? ?? YamlList()) {
            final uses = (step as YamlMap)['uses'];
            if (uses is! String || !uses.startsWith('chla28/CheckScript@')) {
              continue;
            }
            steps++;
            final withKeys =
                ((step['with'] as YamlMap?)?.keys ?? const []).cast<String>();
            for (final k in withKeys) {
              expect(inputs, contains(k), reason: '$path : with.$k');
            }
          }
        }
      }
      expect(steps, greaterThanOrEqualTo(4));
    });

    test('pre-commit : hooks et arguments valides', () {
      final hooks = {
        for (final h
            in loadYaml(File('.pre-commit-hooks.yaml').readAsStringSync())
                as YamlList)
          (h as YamlMap)['id'] as String
      };
      final doc =
          loadYaml(File('doc/ci/pre-commit-config.yaml').readAsStringSync())
              as YamlMap;
      for (final repo in doc['repos'] as YamlList) {
        for (final h in (repo as YamlMap)['hooks'] as YamlList) {
          expect(hooks, contains((h as YamlMap)['id']));
          final args = [
            for (final a in (h['args'] as YamlList? ?? YamlList())) '$a'
          ];
          if (args.isNotEmpty) {
            final r = ArgParser.allowAnything();
            expect(r, isNotNull);
            expect(validate(args.join(' ')), isNull, reason: '$args');
          }
        }
      }
    });

    test('versions citées = version de l\'outil', () {
      final re = RegExp(r'(?:CheckScript@|rev: )v(\d+\.\d+\.\d+)');
      var seen = 0;
      for (final path in files) {
        for (final m in re.allMatches(File(path).readAsStringSync())) {
          seen++;
          expect(m.group(1), appVersion, reason: path);
        }
      }
      expect(seen, greaterThanOrEqualTo(6));
    });

    test('release.dart met ces fichiers à jour à chaque version', () {
      final src = File('tool/release.dart').readAsStringSync();
      for (final path in files.where((f) => RegExp(r'(CheckScript@|rev: )v\d')
          .hasMatch(File(f).readAsStringSync()))) {
        expect(src, contains("'$path'"), reason: path);
      }
    });
  });
}
