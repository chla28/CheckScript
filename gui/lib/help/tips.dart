/// Info-bulles de l'aide contextuelle : une phrase par bouton, filtre ou
/// réglage, dans la langue de l'interface.
library;

import 'package:check_script/check_script.dart';
import 'package:flutter/material.dart';

class Tips {
  const Tips(this.lang);
  final Lang lang;

  String _t(String fr, String en) => lang == Lang.fr ? fr : en;

  // Navigation
  String get navAnalysis => _t('Analyser un script et lire ses résultats',
      'Analyse a script and read its results');
  String get navFolder => _t('Analyser tous les scripts d\'un dossier',
      'Analyse all the scripts of a folder');
  String get navRules => _t('Choisir les règles qui sont signalées',
      'Choose which rules are reported');
  String get navSettings => _t('Langue, thème, profil, outils, configuration',
      'Language, theme, profile, tools, configuration');
  String get navHelp => _t('Aide en ligne (F1)', 'Online help (F1)');
  String get recentMenu => _t('Derniers scripts et dossiers analysés',
      'Last scripts and folders analysed');

  // Barre d'outils
  String get openScript => _t(
      'Choisir un script shell ou Python à analyser (ou le déposer sur la fenêtre)',
      'Pick a shell or Python script to analyse (or drop it on the window)');
  String get openFolder => _t(
      'Choisir un dossier : tous ses scripts sont analysés (ou le déposer sur la fenêtre)',
      'Pick a folder: all its scripts are analysed (or drop it on the window)');
  String get reanalyze => _t(
      'Refaire l\'analyse (après une modification du script, des règles ou des réglages)',
      'Analyse again (after a change to the script, the rules or the settings)');
  String get fix => _t(
      'Proposer les corrections automatiques sûres, avec aperçu avant écriture',
      'Propose the safe automatic fixes, with a preview before writing');
  String get export => _t(
      'Écrire un rapport : HTML, PDF, Markdown, AsciiDoc, JSON, SARIF ou texte (selon l\'extension)',
      'Write a report: HTML, PDF, Markdown, AsciiDoc, JSON, SARIF or text (by extension)');
  String get openInEditor => _t(
      'Ouvrir le script dans votre éditeur, à la ligne sélectionnée',
      'Open the script in your editor, at the selected line');
  String get loadBaseline => _t(
      'Comparer avec un rapport JSON antérieur : seuls les nouveaux problèmes sont détaillés',
      'Compare with an earlier JSON report: only new issues are detailed');
  String get baselineChip => _t('Référence en cours : la croix la retire',
      'Baseline in use: the cross removes it');
  String get cancelAnalysis =>
      _t('Interrompre l\'analyse en cours', 'Stop the analysis in progress');

  // Synthèse
  String get tabSummary => _t(
      'Note globale, radar des catégories et ce qui pèse sur la note',
      'Overall score, category radar and what weighs on the score');
  String get tabIssues => _t(
      'Liste détaillée des problèmes, avec filtres et corrections',
      'Detailed list of issues, with filters and fixes');
  String get globalScore => _t(
      'Note globale sur 10 : moyenne pondérée des catégories, plafonnée à la plus faible + 1,5',
      'Overall score out of 10: weighted mean of the categories, capped at the weakest + 1.5');
  String get grade => _t('Niveau : A ≥ 9 · B ≥ 7,5 · C ≥ 6 · D ≥ 4 · E < 4',
      'Grade: A ≥ 9 · B ≥ 7.5 · C ≥ 6 · D ≥ 4 · E < 4');
  String get delta => _t(
      'Écart avec la référence chargée', 'Difference from the loaded baseline');
  String get radar => _t(
      'Les cinq catégories sur 10 : plus la forme est grande, meilleur est le script',
      'The five categories out of 10: the larger the shape, the better the script');
  String get categoryColumn => _t(
      'Sécurité, Robustesse, Maintenabilité, Portabilité, Performance',
      'Security, Robustness, Maintainability, Portability, Performance');
  String get scoreColumn =>
      _t('Note de la catégorie sur 10', 'Category score out of 10');
  String get totalColumn =>
      _t('Nombre total de problèmes', 'Total number of issues');
  String severity(Severity s) => switch (s) {
        Severity.critical => _t(
            'Critical : compromission ou destruction probable (secret en dur, code téléchargé exécuté…)',
            'Critical: probable compromise or destruction (hard-coded secret, downloaded code executed…)'),
        Severity.high => _t(
            'High : défaut sérieux et exploitable (eval, chmod 777, cd non vérifié…)',
            'High: serious exploitable defect (eval, chmod 777, unchecked cd…)'),
        Severity.medium => _t(
            'Medium : défaut réel à effet limité (variable non protégée, pas de set -e…)',
            'Medium: real defect with limited effect (unquoted variable, no set -e…)'),
        Severity.low => _t('Low : style, lisibilité, bonnes pratiques',
            'Low: style, readability, good practices'),
      };
  String get explainTitle => _t(
      'Les règles qui coûtent le plus de points, et ce que vous gagnez en les corrigeant',
      'The rules that cost the most points, and what you gain by fixing them');
  String get pointsColumn => _t('Points retirés à la catégorie par cette règle',
      'Points removed from the category by this rule');
  String get gainColumn => _t(
      'Gain sur la note globale si toutes les occurrences sont corrigées (0 : une catégorie plus faible plafonne la note)',
      'Gain on the overall score if all occurrences are fixed (0: a weaker category caps the score)');
  String get suppressed => _t(
      'Problèmes neutralisés par des directives « # check-script disable » dans le script',
      'Issues neutralized by “# check-script disable” directives in the script');

  // Problèmes
  String get categoryChip =>
      _t('Afficher ou masquer cette catégorie', 'Show or hide this category');
  String get severityChip =>
      _t('Afficher ou masquer cette sévérité', 'Show or hide this severity');
  String get sortCategory =>
      _t('Ordre du rapport : par catégorie', 'Report order: by category');
  String get sortQuickWin => _t(
      'Du plus rentable au moins rentable pour la note (une règle corrigeable automatiquement compte 1,5 fois son gain)',
      'From the most to the least profitable for the score (an automatically fixable rule counts 1.5 times its gain)');
  String get selectAllFixable => _t(
      'Cocher ou décocher tous les problèmes corrigeables affichés (selon les filtres)',
      'Tick or untick all the fixable issues shown (according to the filters)');
  String get fixSelection => _t(
      'Corriger ensemble les problèmes cochés, après aperçu du diff global',
      'Fix the ticked issues together, after a preview of the global diff');
  String get fixCheckbox => _t('Cocher pour corriger avec la sélection',
      'Tick to fix with the selection');
  String get lineBadge =>
      _t('Sévérité et ligne du problème', 'Severity and line of the issue');
  String get documentation => _t(
      'Ouvrir la documentation de la règle', 'Open the rule\'s documentation');
  String get copyCode => _t('Copier le code proposé dans le presse-papiers',
      'Copy the proposed code to the clipboard');
  String get applyThisFix => _t(
      'Corriger cette occurrence dans le fichier (original conservé en .orig)',
      'Fix this occurrence in the file (original kept as .orig)');
  String get applyRuleFixes => _t(
      'Corriger toutes les occurrences de cette règle (original conservé en .orig)',
      'Fix all the occurrences of this rule (original kept as .orig)');
  String get reportFalsePositive => _t(
      'Enregistrer ce cas sur votre poste, anonymisé, pour améliorer les règles',
      'Save this case on your computer, anonymised, to improve the rules');
  String doNotReport(String id) => _t(
      'Désactiver la règle $id : elle ne sera plus signalée à partir de la prochaine analyse',
      'Disable rule $id: it will no longer be reported from the next analysis');

  // Code
  String get codeFont => _t('Police du code (modifiable dans les Réglages)',
      'Code font (can be changed in Settings)');
  String get codeMargin => _t(
      'La marque colorée indique la plus grave sévérité de la ligne ; survolez la ligne pour lire les problèmes',
      'The coloured mark shows the worst severity of the line; hover the line to read the issues');

  // Dossier
  String get folderSort => _t(
      'Cliquer pour trier ; un second clic inverse l\'ordre',
      'Click to sort; a second click reverses the order');
  String get trend => _t('Évolution de la note par rapport à la référence',
      'Evolution of the score compared with the baseline');
  String get history => _t(
      'Note moyenne des analyses successives de ce dossier',
      'Average score of this folder\'s successive analyses');

  // Règles
  String get searchRules => _t(
      'Chercher par code, texte, outil, CWE, OWASP ou ANSSI',
      'Search by code, text, tool, CWE, OWASP or ANSSI');
  String get enableAll => _t(
      'Recocher toutes les règles que vous avez désactivées',
      'Re-tick all the rules you disabled');
  String get disableOther => _t(
      'Désactiver n\'importe quel code, même absent de la liste (ex. SC2317)',
      'Disable any code, even one missing from the list (e.g. SC2317)');
  String get ruleCheckbox => _t(
      'Décocher : la règle n\'est plus signalée à partir de la prochaine analyse',
      'Untick: the rule is no longer reported from the next analysis');
  String get lockedRule => _t(
      'Désactivée par le profil ou le fichier YAML : non modifiable ici',
      'Disabled by the profile or the YAML file: cannot be changed here');
  String get languageFilter =>
      _t('Filtrer les règles par langage', 'Filter rules by language');
  String get toolFilter =>
      _t('Filtrer les règles par outil', 'Filter rules by tool');
  String get categoryFilter =>
      _t('Filtrer les règles par catégorie', 'Filter rules by category');

  // Réglages
  String get language => _t(
      'Langue de l\'interface ; les messages des outils externes restent en anglais',
      'Interface language; messages of external tools stay in English');
  String get theme => _t('Apparence claire, sombre ou celle du système',
      'Light, dark or system appearance');
  String get codeFontField => _t(
      'Police du code : celle intégrée, ou toute police à chasse fixe installée (nom saisi puis Entrée)',
      'Code font: the built-in one, or any installed monospaced font (type its name then Enter)');
  String get codeFontSize => _t('Taille du code (aussi Ctrl+plus / Ctrl+moins)',
      'Code size (also Ctrl+plus / Ctrl+minus)');
  String get profile => _t(
      'Sévérité de la notation : strict pour du code neuf, standard, legacy pour du code ancien',
      'Strictness of the scoring: strict for new code, standard, legacy for old code');
  String get profileStrict => _t(
      'Code neuf : pénalités plus lourdes, seuils serrés (lignes ≤ 100, fonctions ≤ 40 lignes)',
      'New code: heavier penalties, tight thresholds (lines ≤ 100, functions ≤ 40 lines)');
  String get profileStandard => _t(
      'Réglages par défaut, calibrés sur des scripts réels',
      'Default settings, calibrated on real scripts');
  String get profileLegacy => _t(
      'Code ancien : pénalités allégées, seuils assouplis, règles de pur style désactivées',
      'Old code: lighter penalties, relaxed thresholds, pure style rules disabled');
  String get contexts => _t(
      'Comment le script est lancé : active des règles propres et relève certaines sévérités',
      'How the script is run: enables specific rules and raises some severities');
  String context(ExecContext c) => switch (c) {
        ExecContext.root => _t(
            'Exécuté en root : les défauts dangereux sont plus graves',
            'Run as root: dangerous defects are more serious'),
        ExecContext.cron => _t(
            'Lancé par cron : sans terminal ni PATH, risque de lancements concurrents',
            'Run by cron: no terminal or PATH, risk of concurrent runs'),
        ExecContext.systemd => _t(
            'Service systemd : pas de saisie interactive, journal et environnement restreints',
            'systemd service: no interactive input, restricted journal and environment'),
        ExecContext.interactive => _t('Lancé à la main depuis un terminal',
            'Run by hand from a terminal'),
      };
  String tool(String name) => switch (name) {
        'shellcheck' => _t('Analyse statique du shell (la référence)',
            'Static analysis of shell (the reference)'),
        'shfmt' => _t('Formatage du shell', 'Shell formatting'),
        'bashate' => _t('Style du shell (limites de lignes, indentation)',
            'Shell style (line limits, indentation)'),
        'checkbashisms' => _t('Portabilité : constructions propres à bash',
            'Portability: bash-only constructs'),
        'ruff' => _t('Analyse et formatage Python rapides',
            'Fast Python analysis and formatting'),
        'bandit' => _t('Sécurité du code Python', 'Python code security'),
        'semgrep' => _t('Règles de sécurité Python (nécessite un accès réseau)',
            'Python security rules (needs network access)'),
        'mypy' => _t('Vérification des types Python', 'Python type checking'),
        'radon' => _t('Complexité et maintenabilité Python',
            'Python complexity and maintainability'),
        'vermin' => _t('Version minimale de Python requise par le code',
            'Minimum Python version required by the code'),
        'pydeps' => _t('Dépendances Python', 'Python dependencies'),
        'pip-audit' => _t(
            'Dépendances Python vulnérables', 'Vulnerable Python dependencies'),
        'pylint' => _t('Analyse Python complète (redondante avec Ruff)',
            'Full Python analysis (redundant with Ruff)'),
        'pyright' => _t('Vérification des types (redondante avec Mypy)',
            'Type checking (redundant with Mypy)'),
        'gitleaks' => _t('Détection de secrets', 'Secret detection'),
        'trufflehog' => _t('Détection de secrets', 'Secret detection'),
        'syntax' => _t('Vérification de la syntaxe (toujours disponible)',
            'Syntax check (always available)'),
        'hadolint' => _t('Analyse des Dockerfile', 'Dockerfile analysis'),
        'actionlint' => _t('Analyse des workflows GitHub Actions',
            'GitHub Actions workflow analysis'),
        'zizmor' => _t('Sécurité des workflows GitHub Actions',
            'GitHub Actions workflow security'),
        _ => name,
      };
  String get ruffProjectConfig => _t(
      'Utiliser ruff.toml ou pyproject.toml du projet s\'ils existent',
      'Use the project\'s ruff.toml or pyproject.toml if they exist');
  String get pythonTarget => _t(
      'Version de Python que le script doit supporter (défaut 3.9) : transmise à Vermin, Ruff, Mypy…',
      'Python version the script must support (default 3.9): passed to Vermin, Ruff, Mypy…');
  String get useCache => _t(
      'Ne pas refaire l\'analyse d\'un script inchangé : plus rapide',
      'Do not analyse an unchanged script again: faster');
  String get watchFile => _t(
      'Relancer l\'analyse à chaque enregistrement du script ouvert ou d\'un script du dossier',
      'Re-run the analysis each time the open script or a script of the folder is saved');
  String get editorCommand => _t(
      'Commande qui ouvre un fichier ; {file} et {line} sont remplacés (ex. code -g {file}:{line})',
      'Command that opens a file; {file} and {line} are replaced (e.g. code -g {file}:{line})');
  String get followSource => _t(
      'ShellCheck lit aussi les scripts chargés par « source » (shellcheck -x)',
      'ShellCheck also reads the scripts loaded by “source” (shellcheck -x)');
  String get detect => _t('Relire les outils installés et leur version',
      'Reread the installed tools and their version');
  String get importConfig => _t(
      'Le fichier devient la configuration de référence ; les choix faits dans l\'interface sont remis à zéro',
      'The file becomes the reference configuration; choices made in the interface are reset');
  String get exportConfig => _t(
      'Enregistrer la configuration effective, utilisable par la CLI et la CI',
      'Save the effective configuration, usable by the CLI and CI');
  String get removeConfig => _t('Oublier le fichier de configuration choisi',
      'Forget the chosen configuration file');
}

/// Info-bulle autour de [child] ; sans message, [child] tel quel.
Widget tip(String? message, Widget child) => message == null || message.isEmpty
    ? child
    : Tooltip(
        message: message,
        waitDuration: const Duration(milliseconds: 500),
        child: child);
