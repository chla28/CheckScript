/// Faits structurels extraits de l'arbre syntaxique produit par
/// `shfmt --to-json` : fonctions, profondeur d'imbrication, commandes (nom,
/// arguments littéraux, contrôle du code de retour, boucle, substitution).
///
/// Plus fiable que le découpage heuristique (`shell_lexer.dart`), qui reste le
/// repli quand shfmt est absent ou ne sait pas analyser le script.
library;

import 'dart:convert';

import 'analyzer.dart';
import '../json_num.dart';

class FunctionFact {
  final String name;
  final int startLine;
  final int endLine;
  const FunctionFact(this.name, this.startLine, this.endLine);
}

class CommandFact {
  final String name;
  final int line;

  /// Arguments (hors nom de commande) : valeur littérale, ou null si
  /// l'argument contient une expansion.
  final List<String?> args;

  /// Un argument contient une expansion ($var, $(…), $((…))…).
  final bool hasExpansion;

  /// Le code de retour est contrôlé (condition de if/while, opérande gauche
  /// de && ou ||, commande niée).
  final bool checked;
  final bool inLoop;

  /// La commande est exécutée dans une substitution $(…) / `…`.
  final bool inSubstitution;

  const CommandFact(this.name, this.line, this.args,
      {this.hasExpansion = false,
      this.checked = false,
      this.inLoop = false,
      this.inSubstitution = false});
}

class NestingFact {
  final int line;
  final int depth;
  const NestingFact(this.line, this.depth);
}

class AstFacts {
  final List<FunctionFact> functions;
  final List<CommandFact> commands;

  /// Structures de contrôle (if, for, while, until, case, select) avec leur
  /// profondeur (1 = premier niveau).
  final List<NestingFact> blocks;

  const AstFacts(this.functions, this.commands, this.blocks);

  int get maxDepth => blocks.fold(0, (m, b) => b.depth > m ? b.depth : m);

  /// Blocs qui franchissent le seuil [max] (profondeur max + 1) : un
  /// signalement par franchissement.
  Iterable<NestingFact> deepNodes(int max) =>
      blocks.where((b) => b.depth == max + 1);

  /// Construit les faits depuis la sortie JSON de `shfmt --to-json`.
  /// Lève [FormatException] si le JSON est invalide.
  factory AstFacts.fromJson(String json) {
    final doc = jsonDecode(json);
    if (doc is! Map) throw const FormatException('arbre shfmt inattendu');
    final w = _Walker()..node(doc, const _Ctx());
    return AstFacts(w.functions, w.commands, w.blocks);
  }
}

/// Opérateurs binaires de shfmt (mvdan.cc/sh/v3/syntax.BinCmdOperator).
const _opAnd = 10, _opOr = 11;

class _Ctx {
  final int depth;
  final bool inLoop;
  final bool inSubst;
  final bool checked;
  const _Ctx(
      {this.depth = 0,
      this.inLoop = false,
      this.inSubst = false,
      this.checked = false});

  _Ctx copy({int? depth, bool? inLoop, bool? inSubst, bool? checked}) => _Ctx(
      depth: depth ?? this.depth,
      inLoop: inLoop ?? this.inLoop,
      inSubst: inSubst ?? this.inSubst,
      checked: checked ?? this.checked);
}

int _line(Object? n, [String key = 'Pos']) {
  if (n is Map && n[key] is Map) {
    return jsonInt((n[key] as Map)['Line']) ?? 0;
  }
  return 0;
}

class _Walker {
  final functions = <FunctionFact>[];
  final commands = <CommandFact>[];
  final blocks = <NestingFact>[];

  void node(Object? n, _Ctx c) {
    if (n is List) {
      for (final x in n) {
        node(x, c);
      }
      return;
    }
    if (n is! Map) return;
    final type = n['Type'];
    // Stmt (sans Type) : porte Cmd, Negated, Redirs.
    if (type == null && n.containsKey('Cmd')) {
      final negated = n['Negated'] == true;
      node(n['Cmd'], negated ? c.copy(checked: true) : c);
      node(n['Redirs'], c.copy(checked: false));
      return;
    }
    switch (type) {
      case 'FuncDecl':
        final name = (n['Name'] as Map?)?['Value'] as String? ?? '?';
        functions.add(FunctionFact(name, _line(n), _line(n, 'End')));
        node(n['Body'], c.copy(checked: false));
      case 'BinaryCmd':
        final op = n['Op'];
        final guard = op == _opAnd ||
            op == _opOr ||
            op == '&&' ||
            op == '||' ||
            jsonInt(op) == _opAnd ||
            jsonInt(op) == _opOr;
        node(n['X'], guard ? c.copy(checked: true) : c);
        node(n['Y'], c);
      case 'IfClause':
        _block(n, c);
        final inner = c.copy(depth: c.depth + 1, checked: false);
        node(n['Cond'], inner.copy(checked: true));
        node(n['Then'], inner);
        _else(n['Else'], c);
      case 'WhileClause':
        _block(n, c);
        final inner = c.copy(depth: c.depth + 1, inLoop: true, checked: false);
        node(n['Cond'], inner.copy(checked: true));
        node(n['Do'], inner);
      case 'ForClause':
        _block(n, c);
        final inner = c.copy(depth: c.depth + 1, inLoop: true, checked: false);
        node(n['Loop'], inner);
        node(n['Do'], inner);
      case 'CaseClause':
        _block(n, c);
        node(n['Word'], c);
        node(n['Items'], c.copy(depth: c.depth + 1, checked: false));
      case 'CallExpr':
        _call(n, c);
      case 'CmdSubst' || 'ProcSubst':
        node(n['Stmts'], c.copy(inSubst: true, checked: false));
      default:
        for (final e in n.entries) {
          if (e.key == 'Pos' || e.key == 'End') continue;
          if (e.value is Map || e.value is List) node(e.value, c);
        }
    }
  }

  void _block(Map n, _Ctx c) => blocks.add(NestingFact(_line(n), c.depth + 1));

  /// else / elif : même profondeur que le if d'origine.
  void _else(Object? e, _Ctx c) {
    if (e is! Map) return;
    final inner = c.copy(depth: c.depth + 1, checked: false);
    if (e['Cond'] is List && (e['Cond'] as List).isNotEmpty) {
      node(e['Cond'], inner.copy(checked: true));
    }
    node(e['Then'], inner);
    _else(e['Else'], c);
  }

  void _call(Map n, _Ctx c) {
    node(n['Assigns'], c.copy(checked: false));
    final args = (n['Args'] as List?) ?? const [];
    // Les substitutions des arguments sont parcourues avant tout.
    for (final a in args) {
      node(a, c.copy(checked: false));
    }
    if (args.isEmpty) return;
    final name = _literal(args.first);
    if (name == null) return;
    final rest = [for (final a in args.skip(1)) _literal(a)];
    commands.add(CommandFact(
      name,
      _line(n),
      rest,
      hasExpansion: args.skip(1).any(_hasExpansion),
      checked: c.checked,
      inLoop: c.inLoop,
      inSubstitution: c.inSubst,
    ));
  }
}

/// Valeur littérale d'un mot (Lit, '…', "…" sans expansion), sinon null.
String? _literal(Object? word) {
  if (word is! Map) return null;
  final parts = word['Parts'];
  if (parts is! List) return null;
  final b = StringBuffer();
  for (final p in parts.whereType<Map>()) {
    switch (p['Type']) {
      case 'Lit' || 'SglQuoted':
        b.write(p['Value'] ?? '');
      case 'DblQuoted':
        final inner = _literal({'Parts': p['Parts'] ?? const []});
        if (inner == null) return null;
        b.write(inner);
      default:
        return null;
    }
  }
  return b.toString();
}

bool _hasExpansion(Object? n) {
  if (n is List) return n.any(_hasExpansion);
  if (n is! Map) return false;
  const exp = {'ParamExp', 'CmdSubst', 'ArithmExp', 'ProcSubst'};
  if (exp.contains(n['Type'])) return true;
  return n.values.any((v) => (v is Map || v is List) && _hasExpansion(v));
}

/// Obtient l'arbre syntaxique via shfmt (si activé et installé) ; null sinon
/// ou si le script ne peut pas être analysé.
Future<AstFacts?> loadAst(AnalysisContext ctx) async {
  final tc = ctx.config.tool('shfmt');
  if (!tc.enabled) return null;
  final ln = ctx.script.dialect.shfmtName;
  var r = await ctx.run(tc.executable, ['--to-json', if (ln != null) '-ln=$ln'],
      stdin: ctx.script.content);
  // Script /bin/sh contenant des bashismes : l'arbre bash reste exploitable.
  if (r != null && r.exitCode != 0 && ctx.script.dialect.isPosix) {
    r = await ctx.run(tc.executable, ['--to-json', '-ln=bash'],
        stdin: ctx.script.content);
  }
  if (r == null || r.exitCode != 0) return null;
  try {
    return AstFacts.fromJson(r.stdout);
  } on FormatException {
    return null;
  }
}
