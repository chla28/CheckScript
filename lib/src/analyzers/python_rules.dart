/// Règles intégrées propres aux scripts Python : les points que Ruff, Bandit,
/// mypy… ne couvrent pas (secrets à forte entropie, en-tête du script, garde
/// `__main__`, appels subprocess sans délai, saisie interactive sans
/// terminal, shebang ambigu).
///
/// Les faits structurels viennent du module `ast` de Python (via
/// `python3 -c`) ; sans interpréteur, un découpage ligne à ligne prend le
/// relais (appels multi-lignes non vus).
library;

import 'dart:convert';

import '../config.dart';
import '../i18n.dart';
import '../model/finding.dart';
import '../rules/catalog.dart';
import '../script_info.dart';
import 'analyzer.dart';
import 'builtin_rules.dart' show lineHasSecret;
import 'external_tools.dart' show pythonExecutable;

/// Faits extraits de l'arbre syntaxique d'un script Python.
class PythonFacts {
  /// Le module commence par une docstring.
  final bool docstring;
  final int functions;

  /// Présence d'un `if __name__ == "__main__":` au niveau module.
  final bool mainGuard;

  /// Lignes des instructions exécutées au niveau module (appels, boucles,
  /// with, try) hors de la garde `__main__`.
  final List<int> topLevel;

  /// Lignes des appels subprocess.run / call / check_call / check_output
  /// sans argument `timeout` (ni `**kwargs`).
  final List<int> noTimeout;

  /// Lignes des appels à `input()`.
  final List<int> inputs;

  const PythonFacts({
    this.docstring = false,
    this.functions = 0,
    this.mainGuard = false,
    this.topLevel = const [],
    this.noTimeout = const [],
    this.inputs = const [],
  });

  factory PythonFacts.fromJson(Map<String, Object?> j) {
    List<int> ints(Object? v) => [
          for (final e in v is List ? v : const []) (e as num).toInt(),
        ];
    return PythonFacts(
      docstring: j['docstring'] == true,
      functions: (j['functions'] as num?)?.toInt() ?? 0,
      mainGuard: j['main_guard'] == true,
      topLevel: ints(j['toplevel']),
      noTimeout: ints(j['no_timeout']),
      inputs: ints(j['inputs']),
    );
  }
}

/// Extraction des faits avec le module `ast` (fichier en argument, sinon
/// entrée standard) ; écrit un objet JSON.
const pythonFactsScript = r'''
import ast, json, sys
path = sys.argv[1] if len(sys.argv) > 1 else None
src = open(path, "rb").read() if path else sys.stdin.buffer.read()
tree = ast.parse(src)
facts = {"docstring": ast.get_docstring(tree) is not None, "functions": 0,
         "main_guard": False, "toplevel": [], "no_timeout": [], "inputs": []}
modules, aliases = {"subprocess"}, {}
for n in ast.walk(tree):
    if isinstance(n, ast.Import):
        for a in n.names:
            if a.name == "subprocess":
                modules.add(a.asname or a.name)
    elif isinstance(n, ast.ImportFrom) and n.module == "subprocess":
        for a in n.names:
            aliases[a.asname or a.name] = a.name
runners = {"run", "call", "check_call", "check_output"}
for n in ast.walk(tree):
    if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
        facts["functions"] += 1
    elif isinstance(n, ast.Call):
        f, name = n.func, None
        if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) \
                and f.value.id in modules:
            name = f.attr
        elif isinstance(f, ast.Name):
            name = aliases.get(f.id)
            if f.id == "input":
                facts["inputs"].append(n.lineno)
        kws = {k.arg for k in n.keywords}
        if name in runners and "timeout" not in kws and None not in kws:
            facts["no_timeout"].append(n.lineno)
def is_main(t):
    if not isinstance(t, ast.Compare) or len(t.comparators) != 1:
        return False
    sides = [t.left, t.comparators[0]]
    return any(isinstance(s, ast.Name) and s.id == "__name__" for s in sides) \
        and any(isinstance(s, ast.Constant) and s.value == "__main__" for s in sides)
for s in tree.body:
    if isinstance(s, ast.If) and is_main(s.test):
        facts["main_guard"] = True
    elif (isinstance(s, ast.Expr) and isinstance(s.value, ast.Call)) \
            or isinstance(s, (ast.For, ast.While, ast.With, ast.Try)):
        facts["toplevel"].append(s.lineno)
for k in ("no_timeout", "inputs"):
    facts[k] = sorted(set(facts[k]))
print(json.dumps(facts))
''';

/// Faits de l'arbre syntaxique, ou null (Python absent, fichier invalide).
Future<PythonFacts?> loadPythonFacts(AnalysisContext ctx) async {
  final r =
      await ctx.run(pythonExecutable, ['-c', pythonFactsScript, ctx.filePath]);
  if (r == null || r.exitCode != 0) return null;
  try {
    final j = jsonDecode(r.stdout.trim());
    return j is Map<String, Object?> ? PythonFacts.fromJson(j) : null;
  } on FormatException {
    return null;
  }
}

final _def = RegExp(r'^\s*(?:async\s+)?def\s');
final _guard = RegExp(r'''^if\s+__name__\s*==\s*['"]__main__['"]\s*:''');
final _topCall = RegExp(r'^(?:[A-Za-z_][\w.]*\(|(?:for|while|with|try)\b)');
final _subprocess =
    RegExp(r'\bsubprocess\.(?:run|call|check_call|check_output)\s*\(');
final _input = RegExp(r'(?<![\w.])input\s*\(');
final _docStart = RegExp(r'''^[rRuU]?(?:"""|\'\'\'|"|')''');

/// Faits approchés, ligne à ligne (sans interpréteur Python) : les appels
/// répartis sur plusieurs lignes ne sont pas examinés.
PythonFacts lexPythonFacts(ScriptInfo s) {
  var functions = 0, guard = false, docstring = false, seenCode = false;
  final top = <int>[], noTimeout = <int>[], inputs = <int>[];
  for (var i = 0; i < s.lines.length; i++) {
    final raw = s.lines[i];
    final code = _stripComment(raw);
    final t = code.trim();
    if (t.isEmpty) continue;
    if (!seenCode) {
      seenCode = true;
      docstring = _docStart.hasMatch(t);
    }
    if (_def.hasMatch(code)) functions++;
    if (_guard.hasMatch(code)) guard = true;
    if (!raw.startsWith(RegExp(r'\s')) && _topCall.hasMatch(code)) {
      top.add(i + 1);
    }
    if (_subprocess.hasMatch(code) &&
        !code.contains('timeout') &&
        !code.contains('**') &&
        '('.allMatches(code).length == ')'.allMatches(code).length) {
      noTimeout.add(i + 1);
    }
    if (_input.hasMatch(code)) inputs.add(i + 1);
  }
  return PythonFacts(
      docstring: docstring,
      functions: functions,
      mainGuard: guard,
      topLevel: top,
      noTimeout: noTimeout,
      inputs: inputs);
}

/// Ligne sans commentaire `#` (hors chaînes simples).
String _stripComment(String line) {
  String? quote;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quote != null) {
      if (c == '\\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
    } else if (c == '"' || c == "'") {
      quote = c;
    } else if (c == '#') {
      return line.substring(0, i);
    }
  }
  return line;
}

/// Applique les règles intégrées Python (fonction pure, testable).
List<Finding> runPythonRules(ScriptInfo s, CheckConfig config, Lang lang,
    {PythonFacts? facts}) {
  final f = facts ?? lexPythonFacts(s);
  final out = <Finding>[];
  bool active(RuleInfo r) =>
      r.contexts.isEmpty || r.contexts.any(config.contexts.contains);

  void add(String id, int line,
      {String? extra, bool hide = false, List<String> eq = const []}) {
    final r = ruleInfo(id);
    if (!active(r)) return;
    out.add(Finding(
      tool: 'builtin',
      ruleId: r.id,
      category: r.category,
      severity: r.severity,
      line: line,
      message:
          extra == null ? r.title.of(lang) : '${r.title.of(lang)} ($extra)',
      snippet: hide || line < 1 || line > s.lines.length
          ? null
          : s.lines[line - 1].trim(),
      equivalents: eq,
      hint: r.fix.of(lang),
    ));
  }

  // Secrets par entropie.
  for (var i = 0; i < s.lines.length; i++) {
    if (i == 0 && s.shebang != null) continue;
    if (lineHasSecret(s.lines[i])) {
      add('PYSEC001', i + 1, hide: true, eq: const [
        'GL*', 'TH*', 'B105', 'B106', 'B107', 'S105', 'S106', 'S107', //
      ]);
    }
  }

  // Shebang ambigu : « python » désigne Python 2 sur d'anciens systèmes.
  final sb = s.shebang;
  if (sb != null &&
      RegExp(r'(?:^#!\s*\S*/|\benv\s+(?:-\S+\s+)*)python2?(?:\s|$)')
          .hasMatch(sb)) {
    add('PYPOR001', 1, eq: const ['EXE003']);
  }

  // En-tête : docstring de module, ou commentaire parmi les 3 premières
  // lignes non vides (hors shebang et déclaration d'encodage).
  final head = [
    for (var i = 0; i < s.lines.length; i++)
      if (!(i == 0 && sb != null) &&
          s.lines[i].trim().isNotEmpty &&
          !RegExp(r'^#.*coding[:=]').hasMatch(s.lines[i].trim()))
        s.lines[i].trim()
  ].take(3);
  if (s.codeLines >= 5 && !f.docstring && !head.any((l) => l.startsWith('#'))) {
    add('PYMNT001', 0, eq: const ['D100', 'C0114']);
  }

  if (f.functions > 0 && f.topLevel.isNotEmpty && !f.mainGuard) {
    add('PYMNT002', f.topLevel.first);
  }
  for (final l in f.noTimeout) {
    add('PYROB001', l);
  }
  for (final l in f.inputs) {
    add('PYROB002', l);
  }
  return out;
}
