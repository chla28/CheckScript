/// Catalogue des règles intégrées : identifiant, classement, titre et conseil
/// de correction bilingues. La détection est implémentée dans
/// `analyzers/builtin_rules.dart` (et `ast_rules.dart` quand l'arbre
/// syntaxique de shfmt est disponible).
library;

import '../i18n.dart';
import '../model/finding.dart';

/// Contexte d'exécution déclaré du script (`--context`) : durcit certaines
/// sévérités et active des règles spécifiques.
enum ExecContext {
  interactive,
  root,
  cron,
  systemd;

  static ExecContext? tryParse(String s) {
    for (final c in values) {
      if (c.name == s.toLowerCase()) return c;
    }
    return null;
  }

  /// Script lancé sans terminal (cron, unité systemd).
  bool get unattended => this == cron || this == systemd;
}

class RuleInfo {
  final String id;
  final Category category;
  final Severity severity;
  final Tr title;

  /// Conseil de correction.
  final Tr fix;

  /// Règle active seulement dans l'un de ces contextes (vide : toujours).
  final Set<ExecContext> contexts;

  const RuleInfo(this.id, this.category, this.severity, this.title, this.fix,
      {this.contexts = const {}});

  /// Règle propre aux scripts Python (identifiant `PY…`).
  bool get python => id.startsWith('PY');
}

const _sec = Category.security;
const _rob = Category.robustness;
const _mnt = Category.maintainability;
const _por = Category.portability;
const _perf = Category.performance;
const _c = Severity.critical;
const _h = Severity.high;
const _m = Severity.medium;
const _l = Severity.low;

const List<RuleInfo> ruleCatalog = [
  // ── Sécurité ──────────────────────────────────────────────────────────────
  RuleInfo(
      'SEC001',
      _sec,
      _c,
      Tr('Contenu téléchargé exécuté directement par un shell (curl|sh)',
          'Downloaded content piped straight into a shell (curl|sh)'),
      Tr('Télécharger dans un fichier, vérifier sa somme de contrôle ou sa signature, puis l\'exécuter.',
          'Download to a file, verify its checksum or signature, then run it.')),
  RuleInfo(
      'SEC002',
      _sec,
      _c,
      Tr('Secret (mot de passe, jeton, clé) écrit en dur dans le script',
          'Hard-coded secret (password, token, key) in the script'),
      Tr('Lire le secret depuis l\'environnement, un fichier protégé (chmod 600) ou un coffre (Vault, pass…), et le révoquer.',
          'Read the secret from the environment, a protected file (chmod 600) or a vault (Vault, pass…), and revoke it.')),
  RuleInfo(
      'SEC003',
      _sec,
      _h,
      Tr('eval appliqué à une expansion : risque d\'injection de commande',
          'eval applied to an expansion: command injection risk'),
      Tr('Remplacer eval par un tableau ("\${cmd[@]}"), un case ou une fonction.',
          'Replace eval with an array ("\${cmd[@]}"), a case statement or a function.')),
  RuleInfo(
      'SEC004',
      _sec,
      _h,
      Tr('Permissions en écriture pour tous (chmod 777/666, o+w)',
          'World-writable permissions (chmod 777/666, o+w)'),
      Tr('Donner les droits minimaux (755 / 644, ou 750 / 640 avec un groupe dédié).',
          'Grant minimal permissions (755 / 644, or 750 / 640 with a dedicated group).')),
  RuleInfo(
      'SEC005',
      _sec,
      _h,
      Tr('Vérification TLS / clé d\'hôte désactivée',
          'TLS / host key verification disabled'),
      Tr('Retirer -k / --no-check-certificate ; fournir la bonne autorité (--cacert) ou la clé d\'hôte (known_hosts).',
          'Drop -k / --no-check-certificate; provide the proper CA (--cacert) or host key (known_hosts).')),
  RuleInfo(
      'SEC006',
      _sec,
      _m,
      Tr('Téléchargement en clair (http://) : contenu falsifiable',
          'Clear-text download (http://): content can be tampered with'),
      Tr('Utiliser https:// et vérifier l\'intégrité du fichier téléchargé.',
          'Use https:// and verify the integrity of the downloaded file.')),
  RuleInfo(
      'SEC007',
      _sec,
      _h,
      Tr('rm récursif sur un chemin construit avec une variable non protégée',
          'Recursive rm on a path built from an unguarded variable'),
      Tr('Écrire rm -rf -- "\${VAR:?}/…" : le script s\'arrête si VAR est vide.',
          'Write rm -rf -- "\${VAR:?}/…": the script stops if VAR is empty.')),
  RuleInfo(
      'SEC008',
      _sec,
      _c,
      Tr('Suppression récursive de la racine ou d\'un répertoire système',
          'Recursive removal of the root or of a system directory'),
      Tr('Cibler un chemin précis et vérifié ; ne jamais supprimer / ni un répertoire système.',
          'Target a precise, checked path; never remove / or a system directory.')),
  RuleInfo(
      'SEC009',
      _sec,
      _m,
      Tr('Fichier temporaire au nom prévisible dans /tmp',
          'Predictable temporary file name in /tmp'),
      Tr('Créer le fichier avec tmp=\$(mktemp) et le supprimer par trap \'rm -f "\$tmp"\' EXIT.',
          'Create it with tmp=\$(mktemp) and remove it with trap \'rm -f "\$tmp"\' EXIT.')),
  RuleInfo(
      'SEC010',
      _sec,
      _h,
      Tr('Mot de passe transmis en ligne de commande (visible dans ps)',
          'Password passed on the command line (visible in ps)'),
      Tr('Passer le secret par un fichier d\'options protégé, l\'entrée standard ou une variable d\'environnement dédiée.',
          'Pass the secret through a protected option file, standard input or a dedicated environment variable.')),
  RuleInfo(
      'SEC011',
      _sec,
      _m,
      Tr('Chargement (source) d\'un fichier depuis un emplacement non fiable',
          'Sourcing a file from an untrusted location'),
      Tr('Ne sourcer que des fichiers de l\'installation, appartenant à root ou à l\'utilisateur, non modifiables par d\'autres.',
          'Only source files shipped with the installation, owned by root or the user, not writable by others.')),
  RuleInfo(
      'SEC012',
      _sec,
      _l,
      Tr('Trace d\'exécution (set -x) : des secrets peuvent apparaître dans les journaux',
          'Execution trace (set -x): secrets may leak into logs'),
      Tr('Activer la trace à la demande (ex. [[ \${DEBUG:-} ]] && set -x) et la couper autour des secrets.',
          'Enable tracing on demand (e.g. [[ \${DEBUG:-} ]] && set -x) and disable it around secrets.')),
  RuleInfo(
      'SEC013',
      _sec,
      _h,
      Tr('Positionnement d\'un bit setuid/setgid',
          'Setting a setuid/setgid bit'),
      Tr('Éviter setuid/setgid ; préférer sudo avec une règle restreinte ou des capabilities.',
          'Avoid setuid/setgid; prefer sudo with a narrow rule or capabilities.')),
  RuleInfo(
      'SEC014',
      _sec,
      _m,
      Tr('Saisie d\'un secret sans masquage (read sans -s)',
          'Secret prompted without masking (read without -s)'),
      Tr('Utiliser read -rs pour ne pas afficher la saisie.',
          'Use read -rs so the input is not echoed.')),
  RuleInfo(
      'SEC015',
      _sec,
      _l,
      Tr('sudo avec une commande sans chemin absolu, PATH non fixé',
          'sudo with a command without absolute path, PATH not set'),
      Tr('Fixer PATH en début de script ou appeler sudo /usr/bin/commande.',
          'Set PATH at the top of the script or call sudo /usr/bin/command.')),
  RuleInfo(
      'SEC016',
      _sec,
      _h,
      Tr('PATH contenant le répertoire courant (. ou entrée vide)',
          'PATH containing the current directory (. or empty entry)'),
      Tr('Retirer « . » et les entrées vides (::, : initial ou final) de PATH.',
          'Remove "." and empty entries (::, leading or trailing :) from PATH.')),
  RuleInfo(
      'SEC017',
      _sec,
      _m,
      Tr('Script privilégié sans PATH fixé',
          'Privileged script without a fixed PATH'),
      Tr('Ajouter en tête : PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin ; export PATH',
          'Add at the top: PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; export PATH'),
      contexts: {ExecContext.root, ExecContext.systemd}),
  RuleInfo(
      'SEC018',
      _sec,
      _h,
      Tr('Modification d\'un fichier sensible (sudoers, authorized_keys, passwd, shadow, cron)',
          'Modification of a sensitive file (sudoers, authorized_keys, passwd, shadow, cron)'),
      Tr('Passer par l\'outil dédié (visudo -c, useradd, ssh-copy-id, crontab) et vérifier le contenu ajouté.',
          'Use the dedicated tool (visudo -c, useradd, ssh-copy-id, crontab) and check what is added.')),
  RuleInfo(
      'SEC019',
      _sec,
      _m,
      Tr('Archive téléchargée extraite sans vérification d\'intégrité',
          'Downloaded archive extracted without integrity check'),
      Tr('Télécharger dans un fichier, vérifier sha256sum -c ou gpg --verify, puis extraire.',
          'Download to a file, check sha256sum -c or gpg --verify, then extract.')),
  RuleInfo(
      'SEC020',
      _sec,
      _m,
      Tr('Option SSH risquée (transfert d\'agent, commande locale)',
          'Risky SSH option (agent forwarding, local command)'),
      Tr('Éviter -A / ForwardAgent=yes ; préférer ProxyJump (-J) et des clés dédiées.',
          'Avoid -A / ForwardAgent=yes; prefer ProxyJump (-J) and dedicated keys.')),
  RuleInfo(
      'SEC021',
      _sec,
      _l,
      Tr('Secret exporté dans l\'environnement (visible des processus enfants)',
          'Secret exported to the environment (visible to child processes)'),
      Tr('Ne pas exporter : passer la valeur uniquement à la commande qui en a besoin (VAR=… cmd).',
          'Do not export: pass the value only to the command that needs it (VAR=… cmd).')),
  RuleInfo(
      'SEC022',
      _sec,
      _m,
      Tr('Chaîne à forte entropie : secret potentiel',
          'High-entropy string: potential secret'),
      Tr('Si c\'est un secret, le sortir du script ; sinon, neutraliser la règle sur cette ligne (# check-script disable=SEC022).',
          'If it is a secret, move it out of the script; otherwise suppress the rule on this line (# check-script disable=SEC022).')),
  RuleInfo(
      'SEC023',
      _sec,
      _c,
      Tr('Expression GitHub non fiable insérée dans un script : injection de commande',
          'Untrusted GitHub expression inserted into a script: command injection'),
      Tr('Passer la valeur par l\'environnement (env: TITRE: \${{ … }}) et utiliser "\$TITRE" dans le script.',
          'Pass the value through the environment (env: TITLE: \${{ … }}) and use "\$TITLE" in the script.')),
  RuleInfo(
      'SEC024',
      _sec,
      _m,
      Tr('Paquet installé sans version épinglée (pip, npm -g, go, gem, cargo)',
          'Package installed without a pinned version (pip, npm -g, go, gem, cargo)'),
      Tr('Épingler la version (pip install paquet==1.2.3, npm install -g paquet@1.2.3, go install mod@v1.2.3) ou installer depuis un fichier de dépendances verrouillé (--require-hashes).',
          'Pin the version (pip install package==1.2.3, npm install -g package@1.2.3, go install mod@v1.2.3) or install from a locked requirements file (--require-hashes).')),
  RuleInfo(
      'SEC025',
      _sec,
      _h,
      Tr('Dépôt ou paquet installé sans vérification de signature',
          'Repository or package installed without signature verification'),
      Tr('Retirer [trusted=yes], --allow-unauthenticated, gpgcheck=0, --nogpgcheck ou --nosignature ; importer la clé du dépôt (signed-by=…) et laisser le gestionnaire vérifier.',
          'Remove [trusted=yes], --allow-unauthenticated, gpgcheck=0, --nogpgcheck or --nosignature; import the repository key (signed-by=…) and let the package manager verify.')),
  RuleInfo(
      'SEC026',
      _sec,
      _l,
      Tr('Dépôt git cloné sans révision épinglée (tag ou commit)',
          'Git repository cloned without a pinned revision (tag or commit)'),
      Tr('Cloner une étiquette (git clone --branch v1.2.3) ou fixer le commit après le clonage (git -C dépôt checkout <sha>).',
          'Clone a tag (git clone --branch v1.2.3) or pin the commit after cloning (git -C repo checkout <sha>).')),

  // ── Dockerfile ────────────────────────────────────────────────────────────
  RuleInfo(
      'DKR001',
      _sec,
      _m,
      Tr('Image de base non épinglée (latest ou sans version)',
          'Base image not pinned (latest or no version)'),
      Tr('Indiquer une version précise, idéalement avec son empreinte : FROM debian:12.7@sha256:….',
          'Use a precise version, ideally with its digest: FROM debian:12.7@sha256:….')),
  RuleInfo(
      'DKR002',
      _sec,
      _h,
      Tr('Le conteneur s\'exécute en root (pas d\'instruction USER non privilégiée)',
          'The container runs as root (no unprivileged USER instruction)'),
      Tr('Créer un utilisateur dédié et le déclarer en fin d\'image : RUN useradd -r app, puis USER app.',
          'Create a dedicated user and declare it at the end of the image: RUN useradd -r app, then USER app.')),
  RuleInfo(
      'DKR003',
      _sec,
      _m,
      Tr('ADD d\'une URL : contenu téléchargé sans vérification d\'intégrité',
          'ADD from a URL: content downloaded without integrity check'),
      Tr('Ajouter --checksum=sha256:… à ADD, ou télécharger dans un RUN et vérifier la somme de contrôle.',
          'Add --checksum=sha256:… to ADD, or download in a RUN and verify the checksum.')),
  RuleInfo(
      'DKR004',
      _mnt,
      _l,
      Tr('ADD d\'un fichier local : préférer COPY',
          'ADD of a local file: prefer COPY'),
      Tr('Utiliser COPY (ADD n\'est utile que pour extraire une archive tar locale).',
          'Use COPY (ADD is only useful to extract a local tar archive).')),
  RuleInfo(
      'DKR005',
      _sec,
      _c,
      Tr('Secret dans ENV ou ARG : conservé dans l\'image et son historique',
          'Secret in ENV or ARG: kept in the image and its history'),
      Tr('Passer le secret à la construction par RUN --mount=type=secret, et à l\'exécution par l\'environnement ou un gestionnaire de secrets.',
          'Pass the secret at build time with RUN --mount=type=secret, and at run time through the environment or a secrets manager.')),
  RuleInfo(
      'DKR006',
      _sec,
      _l,
      Tr('apt-get install sans --no-install-recommends : paquets superflus',
          'apt-get install without --no-install-recommends: unneeded packages'),
      Tr('Ajouter --no-install-recommends pour n\'installer que le strict nécessaire.',
          'Add --no-install-recommends to install only what is needed.')),
  RuleInfo(
      'DKR007',
      _perf,
      _l,
      Tr('Cache du gestionnaire de paquets laissé dans l\'image',
          'Package manager cache left in the image'),
      Tr('Nettoyer dans le même RUN : rm -rf /var/lib/apt/lists/* (apt), dnf clean all, apk add --no-cache.',
          'Clean up in the same RUN: rm -rf /var/lib/apt/lists/* (apt), dnf clean all, apk add --no-cache.')),

  // ── Intégration continue (GitHub Actions, GitLab CI) ─────────────────────
  RuleInfo(
      'CI001',
      _sec,
      _m,
      Tr('Action GitHub non épinglée par une empreinte de commit',
          'GitHub action not pinned to a commit SHA'),
      Tr('Référencer l\'action par son SHA complet (uses: owner/action@<sha40> # v4.2.0) ; un tag peut être déplacé.',
          'Reference the action by its full SHA (uses: owner/action@<sha40> # v4.2.0); a tag can be moved.')),
  RuleInfo(
      'CI002',
      _sec,
      _l,
      Tr('Permissions du jeton GITHUB_TOKEN absentes ou trop larges',
          'GITHUB_TOKEN permissions missing or too broad'),
      Tr('Déclarer permissions: au niveau du workflow (contents: read) et n\'élargir que dans les jobs qui en ont besoin ; jamais write-all.',
          'Declare permissions: at workflow level (contents: read) and widen only in the jobs that need it; never write-all.')),
  RuleInfo(
      'CI003',
      _sec,
      _c,
      Tr('pull_request_target ou workflow_run exécute le code de la pull request (Poisoned Pipeline Execution)',
          'pull_request_target or workflow_run runs the pull request code (Poisoned Pipeline Execution)'),
      Tr('Ne pas extraire la branche de la pull request dans un workflow privilégié ; utiliser pull_request, ou séparer la construction (sans secrets) de la publication.',
          'Do not check out the pull request branch in a privileged workflow; use pull_request, or separate the build (without secrets) from the publication.')),
  RuleInfo(
      'CI004',
      _sec,
      _c,
      Tr('Secret écrit en clair dans la configuration de CI',
          'Secret written in clear in the CI configuration'),
      Tr('Le déclarer dans les secrets du dépôt ou du projet (\${{ secrets.NOM }}, variable masquée GitLab) et le révoquer.',
          'Declare it in the repository or project secrets (\${{ secrets.NAME }}, masked GitLab variable) and revoke it.')),
  RuleInfo(
      'CI005',
      _sec,
      _m,
      Tr('Image de conteneur de CI non épinglée (latest ou sans version)',
          'CI container image not pinned (latest or no version)'),
      Tr('Indiquer une version précise, idéalement avec son empreinte (image: python:3.12.6@sha256:…).',
          'Use a precise version, ideally with its digest (image: python:3.12.6@sha256:…).')),

  // ── Robustesse ────────────────────────────────────────────────────────────
  RuleInfo(
      'ROB001',
      _rob,
      _m,
      Tr('Pas d\'arrêt sur erreur (set -e / set -o errexit)',
          'No exit on error (set -e / set -o errexit)'),
      Tr('Ajouter set -euo pipefail (bash) ou set -eu (sh) en tête, ou tester chaque commande.',
          'Add set -euo pipefail (bash) or set -eu (sh) at the top, or check every command.')),
  RuleInfo(
      'ROB002',
      _rob,
      _l,
      Tr('Pipelines sans set -o pipefail : les échecs intermédiaires sont ignorés',
          'Pipelines without set -o pipefail: intermediate failures are ignored'),
      Tr('Ajouter set -o pipefail.', 'Add set -o pipefail.')),
  RuleInfo(
      'ROB003',
      _rob,
      _l,
      Tr('Variables non définies non détectées (set -u / set -o nounset)',
          'Undefined variables not detected (set -u / set -o nounset)'),
      Tr('Ajouter set -u ; utiliser \${VAR:-défaut} pour les variables facultatives.',
          'Add set -u; use \${VAR:-default} for optional variables.')),
  RuleInfo(
      'ROB004',
      _rob,
      _l,
      Tr('Fichier temporaire (mktemp) sans nettoyage par trap',
          'Temporary file (mktemp) without trap cleanup'),
      Tr('Ajouter trap \'rm -rf -- "\$tmp"\' EXIT juste après mktemp.',
          'Add trap \'rm -rf -- "\$tmp"\' EXIT right after mktemp.')),
  RuleInfo(
      'ROB005',
      _rob,
      _m,
      Tr('cd sans contrôle d\'échec', 'cd without failure check'),
      Tr('Écrire cd "\$dir" || exit 1.', 'Write cd "\$dir" || exit 1.')),
  RuleInfo(
      'ROB006',
      _rob,
      _m,
      Tr('Variable non quotée dans un test [ ] (échoue si vide ou avec espaces)',
          'Unquoted variable in a [ ] test (fails when empty or with spaces)'),
      Tr('Quoter la variable : [ "\$var" = … ] (ou utiliser [[ … ]] en bash).',
          'Quote the variable: [ "\$var" = … ] (or use [[ … ]] in bash).')),
  RuleInfo(
      'ROB007',
      _rob,
      _l,
      Tr('read sans -r : les antislashs sont interprétés',
          'read without -r: backslashes are interpreted'),
      Tr('Utiliser read -r.', 'Use read -r.')),
  RuleInfo(
      'ROB008',
      _rob,
      _m,
      Tr('Boucle sur la sortie de ls (casse sur les noms avec espaces)',
          'Looping over ls output (breaks on names with spaces)'),
      Tr('Boucler sur un glob : for f in ./*.log; do [ -e "\$f" ] || continue; …',
          'Loop over a glob: for f in ./*.log; do [ -e "\$f" ] || continue; …')),
  RuleInfo(
      'ROB009',
      _rob,
      _h,
      Tr('Fins de ligne Windows (CRLF) : le script ne s\'exécutera pas correctement',
          'Windows line endings (CRLF): the script will not run correctly'),
      Tr('Convertir en fins de ligne Unix (dos2unix, ou check-script --fix).',
          'Convert to Unix line endings (dos2unix, or check-script --fix).')),
  RuleInfo(
      'ROB010',
      _rob,
      _m,
      Tr('\$@ / \$* non quoté : les arguments sont re-découpés',
          'Unquoted \$@ / \$*: arguments are re-split'),
      Tr('Écrire "\$@".', 'Write "\$@".')),
  RuleInfo(
      'ROB011',
      _rob,
      _l,
      Tr('Code de retour d\'une commande critique ignoré (sans set -e)',
          'Exit status of a critical command ignored (no set -e)'),
      Tr('Tester le résultat (cmd || exit 1) ou activer set -e.',
          'Check the result (cmd || exit 1) or enable set -e.')),
  RuleInfo(
      'ROB012',
      _rob,
      _l,
      Tr('IFS modifié globalement sans être restauré',
          'IFS changed globally without being restored'),
      Tr('Limiter la portée : IFS=… read …, local IFS dans une fonction, ou sauvegarder puis restaurer.',
          'Narrow the scope: IFS=… read …, local IFS in a function, or save then restore.')),
  RuleInfo(
      'ROB013',
      _rob,
      _l,
      Tr('trap de nettoyage sans EXIT', 'Cleanup trap without EXIT'),
      Tr('Ajouter EXIT à la liste des signaux du trap (il couvre aussi les sorties normales et set -e).',
          'Add EXIT to the trap signal list (it also covers normal exits and set -e).')),
  RuleInfo(
      'ROB014',
      _rob,
      _m,
      Tr('Tâche planifiée sans verrou : exécutions concurrentes possibles',
          'Scheduled job without a lock: concurrent runs possible'),
      Tr('Protéger par flock : exec 9>/run/lock/nom.lock; flock -n 9 || exit 0.',
          'Guard with flock: exec 9>/run/lock/name.lock; flock -n 9 || exit 0.'),
      contexts: {ExecContext.cron}),
  RuleInfo(
      'ROB015',
      _rob,
      _m,
      Tr('Saisie interactive dans un script sans terminal',
          'Interactive prompt in a script without a terminal'),
      Tr('Remplacer la saisie par une option, une variable ou un fichier de configuration.',
          'Replace the prompt with an option, a variable or a configuration file.'),
      contexts: {ExecContext.cron, ExecContext.systemd}),
  RuleInfo(
      'ROB016',
      _rob,
      _m,
      Tr('Tâche cron sans PATH fixé (le PATH de cron est minimal)',
          'Cron job without a fixed PATH (cron\'s PATH is minimal)'),
      Tr('Fixer PATH en tête du script (ou dans la crontab).',
          'Set PATH at the top of the script (or in the crontab).'),
      contexts: {ExecContext.cron}),

  // ── Maintenabilité ────────────────────────────────────────────────────────
  RuleInfo(
      'MNT001',
      _mnt,
      _l,
      Tr('Ligne trop longue', 'Line too long'),
      Tr('Couper la ligne avec \\ ou extraire une variable / une fonction.',
          'Split the line with \\ or extract a variable / function.')),
  RuleInfo(
      'MNT002',
      _mnt,
      _l,
      Tr('Fonction trop longue', 'Function too long'),
      Tr('Découper la fonction en sous-fonctions nommées.',
          'Split the function into named helpers.')),
  RuleInfo(
      'MNT003',
      _mnt,
      _m,
      Tr('Imbrication trop profonde', 'Nesting too deep'),
      Tr('Sortir tôt (continue / return), extraire des fonctions.',
          'Return early (continue / return), extract functions.')),
  RuleInfo(
      'MNT004',
      _mnt,
      _l,
      Tr('Pas de commentaire d\'en-tête décrivant le script',
          'No header comment describing the script'),
      Tr('Décrire en tête le rôle du script, son usage et ses prérequis.',
          'Describe at the top what the script does, its usage and prerequisites.')),
  RuleInfo(
      'MNT005',
      _mnt,
      _l,
      Tr('Code très peu commenté', 'Very few comments'),
      Tr('Commenter les intentions et les passages non évidents.',
          'Comment the intent and the non-obvious parts.')),
  RuleInfo(
      'MNT006',
      _mnt,
      _l,
      Tr('Marqueur de travail inachevé (TODO/FIXME/XXX/HACK)',
          'Unfinished work marker (TODO/FIXME/XXX/HACK)'),
      Tr('Traiter le point ou le reporter dans le suivi des tickets.',
          'Address it or move it to the issue tracker.')),
  RuleInfo(
      'MNT007',
      _mnt,
      _l,
      Tr('Substitution par backticks : préférer \$(…)',
          'Backtick substitution: prefer \$(…)'),
      Tr('Remplacer `cmd` par \$(cmd) (corrigé par --fix).',
          'Replace `cmd` with \$(cmd) (fixed by --fix).')),
  RuleInfo(
      'MNT008',
      _mnt,
      _m,
      Tr('Script long sans aucune fonction',
          'Long script without any function'),
      Tr('Structurer en fonctions et une fonction main "\$@".',
          'Structure it into functions and a main "\$@" function.')),
  RuleInfo(
      'MNT009',
      _mnt,
      _l,
      Tr('Indentation mélangeant tabulations et espaces',
          'Indentation mixes tabs and spaces'),
      Tr('Uniformiser l\'indentation (shfmt -w, ou check-script --fix).',
          'Make indentation uniform (shfmt -w, or check-script --fix).')),
  RuleInfo(
      'MNT011',
      _mnt,
      _l,
      Tr('Directive check-script qui ne neutralise plus aucun problème',
          'check-script directive that no longer suppresses any issue'),
      Tr('Retirer la directive (ou ses identifiants devenus inutiles) : le problème a été corrigé ou la règle a changé.',
          'Remove the directive (or its obsolete identifiers): the issue was fixed or the rule changed.')),
  RuleInfo(
      'MNT010',
      _mnt,
      _l,
      Tr('Espaces en fin de ligne', 'Trailing whitespace'),
      Tr('Supprimer les espaces finaux (corrigé par --fix).',
          'Remove trailing whitespace (fixed by --fix).')),

  // ── Portabilité ───────────────────────────────────────────────────────────
  RuleInfo(
      'POR001',
      _por,
      _m,
      Tr('Pas de shebang : interpréteur indéterminé',
          'No shebang: interpreter is undefined'),
      Tr('Ajouter #!/bin/sh ou #!/usr/bin/env bash en première ligne.',
          'Add #!/bin/sh or #!/usr/bin/env bash as the first line.')),
  RuleInfo(
      'POR002',
      _por,
      _l,
      Tr('Chemin d\'interpréteur non standard dans le shebang',
          'Non-standard interpreter path in the shebang'),
      Tr('Utiliser /bin/sh, /bin/bash ou /usr/bin/env bash.',
          'Use /bin/sh, /bin/bash or /usr/bin/env bash.')),
  RuleInfo(
      'POR003',
      _por,
      _m,
      Tr('Construction bash dans un script /bin/sh',
          'Bash construct in a /bin/sh script'),
      Tr('Utiliser l\'équivalent POSIX, ou déclarer #!/usr/bin/env bash.',
          'Use the POSIX equivalent, or declare #!/usr/bin/env bash.')),
  RuleInfo(
      'POR004',
      _por,
      _l,
      Tr('which n\'est pas standard : utiliser command -v',
          'which is not standard: use command -v'),
      Tr('Remplacer which par command -v (corrigé par --fix).',
          'Replace which with command -v (fixed by --fix).')),
  RuleInfo(
      'POR005',
      _por,
      _l,
      Tr('egrep/fgrep sont obsolètes : utiliser grep -E / grep -F',
          'egrep/fgrep are deprecated: use grep -E / grep -F'),
      Tr('Remplacer par grep -E / grep -F (corrigé par --fix).',
          'Replace with grep -E / grep -F (fixed by --fix).')),
  RuleInfo(
      'POR006',
      _por,
      _l,
      Tr('Gestionnaire de paquets propre à une distribution, sans alternative',
          'Distribution-specific package manager, without alternative'),
      Tr('Détecter le gestionnaire disponible (command -v dnf / apt-get…) ou documenter la distribution visée.',
          'Detect the available manager (command -v dnf / apt-get…) or document the target distribution.')),
  RuleInfo(
      'POR007',
      _por,
      _l,
      Tr('Outil réseau obsolète (net-tools) : préférer ip / ss',
          'Deprecated networking tool (net-tools): prefer ip / ss'),
      Tr('ifconfig → ip addr, route → ip route, netstat → ss, arp → ip neigh.',
          'ifconfig → ip addr, route → ip route, netstat → ss, arp → ip neigh.')),

  // ── Performance ───────────────────────────────────────────────────────────
  RuleInfo(
      'PERF001',
      _perf,
      _l,
      Tr('cat inutile : passer le fichier en argument ou en redirection',
          'Useless cat: pass the file as an argument or redirection'),
      Tr('cmd fichier ou cmd < fichier.', 'cmd file or cmd < file.')),
  RuleInfo(
      'PERF002',
      _perf,
      _l,
      Tr('grep | wc -l : utiliser grep -c', 'grep | wc -l: use grep -c'),
      Tr('Remplacer par grep -c motif fichier.',
          'Replace with grep -c pattern file.')),
  RuleInfo(
      'PERF003',
      _perf,
      _l,
      Tr('expr lance un processus : utiliser \$((…))',
          'expr spawns a process: use \$((…))'),
      Tr('n=\$((n + 1)).', 'n=\$((n + 1)).')),
  RuleInfo(
      'PERF004',
      _perf,
      _l,
      Tr('Commande externe lancée à chaque tour de boucle',
          'External command spawned on every loop iteration'),
      Tr('Utiliser une expansion de paramètre : \${f##*/} (basename), \${f%/*} (dirname).',
          'Use parameter expansion: \${f##*/} (basename), \${f%/*} (dirname).')),
  RuleInfo(
      'PERF005',
      _perf,
      _l,
      Tr('Enchaînement de filtres réductible à une seule commande',
          'Filter chain reducible to a single command'),
      Tr('grep -e a -e b, awk \'/motif/ {…}\', sed -e … -e ….',
          'grep -e a -e b, awk \'/pattern/ {…}\', sed -e … -e ….')),
  RuleInfo(
      'PERF006',
      _perf,
      _l,
      Tr('ps | grep : utiliser pgrep', 'ps | grep: use pgrep'),
      Tr('pgrep -f motif (ou pidof).', 'pgrep -f pattern (or pidof).')),
  RuleInfo(
      'PERF007',
      _perf,
      _l,
      Tr('for … in \$(seq …) : préférer une boucle arithmétique',
          'for … in \$(seq …): prefer an arithmetic loop'),
      Tr('for ((i = 1; i <= n; i++)) ou for i in {1..10}.',
          'for ((i = 1; i <= n; i++)) or for i in {1..10}.')),
  RuleInfo(
      'PERF008',
      _perf,
      _l,
      Tr('echo inutile dans une substitution',
          'Useless echo in a substitution'),
      Tr('x=\$y au lieu de x=\$(echo \$y).',
          'x=\$y instead of x=\$(echo \$y).')),
  RuleInfo(
      'PERF009',
      _perf,
      _l,
      Tr('\$(cat fichier) : utiliser \$(< fichier) en bash',
          '\$(cat file): use \$(< file) in bash'),
      Tr('x=\$(< fichier).', 'x=\$(< file).')),

  // ── Python ────────────────────────────────────────────────────────────────
  RuleInfo(
      'PYSEC001',
      _sec,
      _m,
      Tr('Chaîne à forte entropie : secret potentiel',
          'High-entropy string: potential secret'),
      Tr('Lire le secret depuis l\'environnement (os.environ) ou un fichier protégé (chmod 600), et le révoquer ; sinon, neutraliser la règle sur cette ligne (# check-script disable=PYSEC001).',
          'Read the secret from the environment (os.environ) or a protected file (chmod 600), and revoke it; otherwise suppress the rule on this line (# check-script disable=PYSEC001).')),
  RuleInfo(
      'PYROB001',
      _rob,
      _l,
      Tr('Appel subprocess sans timeout : le script peut rester bloqué',
          'subprocess call without timeout: the script may hang'),
      Tr('Passer timeout=… et traiter subprocess.TimeoutExpired.',
          'Pass timeout=… and handle subprocess.TimeoutExpired.')),
  RuleInfo(
      'PYROB002',
      _rob,
      _m,
      Tr('Saisie interactive (input) dans un script sans terminal',
          'Interactive prompt (input) in a script without a terminal'),
      Tr('Remplacer la saisie par une option (argparse), une variable d\'environnement ou un fichier de configuration.',
          'Replace the prompt with an option (argparse), an environment variable or a configuration file.'),
      contexts: {ExecContext.cron, ExecContext.systemd}),
  RuleInfo(
      'PYROB003',
      _rob,
      _m,
      Tr('Tâche planifiée sans verrou : exécutions concurrentes possibles',
          'Scheduled job without a lock: concurrent runs possible'),
      Tr('Prendre un verrou exclusif au démarrage : fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB) sur /run/lock/nom.lock, et sortir s\'il est déjà pris.',
          'Take an exclusive lock at start-up: fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB) on /run/lock/name.lock, and exit if it is already held.'),
      contexts: {ExecContext.cron}),
  RuleInfo(
      'PYROB004',
      _rob,
      _m,
      Tr('Code de retour de main() ignoré : le script sort toujours avec 0',
          'Return value of main() ignored: the script always exits with 0'),
      Tr('Écrire sys.exit(main()) pour que les échecs soient visibles (cron, CI, systemd).',
          'Write sys.exit(main()) so that failures are visible (cron, CI, systemd).')),
  RuleInfo(
      'PYROB005',
      _rob,
      _h,
      Tr('Module importé introuvable (ni installé, ni déclaré dans les dépendances)',
          'Imported module not found (neither installed nor declared as a dependency)'),
      Tr('Vérifier le nom du module, le déclarer (requirements.txt, pyproject.toml ou en-tête PEP 723) et l\'installer ; un import facultatif se place dans try / except ImportError.',
          'Check the module name, declare it (requirements.txt, pyproject.toml or PEP 723 header) and install it; an optional import goes in try / except ImportError.')),
  RuleInfo(
      'PYMNT001',
      _mnt,
      _l,
      Tr('Pas de docstring ni de commentaire d\'en-tête décrivant le script',
          'No docstring or header comment describing the script'),
      Tr('Commencer par une docstring : rôle du script, usage, prérequis.',
          'Start with a docstring: what the script does, usage, prerequisites.')),
  RuleInfo(
      'PYMNT002',
      _mnt,
      _l,
      Tr('Code exécuté au chargement du module, sans garde __main__',
          'Code runs when the module is imported, no __main__ guard'),
      Tr('Regrouper le code dans main() et l\'appeler sous if __name__ == "__main__":.',
          'Move the code into main() and call it under if __name__ == "__main__":.')),
  RuleInfo(
      'PYPOR001',
      _por,
      _h,
      Tr('Shebang « python » ambigu (Python 2 sur d\'anciens systèmes, absent ailleurs)',
          'Ambiguous "python" shebang (Python 2 on old systems, missing elsewhere)'),
      Tr('Utiliser #!/usr/bin/env python3 (ou #!/usr/bin/python3).',
          'Use #!/usr/bin/env python3 (or #!/usr/bin/python3).')),
  RuleInfo(
      'PYPOR002',
      _por,
      _m,
      Tr('Dépendance tierce non déclarée dans le projet',
          'Third-party dependency not declared in the project'),
      Tr('Ajouter le paquet aux dépendances (requirements.txt, pyproject.toml ou en-tête PEP 723 du script) pour qu\'il s\'installe ailleurs.',
          'Add the package to the dependencies (requirements.txt, pyproject.toml or the script\'s PEP 723 header) so it installs elsewhere.')),
];

final Map<String, RuleInfo> _byId = {for (final r in ruleCatalog) r.id: r};

/// Règle du catalogue par identifiant (lève si inconnue : erreur de code).
RuleInfo ruleInfo(String id) =>
    _byId[id] ?? (throw ArgumentError('règle inconnue : $id'));

/// Toutes les règles, shell puis Python, triées par catégorie puis
/// identifiant (`--list-rules`).
List<RuleInfo> allBuiltinRules() => [...ruleCatalog]..sort((a, b) {
    if (a.python != b.python) return a.python ? 1 : -1;
    final o = a.category.index.compareTo(b.category.index);
    return o != 0 ? o : a.id.compareTo(b.id);
  });

/// Sévérités relevées selon le contexte d'exécution (jamais abaissées).
const Map<ExecContext, Map<String, Severity>> contextEscalations = {
  ExecContext.root: {
    'SEC004': Severity.critical,
    'SEC006': Severity.high,
    'SEC007': Severity.critical,
    'SC2115': Severity.critical,
    'SEC009': Severity.high,
    'SEC011': Severity.high,
    'SEC015': Severity.medium,
    'SEC019': Severity.high,
    'ROB001': Severity.high,
    'ROB005': Severity.high,
    'SC2164': Severity.critical,
  },
  ExecContext.cron: {
    'PYROB001': Severity.medium,
    'ROB001': Severity.high,
    'SEC009': Severity.high,
    'SEC012': Severity.medium,
  },
  ExecContext.systemd: {
    'PYROB001': Severity.medium,
    'ROB001': Severity.high,
    'SEC012': Severity.medium,
  },
};
