import 'package:check_script/src/analyzers/secrets.dart';
import 'package:check_script/src/analyzers/shellcheck.dart';
import 'package:check_script/src/json_num.dart';
import 'package:test/test.dart';

void main() {
  test('jsonInt / jsonDouble acceptent nombres et chaînes numériques', () {
    expect(jsonInt(3), 3);
    expect(jsonInt('3'), 3);
    expect(jsonInt(' 4.0 '), 4);
    expect(jsonInt('x'), isNull);
    expect(jsonInt(null), isNull);
    expect(jsonDouble('7.5'), 7.5);
    expect(jsonDouble(2), 2.0);
  });

  test('positions en chaîne (selon la version de l\'outil)', () {
    final gl = parseGitleaks(
        '[{"RuleID":"aws","StartLine":"3","StartColumn":"2","Description":"d"}]');
    expect(gl.single.line, 3);
    expect(gl.single.column, 2);
    final th = parseTrufflehog('{"DetectorName":"AWS","SourceMetadata":'
        '{"Data":{"Filesystem":{"file":"s.sh","line":"5"}}}}');
    expect(th.single.line, 5);
    final sc = parseShellcheckJson('{"comments":[{"code":"2086","level":"info",'
        '"line":"4","column":"7","message":"m"}]}');
    expect(sc.single.ruleId, 'SC2086');
    expect(sc.single.line, 4);
  });
}
