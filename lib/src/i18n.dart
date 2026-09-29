/// Internationalisation (français / anglais) des libellés de l'outil.
///
/// Les messages des outils externes (shellcheck, bashate…) restent dans leur
/// langue d'origine (anglais) ; seuls les libellés de l'outil et les messages
/// des règles intégrées sont traduits.
library;

import 'analyzers/analyzer.dart' show ToolLanguage;
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
  String get references =>
      _t('Référentiels (CWE, OWASP, ANSSI)', 'References (CWE, OWASP, ANSSI)');
  String get reference => _t('Référence', 'Reference');
  String get commands => _t('Commandes externes', 'External commands');
  String get command => _t('Commande', 'Command');
  String get present => _t('Présente', 'Present');
  String get lines_ => _t('Lignes', 'Lines');
  String get packagesToInstall =>
      _t('Paquets à installer', 'Packages to install');
  String get unknown => _t('?', '?');
  String get yes => _t('oui', 'yes');
  String get no => _t('non', 'no');
  String get checkedByScript =>
      _t('vérifiée par le script', 'checked by the script');
  String get family => _t('Famille', 'Family');
  String get issuesCount => _t('Problèmes', 'Issues');
  String get worstSeverity => _t('Sévérité max.', 'Worst severity');
  String get scriptsCount => _t('Scripts', 'Scripts');
  String get referencesIntro => _t(
      'Problèmes de l\'analyse rattachés à chaque référence (les règles sans correspondance directe n\'y figurent pas).',
      'Issues of this analysis linked to each reference (rules without a direct match are not listed).');
  String get message => _t('Message', 'Message');
  String get script => _t('Script', 'Script');
  String get noIssue => _t('Aucun problème détecté.', 'No issue detected.');
  String get wholeFile => _t('fichier', 'file');
  String get maskedSecret => _t('(ligne non reproduite : secret potentiel)',
      '(line not shown: potential secret)');
  String get language_ => _t('Langage', 'Language');
  String toolLanguage(ToolLanguage l) => switch (l) {
        ToolLanguage.shell => 'shell',
        ToolLanguage.python => 'python',
        ToolLanguage.any => _t('tous', 'all'),
      };
  String scriptsOverview(int n, int shell, int python) => _t(
      '$n scripts ($shell shell, $python Python)',
      '$n scripts ($shell shell, $python Python)');
  String get averageScore => _t('Note moyenne', 'Average score');
  String get gradeDistribution => _t('Niveaux', 'Grades');
  String get issuesBySeverity => _t('Problèmes', 'Issues');
  String get topRules =>
      _t('Règles les plus fréquentes', 'Most frequent rules');
  String get occurrences => _t('Occurrences', 'Occurrences');
  String get scriptsAffected => _t('Scripts', 'Scripts');
  String get backToSummary => _t('↑ Sommaire', '↑ Summary');
  String get sortHint =>
      _t('Cliquer sur un en-tête pour trier.', 'Click a header to sort.');
  String dashboardTitle(int n) => _t(
      'Tableau de bord — $n dépôt${n > 1 ? 's' : ''}',
      'Dashboard — $n repositor${n > 1 ? 'ies' : 'y'}');
  String get repository => _t('Dépôt', 'Repository');
  String get repositories => _t('Dépôts', 'Repositories');
  String get trendHeader => _t('Tendance', 'Trend');
  String get weakestScripts =>
      _t('Scripts les plus faibles', 'Weakest scripts');
  String get explainTitle =>
      _t('Ce qui pèse sur la note', 'What weighs on the score');
  String nextGradeLine(String grade, String score, String rules) => _t(
      'Niveau $grade ($score) en corrigeant : $rules',
      'Grade $grade ($score) by fixing: $rules');
  String get gainHeader => _t('Gain global', 'Overall gain');
  String get pointsHeader => _t('Points retirés', 'Points lost');
  String get autoFix => _t('corr. auto', 'auto-fix');
  String get byQuickWin =>
      _t('Problèmes par gain rapide', 'Issues by quick win');
  String get suggestedFix => _t('Correction proposée', 'Suggested fix');
  String get fixExample => _t('Exemple de correction', 'Fix example');
  String get avoid => _t('À éviter', 'Avoid');
  String get writeInstead => _t('À écrire', 'Write instead');
  String get scoringNote => _t(
      'Note = 10 − Σ pénalités (Critical 4, High 2, Medium 0,75, Low 0,25 ; '
          'occurrences répétées d\'une même règle atténuées en log2 ; '
          'Medium/Low atténués selon la taille du script). Note globale = moyenne '
          'pondérée des catégories, plafonnée à la plus faible catégorie + 1,5.',
      'Score = 10 − Σ penalties (Critical 4, High 2, Medium 0.75, Low 0.25; '
          'repeated occurrences of one rule damped logarithmically; '
          'Medium/Low scaled by script size). Overall score = weighted mean of '
          'the categories, capped at the lowest category + 1.5.');
  String missingToolsHint(List<String> tools) => _t(
      'Outils absents (${tools.join(', ')}) : l\'analyse est moins complète. '
          'Voir `check-script --list-tools`.',
      'Missing tools (${tools.join(', ')}): the analysis is less complete. '
          'See `check-script --list-tools`.');
  String moreIssues(int n) =>
      _t('… et $n autre(s) (voir --details)', '… and $n more (see --details)');
  String get hint => _t('Correction', 'Fix');
  String get documentation => _t('Documentation', 'Documentation');
  String get profile => _t('Profil', 'Profile');
  String get contexts => _t('Contexte', 'Context');
  String suppressedCount(int n) => _t(
      '$n problème(s) neutralisé(s) par des directives # check-script disable',
      '$n issue(s) suppressed by # check-script disable directives');
  String get baseline =>
      _t('Comparaison avec la référence', 'Comparison with the baseline');
  String comparisonLine(int added, int fixed, int unchanged) => _t(
      'nouveaux : $added · corrigés : $fixed · inchangés : $unchanged',
      'new: $added · fixed: $fixed · unchanged: $unchanged');
  String get previous => _t('Référence', 'Baseline');
  String get evolution => _t('Évolution', 'Change');
  String get newIssuesOnly => _t('Nouveaux problèmes (absents de la référence)',
      'New issues (not in the baseline)');
  String get notInBaseline =>
      _t('script absent de la référence', 'script not in the baseline');
  String get source => _t('Source', 'Source');
  String get filter => _t('Filtrer', 'Filter');
  String get all => _t('Tous', 'All');
  String reportWritten(String path) =>
      _t('Rapport écrit : $path', 'Report written: $path');

  String _t(String fr, String en) => lang == Lang.fr ? fr : en;
}
