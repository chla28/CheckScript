import 'package:test/test.dart';

import '../tool/conventional.dart';

void main() {
  group('validation des messages', () {
    test('conformes', () {
      for (final m in [
        'feat(gui): ajoute l\'onglet Règles',
        'fix: corrige le cache\n\nDétail.',
        'feat(engine)!: change le format JSON',
        'chore(release): 0.12.0',
        'docs(user.adoc): précise --changed-since',
        'Merge branch \'x\'',
        'Revert "feat: truc"',
        'fixup! fix: cache',
        '# commentaire de l\'éditeur\nci: tests en deux locales',
      ]) {
        expect(lintMessage(m), isEmpty, reason: m);
      }
    });

    test('non conformes, avec la raison', () {
      expect(lintMessage('Ajoute l\'onglet Règles'), hasLength(1));
      expect(lintMessage('feature: x').single, contains('type inconnu'));
      expect(lintMessage('fix: corrige.').single, contains('point final'));
      expect(
          lintMessage('fix: x\nsuite collée').single, contains('ligne vide'));
      expect(lintMessage('fix: ${'x' * 120}').single, contains('trop longue'));
      expect(lintMessage('Feat: x'), isNotEmpty);
      expect(lintMessage(''), ['message vide']);
    });
  });

  group('version et CHANGELOG', () {
    Commit c(String m) => parseCommit(m, hash: 'abcdef1234')!;

    test('montée de version', () {
      expect(nextVersion('0.11.2', [c('fix: a')]), '0.11.3');
      expect(nextVersion('0.11.2', [c('docs: a'), c('ci: b')]), '0.11.3');
      expect(nextVersion('0.11.2', [c('fix: a'), c('feat(gui): b')]), '0.12.0');
      // 0.x : un changement incompatible monte la mineure.
      expect(nextVersion('0.11.2', [c('feat!: b')]), '0.12.0');
      expect(nextVersion('1.4.2', [c('refactor: a\n\nBREAKING CHANGE: x')]),
          '2.0.0');
      expect(nextVersion('1.4.2', []), isNull);
    });

    test('section du CHANGELOG par rubrique', () {
      final s = changelogSection(
          '0.12.0',
          '2026-09-26',
          [
            c('feat(gui): ajoute A'),
            c('fix: corrige B'),
            c('feat(cli)!: change C'),
            c('chore: range D'),
          ],
          manualNotes: '- Note rédigée à la main.\n');
      expect(
          s, startsWith('## 0.12.0 — 2026-09-26\n\n- Note rédigée à la main.'));
      expect(s, contains('### Breaking changes\n\n- **cli**: change C'));
      expect(s.indexOf('### Features'), lessThan(s.indexOf('### Bug fixes')));
      expect(s, contains('- **gui**: ajoute A (abcdef1)'));
      expect(s, contains('### Maintenance\n\n- range D'));
    });
  });
}
