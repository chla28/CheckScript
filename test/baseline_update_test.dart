import 'dart:convert';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  Future<ScriptReport> analyze(String path, String content, Baseline? b) =>
      Engine(runner: noTools(), baseline: b)
          .analyze(ScriptInfo.fromContent(path, content));

  const bad = '#!/bin/bash\nset -euo pipefail\neval "\$x"\n';
  const fixed = '#!/bin/bash\nset -euo pipefail\necho ok\n';

  group('updateBaseline', () {
    test('JSON invalide ou sans "reports" : FormatException', () {
      expect(() => updateBaseline('{', []), throwsFormatException);
      expect(() => updateBaseline('{"x":1}', []), throwsFormatException);
      expect(() => updateBaseline('[]', []), throwsFormatException);
    });

    test('problème corrigé : entrée resserrée', () async {
      final before = await analyze('a.sh', bad, null);
      final json = renderJson([before]);
      final after = await analyze('a.sh', fixed, Baseline.parse(json));
      final u = updateBaseline(json, [after]);
      expect(u.updated, 1);
      expect(u.removed, greaterThanOrEqualTo(1));
      expect(u.refused, isEmpty);
      final doc = jsonDecode(u.json) as Map<String, dynamic>;
      final entry = (doc['reports'] as List).first as Map<String, dynamic>;
      expect(entry['file'], 'a.sh');
      expect(entry.containsKey('comparison'), isFalse);
    });

    test('nouveau problème : mise à jour refusée', () async {
      final before = await analyze('a.sh', fixed, null);
      final json = renderJson([before]);
      final after = await analyze('a.sh', bad, Baseline.parse(json));
      final u = updateBaseline(json, [after]);
      expect(u.updated, 0);
      expect(u.refused, ['a.sh']);
    });

    test(
        'rien de corrigé, rapport sans référence ou sans comparaison : '
        'inchangé', () async {
      final before = await analyze('a.sh', bad, null);
      final json = renderJson([before]);
      final same = await analyze('a.sh', bad, Baseline.parse(json));
      final nocmp = await analyze('a.sh', bad, null);
      final other = await analyze('zzz/other.sh', bad, Baseline.parse(json));
      final u = updateBaseline(json, [same, nocmp, other]);
      expect(u.updated, 0);
      expect(u.removed, 0);
      expect(u.unchanged, 1);
    });

    test('appariement par nom de fichier et chemin normalisé', () async {
      final before = await analyze('old/place/a.sh', bad, null);
      final json = renderJson([before]);
      final after = await analyze('./new/a.sh', fixed, Baseline.parse(json));
      final u = updateBaseline(json, [after]);
      expect(u.updated, 1);
      final doc = jsonDecode(u.json) as Map<String, dynamic>;
      // Le chemin d'origine de la référence est conservé.
      expect(((doc['reports'] as List).first as Map)['file'], 'old/place/a.sh');
    });

    test('entrées de la référence non analysées : conservées', () async {
      final a = await analyze('a.sh', bad, null);
      final b = await analyze('b.sh', bad, null);
      final json = renderJson([a, b]);
      final after = await analyze('a.sh', fixed, Baseline.parse(json));
      final u = updateBaseline(json, [after]);
      expect(u.updated, 1);
      expect(u.unchanged, 1);
      expect(((jsonDecode(u.json) as Map)['reports'] as List), hasLength(2));
    });
  });
}
