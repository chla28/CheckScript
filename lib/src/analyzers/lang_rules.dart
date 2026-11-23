/// Règles intégrées des langages autres que shell et Python (Perl, Ruby, Lua,
/// Node.js) et des fichiers d'administration (unités systemd, crontab,
/// sudoers).
///
/// La détection est lexicale : les commentaires sont retirés ligne à ligne
/// (hors chaînes), puis des motifs sont cherchés. Elle ne remplace pas un
/// linter du langage (perlcritic, RuboCop, luacheck, ESLint) : elle couvre
/// les points de sécurité et de robustesse propres aux scripts d'administration.
library;

import '../config.dart';
import '../i18n.dart';
import '../model/finding.dart';
import '../rules/catalog.dart';
import '../script_info.dart';
import 'builtin_rules.dart' show lineHasSecret;

/// Règles du dialecte de [s] (liste vide pour un shell ou Python).
List<Finding> runLangRules(ScriptInfo s, CheckConfig config, Lang lang) {
  final ctx = _Ctx(s, config, lang);
  switch (s.dialect) {
    case Dialect.perl:
      _perl(ctx);
    case Dialect.ruby:
      _ruby(ctx);
    case Dialect.lua:
      _lua(ctx);
    case Dialect.node:
      _node(ctx);
    case Dialect.systemd:
      _systemd(ctx);
    case Dialect.crontab:
      _crontab(ctx);
    case Dialect.sudoers:
      _sudoers(ctx);
    default:
      return const [];
  }
  return ctx.out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Contexte et utilitaires
// ─────────────────────────────────────────────────────────────────────────────

class _Ctx {
  final ScriptInfo s;
  final CheckConfig config;
  final Lang lang;
  final out = <Finding>[];

  /// Lignes sans commentaires (même nombre de lignes que [s]).
  late final List<String> code = stripComments(s.lines, s.dialect);

  _Ctx(this.s, this.config, this.lang);

  /// Identifiant `PL`+[suffix] selon le dialecte.
  String id(String suffix) => '${_prefix(s.dialect)}$suffix';

  void add(String ruleId, int line, {bool hide = false}) {
    final r = ruleInfo(ruleId);
    if (r.contexts.isNotEmpty && !r.contexts.any(config.contexts.contains)) {
      return;
    }
    out.add(Finding(
      tool: 'builtin',
      ruleId: r.id,
      category: r.category,
      severity: r.severity,
      line: line,
      message: r.title.of(lang),
      snippet: hide || line < 1 || line > s.lines.length
          ? null
          : s.lines[line - 1].trim(),
      hint: r.fix.of(lang),
    ));
  }

  /// Une constatation par ligne dont le code correspond à [re] (sauf si
  /// [unless] correspond aussi).
  void scan(String ruleSuffix, RegExp re,
      {RegExp? unless, bool Function(String line)? where, bool hide = false}) {
    final rule = id(ruleSuffix);
    for (var i = 0; i < code.length; i++) {
      final c = code[i];
      if (c.isEmpty || !re.hasMatch(c)) continue;
      if (unless != null && unless.hasMatch(c)) continue;
      if (where != null && !where(c)) continue;
      add(rule, i + 1, hide: hide);
    }
  }
}

String _prefix(Dialect d) => switch (d) {
      Dialect.perl => 'PL',
      Dialect.ruby => 'RB',
      Dialect.lua => 'LU',
      Dialect.node => 'JS',
      Dialect.systemd => 'SD',
      Dialect.crontab => 'CR',
      Dialect.sudoers => 'SU',
      _ => throw ArgumentError('pas de règles pour $d'),
    };

/// Lignes sans commentaires. Pour les langages de script, le commentaire est
/// cherché hors des chaînes ; les blocs `--[[ … ]]` (Lua) et `/* … */`
/// (Node.js) s'étendent sur plusieurs lignes. Dans les fichiers
/// d'administration, seules les lignes entièrement en commentaire sont
/// retirées : un `#` en fin de ligne de crontab fait partie de la commande.
List<String> stripComments(List<String> lines, Dialect d) {
  if (d.isConfig) {
    return [
      for (final l in lines) _wholeLineComment(l, d) ? '' : l,
    ];
  }
  final out = <String>[];
  var block = false;
  for (final l in lines) {
    final r = _stripLine(l, d, block);
    block = r.$2;
    out.add(r.$1);
  }
  return out;
}

bool _wholeLineComment(String l, Dialect d) {
  final t = l.trimLeft();
  return t.startsWith('#') || (d == Dialect.systemd && t.startsWith(';'));
}

/// (ligne sans commentaire, un commentaire de bloc reste ouvert).
(String, bool) _stripLine(String line, Dialect d, bool inBlock) {
  final b = StringBuffer();
  String? quote;
  var i = 0;
  while (i < line.length) {
    final c = line[i];
    if (inBlock) {
      final end = d == Dialect.lua ? ']]' : '*/';
      final at = line.indexOf(end, i);
      if (at < 0) return (b.toString(), true);
      i = at + end.length;
      inBlock = false;
      continue;
    }
    if (quote != null) {
      b.write(c);
      if (c == '\\' && i + 1 < line.length) {
        b.write(line[i + 1]);
        i += 2;
        continue;
      }
      if (c == quote) quote = null;
      i++;
      continue;
    }
    if (c == '"' || c == "'" || (c == '`' && d != Dialect.lua)) {
      quote = c;
      b.write(c);
      i++;
      continue;
    }
    switch (d) {
      case Dialect.lua:
        if (line.startsWith('--', i)) {
          if (line.startsWith('--[[', i) || line.startsWith('--[=[', i)) {
            inBlock = true;
            i += 4;
            continue;
          }
          return (b.toString(), false);
        }
      case Dialect.node:
        if (line.startsWith('//', i)) return (b.toString(), false);
        if (line.startsWith('/*', i)) {
          inBlock = true;
          i += 2;
          continue;
        }
      default:
        // `$#tableau` (Perl) : pas un commentaire.
        if (c == '#' && !(i > 0 && line[i - 1] == r'$')) {
          return (b.toString(), false);
        }
    }
    b.write(c);
    i++;
  }
  return (b.toString(), inBlock);
}

/// Premier des 5 premières lignes utiles (hors shebang) qui est un commentaire.
bool _hasHeaderComment(ScriptInfo s) {
  var seen = 0;
  for (var i = 0; i < s.lines.length && seen < 5; i++) {
    final t = s.lines[i].trim();
    if (t.isEmpty || (i == 0 && s.shebang != null)) continue;
    seen++;
    if (t.startsWith(s.dialect.commentPrefix) ||
        t.startsWith('/*') ||
        t.startsWith('=pod') ||
        t.startsWith('=head') ||
        t.startsWith('=begin')) {
      return true;
    }
  }
  return false;
}

final _chmodString = RegExp(
    r'\bchmod\s+(?:-\w+\s+)*(?:0?777|0?666|a\+rwx|ugo\+rwx|o\+w|a\+w)\b');

final _secretAssign = RegExp(
    r'''\b(?:password|passwd|secret|token|api_?key|apikey|private_?key)\w*["']?\s*(?:=|=>|:)\s*["'][^"'$#{}\s]{6,}["']''',
    caseSensitive: false);

/// Règles communes aux quatre langages : secret, chmod 777, en-tête,
/// chemin d'interpréteur.
void _common(_Ctx c, String interpreter, RegExp chmodApi) {
  final s = c.s;
  final secret = c.id('SEC001');
  for (var i = 0; i < s.lines.length; i++) {
    if (i == 0 && s.shebang != null) continue;
    final code = c.code[i];
    if (code.isEmpty) continue;
    if (lineHasSecret(code) || _secretAssign.hasMatch(code)) {
      c.add(secret, i + 1, hide: true);
    }
  }
  c.scan('SEC005', chmodApi);
  c.scan('SEC005', _chmodString, where: (l) => !chmodApi.hasMatch(l));
  if (s.codeLines >= 8 && !_hasHeaderComment(s)) c.add(c.id('MNT001'), 0);
  final sb = s.shebang;
  // Chemin d'interpréteur en dur : `#!/usr/bin/perl`, pas `#!/usr/bin/env perl`.
  if (sb != null &&
      RegExp(r'^#!\s*/(?:usr/(?:local/)?)?bin/' '$interpreter(?:\\s|\$)')
          .hasMatch(sb)) {
    c.add(c.id('POR001'), 1);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Perl
// ─────────────────────────────────────────────────────────────────────────────

final _plStrict = RegExp(
    r'^\s*use\s+(?:strict|v?5\.(?:1[2-9]|[2-9]\d)|Modern::Perl|Moose|Moo|Mouse|'
    r'Mojo::Base|Mojolicious::Lite|common::sense|strictures|Dancer2?|Test::Most)\b',
    multiLine: true);
final _plWarnings = RegExp(
    r'^\s*use\s+(?:warnings|v?5\.(?:3[6-9]|[4-9]\d)|Modern::Perl|Moose|Moo|Mouse|'
    r'Mojo::Base|Mojolicious::Lite|common::sense|strictures|Test::Most)\b',
    multiLine: true);

void _perl(_Ctx c) {
  final s = c.s;
  _common(c, r'perl\d*', RegExp(r'\bchmod\s*\(?\s*0?(?:777|666)\b'));
  c.scan(
      'SEC002',
      RegExp(
          r'''\b(?:system|exec)\s*\(?\s*"[^"]*[$@]\w[^"]*"\s*\)?\s*(?:;|or\b|\|\||$)'''
          r'''|\b(?:system|exec)\s*\(?\s*\$\w+\s*\)?\s*(?:;|or\b|\|\||$)'''
          r'|`[^`]*[$@]\w[^`]*`'
          r'''|\bqx\s*[({\[/][^)}\]/]*[$@]\w'''));
  c.scan('SEC003', RegExp(r'''\beval\s*\(?\s*["'$]'''));
  c.scan(
      'SEC004',
      RegExp(
          r'\bSSL_verify_mode\s*=>\s*(?:0\b|SSL_VERIFY_NONE|0x0+\b)'
          r'|\bverify_hostname\s*=>\s*0\b'
          r'|PERL_LWP_SSL_VERIFY_HOSTNAME\W+0\b',
          caseSensitive: false));
  c.scan(
      'SEC006',
      RegExp(r'''\bopen\s*\(?\s*(?:my\s+)?[A-Za-z_$][\w$]*\s*,\s*'''
          r'''(?:"[^",]*"|'[^',]*'|\$\w+)\s*\)?\s*(?:or\b|\|\||;|$)'''));
  if (s.codeLines >= 3) {
    if (!_plStrict.hasMatch(c.code.join('\n'))) c.add('PLROB001', 0);
    final dashW = RegExp(r'\s-\w*w').hasMatch(s.shebang ?? '');
    if (!dashW && !_plWarnings.hasMatch(c.code.join('\n'))) {
      c.add('PLROB002', 0);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ruby
// ─────────────────────────────────────────────────────────────────────────────

void _ruby(_Ctx c) {
  _common(c, r'ruby\d*', RegExp(r'\bchmod(?:_R)?\s*\(?\s*0o?(?:777|666)\b'));
  c.scan(
      'SEC002',
      RegExp(
          r'''\b(?:system|exec|spawn|popen|popen3|capture2e?|capture3)\s*\(?\s*"[^"]*#\{'''
          r'''|\b(?:system|exec)\s*\(\s*[a-z_]\w*\s*\)'''
          r'|`[^`]*#\{'
          r'''|%x[({\[][^)}\]]*#\{'''));
  c.scan(
      'SEC003',
      RegExp(r'''(?<![\w:])(?:eval|(?:instance|class|module)_eval)\b'''
          r'''(?!\s*(?:do\b|\{))\s*\(?\s*(?:["'@$:\w]|<<)'''));
  c.scan(
      'SEC004',
      RegExp(r'VERIFY_NONE'
          r'|verify_ssl\s*(?::|=>|=)\s*false'
          r'|ssl_verify_peer\s*(?::|=>|=)\s*false'));
  c.scan(
      'SEC006',
      RegExp(r'\bMarshal\.(?:load|restore)\b'
          r'|\b(?:YAML|Psych)\.(?:load|unsafe_load)(?:_file|_stream)?\b'));
  c.scan(
      'SEC007',
      RegExp(
          r'''(?<!\bdef\s)(?<![\w.:])open\s*\(?\s*(?:[a-z_@$]\w*|"[^"]*#\{)'''),
      unless: RegExp(r'\bopen\s*\(?\s*(?:do|if|unless)\b'));
  c.scan('ROB001', RegExp(r'\brescue\s+Exception\b'));
}

// ─────────────────────────────────────────────────────────────────────────────
// Lua
// ─────────────────────────────────────────────────────────────────────────────

void _lua(_Ctx c) {
  _common(c, r'lua(?:jit)?[\d.]*', RegExp(r'(?!)'));
  c.scan(
      'SEC002',
      RegExp(r'\b(?:os\.execute|io\.popen)\s*\(.*(?:\.\.|string\.format|%s)'
          r'|\b(?:os\.execute|io\.popen)\s*\(\s*[A-Za-z_]\w*\s*[,)]'),
      unless: RegExp('%q'));
  c.scan(
      'SEC003',
      RegExp(
          r'''(?<![\w.:])(?:loadstring|load|dofile|loadfile)\s*\(\s*(?!["'\[]|\))'''),
      unless: RegExp(r'''"t"\s*,\s*\{'''));
  c.scan(
      'SEC004',
      RegExp(r'''\bverify\s*=\s*\{?\s*["']none["']'''
          r'''|\bverifyext\s*=\s*["']none["']'''));
}

// ─────────────────────────────────────────────────────────────────────────────
// Node.js
// ─────────────────────────────────────────────────────────────────────────────

final _childProcess = RegExp(r'child_process');

void _node(_Ctx c) {
  final s = c.s;
  _common(
      c,
      r'node(?:js)?',
      RegExp(
          r'''\bchmod(?:Sync)?\s*\([^,]+,\s*(?:0o?(?:777|666)\b|["']0?(?:777|666)["'])'''));
  if (_childProcess.hasMatch(s.content)) {
    c.scan(
        'SEC002',
        RegExp(
            r'''(?:(?<![\w$.])|(?<=\b(?:child_process|cp|childProcess)\.))(?:exec|execSync)\s*\(\s*'''
            r'''(?:`[^`]*\$\{|["'][^"']*["']\s*\+|[A-Za-z_$][\w$.]*\s*\+|[A-Za-z_$][\w$]*\s*[,)])'''
            r'''|\bspawn(?:Sync)?\s*\([^)]*shell\s*:\s*true'''));
  }
  c.scan('SEC003', RegExp(r'(?<![\w$.])eval\s*\(|\bnew\s+Function\s*\('));
  c.scan(
      'SEC004',
      RegExp(r'rejectUnauthorized\s*:\s*false'
          r'''|NODE_TLS_REJECT_UNAUTHORIZED\s*(?:=|:|\]\s*=)\s*["']?0\b'''));
  c.scan('SEC006', RegExp(r'Math\.random\s*\('),
      where: (l) => RegExp(
              r'token|secret|passw|nonce|salt|api_?key|session|csrf',
              caseSensitive: false)
          .hasMatch(l));
  final esModule = RegExp(
          r'^\s*(?:import\s.+\sfrom\s|import\s*["\x27]|export\s)',
          multiLine: true)
      .hasMatch(c.code.join('\n'));
  final strict = RegExp(r'''^\s*["']use strict["']''', multiLine: true)
      .hasMatch(c.code.join('\n'));
  if (s.codeLines >= 3 &&
      !esModule &&
      !strict &&
      !s.path.toLowerCase().endsWith('.mjs') &&
      c.code.any((l) => l.contains('require('))) {
    c.add('JSROB001', 0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Unités systemd
// ─────────────────────────────────────────────────────────────────────────────

class _Key {
  final String section, name, value;
  final int line;
  const _Key(this.section, this.name, this.value, this.line);
}

/// Clés `Nom=valeur` d'un fichier d'unité, avec leur section (les lignes
/// continuées par `\` sont jointes à la première).
({List<_Key> keys, Map<String, int> sections}) _unitKeys(List<String> code) {
  final keys = <_Key>[];
  final sections = <String, int>{};
  var section = '';
  for (var i = 0; i < code.length; i++) {
    var l = code[i].trim();
    if (l.isEmpty) continue;
    final sec = RegExp(r'^\[([^\]]+)\]').firstMatch(l);
    if (sec != null) {
      section = sec[1]!;
      sections.putIfAbsent(section, () => i + 1);
      continue;
    }
    final at = l.indexOf('=');
    if (at <= 0) continue;
    final first = i + 1;
    var value = l.substring(at + 1).trim();
    while (value.endsWith('\\') && i + 1 < code.length) {
      i++;
      value = '${value.substring(0, value.length - 1)} ${code[i].trim()}';
    }
    keys.add(_Key(section, l.substring(0, at).trim(), value.trim(), first));
  }
  return (keys: keys, sections: sections);
}

const _hardening = {
  'NoNewPrivileges', 'ProtectSystem', 'ProtectHome', 'PrivateTmp', //
  'PrivateDevices', 'ProtectKernelTunables', 'ProtectKernelModules',
  'ProtectControlGroups', 'CapabilityBoundingSet', 'RestrictAddressFamilies',
  'SystemCallFilter', 'RestrictNamespaces', 'LockPersonality',
  'MemoryDenyWriteExecute', 'ProtectHostname', 'ProtectClock',
};

final _secretEnv = RegExp(
    r'(?:PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY|PRIVATE_KEY|CREDENTIAL)\w*=\S{4,}',
    caseSensitive: false);

void _systemd(_Ctx c) {
  final u = _unitKeys(c.code);
  final keys = u.keys;
  Iterable<_Key> named(String section, String name) =>
      keys.where((k) => k.section == section && k.name == name);

  final isUserUnit =
      RegExp(r'/(?:systemd/user|\.config/systemd)/').hasMatch(c.s.path);
  final start = named('Service', 'ExecStart').where((k) => k.value.isNotEmpty);

  if (u.sections.containsKey('Unit') &&
      !keys.any((k) => k.section == 'Unit' && k.name == 'Description')) {
    c.add('SDMNT001', u.sections['Unit']!);
  }
  if (start.isNotEmpty && !isUserUnit) {
    final asUser = named('Service', 'User').toList();
    final dynamic = named('Service', 'DynamicUser').any((k) => _yes(k.value));
    final root = asUser.where((k) => k.value == 'root' || k.value == '0');
    if (!dynamic && (asUser.isEmpty || root.isNotEmpty)) {
      c.add('SDSEC001', root.isNotEmpty ? root.first.line : start.first.line);
    }
    final hardened = keys.any((k) =>
        k.section == 'Service' &&
        (_hardening.contains(k.name) ||
            (k.name == 'DynamicUser' && _yes(k.value))));
    if (!hardened) c.add('SDSEC002', start.first.line);
  }
  for (final k in named('Service', 'Environment')) {
    if (_secretEnv.hasMatch(k.value) || lineHasSecret(k.value)) {
      c.add('SDSEC003', k.line, hide: true);
    }
  }
  const execs = {
    'ExecStart', 'ExecStartPre', 'ExecStartPost', 'ExecStop', //
    'ExecStopPost', 'ExecReload', 'ExecCondition',
  };
  for (final k in keys) {
    if (k.section != 'Service' || !execs.contains(k.name)) continue;
    final cmd = k.value.replaceFirst(RegExp(r'^[-@:+!]+'), '');
    if (cmd.isNotEmpty && !cmd.startsWith('/')) c.add('SDROB001', k.line);
  }
  final restart = named('Service', 'Restart').where((k) => k.value == 'always');
  if (restart.isNotEmpty && named('Service', 'RestartSec').isEmpty) {
    c.add('SDROB002', restart.first.line);
  }
  final cal = named('Timer', 'OnCalendar');
  if (cal.isNotEmpty &&
      !named('Timer', 'Persistent').any((k) => _yes(k.value))) {
    c.add('SDROB003', cal.first.line);
  }
}

bool _yes(String v) =>
    const {'yes', 'true', '1', 'on'}.contains(v.toLowerCase());

// ─────────────────────────────────────────────────────────────────────────────
// crontab
// ─────────────────────────────────────────────────────────────────────────────

final _cronEnv = RegExp(r'^([A-Za-z_]\w*)\s*=');
final _cronSpecial = RegExp(
    r'^@(?:reboot|yearly|annually|monthly|weekly|daily|midnight|hourly)\b');

/// (planification, utilisateur ou null, commande) d'une ligne de tâche.
({String schedule, String? user, String command})? _cronJob(
    String line, bool system) {
  final t = line.trim();
  final parts = <String>[];
  var rest = t;
  final need = _cronSpecial.hasMatch(t) ? 1 : 5;
  for (var i = 0; i < need; i++) {
    final m = RegExp(r'^(\S+)\s+').firstMatch(rest);
    if (m == null) return null;
    parts.add(m[1]!);
    rest = rest.substring(m.end);
  }
  String? user;
  if (system) {
    final m = RegExp(r'^(\S+)\s+').firstMatch(rest);
    if (m == null) return null;
    user = m[1];
    rest = rest.substring(m.end);
  }
  // Une planification valide ne contient que chiffres et symboles cron.
  if (need == 5 &&
      !parts.every((p) => RegExp(r'^[\d*/,\-?LW#A-Za-z]+$').hasMatch(p))) {
    return null;
  }
  return (schedule: parts.join(' '), user: user, command: rest.trim());
}

void _crontab(_Ctx c) {
  final p = c.s.path.replaceAll('\\', '/');
  var system = p.contains('/cron.d/') || p.endsWith('/etc/crontab');
  // Un fichier « crontab » hors /etc : système si une tâche nomme root.
  system = system ||
      c.code.any(
          (l) => RegExp(r'^\s*(?:@\w+|(?:\S+\s+){5})root\s+\S').hasMatch(l));
  final env = <String>{};
  for (var i = 0; i < c.code.length; i++) {
    final l = c.code[i];
    if (l.trim().isEmpty) continue;
    final e = _cronEnv.firstMatch(l.trim());
    if (e != null && !_cronJobLike(l)) {
      env.add(e[1]!);
      continue;
    }
    final job = _cronJob(l, system);
    if (job == null) continue;
    final cmd = job.command;
    final first = cmd.split(RegExp(r'\s+')).first;
    final n = i + 1;
    final bareScript =
        RegExp(r'^[\w.-]+\.(?:sh|py|pl|rb|js|php|lua)$').hasMatch(first);
    if (RegExp(r'^\.{1,2}/').hasMatch(first) ||
        (bareScript && !env.contains('PATH'))) {
      c.add('CRROB001', n);
    }
    if (RegExp(r'(?<!\\)%').hasMatch(cmd)) c.add('CRROB002', n);
    if (!cmd.contains('>') &&
        !cmd.contains('logger') &&
        !env.contains('MAILTO')) {
      c.add('CRROB003', n);
    }
    if (job.schedule == '* * * * *' &&
        !RegExp(r'\b(?:flock|lockf|lockfile|run-one|setlock|chronic)\b')
            .hasMatch(cmd)) {
      c.add('CRROB004', n);
    }
    if (RegExp(r'\b(?:curl|wget)\b[^|]*\|\s*(?:sudo\s+)?(?:ba|da|z)?sh\b')
        .hasMatch(cmd)) {
      c.add('CRSEC001', n);
    }
    final fromTmp = RegExp(r'^(?:/tmp/|/var/tmp/|/dev/shm/)').hasMatch(first);
    final rootHome =
        job.user == 'root' && RegExp(r'^(?:/home/|~/)').hasMatch(first);
    if (fromTmp || rootHome) c.add('CRSEC002', n);
    if (RegExp(
            r'--?(?:password|passwd|pass|token|secret|api-?key)(?:=|\s+)(?![$/<])\S{3,}'
            r'|\b(?:password|passwd|token|secret|api_?key)=(?![$/<])\S{3,}',
            caseSensitive: false)
        .hasMatch(cmd)) {
      c.add('CRSEC003', n, hide: true);
    }
  }
}

/// La ligne ressemble à une tâche (planification) plutôt qu'à `NOM=valeur`.
bool _cronJobLike(String l) =>
    RegExp(r'^\s*(?:@\w+\s|(?:\S+\s+){5}\S)').hasMatch(l) &&
    !RegExp(r'^\s*[A-Za-z_]\w*\s*=').hasMatch(l);

// ─────────────────────────────────────────────────────────────────────────────
// sudoers
// ─────────────────────────────────────────────────────────────────────────────

/// Commandes qui ouvrent un shell quels que soient leurs arguments.
const _escapeAlways = {
  'sh', 'bash', 'dash', 'zsh', 'ksh', 'csh', 'tcsh', 'fish', 'su', 'sudo', //
  'vi', 'vim', 'view', 'nano', 'emacs', 'ed', 'less', 'more', 'most', 'man',
  'perl', 'python', 'python2', 'python3', 'ruby', 'lua', 'node', 'php',
  'ftp', 'gdb', 'busybox', 'expect', 'screen', 'tmux', 'script',
};

/// Commandes détournables seulement sans arguments imposés.
const _escapeBare = {
  'find', 'awk', 'gawk', 'env', 'tar', 'zip', 'unzip', 'nmap', 'git', //
  'ssh', 'scp', 'rsync', 'tee', 'cp', 'mv', 'dd', 'mount', 'docker', 'podman',
  'systemctl', 'journalctl', 'strace', 'tcpdump', 'wget', 'curl', 'xargs',
  'nice', 'time', 'timeout', 'watch', 'socat', 'nc', 'ncat', 'openssl',
};

void _sudoers(_Ctx c) {
  final specRe = RegExp(r'^\s*(\S+)\s+([^\s=]+)\s*=\s*(.*)$');
  var i = 0;
  while (i < c.code.length) {
    var line = c.code[i].trim();
    final n = i + 1;
    i++;
    if (line.isEmpty) continue;
    // Lignes continuées par « \ ».
    while (line.endsWith('\\') && i < c.code.length) {
      line = '${line.substring(0, line.length - 1)} ${c.code[i].trim()}';
      i++;
    }
    if (line.startsWith('#') || line.startsWith('@')) continue;
    if (RegExp(r'^Defaults\b').hasMatch(line)) {
      if (RegExp(r'!\s*(?:env_reset|authenticate)\b').hasMatch(line) ||
          RegExp(r'\benv_keep\s*\+?=.*\b(?:LD_\w+|PATH|BASH_ENV|ENV|SHELLOPTS|PYTHON\w*|PERL\w*|RUBY\w*)\b')
              .hasMatch(line)) {
        c.add('SUSEC004', n);
      }
      continue;
    }
    if (RegExp(r'^(?:User|Runas|Host|Cmnd)_Alias\b').hasMatch(line)) continue;
    final m = specRe.firstMatch(line);
    if (m == null) continue;
    final who = m[1]!;
    final cmds = m[3]!;
    final nopassAll =
        RegExp(r'NOPASSWD\s*:(?:\s*\w+\s*:)*\s*ALL\b').hasMatch(cmds);
    if (nopassAll) {
      c.add('SUSEC001', n);
    } else if (RegExp(r'^(?:\([^)]*\)\s*)?(?:\w+\s*:\s*)*ALL\s*$')
            .hasMatch(cmds) &&
        who != 'root' &&
        !who.startsWith('%') &&
        !who.startsWith('+') &&
        !RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(who)) {
      c.add('SUSEC002', n);
    }
    final list = [
      for (final part
          in cmds.replaceFirst(RegExp(r'^\([^)]*\)\s*'), '').split(','))
        part.trim().replaceFirst(RegExp(r'^(?:[A-Z_]+\s*:\s*)+'), '')
    ];
    if (list.any((p) => p != 'ALL' && RegExp(r'/\S*\*|\s\S*\*').hasMatch(p))) {
      c.add('SUSEC003', n);
    }
    if (list.any(_escapesToShell)) c.add('SUSEC005', n);
  }
}

bool _escapesToShell(String command) {
  final words = command.split(RegExp(r'\s+'));
  if (words.isEmpty || words.first.isEmpty) return false;
  final name = words.first.split('/').last;
  if (_escapeAlways.contains(name)) return true;
  return _escapeBare.contains(name) && words.length == 1;
}
