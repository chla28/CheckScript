/// Internationalisation (français / anglais) des libellés de l'outil.
///
/// Les messages des outils externes (shellcheck, bashate…) restent dans leur
/// langue d'origine (anglais) ; seuls les libellés de l'outil et les messages
/// des règles intégrées sont traduits.
library;

import 'model/finding.dart';

enum Lang {
  fr,
  en;

  static Lang? tryParse(String s) {
    final v = s.toLowerCase();
    for (final l in values) {
      if (l.name == v) return l;
    }
    return null;
  }

  /// Langue déduite des variables d'environnement POSIX
  /// (`LC_ALL` > `LC_MESSAGES` > `LANG`) : français si `fr*`, sinon anglais.
  static Lang fromEnvironment(Map<String, String> env) {
    for (final key in ['LC_ALL', 'LC_MESSAGES', 'LANG']) {
      final v = env[key];
      if (v != null && v.isNotEmpty) {
        return v.toLowerCase().startsWith('fr') ? Lang.fr : Lang.en;
      }
    }
    return Lang.en;
  }
}

/// Texte bilingue, utilisé par les règles intégrées.
class Tr {
  final String fr;
  final String en;
  const Tr(this.fr, this.en);

  String of(Lang lang) => lang == Lang.fr ? fr : en;
}

class Messages {
  final Lang lang;
  const Messages(this.lang);

  String category(Category c) => switch (c) {
        Category.security => _t('Sécurité', 'Security'),
        Category.robustness => _t('Robustesse', 'Robustness'),
        Category.maintainability => _t('Maintenabilité', 'Maintainability'),
        Category.portability => _t('Portabilité', 'Portability'),
        Category.performance => _t('Performance', 'Performance'),
      };

  String toolStatus(ToolStatus s) => switch (s) {
        ToolStatus.ok => _t('exécuté', 'run'),
        ToolStatus.missing => _t('absent', 'not installed'),
        ToolStatus.skipped => _t('non applicable', 'not applicable'),
        ToolStatus.failed => _t('échec', 'failed'),
        ToolStatus.disabled => _t('désactivé', 'disabled'),
      };

  /// Séparateur « libellé : valeur » (espace avant les deux-points en français).
  String get colon => _t(' : ', ': ');

  String get reportTitle => _t('Évaluation du script', 'Script assessment');
  String get summaryTitle =>
      _t('Synthèse multi-scripts', 'Multi-script summary');
  String get file => _t('Fichier', 'File');
  String get dialect => _t('Dialecte', 'Dialect');
  String get lines => _t('Lignes', 'Lines');
  String linesDetail(int total, int code, int comments) => _t(
      '$total (code : $code, commentaires : $comments)',
      '$total (code: $code, comments: $comments)');
  String get date => _t('Date', 'Date');
  String get tools => _t('Outils', 'Tools');
  String get tool => _t('Outil', 'Tool');
  String get status => _t('Statut', 'Status');
  String get version => _t('Version', 'Version');
  String get issuesCol => _t('Problèmes', 'Issues');
  String get category_ => _t('Catégorie', 'Category');
  String get score => _t('Note /10', 'Score /10');
  String get total => _t('Total', 'Total');
  String get globalScore => _t('Note globale', 'Overall score');
  String get grade => _t('Niveau', 'Grade');
  String get details => _t('Détail des problèmes', 'Issue details');
  String get line => _t('Ligne', 'Line');
  String get severity => _t('Sévérité', 'Severity');
  String get rule => _t('Règle', 'Rule');
  String get message => _t('Message', 'Message');
  String get script => _t('Script', 'Script');
  String get noIssue => _t('Aucun problème détecté.', 'No issue detected.');
  String get wholeFile => _t('fichier', 'file');
  String get scoringNote => _t(
      'Note = 10 − Σ pénalités (Critical 4, High 2, Medium 0,75, Low 0,25 ; '
          'occurrences répétées d\'une même règle atténuées en log2 ; '
          'Medium/Low atténués selon la taille du script). Note globale = moyenne '
          'pondérée des catégories, plafonnée à la plus faible catégorie + 2,5.',
      'Score = 10 − Σ penalties (Critical 4, High 2, Medium 0.75, Low 0.25; '
          'repeated occurrences of one rule damped logarithmically; '
          'Medium/Low scaled by script size). Overall score = weighted mean of '
          'the categories, capped at the lowest category + 2.5.');
  String missingToolsHint(List<String> tools) => _t(
      'Outils absents (${tools.join(', ')}) : l\'analyse est moins complète. '
          'Voir `check-script --list-tools`.',
      'Missing tools (${tools.join(', ')}): the analysis is less complete. '
          'See `check-script --list-tools`.');
  String moreIssues(int n) =>
      _t('… et $n autre(s) (voir --details)', '… and $n more (see --details)');
  String reportWritten(String path) =>
      _t('Rapport écrit : $path', 'Report written: $path');

  String _t(String fr, String en) => lang == Lang.fr ? fr : en;
}
