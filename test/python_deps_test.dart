import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

String? _noPython() {
  try {
    return Process.runSync('python3', ['--version']).exitCode == 0
        ? null
        : 'python3 absent';
  } on ProcessException {
    return 'python3 absent';
  }
}

void main() {
  group('dépendances déclarées', () {
    test('requirements, pyproject, Pipfile, setup.cfg', () {
      expect(declaredIn('requirements.txt', '''
# commentaire
requests[socks]>=2.31 ; python_version >= "3.9"
PyYAML==6.0.1  # yaml
-e git+https://github.com/x/y.git#egg=my_pkg
--index-url https://pypi.org/simple
Django @ https://x/django.whl
'''), {'requests', 'pyyaml', 'my-pkg', 'django'});
      expect(declaredIn('pyproject.toml', '''
[project]
name = "x"
dependencies = [
  "httpx>=0.27",
  'rich',
]
[project.optional-dependencies]
dev = ["pytest"]
[tool.poetry.dependencies]
python = "^3.9"
Click = "^8"
[dependency-groups]
lint = ["ruff"]
'''), {'httpx', 'rich', 'pytest', 'click', 'ruff'});
      expect(
          declaredIn('Pipfile',
              '[packages]\nflask = "*"\n[dev-packages]\nblack = "*"\n'),
          {'flask', 'black'});
      expect(
          declaredIn('setup.cfg',
              '[options]\ninstall_requires =\n    numpy>=1\n    pandas\npython_requires = >=3.9\n'),
          {'numpy', 'pandas'});
    });

    test('en-tête PEP 723', () {
      expect(
          inlineDependencies([
            '#!/usr/bin/env python3',
            '# /// script',
            '# requires-python = ">=3.11"',
            '# dependencies = [',
            '#   "requests<3",',
            '#   "rich",',
            '# ]',
            '# ///',
            'import requests',
          ]),
          {'requests', 'rich'});
      expect(inlineDependencies(['import os']), isNull);
    });

    test('correspondance module → paquet', () {
      bool declared(String module, Set<String> d,
              {List<String> dists = const []}) =>
          isDeclared(PythonImport(module, 1, 1, 'installed', dists: dists), d);
      expect(declared('yaml', {'pyyaml'}), isTrue);
      expect(declared('psycopg2', {'psycopg2-binary'}), isTrue);
      expect(declared('my_pkg', {'my-pkg'}), isTrue);
      expect(declared('foo', {'bar'}, dists: ['Foo-Lib']), isFalse);
      expect(declared('foo', {'foo-lib'}, dists: ['Foo_Lib']), isTrue);
    });
  });

  test('règles : introuvable, non déclaré, facultatif', () {
    const imports = [
      PythonImport('os', 1, 1, 'stdlib'),
      PythonImport('lib', 2, 1, 'local'),
      PythonImport('requests', 3, 1, 'installed'),
      PythonImport('rich', 4, 1, 'installed'),
      PythonImport('typo_mod', 5, 1, 'missing'),
      PythonImport('ujson', 6, 1, 'missing', optional: true),
      PythonImport('httpx', 7, 1, 'missing'),
    ];
    String ids(Set<String>? declared) => [
          for (final f in checkImports(imports, declared, Lang.fr))
            '${f.ruleId}:${f.line}'
        ].join(' ');
    // Sans déclaration : seuls les introuvables.
    expect(ids(null), 'PYROB005:5 PYROB005:7');
    // httpx déclaré mais pas installé : pas un défaut du script.
    expect(ids({'requests', 'httpx'}), 'PYPOR002:4 PYROB005:5');
  });

  test('pip-audit : vulnérabilités des paquets importés', () {
    const json = '''
{"dependencies": [
  {"name": "requests", "version": "2.19.0", "vulns": [
    {"id": "PYSEC-2018-28", "fix_versions": ["2.20.0"], "aliases": ["CVE-2018-18074"]}]},
  {"name": "PyYAML", "version": "5.3", "vulns": [
    {"id": "GHSA-8q59-q68h-6hv4", "fix_versions": [], "aliases": []}]},
  {"name": "urllib3", "version": "1.0", "vulns": [
    {"id": "PYSEC-1", "fix_versions": ["2"], "aliases": []}]}
], "fixes": []}''';
    final imports =
        importLines(['import os, requests', 'from yaml import safe_load']);
    expect(imports, {'os': 1, 'requests': 1, 'yaml': 2});
    final f = parsePipAudit(json, imports, Lang.fr);
    expect(f.map((x) => '${x.ruleId}:${x.line}'),
        ['PYSEC-2018-28:1', 'GHSA-8q59-q68h-6hv4:2']); // urllib3 non importé
    expect(f.first.message, contains('CVE-2018-18074'));
    expect(f.first.hint, contains('2.20.0'));
    expect(f.first.severity, Severity.high);
    expect(
        () => parsePipAudit('oops', imports, Lang.fr), throwsFormatException);
  });

  group('interpréteur réel', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('cs_deps_'));
    tearDown(() => tmp.delete(recursive: true));

    test('classement des imports et projet', () async {
      Directory('${tmp.path}/.git').createSync();
      File('${tmp.path}/requirements.txt').writeAsStringSync('requests\n');
      File('${tmp.path}/localmod.py').writeAsStringSync('X = 1\n');
      final path = '${tmp.path}/s.py';
      File(path).writeAsStringSync('''
import os
import requests
import localmod
import zz_module_introuvable_42
try:
    import zz_facultatif_42
except ImportError:
    zz_facultatif_42 = None
''');
      final r = await Engine(analyzers: [PythonDepsAnalyzer()], lang: Lang.fr)
          .analyzeFile(path);
      final run = r.tools.single;
      expect(run.status, ToolStatus.ok);
      expect(run.detail, 'requirements.txt');
      expect(r.findings.map((f) => '${f.ruleId}:${f.line}'), ['PYROB005:4']);
    }, skip: _noPython());
  });
}
