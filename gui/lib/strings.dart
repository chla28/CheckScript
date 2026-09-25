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
  String get rules => _t('Règles', 'Rules');
  String get searchRules =>
      _t('Rechercher (code, texte, outil)', 'Search (code, text, tool)');
  String get allLanguages => _t('Tous les langages', 'All languages');
  String get allTools => _t('Tous les outils', 'All tools');
  String get allCategories => _t('Toutes les catégories', 'All categories');
  String rulesCount(int shown, int total, int disabled) => _t(
      '$shown / $total règles · $disabled désactivée${disabled > 1 ? 's' : ''}',
      '$shown / $total rules · $disabled disabled');
  String enableAll(int n) => _t('Tout réactiver ($n)', 'Enable all ($n)');
  String get nextScanHint => _t(
      'Les changements s\'appliquent à la prochaine analyse.',
      'Changes apply from the next analysis.');
  String get disableOtherHint => _t('Autre code à désactiver (ex. SC2317)',
      'Other code to disable (e.g. SC2317)');
  String get disableOther => _t('Désactiver', 'Disable');
  String get typedCode => _t('code saisi', 'typed code');
  String get lockedByConfig => _t(
      'désactivée par le profil ou la configuration',
      'disabled by the profile or configuration');
  String get seenInScan => _t('rencontrée', 'seen');
  String get severityVaries => _t('sévérité variable', 'varying severity');
  String doNotReport(String id) =>
      _t('Ne plus signaler $id', 'Stop reporting $id');
  String ruleDisabled(String id) => _t(
      'Règle $id désactivée à partir de la prochaine analyse.',
      'Rule $id disabled from the next analysis.');
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
  String get importConfig => _t('Importer…', 'Import…');
  String get exportConfig => _t('Exporter…', 'Export…');
  String get importHint => _t(
      'Le fichier devient la configuration de référence ; les choix faits dans l\'interface (règles, outils) sont remis à zéro.',
      'The file becomes the reference configuration; choices made in the interface (rules, tools) are reset.');
  String get exportHint => _t(
      'Enregistre la configuration effective (fichier et choix de l\'interface), utilisable par la CLI et la CI.',
      'Saves the effective configuration (file and interface choices), usable by the CLI and CI.');
  String configImported(String path) =>
      _t('Configuration importée : $path', 'Configuration imported: $path');
  String configExported(String path) =>
      _t('Configuration exportée : $path', 'Configuration exported: $path');
  String get remove => _t('Retirer', 'Remove');
  String get detect => _t('Détecter', 'Detect');
  String get available => _t('disponible', 'available');
  String get notInstalled => _t('non installé', 'not installed');
  String get filters => _t('Filtres', 'Filters');
  String get noSelection => _t('Aucun script analysé.', 'No script analysed.');
  String get trend => _t('Tendance', 'Trend');
  String get issues => _t('Problèmes', 'Issues');
  String get openInAnalysis => _t('Ouvrir dans l\'analyse', 'Open in analysis');
  String get noScripts => _t('Aucun script shell ou Python trouvé.',
      'No shell or Python script found.');
  String get shellTools => _t('Scripts shell', 'Shell scripts');
  String get pythonTools => _t('Scripts Python', 'Python scripts');
  String get commonTools => _t('Tous les scripts', 'All scripts');
  String get pythonTarget => _t('Version minimale de Python à supporter',
      'Minimum Python version to support');
  String get semgrepNetwork =>
      _t('règles p/python (accès réseau)', 'p/python rules (network access)');
  String get optIn =>
      _t('redondant, désactivé par défaut', 'redundant, disabled by default');
  String get baselineLoaded => _t('Référence chargée', 'Baseline loaded');
  String get newOnly => _t('Nouveaux uniquement', 'New only');
  String get documentation => _t('Documentation', 'Documentation');
  String get summary => _t('Synthèse', 'Summary');
  String get wholeFile => _t('fichier entier', 'whole file');
  String get copy => _t('Copier', 'Copy');
  String get reportFalsePositive =>
      _t('Signaler un faux positif', 'Report a false positive');
  String get falsePositiveIntro => _t(
      'Le cas est enregistré sur ce poste, anonymisé comme ci-dessous, pour améliorer les règles.',
      'The case is saved on this computer, anonymised as below, to improve the rules.');
  String get falsePositiveComment => _t(
      'Pourquoi est-ce un faux positif ? (facultatif)',
      'Why is it a false positive? (optional)');
  String get save => _t('Enregistrer', 'Save');
  String falsePositiveSaved(int n) => _t(
      'Faux positif enregistré ($n cas au total).',
      'False positive saved ($n cases in total).');
  String get fileChanged => _t(
      'Script modifié : analyse relancée.', 'Script changed: analysis re-run.');
  String get openInEditor => _t('Ouvrir dans l\'éditeur', 'Open in editor');
  String openAtLine(int line) =>
      _t('Ouvrir dans l\'éditeur (ligne $line)', 'Open in editor (line $line)');
  String get editorCommand => _t('Commande de l\'éditeur', 'Editor command');
  String editorHint(String? detected) => _t(
      '{file} et {line} sont remplacés ; vide : ${detected ?? 'xdg-open (sans ligne)'}',
      '{file} and {line} are replaced; empty: ${detected ?? 'xdg-open (no line)'}');
  String get watchFileSetting => _t(
      'Relancer l\'analyse quand le script est enregistré',
      'Re-run the analysis when the script is saved');
  String get useCacheSetting => _t(
      'Réutiliser les résultats d\'un script inchangé (cache)',
      'Reuse results of an unchanged script (cache)');
  String get history => _t('Historique', 'History');
  String historyLine(int n, String first, String last, String delta) => _t(
      '$n analyses : note moyenne $first → $last ($delta)',
      '$n analyses: average score $first → $last ($delta)');
  String get ruffProjectConfig => _t(
      'Ruff : respecter la configuration du projet (ruff.toml, pyproject.toml)',
      'Ruff: follow the project configuration (ruff.toml, pyproject.toml)');
  String get sortCategory => _t('Par catégorie', 'By category');
  String get sortQuickWin => _t('Par gain rapide', 'By quick win');
  String get hideSource => _t('Masquer le code', 'Hide the code');
  String get hideResults => _t('Masquer les résultats', 'Hide the results');
  String get showBoth => _t('Réafficher les deux panneaux', 'Show both panels');
  String get copied => _t('Code copié.', 'Code copied.');
  String applyRuleFixes(int n, String rule) => _t(
      'Corriger les $n occurrences ($rule)', 'Fix all $n occurrences ($rule)');
  String rulesFixed(int n, String rule) => _t(
      '$n occurrences de $rule corrigées (original conservé en .orig).',
      '$n occurrences of $rule fixed (original kept as .orig).');
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
