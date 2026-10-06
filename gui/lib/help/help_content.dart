/// Contenu de l'aide en ligne (français / anglais) : une page par sujet,
/// avec un résumé court (`quick`) pour l'aide contextuelle et un corps pour
/// l'écran d'aide.
///
/// Mise en forme minimale : `**gras**` et `` `code` `` dans les textes.
library;

import 'package:check_script/check_script.dart';

/// Sujets d'aide ; l'ordre est celui de la liste de l'écran d'aide.
enum HelpTopic {
  start,
  analysis,
  score,
  issues,
  fix,
  folder,
  baseline,
  compare,
  rules,
  settings,
  profiles,
  tools,
  config,
  directives,
  falsePositive,
  export,
  shortcuts,
  about,
}

/// Élément d'une page d'aide.
sealed class HelpBlock {
  const HelpBlock();
}

/// Sous-titre.
class HelpHeading extends HelpBlock {
  const HelpHeading(this.text);
  final String text;
}

/// Paragraphe.
class HelpPara extends HelpBlock {
  const HelpPara(this.text);
  final String text;
}

/// Liste à puces.
class HelpBullets extends HelpBlock {
  const HelpBullets(this.items);
  final List<String> items;
}

/// Bloc de code.
class HelpCode extends HelpBlock {
  const HelpCode(this.text);
  final String text;
}

/// Une page d'aide.
class HelpPage {
  const HelpPage(this.topic, this.title, this.quick, this.blocks);
  final HelpTopic topic;
  final String title;

  /// Résumé affiché par l'aide contextuelle (bouton « ? »).
  final String quick;
  final List<HelpBlock> blocks;

  /// Tout le texte de la page, en minuscules (recherche).
  String get searchText => [
        title,
        quick,
        for (final b in blocks)
          switch (b) {
            HelpHeading(:final text) ||
            HelpPara(:final text) ||
            HelpCode(:final text) =>
              text,
            HelpBullets(:final items) => items.join(' '),
          }
      ].join('\n').toLowerCase();
}

/// Pages d'aide dans la langue [lang].
List<HelpPage> helpPages(Lang lang) {
  String t(String fr, String en) => lang == Lang.fr ? fr : en;
  return [
    HelpPage(
      HelpTopic.start,
      t('Premiers pas', 'Getting started'),
      t('Ouvrez un script (ou déposez-le sur la fenêtre) : CheckScript l\'analyse avec ShellCheck, Ruff, Bandit… et ses règles intégrées, puis note le script de 0 à 10.',
          'Open a script (or drop it on the window): CheckScript analyses it with ShellCheck, Ruff, Bandit… and its built-in rules, then scores it from 0 to 10.'),
      [
        HelpPara(t(
            'CheckScript évalue des scripts **shell** et **Python** (ainsi que le shell embarqué dans les Dockerfile, Makefile, workflows GitHub Actions et GitLab CI) et produit une note de 0 à 10 dans cinq catégories : Sécurité, Robustesse, Maintenabilité, Portabilité et Performance.',
            'CheckScript evaluates **shell** and **Python** scripts (and the shell embedded in Dockerfiles, Makefiles, GitHub Actions and GitLab CI workflows) and gives a score from 0 to 10 in five categories: Security, Robustness, Maintainability, Portability and Performance.')),
        HelpHeading(t('En trois étapes', 'In three steps')),
        HelpBullets([
          t('**Analyser** : bouton *Ouvrir un script*, glisser-déposer d\'un script ou d\'un dossier sur la fenêtre, menu *Récents* (icône horloge), ou chemin passé en argument au lancement.',
              '**Analyse**: *Open a script* button, drag and drop a script or a folder on the window, the *Recent* menu (clock icon), or a path passed as an argument at startup.'),
          t('**Comprendre** : l\'onglet *Synthèse* donne la note globale, le radar des cinq catégories et ce qui pèse sur la note ; l\'onglet *Problèmes* liste chaque défaut avec sa ligne, sa sévérité et sa correction.',
              '**Understand**: the *Summary* tab gives the overall score, the radar of the five categories and what weighs on the score; the *Issues* tab lists each defect with its line, severity and fix.'),
          t('**Corriger** : *Corriger…* applique les corrections sûres après aperçu du diff ; chaque problème dépliable montre aussi le code à écrire.',
              '**Fix**: *Fix…* applies the safe fixes after a diff preview; each expandable issue also shows the code to write.'),
        ]),
        HelpHeading(t('Les écrans', 'The screens')),
        HelpBullets([
          t('**Analyse** : un script, source annotée et résultats.',
              '**Analysis**: one script, annotated source and results.'),
          t('**Dossier** : tous les scripts d\'un dossier, en tableau.',
              '**Folder**: all the scripts of a folder, in a table.'),
          t('**Règles** : choisir les règles qui sont signalées.',
              '**Rules**: choose which rules are reported.'),
          t('**Réglages** : langue, thème, profil, outils, configuration.',
              '**Settings**: language, theme, profile, tools, configuration.'),
          t('**Aide** : cette page. **F1** ouvre l\'aide du sujet en cours.',
              '**Help**: this page. **F1** opens the help of the current topic.'),
        ]),
        HelpPara(t(
            'Partout dans l\'interface, laissez la souris sur un bouton ou une étiquette : une info-bulle l\'explique. Les icônes **?** ouvrent l\'aide du sujet concerné.',
            'Everywhere in the interface, leave the mouse over a button or a label: a tooltip explains it. The **?** icons open the help of the topic concerned.')),
      ],
    ),
    HelpPage(
      HelpTopic.analysis,
      t('Écran Analyse', 'Analysis screen'),
      t('À gauche, le code annoté (marque de sévérité dans la marge) ; à droite, la synthèse des notes et la liste des problèmes. Un clic sur un problème amène le code à la ligne concernée.',
          'On the left, the annotated code (severity mark in the margin); on the right, the score summary and the list of issues. Clicking an issue moves the code to its line.'),
      [
        HelpHeading(t('Barre d\'outils', 'Toolbar')),
        HelpBullets([
          t('**Ouvrir un script** : choisit un script shell ou Python à analyser.',
              '**Open a script**: picks a shell or Python script to analyse.'),
          t('**Relancer l\'analyse** : refait l\'analyse (après une modification du script, des règles ou des réglages).',
              '**Re-run analysis**: analyses again (after a change to the script, the rules or the settings).'),
          t('**Corriger…** : propose les corrections automatiques sûres, avec aperçu.',
              '**Fix…**: proposes the safe automatic fixes, with a preview.'),
          t('**Exporter…** : écrit un rapport (HTML, PDF, Markdown, AsciiDoc, JSON, SARIF, texte).',
              '**Export…**: writes a report (HTML, PDF, Markdown, AsciiDoc, JSON, SARIF, text).'),
          t('**Ouvrir dans l\'éditeur** : ouvre le script à la ligne sélectionnée.',
              '**Open in editor**: opens the script at the selected line.'),
          t('**Charger une référence…** : compare avec un rapport JSON antérieur (voir *Référence*).',
              '**Load a baseline…**: compares with an earlier JSON report (see *Baseline*).'),
          t('**Définir comme référence…** : enregistre l\'analyse affichée comme référence, en un clic (voir *Référence*).',
              '**Set as baseline…**: saves the displayed analysis as the baseline, in one click (see *Baseline*).'),
          t('**Comparer…** : compare l\'analyse affichée à un rapport JSON antérieur, côte à côte (voir *Comparer deux analyses*).',
              '**Compare…**: compares the displayed analysis with an earlier JSON report, side by side (see *Comparing two analyses*).'),
        ]),
        HelpHeading(t('Modifier le script', 'Editing the script')),
        HelpBullets([
          t('Le **crayon** au-dessus du code ouvre un éditeur de texte dans le panneau : pour un petit correctif, sans passer par l\'éditeur externe. **Tab** insère une tabulation.',
              'The **pencil** above the code opens a text editor in the panel: for a small fix, without going through the external editor. **Tab** inserts a tab.'),
          t('**Ctrl+S** ou **Enregistrer** écrit le fichier (une copie **.orig** garde l\'original, les fins de ligne sont conservées) et relance l\'analyse. **Abandonner** supprime les modifications.',
              '**Ctrl+S** or **Save** writes the file (a **.orig** copy keeps the original, line endings are kept) and re-runs the analysis. **Discard** drops the changes.'),
          t('Les modifications non enregistrées forment un **brouillon** : il survit au changement d\'onglet (pastille ● devant le nom) et un bandeau le rappelle. Fermer un onglet modifié demande confirmation.',
              'Unsaved changes form a **draft**: it survives tab changes (● mark before the name) and a banner reminds it. Closing a modified tab asks for confirmation.'),
          t('Si le fichier a changé sur le disque depuis l\'analyse, l\'enregistrement est refusé : relancez l\'analyse, votre brouillon est conservé.',
              'If the file changed on disk since the analysis, saving is refused: re-run the analysis, your draft is kept.'),
        ]),
        HelpHeading(t('Plusieurs scripts', 'Several scripts')),
        HelpBullets([
          t('*Ouvrir un script* accepte plusieurs fichiers (Ctrl+clic ou Maj+clic) ; on peut aussi en déposer plusieurs sur la fenêtre : chaque script a son **onglet**.',
              '*Open a script* accepts several files (Ctrl+click or Shift+click); you can also drop several on the window: each script gets its own **tab**.'),
          t('La barre d\'onglets apparaît dès deux scripts. Un clic affiche le script (son analyse est mémorisée, et refaite si le fichier a changé) ; la croix le ferme. **Ctrl+Tab** / **Ctrl+Maj+Tab** passent d\'un onglet à l\'autre, **Ctrl+W** ferme l\'onglet affiché.',
              'The tab bar appears from two scripts on. A click shows the script (its analysis is kept, and redone if the file changed); the cross closes it. **Ctrl+Tab** / **Ctrl+Shift+Tab** switch tabs, **Ctrl+W** closes the displayed tab.'),
        ]),
        HelpHeading(t('Le code', 'The code')),
        HelpBullets([
          t('La **marque colorée** dans la marge indique la plus grave sévérité de la ligne ; survolez la ligne pour lire les problèmes.',
              'The **coloured mark** in the margin shows the worst severity of the line; hover the line to read the issues.'),
          t('**A−/A+** (au-dessus du code) règlent la taille du texte ; un clic sur la taille la remet par défaut.',
              '**A−/A+** (above the code) set the text size; a click on the size resets it.'),
          t('La **barre verticale** entre le code et les résultats se déplace à la souris ; un double-clic rétablit la répartition par défaut, ses flèches replient un panneau.',
              'The **bar** between the code and the results can be dragged; a double-click restores the default split, its arrows collapse a panel.'),
          t('La **loupe** (ou **Ctrl+F**, onglet Synthèse affiché) ouvre la recherche dans le code : les lignes trouvées sont teintées, **Entrée** va à la suivante, **Maj+Entrée** à la précédente, **Échap** ferme.',
              'The **magnifier** (or **Ctrl+F**, Summary tab shown) opens the code search: matching lines are tinted, **Enter** goes to the next one, **Shift+Enter** to the previous one, **Esc** closes.'),
        ]),
        HelpPara(t(
            'Le script ouvert est **surveillé** : à chaque enregistrement, l\'analyse est relancée (réglable dans *Réglages*).',
            'The open script is **watched**: on each save, the analysis is re-run (can be changed in *Settings*).')),
      ],
    ),
    HelpPage(
      HelpTopic.score,
      t('Comprendre la note', 'Understanding the score'),
      t('Chaque catégorie part de 10 et perd des points selon la sévérité des problèmes. La note globale est la moyenne pondérée, plafonnée à la plus faible catégorie + 1,5. Niveaux : A ≥ 9 · B ≥ 7,5 · C ≥ 6 · D ≥ 4 · E < 4.',
          'Each category starts at 10 and loses points according to the severity of the issues. The overall score is the weighted mean, capped at the weakest category + 1.5. Levels: A ≥ 9 · B ≥ 7.5 · C ≥ 6 · D ≥ 4 · E < 4.'),
      [
        HelpHeading(t('Sévérités', 'Severities')),
        HelpBullets([
          t('**Critical** : compromission ou destruction probable (code téléchargé puis exécuté, secret en dur, `rm -rf /`, syntaxe invalide).',
              '**Critical**: probable compromise or destruction (downloaded code executed, hard-coded secret, `rm -rf /`, invalid syntax).'),
          t('**High** : défaut sérieux et exploitable (`eval` d\'une variable, `chmod 777`, TLS désactivé, `cd` non vérifié).',
              '**High**: serious exploitable defect (`eval` of a variable, `chmod 777`, disabled TLS, unchecked `cd`).'),
          t('**Medium** : défaut réel à effet limité (variable non protégée, pas de `set -e`, fichier temporaire prévisible).',
              '**Medium**: real defect with limited effect (unquoted variable, no `set -e`, predictable temporary file).'),
          t('**Low** : style, lisibilité, performance, bonnes pratiques.',
              '**Low**: style, readability, performance, good practices.'),
        ]),
        HelpHeading(t('Calcul', 'Computation')),
        HelpCode(
            'note = 10 − Σ pénalités          (plancher 0, arrondi au dixième)\n'
            'pénalité d\'une règle déclenchée n fois = poids × (1 + log2 n)\n'
            'poids (profil standard) : Critical 4 · High 2 · Medium 0,75 · Low 0,25'),
        HelpBullets([
          t('Une règle répétée 8 fois coûte 4 fois son poids, pas 8 : les répétitions traduisent une seule habitude.',
              'A rule repeated 8 times costs 4 times its weight, not 8: repetitions reflect a single habit.'),
          t('Au-delà de 100 lignes de code, les pénalités Medium et Low sont atténuées ; Critical et High ne le sont jamais.',
              'Beyond 100 lines of code, Medium and Low penalties are attenuated; Critical and High never are.'),
          t('La note globale pondère les catégories (Sécurité 1,5 · Robustesse 1,25 · Maintenabilité 1 · Portabilité 0,75 · Performance 0,5) et ne dépasse jamais la plus faible + 1,5 : une catégorie faible ne se cache pas derrière les autres.',
              'The overall score weights the categories (Security 1.5 · Robustness 1.25 · Maintainability 1 · Portability 0.75 · Performance 0.5) and never exceeds the weakest + 1.5: a weak category cannot hide behind the others.'),
        ]),
        HelpHeading(t('Améliorer la note', 'Improving the score')),
        HelpPara(t(
            '« **Ce qui pèse sur la note** » classe les règles par points retirés et par **gain** sur la note globale si toutes leurs occurrences sont corrigées. Un gain nul signifie que la note est plafonnée par une autre catégorie plus faible : commencez par celle-là. La ligne « → Niveau B (7,6) en corrigeant : … » indique le chemin le plus court vers le niveau supérieur.',
            '“**What weighs on the score**” ranks the rules by points removed and by **gain** on the overall score if all their occurrences are fixed. A zero gain means the score is capped by another, weaker category: fix that one first. The line “→ Grade B (7.6) by fixing: …” shows the shortest path to the next grade.')),
        HelpPara(t(
            'Les valeurs dépendent du **profil** (strict, standard, legacy) : voir *Profils et contextes*.',
            'The values depend on the **profile** (strict, standard, legacy): see *Profiles and contexts*.')),
      ],
    ),
    HelpPage(
      HelpTopic.issues,
      t('Liste des problèmes', 'List of issues'),
      t('Filtrez par catégorie et par sévérité, triez par catégorie ou par gain rapide ; dépliez un problème pour voir le code à écrire, le corriger, l\'ouvrir dans l\'éditeur ou ne plus signaler sa règle.',
          'Filter by category and severity, sort by category or quick win; expand an issue to see the code to write, fix it, open it in the editor or stop reporting its rule.'),
      [
        HelpHeading(t('Lire un problème', 'Reading an issue')),
        HelpBullets([
          t('Le **badge** donne la sévérité ; **L12** est la ligne (« fichier entier » si le problème concerne tout le script).',
              'The **badge** gives the severity; **L12** is the line (“whole file” if the issue concerns the entire script).'),
          t('La ligne grise indique le **code de la règle**, l\'**outil** qui l\'a détectée et la **catégorie** ; viennent ensuite la suggestion (→) et les références CWE / OWASP / ANSSI.',
              'The grey line gives the **rule code**, the **tool** that detected it and the **category**; then come the suggestion (→) and the CWE / OWASP / ANSSI references.'),
          t('L\'icône **↗** ouvre la documentation de la règle dans le navigateur.',
              'The **↗** icon opens the rule\'s documentation in the browser.'),
        ]),
        HelpHeading(t('Filtres et tri', 'Filters and sorting')),
        HelpBullets([
          t('Le **champ de recherche** (ou **Ctrl+F**, onglet Problèmes affiché) filtre par code de règle, texte, outil, catégorie, référence ou ligne (`SEC003`, `eval`, `L12`) ; plusieurs mots : tous doivent y figurer.',
              'The **search field** (or **Ctrl+F**, Issues tab shown) filters by rule code, text, tool, category, reference or line (`SEC003`, `eval`, `L12`); several words: all must match.'),
          t('Les **pastilles** de catégorie et de sévérité masquent ou affichent les problèmes correspondants ; le nombre entre parenthèses est le total de la catégorie.',
              'The category and severity **chips** hide or show the matching issues; the number in brackets is the category total.'),
          t('**Par catégorie** : ordre du rapport. **Par gain rapide** : du plus rentable au moins rentable (une règle corrigeable automatiquement compte 1,5 fois son gain).',
              '**By category**: report order. **By quick win**: from the most to the least profitable (an automatically fixable rule counts 1.5 times its gain).'),
        ]),
        HelpHeading(t('Un problème déplié', 'An expanded issue')),
        HelpBullets([
          t('**Copier** : copie le code proposé.',
              '**Copy**: copies the proposed code.'),
          t('**Appliquer cette correction** : corrige cette occurrence. **Corriger les N occurrences** : toute la règle.',
              '**Apply this fix**: fixes this occurrence. **Fix all N occurrences**: the whole rule.'),
          t('**Ouvrir dans l\'éditeur (ligne N)**, **Signaler un faux positif**, **Ne plus signaler la règle**.',
              '**Open in editor (line N)**, **Report a false positive**, **Stop reporting the rule**.'),
        ]),
        HelpPara(t(
            'Les cases à cocher des problèmes corrigeables préparent une **correction groupée** (voir *Corrections automatiques*).',
            'The checkboxes of fixable issues prepare a **grouped fix** (see *Automatic fixes*).')),
      ],
    ),
    HelpPage(
      HelpTopic.fix,
      t('Corrections automatiques', 'Automatic fixes'),
      t('Seules les transformations sûres sont appliquées. Un diff est toujours montré avant l\'écriture, l\'original est gardé en .orig, et rien n\'est écrit si la syntaxe deviendrait invalide.',
          'Only safe transformations are applied. A diff is always shown before writing, the original is kept as .orig, and nothing is written if the syntax would become invalid.'),
      [
        HelpHeading(t('Ce qui est corrigé', 'What is fixed')),
        HelpBullets([
          t('les corrections proposées par ShellCheck (guillemets, `cd … || exit`, backticks…) ;',
              'the fixes proposed by ShellCheck (quoting, `cd … || exit`, backticks…);'),
          t('les corrections intégrées : fins de ligne CRLF, espaces en fin de ligne, backticks → `\$(…)`, `egrep`/`fgrep` → `grep -E`/`-F`, `which` → `command -v`, `read` → `read -r` ;',
              'built-in fixes: CRLF line endings, trailing spaces, backticks → `\$(…)`, `egrep`/`fgrep` → `grep -E`/`-F`, `which` → `command -v`, `read` → `read -r`;'),
          t('le formatage shfmt, dans le style d\'indentation du script.',
              'shfmt formatting, in the script\'s indentation style.'),
        ]),
        HelpHeading(t('Trois façons de corriger', 'Three ways to fix')),
        HelpBullets([
          t('**Corriger…** (barre d\'outils) : toutes les corrections sûres du script, après aperçu.',
              '**Fix…** (toolbar): all the safe fixes of the script, after a preview.'),
          t('**Appliquer cette correction** / **Corriger les N occurrences** : depuis un problème déplié.',
              '**Apply this fix** / **Fix all N occurrences**: from an expanded issue.'),
          t('**Corriger la sélection** : cochez des problèmes (ou *Corrigeables affichés* pour tout cocher selon les filtres) ; le diff global s\'affiche avant application.',
              '**Fix selection**: tick issues (or *Fixable shown* to tick them all according to the filters); the global diff is shown before applying.'),
        ]),
        HelpPara(t(
            'Si le fichier a changé depuis l\'analyse, relancez l\'analyse avant de corriger. Pour les règles sans correction automatique, le problème déplié montre un exemple « à éviter / à écrire ».',
            'If the file changed since the analysis, re-run it before fixing. For rules without an automatic fix, the expanded issue shows an “avoid / write instead” example.')),
      ],
    ),
    HelpPage(
      HelpTopic.folder,
      t('Écran Dossier', 'Folder screen'),
      t('Analyse tous les scripts d\'un dossier et les présente en tableau triable ; un clic sur une ligne ouvre le script dans l\'écran Analyse. L\'historique montre l\'évolution de la note moyenne.',
          'Analyses all the scripts of a folder and shows them in a sortable table; a click on a row opens the script in the Analysis screen. The history shows the evolution of the average score.'),
      [
        HelpBullets([
          t('**Ouvrir un dossier** ou déposez-le sur la fenêtre ; plusieurs scripts sont analysés en parallèle, et le dossier est surveillé (scripts créés ou enregistrés réanalysés).',
              '**Open a folder** or drop it on the window; several scripts are analysed in parallel, and the folder is watched (created or saved scripts are re-analysed).'),
          t('Cliquez sur un **en-tête de colonne** pour trier ; un second clic inverse l\'ordre.',
              'Click a **column header** to sort; a second click reverses the order.'),
          t('La colonne **Tendance** apparaît quand une référence est chargée : évolution de la note de chaque script.',
              'The **Trend** column appears when a baseline is loaded: evolution of each script\'s score.'),
          t('**Historique** : courbe de la note moyenne des analyses successives du dossier (200 analyses conservées par dossier).',
              '**History**: curve of the average score of the folder\'s successive analyses (200 analyses kept per folder).'),
          t('Les chemins listés dans le fichier **.checkscriptignore** du dossier (syntaxe .gitignore) ou dans la clé `exclude` de la configuration sont ignorés.',
              'Paths listed in the folder\'s **.checkscriptignore** file (.gitignore syntax) or in the `exclude` key of the configuration are ignored.'),
          t('**Définir comme référence…** enregistre l\'analyse de tout le dossier comme référence ; la colonne *Tendance* montre ensuite l\'évolution de chaque script.',
              '**Set as baseline…** saves the analysis of the whole folder as the baseline; the *Trend* column then shows each script\'s evolution.'),
          t('**Exporter…** : le rapport HTML d\'un dossier commence par un résumé (note moyenne, niveaux, problèmes par sévérité), un tableau triable et les règles les plus fréquentes.',
              '**Export…**: a folder\'s HTML report starts with a summary (average score, grades, issues by severity), a sortable table and the most frequent rules.'),
        ]),
      ],
    ),
    HelpPage(
      HelpTopic.baseline,
      t('Référence (baseline)', 'Baseline'),
      t('Un rapport JSON antérieur sert de référence : seuls les nouveaux problèmes sont détaillés et l\'évolution des notes est affichée. Idéal pour adopter l\'outil sur du code existant.',
          'An earlier JSON report serves as a baseline: only new issues are detailed and the evolution of the scores is shown. Ideal to adopt the tool on existing code.'),
      [
        HelpBullets([
          t('**Définir comme référence…** (écrans Analyse et Dossier) : choisissez où enregistrer le rapport JSON ; il est écrit puis chargé comme référence en un clic.',
              '**Set as baseline…** (Analysis and Folder screens): choose where to save the JSON report; it is written then loaded as the baseline in one click.'),
          t('Pour la partager avec la CI, enregistrez-la dans le dépôt : `check-script -b référence.json --fail-on-new high`. Un rapport exporté en **JSON** convient aussi.',
              'To share it with CI, save it in the repository: `check-script -b baseline.json --fail-on-new high`. A report exported as **JSON** works too.'),
          t('*Charger une référence…* : choisissez ce fichier ; la puce *Référence chargée* apparaît (la croix la retire).',
              '*Load a baseline…*: choose that file; the *Baseline loaded* chip appears (the cross removes it).'),
          t('Les problèmes sont rapprochés par une **empreinte indépendante du numéro de ligne** : ajouter du code au-dessus d\'un problème connu ne le rend pas « nouveau ».',
              'Issues are matched by a **fingerprint independent of the line number**: adding code above a known issue does not make it look new.'),
          t('Le résumé indique « nouveaux · corrigés · inchangés » et l\'écart de note (+1,3 en vert, −0,4 en rouge) ; le radar superpose l\'ancienne forme.',
              'The summary shows “new · fixed · unchanged” and the score difference (+1.3 in green, −0.4 in red); the radar overlays the old shape.'),
        ]),
        HelpPara(t(
            'Pour voir en détail ce qui a changé entre deux états, utilisez **Comparer…** (voir *Comparer deux analyses*).',
            'To see in detail what changed between two states, use **Compare…** (see *Comparing two analyses*).')),
        HelpPara(t(
            'C\'est la bonne façon d\'adopter l\'outil : la dette actuelle est tolérée, toute nouvelle dette se voit.',
            'This is the way to adopt the tool: the current debt is tolerated, any new debt shows.')),
      ],
    ),
    HelpPage(
      HelpTopic.compare,
      t('Comparer deux analyses', 'Comparing two analyses'),
      t('Le bouton « Comparer… » met côte à côte un état « avant » (rapport JSON ou référence) et un état « après » : problèmes corrigés en vert à gauche, nouveaux en rouge à droite.',
          'The “Compare…” button puts a “before” state (JSON report or baseline) and an “after” state side by side: fixed issues in green on the left, new ones in red on the right.'),
      [
        HelpBullets([
          t('**Avant** : *Choisir un rapport JSON…* (un rapport exporté en JSON, ou produit par `check-script -o rapport.json`), ou *Référence chargée* si une référence est active.',
              '**Before**: *Pick a JSON report…* (a report exported as JSON, or produced by `check-script -o report.json`), or *Loaded baseline* when a baseline is active.'),
          t('**Après** : *Analyse affichée* (le script, ou le dossier si vous venez de l\'écran Dossier) ou *Fichier JSON…* pour comparer deux rapports.',
              '**After**: *Displayed analysis* (the script, or the folder when you come from the Folder screen) or *JSON file…* to compare two reports.'),
          t('Le résumé donne la note moyenne avant → après, le nombre de problèmes **nouveaux**, **corrigés** et **inchangés**, et les scripts ajoutés ou retirés.',
              'The summary gives the average score before → after, the number of **new**, **fixed** and **unchanged** issues, and the added or removed scripts.'),
          t('La liste des scripts met en tête les **régressions**, puis ceux qui ont des problèmes nouveaux. Un clic affiche les deux états côte à côte ; la pastille *Inchangés* ajoute les problèmes qui n\'ont pas bougé.',
              'The script list puts **regressions** first, then those with new issues. A click shows both states side by side; the *Unchanged* chip adds the issues that did not move.'),
          t('Les problèmes sont appariés par **empreinte**, indépendante du numéro de ligne : du code ajouté au-dessus ne crée pas de faux « nouveau ».',
              'Issues are matched by **fingerprint**, independent of the line number: code added above does not create a false “new”.'),
          t('**Copier (Markdown)** met la comparaison dans le presse-papiers, prête pour un commentaire de merge request.',
              '**Copy (Markdown)** puts the comparison on the clipboard, ready for a merge request comment.'),
        ]),
        HelpPara(t(
            'La même comparaison existe en ligne de commande : `check-script diff avant.json apres.json` (avec `--fail-on-new` et `--fail-on-worse` pour la CI).',
            'The same comparison exists on the command line: `check-script diff before.json after.json` (with `--fail-on-new` and `--fail-on-worse` for CI).')),
      ],
    ),
    HelpPage(
      HelpTopic.rules,
      t('Écran Règles', 'Rules screen'),
      t('Toutes les règles de détection, chacune avec une case à cocher : une règle décochée n\'est plus signalée à partir de la prochaine analyse.',
          'All the detection rules, each with a checkbox: an unticked rule is no longer reported from the next analysis.'),
      [
        HelpBullets([
          t('Les règles viennent de CheckScript (intégrées), des outils (ShellCheck, Ruff, Bandit, Pylint…) et des codes **rencontrés** lors de vos analyses.',
              'Rules come from CheckScript (built-in), from the tools (ShellCheck, Ruff, Bandit, Pylint…) and from codes **encountered** during your analyses.'),
          t('**Recherche** (**Ctrl+F**) : par code, texte, outil, CWE, OWASP ou ANSSI. Les listes filtrent par langage, outil et catégorie.',
              '**Search** (**Ctrl+F**): by code, text, tool, CWE, OWASP or ANSSI. The lists filter by language, tool and category.'),
          t('L\'icône **ⓘ** d\'une règle ouvre son **détail** : description, catégorie, sévérité, références, exemple « à éviter / à écrire », équivalents dans d\'autres outils, occurrences dans le script et le dossier affichés, interrupteur d\'activation et façons de l\'ignorer (la même chose que `check-script explain`).',
              'The **ⓘ** icon of a rule opens its **details**: description, category, severity, references, “avoid / write instead” example, equivalents in other tools, occurrences in the displayed script and folder, enable switch and ways to ignore it (the same as `check-script explain`).'),
          t('**Tout réactiver (N)** recoche toutes les règles que vous avez désactivées.',
              '**Enable all (N)** re-ticks all the rules you disabled.'),
          t('**Autre code à désactiver** : saisissez n\'importe quel code (ex. `SC2317`), même absent de la liste.',
              '**Other code to disable**: type any code (e.g. `SC2317`), even one missing from the list.'),
          t('Une règle **grisée** est désactivée par le profil ou le fichier YAML : elle ne se modifie pas ici.',
              'A **greyed-out** rule is disabled by the profile or the YAML file: it cannot be changed here.'),
          t('Une règle est désactivée par son identifiant, quel que soit l\'outil, comme `rules.disabled` dans la configuration. Le choix est mémorisé.',
              'A rule is disabled by its identifier, whatever the tool, like `rules.disabled` in the configuration. The choice is remembered.'),
        ]),
        HelpPara(t(
            'Pensez à **Relancer l\'analyse** : les changements ne s\'appliquent qu\'à la prochaine analyse.',
            'Remember to **Re-run analysis**: changes only apply from the next analysis.')),
      ],
    ),
    HelpPage(
      HelpTopic.settings,
      t('Réglages', 'Settings'),
      t('Langue, thème, police du code, profil, contextes, outils, éditeur, cache et surveillance. Les choix sont mémorisés.',
          'Language, theme, code font, profile, contexts, tools, editor, cache and watching. Choices are remembered.'),
      [
        HelpBullets([
          t('**Langue** : français, anglais, ou celle du système. Les messages des outils externes restent en anglais.',
              '**Language**: French, English, or the system\'s. Messages of external tools stay in English.'),
          t('**Thème** : clair, sombre ou système.',
              '**Theme**: light, dark or system.'),
          t('**Police du code** : JetBrains Mono (intégrée) ou toute police à chasse fixe installée (liste, ou nom saisi puis Entrée) ; la flèche circulaire revient à la police intégrée. La taille se règle aussi avec Ctrl+plus / Ctrl+moins.',
              '**Code font**: JetBrains Mono (built in) or any installed monospaced font (list, or name typed then Enter); the circular arrow returns to the built-in font. The size can also be set with Ctrl+plus / Ctrl+minus.'),
          t('**Version minimale de Python** : cible des outils comme Vermin et Ruff.',
              '**Minimum Python version**: target of tools such as Vermin and Ruff.'),
          t('**Réutiliser les résultats d\'un script inchangé** (cache) : accélère les analyses répétées.',
              '**Reuse results of an unchanged script** (cache): speeds up repeated analyses.'),
          t('**Relancer l\'analyse à l\'enregistrement** : surveille le script ouvert ou le dossier.',
              '**Re-run the analysis when a script is saved**: watches the open script or folder.'),
          t('**Commande de l\'éditeur** : `{file}` et `{line}` sont remplacés (ex. `code -g {file}:{line}`). Vide : éditeur détecté (VS Code, VSCodium, GNOME Text Editor, gedit, Kate, KWrite, Xed, Geany), sinon `xdg-open`.',
              '**Editor command**: `{file}` and `{line}` are replaced (e.g. `code -g {file}:{line}`). Empty: detected editor (VS Code, VSCodium, GNOME Text Editor, gedit, Kate, KWrite, Xed, Geany), otherwise `xdg-open`.'),
          t('**Suivre les fichiers sourcés** : ShellCheck lit aussi les scripts chargés par `source` (`shellcheck -x`).',
              '**Follow sourced files**: ShellCheck also reads the scripts loaded by `source` (`shellcheck -x`).'),
        ]),
        HelpPara(t(
            'Profil, contextes, outils et fichier YAML ont leur propre page d\'aide.',
            'Profile, contexts, tools and the YAML file have their own help pages.')),
      ],
    ),
    HelpPage(
      HelpTopic.profiles,
      t('Profils et contextes', 'Profiles and contexts'),
      t('Le profil règle la sévérité de la notation (strict pour du neuf, standard, legacy pour du code ancien) ; les contextes d\'exécution (root, cron, systemd) activent des règles et relèvent certaines sévérités.',
          'The profile sets the strictness of the scoring (strict for new code, standard, legacy for old code); execution contexts (root, cron, systemd) enable rules and raise some severities.'),
      [
        HelpHeading(t('Profil de notation', 'Scoring profile')),
        HelpBullets([
          t('**Strict** (nouveaux scripts) : poids Critical 5, High 3, Medium 1, Low 0,4 ; atténuation dès 50 lignes ; lignes ≤ 100, fonctions ≤ 40 lignes, imbrication ≤ 3.',
              '**Strict** (new scripts): weights Critical 5, High 3, Medium 1, Low 0.4; attenuation from 50 lines; lines ≤ 100, functions ≤ 40 lines, nesting ≤ 3.'),
          t('**Standard** : les réglages décrits dans *Comprendre la note*.',
              '**Standard**: the settings described in *Understanding the score*.'),
          t('**Existant (legacy)** : code ancien — High 1,5, Medium 0,5, Low 0,1 ; seuils assouplis ; règles de pur style désactivées.',
              '**Legacy**: old code — High 1.5, Medium 0.5, Low 0.1; relaxed thresholds; pure style rules disabled.'),
        ]),
        HelpHeading(t('Contextes d\'exécution', 'Execution contexts')),
        HelpPara(t(
            'Déclarer comment le script est lancé active des règles propres et relève (jamais n\'abaisse) des sévérités :',
            'Declaring how the script is run enables specific rules and raises (never lowers) severities:')),
        HelpBullets([
          t('**root** : PATH non défini (SEC017) ; fichier temporaire prévisible, téléchargement en clair, `source` non fiable → High ; `chmod 777`, `rm -rf "\$VAR/"`, `cd` non vérifié → Critical ; pas de `set -e` → High.',
              '**root**: PATH not set (SEC017); predictable temporary file, cleartext download, untrusted `source` → High; `chmod 777`, `rm -rf "\$VAR/"`, unchecked `cd` → Critical; no `set -e` → High.'),
          t('**cron** : pas de verrou (ROB014), saisie interactive (ROB015), PATH non défini (ROB016) ; pas de `set -e` → High ; `set -x` → Medium.',
              '**cron**: no lock (ROB014), interactive input (ROB015), PATH not set (ROB016); no `set -e` → High; `set -x` → Medium.'),
          t('**systemd** : SEC017, ROB015 ; pas de `set -e` → High ; `set -x` → Medium.',
              '**systemd**: SEC017, ROB015; no `set -e` → High; `set -x` → Medium.'),
        ]),
      ],
    ),
    HelpPage(
      HelpTopic.tools,
      t('Outils d\'analyse', 'Analysis tools'),
      t('CheckScript s\'appuie sur des outils externes s\'ils sont installés. Chaque interrupteur l\'active ou le désactive ; « Détecter » relit les outils présents et leur version.',
          'CheckScript relies on external tools when they are installed. Each switch enables or disables it; “Detect” rereads the tools present and their version.'),
      [
        HelpBullets([
          t('**Scripts shell** : ShellCheck (analyse), shfmt (format), bashate (style), checkbashisms (portabilité).',
              '**Shell scripts**: ShellCheck (analysis), shfmt (format), bashate (style), checkbashisms (portability).'),
          t('**Scripts Python** : Ruff, Bandit (sécurité), Semgrep (règles `p/python`, **accès réseau**), Mypy (types), Radon (complexité), Vermin (version minimale), pydeps, pip-audit (dépendances vulnérables), Pylint et Pyright (redondants : désactivés par défaut).',
              '**Python scripts**: Ruff, Bandit (security), Semgrep (`p/python` rules, **network access**), Mypy (types), Radon (complexity), Vermin (minimum version), pydeps, pip-audit (vulnerable dependencies), Pylint and Pyright (redundant: disabled by default).'),
          t('**Tous les scripts** : gitleaks et trufflehog (secrets), et la vérification de **syntaxe** (`bash -n`, `sh -n`, `python3 compile()`).',
              '**All scripts**: gitleaks and trufflehog (secrets), and the **syntax** check (`bash -n`, `sh -n`, `python3 compile()`).'),
          t('**Dockerfile et workflows GitHub Actions** : hadolint, actionlint, zizmor.',
              '**Dockerfiles and GitHub Actions workflows**: hadolint, actionlint, zizmor.'),
          t('**Ruff : respecter la configuration du projet** : utilise `ruff.toml` / `pyproject.toml` s\'ils existent.',
              '**Ruff: follow the project configuration**: uses `ruff.toml` / `pyproject.toml` when present.'),
        ]),
        HelpPara(t(
            'Un outil « non installé » est simplement ignoré : les règles intégrées de CheckScript s\'appliquent toujours. Pour un résultat complet, installez au moins ShellCheck (shell) et Ruff + Bandit (Python).',
            'A “not installed” tool is simply skipped: CheckScript\'s built-in rules always apply. For a complete result, install at least ShellCheck (shell) and Ruff + Bandit (Python).')),
      ],
    ),
    HelpPage(
      HelpTopic.config,
      t('Fichier de configuration YAML', 'YAML configuration file'),
      t('Un fichier .checkscript.yaml partagé avec la CLI et la CI : profil, contextes, règles désactivées ou personnalisées, poids, seuils. Importer le choisit comme référence ; exporter écrit la configuration effective.',
          'A .checkscript.yaml file shared with the CLI and CI: profile, contexts, disabled or custom rules, weights, thresholds. Importing makes it the reference; exporting writes the effective configuration.'),
      [
        HelpBullets([
          t('**Importer…** : le fichier devient la configuration de référence ; son profil et ses contextes sont repris et les choix faits dans l\'interface (règles, outils) sont remis à zéro.',
              '**Import…**: the file becomes the reference configuration; its profile and contexts are taken over and the choices made in the interface (rules, tools) are reset.'),
          t('**Exporter…** : écrit la configuration effective (fichier + choix de l\'interface) dans un `.checkscript.yaml` : la CLI et la CI noteront comme l\'interface.',
              '**Export…**: writes the effective configuration (file + interface choices) to a `.checkscript.yaml`: the CLI and CI will score like the interface.'),
          t('**Retirer** : oublie le fichier choisi.',
              '**Remove**: forgets the chosen file.'),
          t('Sans fichier choisi, le `.checkscript.yaml` du projet du script ou du dossier analysé s\'applique (le plus proche en remontant jusqu\'à la racine git).',
              'With no file chosen, the `.checkscript.yaml` of the analysed script\'s or folder\'s project applies (the nearest one, up to the git root).'),
        ]),
        HelpCode('profile: strict            # strict | default | legacy\n'
            'context: [root]            # root, cron, systemd\n'
            'exclude: [vendor/, "*.min.sh"]   # chemins ignorés (.gitignore)\n'
            'rules:\n'
            '  disabled: [MNT005, E006]\n'
            'tools:\n'
            '  semgrep: false           # machine sans réseau\n'
            'thresholds:\n'
            '  maxFunctionLines: 60'),
        HelpPara(t(
            'Un exemple commenté complet est fourni dans `doc/checkscript.example.yaml`.',
            'A complete commented example is provided in `doc/checkscript.example.yaml`.')),
      ],
    ),
    HelpPage(
      HelpTopic.directives,
      t('Directives dans le script', 'Directives in the script'),
      t('Un faux positif ou un choix délibéré se neutralise dans le script lui-même avec un commentaire « # check-script disable=… ».',
          'A false positive or a deliberate choice can be neutralized in the script itself with a “# check-script disable=…” comment.'),
      [
        HelpCode(
            '# check-script disable-file=MNT005,E003      # tout le fichier\n'
            '\n'
            '# check-script disable=SEC005                # seul : ligne de code suivante\n'
            'curl -k "\$INTERNAL_URL"\n'
            '\n'
            'eval "\$SAFE_CMD"  # check-script disable=SEC003   # cette ligne\n'
            '# check-script disable-next-line=SEC022'),
        HelpBullets([
          t('Les identifiants acceptent un joker final (`SC20*`) et `all`.',
              'Identifiers accept a trailing wildcard (`SC20*`) and `all`.'),
          t('Le nombre de problèmes neutralisés apparaît dans le rapport.',
              'The number of neutralized issues appears in the report.'),
          t('Une directive devenue inutile est signalée par **MNT011** pour être retirée.',
              'A directive that has become useless is reported by **MNT011** so it can be removed.'),
          t('Python : `# noqa`, `# noqa: S307`, `# nosec` et `# nosec B602` s\'appliquent à tous les outils ; ShellCheck garde ses `# shellcheck disable=…`.',
              'Python: `# noqa`, `# noqa: S307`, `# nosec` and `# nosec B602` apply to all tools; ShellCheck keeps its `# shellcheck disable=…`.'),
        ]),
      ],
    ),
    HelpPage(
      HelpTopic.falsePositive,
      t('Signaler un faux positif', 'Reporting a false positive'),
      t('Depuis un problème déplié : le cas est enregistré sur votre poste, anonymisé, pour améliorer les règles. Il n\'est jamais envoyé nulle part.',
          'From an expanded issue: the case is saved on your computer, anonymised, to improve the rules. It is never sent anywhere.'),
      [
        HelpBullets([
          t('L\'aperçu montre exactement ce qui sera enregistré : le contenu des chaînes et les longs jetons sont masqués ; la ligne d\'un secret n\'est jamais copiée.',
              'The preview shows exactly what will be saved: string contents and long tokens are masked; a secret\'s line is never copied.'),
          t('Ajoutez un commentaire (facultatif) pour expliquer pourquoi c\'est un faux positif.',
              'Add a comment (optional) to explain why it is a false positive.'),
          t('Après l\'enregistrement, la barre de message propose **Ne plus signaler** la règle.',
              'After saving, the message bar offers to **Stop reporting** the rule.'),
          t('Les cas sont écrits dans `~/.local/share/check-script/false-positives.jsonl`.',
              'Cases are written to `~/.local/share/check-script/false-positives.jsonl`.'),
        ]),
        HelpPara(t(
            'Pour neutraliser un cas précis dans le script, voir *Directives dans le script*.',
            'To neutralize a specific case in the script, see *Directives in the script*.')),
      ],
    ),
    HelpPage(
      HelpTopic.export,
      t('Exports', 'Exports'),
      t('Le format du rapport se déduit de l\'extension du fichier : HTML, PDF, Markdown, AsciiDoc, JSON, SARIF ou texte.',
          'The report format is deduced from the file extension: HTML, PDF, Markdown, AsciiDoc, JSON, SARIF or text.'),
      [
        HelpBullets([
          t('**.html** : rapport autonome, lisible dans un navigateur. **.pdf** : à imprimer ou archiver.',
              '**.html**: standalone report, readable in a browser. **.pdf**: to print or archive.'),
          t('**.md** / **.adoc** : à insérer dans une documentation ou une merge request.',
              '**.md** / **.adoc**: to include in documentation or a merge request.'),
          t('**.json** : sert aussi de **référence** pour suivre l\'évolution (voir *Référence*).',
              '**.json**: also serves as a **baseline** to track evolution (see *Baseline*).'),
          t('**.sarif** : pour les outils de revue de code (GitHub code scanning…).',
              '**.sarif**: for code review tools (GitHub code scanning…).'),
        ]),
        HelpPara(t(
            'L\'export d\'un dossier regroupe tous les scripts du tableau, avec un résumé en tête.',
            'Exporting a folder gathers all the scripts of the table, with a summary at the top.')),
      ],
    ),
    HelpPage(
      HelpTopic.shortcuts,
      t('Raccourcis et astuces', 'Shortcuts and tips'),
      t('F1 : aide · Ctrl+O : ouvrir · F5 : relancer · Ctrl+E : exporter · Ctrl+F : chercher · Ctrl+Tab : onglet suivant · Ctrl+plus / moins / 0 : taille du code.',
          'F1: help · Ctrl+O: open · F5: re-run · Ctrl+E: export · Ctrl+F: search · Ctrl+Tab: next tab · Ctrl+plus / minus / 0: code size.'),
      [
        HelpHeading(t('Clavier', 'Keyboard')),
        HelpBullets([
          t('**F1** : ouvre l\'aide du sujet de l\'écran en cours.',
              '**F1**: opens the help of the current screen\'s topic.'),
          t('**Ctrl+O** : ouvrir un ou plusieurs scripts. **Ctrl+Maj+O** : ouvrir un dossier.',
              '**Ctrl+O**: open one or more scripts. **Ctrl+Shift+O**: open a folder.'),
          t('**F5** ou **Ctrl+R** : relancer l\'analyse (du dossier sur l\'écran Dossier, sinon du script affiché).',
              '**F5** or **Ctrl+R**: re-run the analysis (of the folder on the Folder screen, otherwise of the displayed script).'),
          t('**Ctrl+E** : exporter le rapport (du dossier sur l\'écran Dossier, sinon du script).',
              '**Ctrl+E**: export the report (of the folder on the Folder screen, otherwise of the script).'),
          t('**Ctrl+F** : chercher — dans le code (onglet Synthèse), dans les problèmes (onglet Problèmes), dans les règles ou dans l\'aide, selon l\'écran.',
              '**Ctrl+F**: search — in the code (Summary tab), in the issues (Issues tab), in the rules or in the help, depending on the screen.'),
          t('**Ctrl+Tab**, **Ctrl+Maj+Tab** (ou **Ctrl+Page suiv.** / **Page préc.**) : onglet suivant / précédent. **Ctrl+W** : fermer l\'onglet.',
              '**Ctrl+Tab**, **Ctrl+Shift+Tab** (or **Ctrl+Page Down** / **Page Up**): next / previous tab. **Ctrl+W**: close the tab.'),
          t('**Ctrl+1** à **Ctrl+5** : Analyse, Dossier, Règles, Réglages, Aide.',
              '**Ctrl+1** to **Ctrl+5**: Analysis, Folder, Rules, Settings, Help.'),
          t('**Ctrl + plus**, **Ctrl + moins**, **Ctrl + 0** : agrandir, réduire, rétablir la taille du code (aussi **Ctrl + molette** sur le code).',
              '**Ctrl + plus**, **Ctrl + minus**, **Ctrl + 0**: enlarge, reduce, reset the code size (also **Ctrl + wheel** on the code).'),
          t('Dans la recherche du code : **Entrée** (suivante), **Maj+Entrée** (précédente), **Échap** (fermer).',
              'In the code search: **Enter** (next), **Shift+Enter** (previous), **Esc** (close).'),
          t('Dans l\'éditeur du script : **Ctrl+S** (enregistrer), **Tab** (tabulation).',
              'In the script editor: **Ctrl+S** (save), **Tab** (tab character).'),
        ]),
        HelpHeading(t('Accessibilité', 'Accessibility')),
        HelpBullets([
          t('Les couleurs des sévérités et des notes ont un contraste d\'au moins **4,5:1** (WCAG AA) sur tous les fonds, en thème clair comme sombre.',
              'Severity and score colours have a contrast of at least **4.5:1** (WCAG AA) on every background, in both light and dark themes.'),
          t('La couleur n\'est jamais le seul indice : chaque sévérité a son **libellé**, et la marque colorée dans la marge du code est lue par les **lecteurs d\'écran** avec le détail des problèmes de la ligne.',
              'Colour is never the only cue: each severity has its **label**, and the coloured mark in the code margin is read by **screen readers** with the details of the line\'s issues.'),
          t('Le radar et la courbe d\'historique ont une **description textuelle** ; la taille du code se règle (Ctrl+plus / moins) et tout se pilote au **clavier**.',
              'The radar and the history curve have a **text description**; the code size can be set (Ctrl+plus / minus) and everything can be driven from the **keyboard**.'),
        ]),
        HelpHeading(t('Souris', 'Mouse')),
        HelpBullets([
          t('**Glisser-déposer** un ou plusieurs scripts, ou un dossier, sur la fenêtre : analyse immédiate.',
              '**Drag and drop** one or more scripts, or a folder, on the window: immediate analysis.'),
          t('**Double-clic** sur la barre entre le code et les résultats : répartition par défaut.',
              '**Double-click** the bar between the code and the results: default split.'),
          t('**Survol** : toute icône, bouton ou étiquette a une info-bulle, qui rappelle son raccourci.',
              '**Hover**: every icon, button or label has a tooltip, which recalls its shortcut.'),
        ]),
        HelpHeading(t('En ligne de commande', 'On the command line')),
        HelpCode('check-script-gui deploy.sh      # analyse au démarrage\n'
            'check-script-gui scripts/        # un dossier'),
      ],
    ),
    HelpPage(
      HelpTopic.about,
      t('À propos', 'About'),
      t('CheckScript $appVersion — logiciel libre sous licence LGPL-3.0-or-later.',
          'CheckScript $appVersion — free software under the LGPL-3.0-or-later licence.'),
      [
        HelpPara(t(
            'CheckScript **$appVersion** réutilise dans cette interface le même moteur, les mêmes règles et les mêmes rapports que la ligne de commande `check-script`.',
            'CheckScript **$appVersion** reuses in this interface the same engine, rules and reports as the `check-script` command line.')),
        HelpBullets([
          t('Licence : GNU LGPL version 3 ou ultérieure. L\'interface embarque la police JetBrains Mono (SIL Open Font License 1.1).',
              'Licence: GNU LGPL version 3 or later. The interface bundles the JetBrains Mono font (SIL Open Font License 1.1).'),
          t('Dépôt et signalement de problèmes : https://github.com/chla28/CheckScript',
              'Repository and issue reporting: https://github.com/chla28/CheckScript'),
          t('Guide utilisateur complet : `doc/user.fr.adoc` ; page de manuel : `man check-script`.',
              'Complete user guide: `doc/user.adoc`; manual page: `man check-script`.'),
        ]),
      ],
    ),
  ];
}
