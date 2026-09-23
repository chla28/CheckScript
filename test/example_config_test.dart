import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

void main() {
  test('doc/checkscript.example.yaml est une configuration valide', () {
    final c = CheckConfig.parse(
        File('doc/checkscript.example.yaml').readAsStringSync());
    expect(c.tool('bashate').exclude, ['E006']);
    expect(c.disabledRules, {'MNT005'});
    expect(c.overrides['SC2086']!.category, Category.security);
  });
}
