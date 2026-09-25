/// Scripts shell intégrés à d'autres fichiers : blocs `run:` de GitHub
/// Actions, `script:` de GitLab CI, `RUN` de Dockerfile, recettes de
/// Makefile, tâches `shell:` d'Ansible.
///
/// Les blocs sont rassemblés en un script virtuel qui a autant de lignes que
/// le fichier d'origine : chaque ligne de shell garde son numéro, les autres
/// sont vides. Les problèmes désignent donc directement le fichier d'origine.
/// Les expressions du fichier hôte (`${{ … }}`, `{{ … }}`, `$(VAR)` de make)
/// sont remplacées par un mot neutre de même longueur.
library;

import 'package:yaml/yaml.dart';

import 'script_info.dart' show Dialect;

/// Type de fichier hôte.
enum EmbeddedKind {
  githubActions('GitHub Actions'),
  gitlabCi('GitLab CI'),
  dockerfile('Dockerfile'),
  makefile('Makefile'),
  ansible('Ansible');

  const EmbeddedKind(this.label);
  final String label;

  static EmbeddedKind? tryParse(String s) {
    for (final k in values) {
      if (k.name == s) return k;
    }
    return null;
  }
}

/// Bloc de shell dans le fichier hôte (lignes 1-based, bornes incluses).
class EmbeddedBlock {
  final int line, endLine;
  const EmbeddedBlock(this.line, this.endLine);
}

/// Problème visible seulement dans le fichier hôte, avant le remplacement
/// de ses expressions : expression GitHub non fiable (SEC023), variable de
/// make dans un `rm -r` (SEC007).
class EmbeddedIssue {
  final String ruleId;
  final int line, column;
  final String detail;
  const EmbeddedIssue(this.ruleId, this.line, this.column, this.detail);
}

class EmbeddedScript {
  final EmbeddedKind kind;
  final Dialect dialect;

  /// Script virtuel : une entrée par ligne du fichier hôte.
  final List<String> lines;

  /// Lignes du fichier hôte.
  final List<String> source;
  final List<EmbeddedBlock> blocks;

  /// L'environnement d'exécution active déjà `pipefail` (GitHub Actions,
  /// `SHELL [… "-o", "pipefail" …]` d'un Dockerfile).
  final bool pipefail;
  final List<EmbeddedIssue> issues;

  const EmbeddedScript(
      this.kind, this.dialect, this.lines, this.source, this.blocks,
      {this.pipefail = false, this.issues = const []});

  /// Lignes où chercher les directives `# check-script` : le shell, plus les
  /// commentaires du fichier hôte (une directive peut précéder `run:`).
  List<String> get directiveLines => [
        for (var i = 0; i < lines.length; i++)
          lines[i].isEmpty && source[i].trimLeft().startsWith('#')
              ? source[i]
              : lines[i],
      ];
}

const _scriptExt = {'.sh', '.bash', '.ksh', '.dash', '.zsh', '.py', '.pyw'};

final _ansibleShell = RegExp(
    r'^\s*(?:-\s+)?(?:ansible\.(?:builtin|legacy)\.)?shell\s*:',
    multiLine: true);

/// Type de fichier hôte d'après le chemin seul (null : pas un fichier hôte
/// reconnaissable sans lire son contenu).
EmbeddedKind? embeddedKindForPath(String path) {
  final p = path.replaceAll('\\', '/');
  final base = p.split('/').last;
  final lower = base.toLowerCase();
  final dot = lower.lastIndexOf('.');
  final ext = dot <= 0 ? '' : lower.substring(dot);
  if (_scriptExt.contains(ext)) return null;
  final yaml = ext == '.yml' || ext == '.yaml';
  if (yaml &&
      (p.contains('/.github/workflows/') ||
          p.startsWith('.github/workflows/'))) {
    return EmbeddedKind.githubActions;
  }
  if (lower == 'action.yml' || lower == 'action.yaml') {
    return EmbeddedKind.githubActions;
  }
  if (lower == '.gitlab-ci.yml' || lower.endsWith('.gitlab-ci.yml')) {
    return EmbeddedKind.gitlabCi;
  }
  if (yaml && (p.contains('/.gitlab/') || p.startsWith('.gitlab/'))) {
    return EmbeddedKind.gitlabCi;
  }
  if (lower == 'dockerfile' ||
      lower == 'containerfile' ||
      lower.startsWith('dockerfile.') ||
      lower.startsWith('containerfile.') ||
      lower.endsWith('.dockerfile') ||
      lower.endsWith('.containerfile')) {
    return EmbeddedKind.dockerfile;
  }
  if (lower == 'makefile' ||
      lower == 'gnumakefile' ||
      ext == '.mk' ||
      ext == '.make') {
    return EmbeddedKind.makefile;
  }
  return null;
}

/// Type de fichier hôte d'après le chemin et le contenu (Ansible : fichier
/// YAML contenant une tâche `shell:`). Un script (extension de script, ou
/// shebang d'un interpréteur autre que make) n'est pas un fichier hôte.
EmbeddedKind? detectEmbedded(String path, String content) {
  if (content.startsWith('#!')) {
    final first = content.split('\n').first;
    return RegExp(r'\bmake\b').hasMatch(first) ? EmbeddedKind.makefile : null;
  }
  final kind = embeddedKindForPath(path);
  if (kind != null) return kind;
  final lower = path.toLowerCase();
  if ((lower.endsWith('.yml') || lower.endsWith('.yaml')) &&
      _ansibleShell.hasMatch(content)) {
    return EmbeddedKind.ansible;
  }
  return null;
}

/// Extrait les blocs de shell de [content] (fins de ligne déjà normalisées).
/// Un document YAML invalide donne un script sans bloc.
EmbeddedScript extractEmbedded(EmbeddedKind kind, String content) {
  var source = content.split('\n');
  if (source.isNotEmpty && source.last.isEmpty) {
    source = source.sublist(0, source.length - 1);
  }
  final b = _Builder(kind, source);
  switch (kind) {
    case EmbeddedKind.githubActions:
      b.github();
    case EmbeddedKind.gitlabCi:
      b.gitlab();
    case EmbeddedKind.ansible:
      b.ansible();
    case EmbeddedKind.dockerfile:
      b.dockerfile();
    case EmbeddedKind.makefile:
      b.makefile();
  }
  return b.build();
}

/// Remplace chaque correspondance de [re] par un mot neutre de même longueur.
String _mask(String s, RegExp re) =>
    s.replaceAllMapped(re, (m) => 'x' * m[0]!.length);

/// `rm -r` sur un chemin qui commence par une variable de make : si elle est
/// vide, la commande vise la racine.
final _makeRm = RegExp(
    r'\brm\s+(?:-\w+\s+)*-[a-zA-Z]*[rR][a-zA-Z]*\s+(?:\S+\s+)*?"?(\$[({]\w+[)}])/');

final _ghExpr = RegExp(r'\$\{\{.*?\}\}');
final _jinja = RegExp(r'\{\{.*?\}\}|\{%.*?%\}|\{#.*?#\}');

/// Contextes GitHub contrôlables par un tiers (titre d'issue, corps de pull
/// request, nom de branche, message de commit…).
final _untrusted = RegExp(r'github\.head_ref\b|github\.event\.[\w.*\[\]-]*?'
    r'\b(?:title|body|message|head_ref|head_branch|label|ref|page_name|'
    r'display_title|default_branch|email|name)\b');

class _Builder {
  _Builder(this.kind, this.source)
      : lines = List.filled(source.length, '', growable: false);

  final EmbeddedKind kind;
  final List<String> source;
  final List<String> lines;
  final blocks = <EmbeddedBlock>[];
  final issues = <EmbeddedIssue>[];
  var bash = false, sh = false, pipefail = false;

  EmbeddedScript build() => EmbeddedScript(
      kind,
      bash || !sh ? Dialect.bash : Dialect.sh,
      List.unmodifiable(lines),
      List.unmodifiable(source),
      List.unmodifiable(blocks),
      pipefail: pipefail,
      issues: List.unmodifiable(issues));

  void _shell(String? name) {
    if (name == 'sh' || name == 'dash') {
      sh = true;
    } else {
      bash = true;
    }
  }

  // ── YAML ──────────────────────────────────────────────────────────────────

  YamlNode? _load() {
    try {
      return loadYamlNode(source.join('\n'));
    } on Object {
      return null; // YAML invalide ou étiquettes inconnues
    }
  }

  /// Place le scalaire [node] (un script) dans le script virtuel.
  void _scalar(YamlNode? node, {RegExp? expressions, bool github = false}) {
    if (node is! YamlScalar || node.value is! String) return;
    final value = node.value as String;
    if (value.trim().isEmpty) return;
    final start = node.span.start;
    final block =
        node.style == ScalarStyle.LITERAL || node.style == ScalarStyle.FOLDED;
    var first = block ? start.line + 1 : start.line;
    final parts = value.split('\n');
    // Colonne du texte dans le fichier : indentation du bloc, ou position
    // de la valeur (après le guillemet ouvrant).
    var column = start.column +
        (node.style == ScalarStyle.DOUBLE_QUOTED ||
                node.style == ScalarStyle.SINGLE_QUOTED
            ? 1
            : 0);
    if (block) {
      // Lignes vides en tête du bloc : la première ligne de texte fixe
      // l'indentation.
      while (first < source.length && source[first].trim().isEmpty) {
        first++;
        if (parts.isNotEmpty && parts.first.isEmpty) parts.removeAt(0);
      }
      if (first >= source.length) return;
      column = source[first].length - source[first].trimLeft().length;
    }
    var last = first;
    for (var i = 0; i < parts.length && first + i < source.length; i++) {
      final text = parts[i];
      if (text.isEmpty) continue;
      final n = first + i;
      if (github) {
        for (final m in _ghExpr.allMatches(text)) {
          if (_untrusted.hasMatch(m[0]!)) {
            issues.add(EmbeddedIssue(
                'SEC023', n + 1, column + m.start + 1, m[0]!.trim()));
          }
        }
      }
      lines[n] = expressions == null ? text : _mask(text, expressions);
      last = n;
    }
    blocks.add(EmbeddedBlock(first + 1, last + 1));
  }

  static Object? _get(YamlNode? n, String key) =>
      n is YamlMap ? n.nodes[key] : null;

  static String? _shellName(Object? n) {
    final v = n is YamlScalar ? n.value : null;
    if (v is! String) return null;
    final exe = v.trim().split(RegExp(r'\s+')).first.split('/').last;
    return exe;
  }

  void github() {
    final doc = _load();
    if (doc is! YamlMap) return;
    String? defaults(YamlNode? n) => _shellName(_get(
        _get(_get(n, 'defaults') as YamlNode?, 'run') as YamlNode?, 'shell'));
    final wf = defaults(doc);
    void steps(Object? list, String? shell, bool windows) {
      if (list is! YamlList) return;
      for (final step in list.nodes) {
        final run = _get(step, 'run');
        if (run == null) continue;
        final s = _shellName(_get(step, 'shell')) ??
            shell ??
            (windows ? 'pwsh' : 'bash');
        if (s != 'bash' && s != 'sh') continue; // pwsh, python, cmd…
        _shell(s);
        _scalar(run as YamlNode, expressions: _ghExpr, github: true);
      }
    }

    // Workflow.
    final jobs = _get(doc, 'jobs');
    if (jobs is YamlMap) {
      for (final job in jobs.nodes.values) {
        final runsOn = _get(job, 'runs-on');
        final windows = runsOn is YamlNode &&
            '${runsOn is YamlScalar ? runsOn.value : runsOn}'
                .toLowerCase()
                .contains('windows');
        steps(_get(job, 'steps'), defaults(job) ?? wf, windows);
      }
    }
    // Action composite : le shell de chaque étape est obligatoire.
    steps(_get(_get(doc, 'runs') as YamlNode?, 'steps'), null, false);
    pipefail = true; // bash -eo pipefail {0}
  }

  static const _gitlabReserved = {
    'variables', 'stages', 'include', 'workflow', 'image', 'services', //
    'cache', 'spec',
  };

  void gitlab() {
    final doc = _load();
    if (doc is! YamlMap) return;
    void scripts(YamlNode? job) {
      for (final key in const ['before_script', 'script', 'after_script']) {
        final v = _get(job, key);
        if (v is YamlList) {
          for (final item in v.nodes) {
            _scalar(item); // les listes imbriquées (!reference) sont ignorées
          }
        } else {
          _scalar(v as YamlNode?);
        }
      }
    }

    // before_script / after_script globaux (anciens), puis default: et jobs.
    scripts(doc);
    doc.nodes.forEach((k, v) {
      final name = k is YamlScalar ? '${k.value}' : '$k';
      if (_gitlabReserved.contains(name) || v is! YamlMap) return;
      if (name.endsWith('_script') || name == 'script') return;
      scripts(v);
    });
    bash = true;
  }

  static const _ansibleKeys = {
    'shell',
    'ansible.builtin.shell',
    'ansible.legacy.shell',
  };

  void ansible() {
    final doc = _load();
    if (doc == null) return;
    void walk(YamlNode n) {
      if (n is YamlList) {
        n.nodes.forEach(walk);
        return;
      }
      if (n is! YamlMap) return;
      for (final e in n.nodes.entries) {
        final key = e.key is YamlScalar ? '${(e.key as YamlScalar).value}' : '';
        if (_ansibleKeys.contains(key)) {
          final v = e.value;
          final args = _get(n, 'args') as YamlNode?;
          final exe = _shellName(_get(v, 'executable')) ??
              _shellName(_get(args, 'executable'));
          _shell(exe != null && exe.contains('bash') ? 'bash' : 'sh');
          _scalar(v is YamlMap ? v.nodes['cmd'] : v, expressions: _jinja);
          continue;
        }
        walk(e.value);
      }
    }

    walk(doc);
  }

  // ── Dockerfile ────────────────────────────────────────────────────────────

  void dockerfile() {
    var escape = '\\';
    final directive = RegExp(r'^#\s*escape\s*=\s*(\S)', caseSensitive: false);
    for (final l in source.take(5)) {
      final m = directive.firstMatch(l);
      if (m != null) escape = m[1]!;
      if (!l.startsWith('#')) break;
    }
    String? shell = 'sh';
    var i = 0;
    while (i < source.length) {
      final line = source[i];
      final t = line.trimLeft();
      if (t.isEmpty || t.startsWith('#')) {
        i++;
        continue;
      }
      // Instruction et ses lignes de continuation.
      var end = i;
      while (
          end < source.length - 1 && source[end].trimRight().endsWith(escape)) {
        end++;
        // Les commentaires et lignes vides d'une continuation sont ignorés
        // par Docker.
        while (end < source.length - 1 &&
            (source[end].trim().isEmpty ||
                source[end].trimLeft().startsWith('#'))) {
          end++;
        }
      }
      final m = RegExp(r'^(\s*)([A-Za-z]+)(\s+|$)').firstMatch(line);
      final instr = m?[2]!.toUpperCase();
      if (instr == 'SHELL') {
        final text = source.sublist(i, end + 1).join(' ');
        final words = RegExp(r'"([^"]*)"').allMatches(text).map((x) => x[1]!);
        final exe = words.isEmpty ? null : words.first.split('/').last;
        shell = exe == 'bash' || exe == 'sh' || exe == 'dash' ? exe : null;
        pipefail = words.contains('pipefail');
      } else if (instr == 'RUN' && shell != null) {
        end = _dockerRun(i, end, m!.end, shell);
      }
      i = end + 1;
    }
  }

  /// Place l'instruction RUN des lignes [start]..[end] ; renvoie la dernière
  /// ligne consommée (heredoc compris).
  int _dockerRun(int start, int end, int offset, String shell) {
    final line = source[start];
    var rest = line.substring(offset);
    var col = offset;
    // Options de RUN (--mount=…, --network=…).
    final opts = RegExp(r'^(?:--\S+\s+)+').firstMatch(rest);
    if (opts != null) {
      col += opts.end;
      rest = rest.substring(opts.end);
    }
    if (rest.startsWith('[')) return end; // forme exec : pas de shell
    _shell(shell);
    final heredoc =
        RegExp(r'''^<<(-?)(["']?)(\w+)\2''').firstMatch(rest.trimRight());
    if (heredoc != null) {
      final strip = heredoc[1] == '-';
      final word = heredoc[3]!;
      var j = start + 1;
      final first = j;
      while (
          j < source.length && (strip ? source[j].trim() : source[j]) != word) {
        lines[j] = source[j];
        j++;
      }
      if (first < j) {
        final shebang = source[first];
        if (shebang.startsWith('#!')) {
          _shell(shebang.contains('bash') ? 'bash' : 'sh');
        }
        blocks.add(EmbeddedBlock(first + 1, j));
      }
      return j < source.length ? j : source.length - 1;
    }
    lines[start] = ' ' * col + rest;
    for (var j = start + 1; j <= end; j++) {
      final t = source[j].trimLeft();
      lines[j] = t.isEmpty || t.startsWith('#') ? '' : source[j];
    }
    blocks.add(EmbeddedBlock(start + 1, end + 1));
    return end;
  }

  // ── Makefile ──────────────────────────────────────────────────────────────

  void makefile() {
    final assign =
        RegExp(r'^\s*(?:override\s+|export\s+)?SHELL\s*[:?+!]?=\s*(\S+)');
    final rule = RegExp(r'^[^\s#=:][^=]*?(?<![:?+!])::?(?!=)');
    final directive = RegExp(
        r'^\s*(?:ifeq|ifneq|ifdef|ifndef|else|endif|include|-include|sinclude)\b');
    var inRule = false, inDefine = false;
    var i = 0;
    while (i < source.length) {
      final line = source[i];
      if (inDefine) {
        if (RegExp(r'^\s*endef\b').hasMatch(line)) inDefine = false;
        i++;
        continue;
      }
      if (line.startsWith('\t') && inRule) {
        var end = i;
        while (end < source.length - 1 && source[end].endsWith('\\')) {
          end++;
        }
        for (var j = i; j <= end; j++) {
          var text = source[j];
          var col = 0;
          if (text.startsWith('\t')) {
            text = text.substring(1);
            col = 1;
          }
          if (j == i) {
            final prefix = RegExp(r'^[@+\-\s]*').firstMatch(text)!;
            text = ' ' * (col + prefix.end) + text.substring(prefix.end);
          } else {
            text = ' ' * col + text;
          }
          final rm = _makeRm.firstMatch(text);
          if (rm != null) {
            issues.add(EmbeddedIssue('SEC007', j + 1, rm.start + 1, rm[1]!));
          }
          lines[j] = _unmake(text);
        }
        blocks.add(EmbeddedBlock(i + 1, end + 1));
        i = end + 1;
        continue;
      }
      final t = line.trim();
      final a = assign.firstMatch(line);
      if (a != null) _shell(a[1]!.split('/').last);
      if (RegExp(r'^\s*define\b').hasMatch(line)) {
        inDefine = true;
      } else if (t.isNotEmpty &&
          !t.startsWith('#') &&
          !directive.hasMatch(line)) {
        inRule = rule.hasMatch(line);
      }
      i++;
    }
    if (!bash) sh = true;
  }

  /// Ligne de recette telle que le shell la reçoit : `$$` → `$`, expansions
  /// de make (`$(VAR)`, `${VAR}`, `$@`) remplacées par un mot neutre.
  static String _unmake(String s) {
    final b = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c != r'$' || i + 1 >= s.length) {
        b.write(c);
        i++;
        continue;
      }
      final n = s[i + 1];
      if (n == r'$') {
        b.write(r'$');
        i += 2;
      } else if (n == '(' || n == '{') {
        final close = n == '(' ? ')' : '}';
        var depth = 0, j = i + 1;
        for (; j < s.length; j++) {
          if (s[j] == n) depth++;
          if (s[j] == close && --depth == 0) break;
        }
        final len = (j < s.length ? j + 1 : s.length) - i;
        b.write('x' * len);
        i += len;
      } else {
        b.write('xx');
        i += 2;
      }
    }
    return b.toString();
  }
}
