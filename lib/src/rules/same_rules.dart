/// Une même règle calculée par plusieurs outils : ShellCheck ↔ règle
/// intégrée, Ruff `Snnn` ↔ Bandit `Bnnn`, Ruff `PLxnnnn` ↔ Pylint `xnnnn`…
///
/// Désactiver l'une désactive l'autre. Ce n'est pas la relation
/// `Finding.equivalents`, plus large, qui sert au dédoublonnage de détections
/// voisines sur une même ligne (ex. Semgrep et Bandit).
library;

/// Codes ShellCheck couverts par une règle intégrée identique.
const Map<String, String> shellcheckToBuiltin = {
  'SC2164': 'ROB005',
  'SC2162': 'ROB007',
  'SC2045': 'ROB008',
  'SC2115': 'SEC007',
  'SC2114': 'SEC008',
  'SC2006': 'MNT007',
  'SC2148': 'POR001',
  'SC2230': 'POR004',
  'SC2196': 'POR005',
  'SC2197': 'POR005',
  'SC2002': 'PERF001',
  'SC2126': 'PERF002',
  'SC2003': 'PERF003',
  'SC2009': 'PERF006',
  'SC2116': 'PERF008',
};

/// Codes Ruff ↔ Pylint désignant le même défaut (hors famille PL, dont les
/// numéros sont ceux de Pylint).
const Map<String, String> ruffToPylint = {
  'E722': 'W0702',
  'B006': 'W0102',
  'F401': 'W0611',
  'F841': 'W0612',
  'E401': 'C0410',
  'F821': 'E0602',
  'F811': 'E0102',
  'SIM115': 'R1732',
  'S307': 'W0123',
  'B904': 'W0707',
  'E501': 'C0301',
  'W291': 'C0303',
  'C901': 'R1260',
};

/// Les autres identifiants de la même règle (en majuscules), sans [id].
Set<String> sameRuleIds(String id) {
  final k = id.toUpperCase();
  final out = <String>{};
  void add(String? v) {
    if (v != null && v != k) out.add(v);
  }

  // Ruff S (flake8-bandit) reprend les numéros de Bandit.
  add(RegExp(r'^S([1-7]\d\d)$').firstMatch(k)?.let((m) => 'B${m[1]}'));
  add(RegExp(r'^B([1-7]\d\d)$').firstMatch(k)?.let((m) => 'S${m[1]}'));
  // Ruff PL reprend les codes de Pylint.
  add(RegExp(r'^PL([CERW]\d{4})$').firstMatch(k)?.let((m) => m[1]));
  add(RegExp(r'^([CERW]\d{4})$').firstMatch(k)?.let((m) => 'PL${m[1]}'));
  for (final (a, b) in [
    for (final e in ruffToPylint.entries) (e.key, e.value),
    for (final e in shellcheckToBuiltin.entries) (e.key, e.value),
  ]) {
    if (a == k) add(b);
    if (b == k) add(a);
  }
  // Deux codes ShellCheck couverts par la même règle intégrée (egrep, fgrep).
  for (final b in [...out]) {
    for (final e in shellcheckToBuiltin.entries) {
      if (e.value == b) add(e.key);
    }
  }
  return out;
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
