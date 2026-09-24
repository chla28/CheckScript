/// Libellés propres à l'interface graphique (français / anglais). Les
/// libellés partagés avec le CLI (catégories, statuts…) viennent de
/// `Messages` (package check_script).
library;

import 'package:check_script/check_script.dart';

class S {
  final Lang lang;
  const S(this.lang);

  String _t(String fr, String en) => lang == Lang.fr ? fr : en;

  Messages get m => Messages(lang);

  String get appTitle => 'CheckScript';
  String get analysis => _t('Analyse', 'Analysis');
  String get folder => _t('Dossier', 'Folder');
  String get settings => _t('Réglages', 'Settings');
  String get openScript => _t('Ouvrir un script', 'Open a script');
  String get openFolder => _t('Ouvrir un dossier', 'Open a folder');
  String get reanalyze => _t('Relancer l\'analyse', 'Re-run analysis');
  String get fix => _t('Corriger…', 'Fix…');
  String get export => _t('Exporter…', 'Export…');
  String get loadBaseline => _t('Charger une référence…', 'Load a baseline…');
  String get clearBaseline => _t('Retirer la référence', 'Clear baseline');
  String get cancel => _t('Annuler', 'Cancel');
  String get apply => _t('Appliquer', 'Apply');
  String get close => _t('Fermer', 'Close');
  String get dropHere => _t(
      'Déposez un script ou un dossier ici, ou utilisez les boutons ci-dessus.',
      'Drop a script or a folder here, or use the buttons above.');
  String analyzing(String tool) => _t('Analyse : $tool…', 'Analysing: $tool…');
  String analyzingFile(int i, int n, String f) =>
      _t('Script $i / $n : $f', 'Script $i / $n: $f');
  String get cancelled => _t('Analyse annulée.', 'Analysis cancelled.');
  String error(Object e) => _t('Erreur : $e', 'Error: $e');
  String get noFix => _t('Aucune correction automatique applicable.',
      'No automatic fix applicable.');
  String get fixTitle => _t('Corrections proposées', 'Proposed fixes');
  String fixApplied(String summary) =>
      _t('Corrigé : $summary', 'Fixed: $summary');
  String fixAborted(String why) => _t(
      'Corrections abandonnées (la syntaxe ne serait plus valide) : $why',
      'Fixes dropped (the syntax would become invalid): $why');
  String get backupHint => _t(
      'L\'original est conservé en .orig.', 'The original is kept as .orig.');
  String exported(String path) =>
      _t('Rapport écrit : $path', 'Report written: $path');
  String get language => _t('Langue', 'Language');
  String get systemDefault => _t('Système', 'System');
  String get theme => _t('Thème', 'Theme');
  String get light => _t('Clair', 'Light');
  String get dark => _t('Sombre', 'Dark');
  String get profile => _t('Profil de notation', 'Scoring profile');
  String get profileStrict =>
      _t('Strict (nouveaux scripts)', 'Strict (new scripts)');
  String get profileStandard => _t('Standard', 'Standard');
  String get profileLegacy => _t('Existant (legacy)', 'Legacy');
  String get contexts => _t('Contextes d\'exécution', 'Execution contexts');
  String get tools => _t('Outils d\'analyse', 'Analysis tools');
  String get followSource => _t('Suivre les fichiers sourcés (shellcheck -x)',
      'Follow sourced files (shellcheck -x)');
  String get configFile =>
      _t('Fichier de configuration YAML', 'YAML configuration file');
  String get none => _t('aucun', 'none');
  String get choose => _t('Choisir…', 'Choose…');
  String get remove => _t('Retirer', 'Remove');
  String get detect => _t('Détecter', 'Detect');
  String get available => _t('disponible', 'available');
  String get notInstalled => _t('non installé', 'not installed');
  String get filters => _t('Filtres', 'Filters');
  String get noSelection => _t('Aucun script analysé.', 'No script analysed.');
  String get trend => _t('Tendance', 'Trend');
  String get issues => _t('Problèmes', 'Issues');
  String get openInAnalysis => _t('Ouvrir dans l\'analyse', 'Open in analysis');
  String get noScripts =>
      _t('Aucun script shell trouvé.', 'No shell script found.');
  String get baselineLoaded => _t('Référence chargée', 'Baseline loaded');
  String get newOnly => _t('Nouveaux uniquement', 'New only');
  String get documentation => _t('Documentation', 'Documentation');
  String get summary => _t('Synthèse', 'Summary');
  String get wholeFile => _t('fichier entier', 'whole file');
  String get copy => _t('Copier', 'Copy');
  String get copied => _t('Code copié.', 'Code copied.');
  String get applyThisFix => _t('Appliquer cette correction', 'Apply this fix');
  String before(int line) => _t('Avant (ligne $line)', 'Before (line $line)');
  String get after => _t('Après', 'After');
  String singleFixApplied(String rule) => _t(
      'Correction $rule appliquée (original conservé en .orig).',
      '$rule fix applied (original kept as .orig).');
  String get fixStale => _t(
      'Le fichier a changé depuis l\'analyse : relancez-la avant de corriger.',
      'The file changed since the analysis: re-run it before fixing.');
  String get noFixAvailable => _t(
      'Pas de correction automatique ni d\'exemple pour cette règle : voir la documentation.',
      'No automatic fix or example for this rule: see the documentation.');
}
