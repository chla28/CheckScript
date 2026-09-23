/// Diff unifié ligne à ligne (algorithme de Myers, O((N+M)·D)), pour
/// `--fix --dry-run`.
library;

enum _Op { equal, delete, insert }

class _Edit {
  final _Op op;
  final int a; // index dans l'ancien texte (delete/equal)
  final int b; // index dans le nouveau texte (insert/equal)
  const _Edit(this.op, this.a, this.b);
}

List<_Edit> _myers(List<String> a, List<String> b) {
  final n = a.length, m = b.length, max = n + m;
  final offset = max + 1;
  var v = List<int>.filled(2 * max + 3, 0);
  final trace = <List<int>>[];
  outer:
  for (var d = 0; d <= max; d++) {
    trace.add(List.of(v));
    for (var k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) {
        x = v[offset + k + 1];
      } else {
        x = v[offset + k - 1] + 1;
      }
      var y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      v[offset + k] = x;
      if (x >= n && y >= m) break outer;
    }
  }
  // Remontée de la trace.
  final edits = <_Edit>[];
  var x = n, y = m;
  for (var d = trace.length - 1; d >= 0; d--) {
    v = trace[d];
    final k = x - y;
    final prevK = (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]))
        ? k + 1
        : k - 1;
    final prevX = v[offset + prevK];
    final prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      edits.add(_Edit(_Op.equal, x - 1, y - 1));
      x--;
      y--;
    }
    if (d > 0) {
      if (x == prevX) {
        edits.add(_Edit(_Op.insert, x, prevY));
      } else {
        edits.add(_Edit(_Op.delete, prevX, y));
      }
    }
    x = prevX;
    y = prevY;
  }
  return edits.reversed.toList();
}

/// Diff unifié entre [before] et [after] ; chaîne vide s'ils sont identiques.
String unifiedDiff(String before, String after,
    {String fromName = 'a', String toName = 'b', int context = 3}) {
  List<String> split(String s) {
    final l = s.split('\n');
    if (l.isNotEmpty && l.last.isEmpty) l.removeLast();
    return l;
  }

  final a = split(before), b = split(after);
  final edits = _myers(a, b);
  if (edits.every((e) => e.op == _Op.equal)) return '';

  final out = StringBuffer('--- $fromName\n+++ $toName\n');
  var i = 0;
  while (i < edits.length) {
    // Prochain changement.
    while (i < edits.length && edits[i].op == _Op.equal) {
      i++;
    }
    if (i >= edits.length) break;
    final start = i - context < 0 ? 0 : i - context;
    // Étend le bloc tant que les changements sont proches.
    var end = i;
    var lastChange = i;
    while (end < edits.length) {
      if (edits[end].op != _Op.equal) lastChange = end;
      if (end - lastChange > 2 * context) break;
      end++;
    }
    end = lastChange + context + 1 > edits.length
        ? edits.length
        : lastChange + context + 1;
    final hunk = edits.sublist(start, end);
    final aStart =
        hunk.firstWhere((e) => e.op != _Op.insert, orElse: () => hunk.first);
    final bStart =
        hunk.firstWhere((e) => e.op != _Op.delete, orElse: () => hunk.first);
    final aLen = hunk.where((e) => e.op != _Op.insert).length;
    final bLen = hunk.where((e) => e.op != _Op.delete).length;
    final aFrom = aLen == 0 ? aStart.a : aStart.a + 1;
    final bFrom = bLen == 0 ? bStart.b : bStart.b + 1;
    out.writeln('@@ -$aFrom,$aLen +$bFrom,$bLen @@');
    for (final e in hunk) {
      switch (e.op) {
        case _Op.equal:
          out.writeln(' ${a[e.a]}');
        case _Op.delete:
          out.writeln('-${a[e.a]}');
        case _Op.insert:
          out.writeln('+${b[e.b]}');
      }
    }
    i = end;
  }
  return out.toString();
}
