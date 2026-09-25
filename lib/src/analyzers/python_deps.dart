/// Dépendances des scripts Python : imports introuvables (PYROB005),
/// dépendances tierces non déclarées dans le projet (PYPOR002), paquets
/// vulnérables (pip-audit, facultatif).
///
/// Les imports sont classés par l'interpréteur (bibliothèque standard,
/// module local, paquet installé, introuvable) sans être exécutés
/// (`importlib.util.find_spec`). Les dépendances déclarées viennent du
/// projet (requirements*.txt, pyproject.toml, setup.cfg, Pipfile) ou de
/// l'en-tête PEP 723 du script.
library;

import 'dart:convert';
import 'dart:io';

import '../config.dart';
import '../i18n.dart';
import '../model/finding.dart';
import '../rules/catalog.dart';
import 'analyzer.dart';
import 'external_tools.dart' show pythonExecutable;

/// Classement des imports ; écrit une liste JSON (un élément par module de
/// premier niveau, dans l'ordre des lignes).
const pythonImportsScript = r'''
import ast, json, os, sys, importlib.util
path, base = sys.argv[1], sys.argv[2]
tree = ast.parse(open(path, "rb").read())
if base:
    sys.path.insert(0, base)
std = getattr(sys, "stdlib_module_names", None)
try:
    from importlib.metadata import packages_distributions
    dists = packages_distributions()
except Exception:
    dists = {}
optional = set()
for n in ast.walk(tree):
    if not isinstance(n, ast.Try):
        continue
    caught = set()
    for h in n.handlers:
        types = h.type.elts if isinstance(h.type, ast.Tuple) else [h.type]
        for t in types:
            caught.add("*" if t is None else getattr(t, "id", getattr(t, "attr", "")))
    if caught & {"*", "ImportError", "ModuleNotFoundError", "Exception", "BaseException"}:
        for s in n.body:
            optional.update(id(m) for m in ast.walk(s))
nodes = sorted((n for n in ast.walk(tree)
                if isinstance(n, ast.Import)
                or (isinstance(n, ast.ImportFrom) and n.level == 0 and n.module)),
               key=lambda n: (n.lineno, n.col_offset))
out, seen = [], set()
for n in nodes:
    names = [a.name for a in n.names] if isinstance(n, ast.Import) else [n.module]
    for name in names:
        top = name.split(".")[0]
        if top in seen or top == "__future__":
            continue
        seen.add(top)
        if top in sys.builtin_module_names or (std is not None and top in std):
            status = "stdlib"
        elif base and (os.path.exists(os.path.join(base, top + ".py"))
                       or os.path.isdir(os.path.join(base, top))):
            status = "local"
        else:
            try:
                spec = importlib.util.find_spec(top)
            except Exception:
                spec = None
            if spec is None:
                status = "missing"
            else:
                origin = spec.origin or ""
                status = "installed"
                if std is None and "-packages" not in origin:
                    status = "stdlib"
        out.append({"module": top, "line": n.lineno, "column": n.col_offset + 1,
                    "status": status, "optional": id(n) in optional,
                    "dists": dists.get(top, [])})
print(json.dumps(out))
''';

class PythonImport {
  final String module;
  final int line, column;

  /// `stdlib`, `local`, `installed` ou `missing`.
  final String status;

  /// Import placé dans un `try` qui intercepte ImportError.
  final bool optional;

  /// Distributions installées qui fournissent le module.
  final List<String> dists;

  const PythonImport(this.module, this.line, this.column, this.status,
      {this.optional = false, this.dists = const []});

  static List<PythonImport> parse(String json) => [
        for (final j in jsonDecode(json) as List)
          if (j is Map)
            PythonImport(
              '${j['module']}',
              (j['line'] as num).toInt(),
              (j['column'] as num?)?.toInt() ?? 0,
              '${j['status']}',
              optional: j['optional'] == true,
              dists: [for (final d in j['dists'] as List? ?? const []) '$d'],
            ),
      ];
}

/// Nom de distribution normalisé (PEP 503).
String normalizeDist(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[-_.]+'), '-');

/// Modules dont la distribution porte un autre nom (quand elle n'est pas
/// installée, l'interpréteur ne peut pas le dire).
const Map<String, String> moduleDistributions = {
  'yaml': 'pyyaml',
  'PIL': 'pillow',
  'cv2': 'opencv-python',
  'sklearn': 'scikit-learn',
  'skimage': 'scikit-image',
  'bs4': 'beautifulsoup4',
  'dateutil': 'python-dateutil',
  'dotenv': 'python-dotenv',
  'jwt': 'pyjwt',
  'Crypto': 'pycryptodome',
  'Cryptodome': 'pycryptodomex',
  'OpenSSL': 'pyopenssl',
  'magic': 'python-magic',
  'serial': 'pyserial',
  'usb': 'pyusb',
  'git': 'gitpython',
  'attr': 'attrs',
  'zmq': 'pyzmq',
  'docx': 'python-docx',
  'pptx': 'python-pptx',
  'ldap': 'python-ldap',
  'gi': 'pygobject',
  'dns': 'dnspython',
  'nmap': 'python-nmap',
  'MySQLdb': 'mysqlclient',
  'google': 'protobuf',
  'fitz': 'pymupdf',
  'win32api': 'pywin32',
  'Levenshtein': 'python-levenshtein',
  'slugify': 'python-slugify',
  'telegram': 'python-telegram-bot',
  'socks': 'pysocks',
  'kafka': 'kafka-python',
  'jose': 'python-jose',
  'multipart': 'python-multipart',
};

/// Noms de distribution possibles pour un import.
Set<String> distCandidates(PythonImport i) => {
      for (final d in i.dists) normalizeDist(d),
      if (moduleDistributions[i.module] case final d?) d,
      normalizeDist(i.module),
    };

/// Le module est couvert par une dépendance déclarée (`psycopg2` par
/// `psycopg2-binary`, `foo` par `foo-extras`…).
bool isDeclared(PythonImport i, Set<String> declared) {
  final c = distCandidates(i);
  return c.any(declared.contains) ||
      declared.any((d) => c.any((x) => d.startsWith('$x-')));
}

// ── Dépendances déclarées ─────────────────────────────────────────────────

/// Fichiers de dépendances d'un projet et environnement virtuel.
class PythonProject {
  /// Fichiers de déclaration trouvés (dossier le plus proche du script).
  final List<File> files;

  /// Fichiers requirements (pip-audit).
  List<File> get requirements => [
        for (final f in files)
          if (f.path.endsWith('.txt')) f
      ];

  const PythonProject(this.files);

  static final _reqName = RegExp(r'^requirements[\w.-]*\.txt$');

  /// Projet du script [scriptPath] : premier dossier, en remontant jusqu'à
  /// la racine git, qui déclare des dépendances.
  static PythonProject find(String scriptPath) {
    var dir = File(scriptPath).absolute.parent;
    while (true) {
      final found = <File>[];
      try {
        for (final e in dir.listSync()) {
          if (e is! File) continue;
          final name = e.uri.pathSegments.last;
          if (_reqName.hasMatch(name) ||
              name == 'pyproject.toml' ||
              name == 'setup.cfg' ||
              name == 'Pipfile') {
            found.add(e);
          }
        }
        final sub = Directory('${dir.path}/requirements');
        if (sub.existsSync()) {
          found.addAll(sub
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.txt')));
        }
      } on FileSystemException {
        // Dossier illisible : on remonte.
      }
      found.sort((a, b) => a.path.compareTo(b.path));
      if (found.isNotEmpty) return PythonProject(found);
      if (FileSystemEntity.typeSync('${dir.path}/.git') !=
          FileSystemEntityType.notFound) {
        return const PythonProject([]);
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return const PythonProject([]);
      dir = parent;
    }
  }

  /// Dépendances déclarées (noms normalisés).
  Set<String> declared() => {
        for (final f in files)
          ...declaredIn(f.uri.pathSegments.last, _read(f), dir: f.parent.path),
      };

  static String _read(File f) {
    try {
      return f.readAsStringSync();
    } on Object {
      return '';
    }
  }
}

final _requirement = RegExp(r'^\s*([A-Za-z0-9][A-Za-z0-9._-]*)');

/// Nom d'une exigence (`requests[socks]>=2 ; python_version<"3.9"`).
String? requirementName(String spec) {
  final t = spec.trim().replaceFirst(RegExp(r'^(?:-e|--editable)[ =]\s*'), '');
  if (t.isEmpty || t.startsWith('#') || t.startsWith('-')) return null;
  if (RegExp(r'^[\w+]+://').hasMatch(t)) {
    final egg = RegExp(r'#egg=([\w.-]+)').firstMatch(t);
    return egg == null ? null : normalizeDist(egg[1]!);
  }
  final at = RegExp(r'^([A-Za-z0-9][\w.-]*)\s*@').firstMatch(t);
  if (at != null) return normalizeDist(at[1]!);
  final m = _requirement.firstMatch(t);
  return m == null ? null : normalizeDist(m[1]!);
}

/// Dépendances d'un fichier de déclaration d'après son nom ; [dir] sert aux
/// inclusions `-r autre.txt` des requirements (un niveau).
Set<String> declaredIn(String name, String content, {String? dir}) {
  final out = <String>{};
  if (name.endsWith('.txt')) {
    for (final l in content.split('\n')) {
      final line = l.split(' #').first;
      final inc =
          RegExp(r'^\s*(?:-r|--requirement)[ =]\s*(\S+)').firstMatch(line);
      if (inc != null && dir != null) {
        final f = File('$dir/${inc[1]}');
        if (f.existsSync()) {
          out.addAll(declaredIn('x.txt', f.readAsStringSync()));
        }
        continue;
      }
      final n = requirementName(line);
      if (n != null) out.add(n);
    }
  } else if (name == 'pyproject.toml' || name == 'Pipfile') {
    out.addAll(_tomlDependencies(content));
  } else if (name == 'setup.cfg') {
    var inList = false;
    for (final l in content.split('\n')) {
      if (RegExp(r'^\s*install_requires\s*=').hasMatch(l)) {
        inList = true;
        final rest = l.split('=').skip(1).join('=');
        final n = requirementName(rest);
        if (n != null) out.add(n);
        continue;
      }
      if (!inList || l.trim().isEmpty) continue;
      if (!l.startsWith(RegExp(r'\s'))) {
        inList = false; // fin de la liste (clé suivante)
        continue;
      }
      final n = requirementName(l);
      if (n != null) out.add(n);
    }
  }
  return out;
}

/// Dépendances d'un document TOML (pyproject.toml, Pipfile, en-tête PEP
/// 723) : listes `dependencies = [...]`, tables d'extras et de groupes,
/// tables `[tool.poetry.*dependencies]` et `[packages]` de Pipfile.
Set<String> _tomlDependencies(String toml) {
  final out = <String>{};
  String? table;
  var inArray = false;
  final tableHeader = RegExp(r'^\s*\[\[?([^\]]+)\]\]?\s*$');
  final nameTables = RegExp(
      r'^(?:tool\.poetry(?:\.group\.[\w-]+)?\.(?:dev-)?dependencies|packages|dev-packages)$');
  final listTables =
      RegExp(r'^(?:project\.optional-dependencies|dependency-groups)$');
  void strings(String s) {
    for (final m in RegExp(r'''["']([^"']+)["']''').allMatches(s)) {
      final n = requirementName(m[1]!);
      if (n != null) out.add(n);
    }
  }

  for (final raw in toml.split('\n')) {
    final l = raw.replaceFirst(RegExp(r'\s+#.*$'), '');
    if (inArray) {
      strings(l.split(']').first);
      if (l.contains(']')) inArray = false;
      continue;
    }
    final h = tableHeader.firstMatch(l);
    if (h != null) {
      table = h[1]!.trim();
      continue;
    }
    final kv = RegExp(r'^\s*([\w."-]+)\s*=\s*(.*)$').firstMatch(l);
    if (kv == null) continue;
    final key = kv[1]!.replaceAll('"', '');
    final value = kv[2]!;
    final isList = value.startsWith('[');
    if (table != null && nameTables.hasMatch(table)) {
      if (key != 'python') out.add(normalizeDist(key));
    } else if ((key == 'dependencies' &&
            (table == null || table == 'project')) ||
        (table != null && listTables.hasMatch(table) && isList)) {
      if (isList) {
        strings(value.split(']').first);
        inArray = !value.contains(']');
      }
    }
  }
  return out;
}

/// Dépendances de l'en-tête PEP 723 (`# /// script` … `# ///`), ou null si
/// le script n'en a pas.
Set<String>? inlineDependencies(List<String> lines) {
  final start = lines.indexWhere((l) => l.trim() == '# /// script');
  if (start < 0) return null;
  final body = <String>[];
  for (final l in lines.skip(start + 1)) {
    if (l.trim() == '# ///') break;
    if (!l.startsWith('#')) return null;
    body.add(l.length > 1 ? l.substring(l.startsWith('# ') ? 2 : 1) : '');
  }
  return _tomlDependencies(body.join('\n'));
}

// ── Analyseurs ────────────────────────────────────────────────────────────

/// Imports introuvables et dépendances non déclarées.
class PythonDepsAnalyzer extends Analyzer {
  @override
  String get name => 'pydeps';

  @override
  ToolLanguage get language => ToolLanguage.python;

  /// Interpréteur : `tools.pydeps.path`, sinon celui de l'environnement
  /// virtuel actif (`VIRTUAL_ENV`), sinon python3. Celui d'un `.venv` du
  /// projet analysé n'est jamais lancé de lui-même : le dépôt peut être
  /// étranger.
  static String interpreter(CheckConfig config) {
    final exe = config.tool('pydeps').executable;
    if (exe.isNotEmpty) return exe;
    final venv = Platform.environment['VIRTUAL_ENV'];
    if (venv != null && File('$venv/bin/python').existsSync()) {
      return '$venv/bin/python';
    }
    return pythonExecutable;
  }

  @override
  Future<String?> version(CommandRunner runner, CheckConfig config) async {
    final r = await runner.run(interpreter(config), ['--version']);
    return r == null ? null : extractVersion('${r.stdout}${r.stderr}') ?? '?';
  }

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final real = File(ctx.script.path).existsSync();
    final base = real ? File(ctx.script.path).absolute.parent.path : '';
    final r = await ctx.run(interpreter(ctx.config),
        ['-c', pythonImportsScript, ctx.filePath, base]);
    if (r == null) return AnalyzerResult(ToolRun(name, ToolStatus.missing));
    // Erreur de syntaxe : signalée par le contrôle de syntaxe.
    if (r.exitCode != 0) {
      return AnalyzerResult(ToolRun(name, ToolStatus.skipped,
          detail: r.stderr.trim().split('\n').last));
    }
    final List<PythonImport> imports;
    try {
      imports = PythonImport.parse(r.stdout.trim());
    } on Object catch (e) {
      return AnalyzerResult(ToolRun(name, ToolStatus.failed, detail: '$e'));
    }
    final inline = inlineDependencies(ctx.script.lines);
    final project = real ? PythonProject.find(ctx.script.path) : null;
    final declared = inline ??
        (project == null || project.files.isEmpty ? null : project.declared());
    final findings = checkImports(imports, declared, ctx.lang);
    return AnalyzerResult(
        ToolRun(name, ToolStatus.ok,
            findings: findings.length,
            detail: inline != null
                ? 'PEP 723'
                : project == null || project.files.isEmpty
                    ? null
                    : project.files
                        .map((f) => f.uri.pathSegments.last)
                        .join(', ')),
        findings);
  }
}

/// Problèmes des [imports] : sans déclaration ([declared] null), seuls les
/// modules introuvables sont signalés ; avec, aussi les paquets installés
/// mais non déclarés. Un module déclaré mais absent de l'environnement
/// d'analyse n'est pas un défaut du script.
List<Finding> checkImports(
    List<PythonImport> imports, Set<String>? declared, Lang lang) {
  final out = <Finding>[];
  void add(String id, PythonImport i) {
    final r = ruleInfo(id);
    out.add(Finding(
      tool: 'pydeps',
      ruleId: id,
      category: r.category,
      severity: r.severity,
      line: i.line,
      column: i.column,
      message: '${r.title.of(lang)} (${i.module})',
      hint: r.fix.of(lang),
    ));
  }

  for (final i in imports) {
    if (i.status == 'stdlib' || i.status == 'local') continue;
    final ok = declared != null && isDeclared(i, declared);
    if (ok) continue;
    if (i.status == 'missing') {
      if (!i.optional) add('PYROB005', i);
    } else if (declared != null) {
      add('PYPOR002', i);
    }
  }
  return out;
}

/// Vulnérabilités connues des dépendances déclarées dans les requirements
/// du projet (pip-audit, sans installation quand les versions sont
/// épinglées) ; signalées sur l'import du paquet concerné.
class PipAuditAnalyzer extends Analyzer {
  @override
  String get name => 'pip-audit';

  @override
  ToolLanguage get language => ToolLanguage.python;

  /// Résultats par fichier requirements (et date de modification) : un
  /// seul audit pour tous les scripts d'un projet.
  static final _audits = <String, Future<CommandResult?>>{};

  @override
  Future<String?> version(CommandRunner runner, CheckConfig config) async {
    final r = await runner.run(config.tool(name).executable, ['--version']);
    return r == null ? null : extractVersion('${r.stdout}${r.stderr}') ?? '?';
  }

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final exe = ctx.config.tool(name).executable;
    final real = File(ctx.script.path).existsSync();
    final reqs =
        real ? PythonProject.find(ctx.script.path).requirements : <File>[];
    if (reqs.isEmpty) {
      return AnalyzerResult(
          ToolRun(name, ToolStatus.skipped, detail: 'requirements.txt'));
    }
    final imports = importLines(ctx.script.lines);
    final findings = <Finding>[];
    for (final req in reqs) {
      final key = '${req.absolute.path}@${req.lastModifiedSync()}';
      final r = await (_audits[key] ??= _audit(ctx, exe, req.absolute.path));
      if (r == null) return AnalyzerResult(ToolRun(name, ToolStatus.missing));
      try {
        findings.addAll(parsePipAudit(r.stdout, imports, ctx.lang));
      } on FormatException {
        _audits.remove(key); // réessayer à la prochaine analyse
        final detail = r.stderr.trim().split('\n').last;
        return AnalyzerResult(ToolRun(name, ToolStatus.failed,
            detail: detail.isEmpty ? 'pip-audit' : detail));
      }
    }
    return AnalyzerResult(
        ToolRun(name, ToolStatus.ok,
            findings: findings.length,
            detail: reqs.map((f) => f.uri.pathSegments.last).join(', ')),
        findings);
  }

  /// Versions épinglées : sans pip ; sinon pip résout les dépendances (plus
  /// lent, dans un environnement temporaire).
  static Future<CommandResult?> _audit(
      AnalysisContext ctx, String exe, String req) async {
    const common = ['--format=json', '--progress-spinner=off', '--no-deps'];
    final fast = await ctx.run(exe, ['-r', req, '--disable-pip', ...common]);
    if (fast == null || fast.stdout.trim().startsWith('{')) return fast;
    return ctx.run(exe, ['-r', req, ...common]);
  }
}

/// Ligne du premier import de chaque module de premier niveau.
Map<String, int> importLines(List<String> lines) {
  final out = <String, int>{};
  final imp =
      RegExp(r'^\s*(?:import\s+([\w., ]+)|from\s+(\w+)[\w.]*\s+import\b)');
  for (var i = 0; i < lines.length; i++) {
    final m = imp.firstMatch(lines[i]);
    if (m == null) continue;
    final names = m[1] != null
        ? m[1]!.split(',').map((s) => s.trim().split(RegExp(r'[.\s]')).first)
        : [m[2]!];
    for (final n in names) {
      if (n.isNotEmpty) out.putIfAbsent(n, () => i + 1);
    }
  }
  return out;
}

/// Sortie JSON de pip-audit → problèmes sur les imports des paquets
/// vulnérables ([imports] : module → ligne). Lève [FormatException].
List<Finding> parsePipAudit(String json, Map<String, int> imports, Lang lang) {
  final j = jsonDecode(json.trim());
  final deps = j is Map ? j['dependencies'] : j;
  if (deps is! List) throw const FormatException('pip-audit');
  // Paquet (normalisé) → ligne de l'import qui le charge.
  final byDist = <String, int>{};
  imports.forEach((module, line) {
    final i = PythonImport(module, line, 0, 'installed');
    for (final d in distCandidates(i)) {
      byDist.putIfAbsent(d, () => line);
    }
  });
  final out = <Finding>[];
  for (final d in deps) {
    if (d is! Map) continue;
    final name = normalizeDist('${d['name']}');
    final line = byDist[name];
    if (line == null) continue;
    for (final v in d['vulns'] as List? ?? const []) {
      if (v is! Map) continue;
      final id = '${v['id']}';
      final aliases = [for (final a in v['aliases'] as List? ?? const []) '$a'];
      final fixes = [
        for (final f in v['fix_versions'] as List? ?? const []) '$f'
      ];
      final fr = lang == Lang.fr;
      out.add(Finding(
        tool: 'pip-audit',
        ruleId: id,
        category: Category.security,
        severity: Severity.high,
        line: line,
        message: '${d['name']} ${d['version']} : '
            '${fr ? 'vulnérabilité connue' : 'known vulnerability'}'
            '${aliases.isEmpty ? '' : ' (${aliases.join(', ')})'}',
        hint: fixes.isEmpty
            ? (fr
                ? 'Aucune version corrigée : remplacer le paquet ou limiter son usage.'
                : 'No fixed version: replace the package or limit its use.')
            : (fr
                ? 'Passer à ${d['name']} ${fixes.first} ou plus récent (requirements).'
                : 'Upgrade to ${d['name']} ${fixes.first} or later (requirements).'),
        url: 'https://osv.dev/vulnerability/$id',
      ));
    }
  }
  return out;
}
