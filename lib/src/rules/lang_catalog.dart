/// Règles intégrées des langages autres que shell et Python (Perl, Ruby, Lua,
/// Node.js) et des fichiers d'administration (unités systemd, crontab,
/// sudoers). Les identifiants commencent par `PL`, `RB`, `LU`, `JS`, `SD`,
/// `CR` ou `SU`. La détection est dans `analyzers/lang_rules.dart`.
library;

import '../analyzers/analyzer.dart' show ToolLanguage;
import '../i18n.dart';
import '../model/finding.dart';
import 'catalog.dart';
import 'examples.dart';
import 'references.dart';

const _sec = Category.security;
const _rob = Category.robustness;
const _mnt = Category.maintainability;
const _por = Category.portability;
const _h = Severity.high;
const _m = Severity.medium;
const _l = Severity.low;
const _c = Severity.critical;

/// Préfixe d'identifiant → langage.
const Map<String, ToolLanguage> languagePrefixes = {
  'PY': ToolLanguage.python,
  'PL': ToolLanguage.perl,
  'RB': ToolLanguage.ruby,
  'LU': ToolLanguage.lua,
  'JS': ToolLanguage.node,
  'DT': ToolLanguage.dart,
  'SD': ToolLanguage.systemd,
  'CR': ToolLanguage.crontab,
  'SU': ToolLanguage.sudoers,
};

/// Langage d'une règle intégrée d'après son identifiant (shell par défaut).
ToolLanguage languageOfRule(String id) {
  final m = RegExp(r'^([A-Z]{2})[A-Z]+\d+$').firstMatch(id);
  return (m == null ? null : languagePrefixes[m[1]]) ?? ToolLanguage.shell;
}

/// Règles communes aux quatre langages de script, avec leurs particularités
/// (variable d'environnement, API d'exécution…).
class _Script {
  final String p; // préfixe
  final String nameFr, nameEn;
  final String envFr, envEn; // lecture d'un secret dans l'environnement
  final String execFr, execEn; // exécution sans shell
  final String evalTitleFr, evalTitleEn, evalFixFr, evalFixEn;
  final String tlsFix;
  final String interp; // interpréteur du shebang
  const _Script(this.p, this.nameFr, this.nameEn,
      {required this.envFr,
      required this.envEn,
      required this.execFr,
      required this.execEn,
      required this.evalTitleFr,
      required this.evalTitleEn,
      required this.evalFixFr,
      required this.evalFixEn,
      required this.tlsFix,
      required this.interp});
}

const _scripts = [
  _Script('PL', 'Perl', 'Perl',
      envFr: r'$ENV{NOM}',
      envEn: r'$ENV{NAME}',
      execFr: "system('cmd', \$arg) (liste d'arguments, sans shell)",
      execEn: "system('cmd', \$arg) (argument list, no shell)",
      evalTitleFr: 'eval d\'une chaîne : exécution de code dynamique',
      evalTitleEn: 'eval of a string: dynamic code execution',
      evalFixFr:
          'Utiliser le bloc eval { … } ; ne jamais évaluer une donnée venant de l\'extérieur.',
      evalFixEn:
          'Use the eval { … } block; never evaluate data coming from outside.',
      tlsFix:
          'Laisser la vérification activée (SSL_verify_mode => SSL_VERIFY_PEER, verify_hostname => 1) et installer l\'autorité de certification manquante.',
      interp: 'perl'),
  _Script('RB', 'Ruby', 'Ruby',
      envFr: 'ENV.fetch("NOM")',
      envEn: 'ENV.fetch("NAME")',
      execFr: 'system("cmd", arg) (liste d\'arguments, sans shell)',
      execEn: 'system("cmd", arg) (argument list, no shell)',
      evalTitleFr:
          'eval / instance_eval / class_eval sur une chaîne : exécution de code dynamique',
      evalTitleEn:
          'eval / instance_eval / class_eval on a string: dynamic code execution',
      evalFixFr:
          'Appeler une méthode explicite (public_send avec liste blanche, table de dispatch) au lieu d\'évaluer du texte.',
      evalFixEn:
          'Call an explicit method (public_send with an allow-list, dispatch table) instead of evaluating text.',
      tlsFix:
          'Utiliser OpenSSL::SSL::VERIFY_PEER et installer l\'autorité de certification manquante (ca_file).',
      interp: 'ruby'),
  _Script('LU', 'Lua', 'Lua',
      envFr: 'os.getenv("NOM")',
      envEn: 'os.getenv("NAME")',
      execFr:
          'valider l\'argument (liste blanche) ou le citer avec string.format("%q")',
      execEn:
          'validate the argument (allow-list) or quote it with string.format("%q")',
      evalTitleFr:
          'load / loadstring / dofile sur une donnée : exécution de code dynamique',
      evalTitleEn: 'load / loadstring / dofile on data: dynamic code execution',
      evalFixFr:
          'Utiliser une table de fonctions (handlers[nom]()) ; si load est indispensable, imposer un environnement vide : load(src, nom, "t", {}).',
      evalFixEn:
          'Use a function table (handlers[name]()); if load is unavoidable, force an empty environment: load(src, name, "t", {}).',
      tlsFix: 'Utiliser verify = "peer" (LuaSec) et fournir cafile / capath.',
      interp: 'lua'),
  _Script('JS', 'Node.js', 'Node.js',
      envFr: 'process.env.NOM',
      envEn: 'process.env.NAME',
      execFr: 'execFile("cmd", [arg]) (liste d\'arguments, sans shell)',
      execEn: 'execFile("cmd", [arg]) (argument list, no shell)',
      evalTitleFr: 'eval / new Function : exécution de code dynamique',
      evalTitleEn: 'eval / new Function: dynamic code execution',
      evalFixFr:
          'Utiliser JSON.parse pour des données, une table de fonctions pour des actions ; ne jamais évaluer du texte externe.',
      evalFixEn:
          'Use JSON.parse for data, a function table for actions; never evaluate external text.',
      tlsFix:
          'Laisser rejectUnauthorized à true (valeur par défaut) et ajouter l\'autorité de certification manquante (option ca, NODE_EXTRA_CA_CERTS).',
      interp: 'node'),
  _Script('DT', 'Dart', 'Dart',
      envFr: "Platform.environment['NOM']",
      envEn: "Platform.environment['NAME']",
      execFr: "Process.run('cmd', [arg]) (liste d'arguments, sans shell)",
      execEn: "Process.run('cmd', [arg]) (argument list, no shell)",
      evalTitleFr:
          'Chargement de code dynamique (Isolate.spawnUri, dart:mirrors)',
      evalTitleEn: 'Dynamic code loading (Isolate.spawnUri, dart:mirrors)',
      evalFixFr:
          'Appeler des fonctions connues à l\'avance (table de dispatch) ; ne jamais charger de code dont la source n\'est pas maîtrisée.',
      evalFixEn:
          'Call functions known in advance (dispatch table); never load code whose source is not under control.',
      tlsFix:
          'Retirer badCertificateCallback permissif et installer l\'autorité de certification manquante (SecurityContext.setTrustedCertificates).',
      interp: 'dart'),
];

List<RuleInfo> _scriptRules(_Script s) => [
      RuleInfo(
          '${s.p}SEC001',
          _sec,
          _m,
          const Tr('Chaîne à forte entropie : secret potentiel',
              'High-entropy string: potential secret'),
          Tr('Lire le secret depuis l\'environnement (${s.envFr}) ou un fichier protégé (chmod 600), et le révoquer ; sinon, neutraliser la règle sur cette ligne (check-script disable=${s.p}SEC001).',
              'Read the secret from the environment (${s.envEn}) or a protected file (chmod 600), and revoke it; otherwise suppress the rule on this line (check-script disable=${s.p}SEC001).')),
      RuleInfo(
          '${s.p}SEC002',
          _sec,
          _h,
          Tr('Commande shell construite avec une variable (injection de commande) en ${s.nameFr}',
              'Shell command built from a variable (command injection) in ${s.nameEn}'),
          Tr('Passer les arguments séparément : ${s.execFr}.',
              'Pass the arguments separately: ${s.execEn}.')),
      RuleInfo('${s.p}SEC003', _sec, _h, Tr(s.evalTitleFr, s.evalTitleEn),
          Tr(s.evalFixFr, s.evalFixEn)),
      RuleInfo(
          '${s.p}SEC004',
          _sec,
          _h,
          const Tr('Vérification du certificat TLS désactivée',
              'TLS certificate verification disabled'),
          Tr(s.tlsFix, s.tlsFix)),
      RuleInfo(
          '${s.p}SEC005',
          _sec,
          _m,
          const Tr('Droits d\'écriture pour tous (chmod 777 / 666)',
              'World-writable permissions (chmod 777 / 666)'),
          const Tr(
              'Utiliser 755 / 644 (ou 700 / 600 pour un fichier privé) ; donner l\'écriture à un groupe plutôt qu\'à tous.',
              'Use 755 / 644 (or 700 / 600 for a private file); grant write to a group rather than to everyone.')),
      RuleInfo(
          '${s.p}MNT001',
          _mnt,
          _l,
          const Tr('Pas de commentaire d\'en-tête décrivant le script',
              'No header comment describing the script'),
          const Tr(
              'Commencer par un commentaire : rôle du script, usage, prérequis.',
              'Start with a comment: what the script does, usage, prerequisites.')),
      RuleInfo(
          '${s.p}POR001',
          _por,
          _l,
          const Tr('Shebang avec un chemin d\'interpréteur codé en dur',
              'Shebang with a hard-coded interpreter path'),
          Tr('Utiliser #!/usr/bin/env ${s.interp} : l\'interpréteur n\'est pas au même endroit partout (BSD, NixOS, gestionnaires de versions).',
              'Use #!/usr/bin/env ${s.interp}: the interpreter is not in the same place everywhere (BSD, NixOS, version managers).')),
    ];

/// Règles propres à un langage, en plus des règles communes.
const List<RuleInfo> _specific = [
  // ── Perl ──────────────────────────────────────────────────────────────────
  RuleInfo(
      'PLROB001',
      _rob,
      _m,
      Tr('Pas de « use strict » : variables non déclarées et références symboliques acceptées',
          'No "use strict": undeclared variables and symbolic references accepted'),
      Tr('Ajouter use strict; (ou use v5.12 et plus, Modern::Perl, Moose) en tête de fichier.',
          'Add use strict; (or use v5.12 or later, Modern::Perl, Moose) at the top of the file.')),
  RuleInfo(
      'PLROB002',
      _rob,
      _l,
      Tr('Pas de « use warnings » : les avertissements du compilateur sont perdus',
          'No "use warnings": compiler warnings are lost'),
      Tr('Ajouter use warnings; (ou l\'option -w du shebang).',
          'Add use warnings; (or the -w shebang option).')),
  RuleInfo(
      'PLSEC006',
      _sec,
      _m,
      Tr('open à deux arguments : le nom de fichier peut contenir un mode ou une commande (|)',
          'Two-argument open: the file name may carry a mode or a command (|)'),
      Tr('Écrire open(my \$fh, \'<\', \$fichier) : mode et nom séparés.',
          'Write open(my \$fh, \'<\', \$file): mode and name kept apart.')),
  // ── Ruby ──────────────────────────────────────────────────────────────────
  RuleInfo(
      'RBSEC006',
      _sec,
      _h,
      Tr('Désérialisation non sûre (Marshal.load, YAML.load, YAML.unsafe_load)',
          'Unsafe deserialization (Marshal.load, YAML.load, YAML.unsafe_load)'),
      Tr('Lire des données externes avec JSON.parse ou YAML.safe_load(permitted_classes: […]) ; ne jamais appeler Marshal.load sur une source non fiable.',
          'Read external data with JSON.parse or YAML.safe_load(permitted_classes: […]); never call Marshal.load on an untrusted source.')),
  RuleInfo(
      'RBSEC007',
      _sec,
      _m,
      Tr('Kernel#open avec une variable : « |commande » ou une URL sont interprétées',
          'Kernel#open with a variable: "|command" or a URL is interpreted'),
      Tr('Utiliser File.open (fichier) ou URI.open / Net::HTTP (réseau) explicitement.',
          'Use File.open (file) or URI.open / Net::HTTP (network) explicitly.')),
  RuleInfo(
      'RBROB001',
      _rob,
      _l,
      Tr('rescue Exception capture aussi SystemExit et Interrupt',
          'rescue Exception also catches SystemExit and Interrupt'),
      Tr('Intercepter StandardError (ou l\'exception précise attendue).',
          'Rescue StandardError (or the specific expected exception).')),
  // ── Node.js ───────────────────────────────────────────────────────────────
  RuleInfo(
      'JSSEC006',
      _sec,
      _m,
      Tr('Math.random pour un jeton, un secret ou un identifiant : générateur non cryptographique',
          'Math.random for a token, secret or identifier: non-cryptographic generator'),
      Tr('Utiliser crypto.randomBytes(16).toString("hex") ou crypto.randomUUID().',
          'Use crypto.randomBytes(16).toString("hex") or crypto.randomUUID().')),
  RuleInfo(
      'JSROB001',
      _rob,
      _l,
      Tr('Module CommonJS sans « use strict »',
          'CommonJS module without "use strict"'),
      Tr('Ajouter "use strict"; en tête de fichier (ou passer en modules ES, stricts par défaut).',
          'Add "use strict"; at the top of the file (or switch to ES modules, strict by default).')),
  // ── Dart / Flutter ────────────────────────────────────────────────────────
  RuleInfo(
      'DTSEC006',
      _sec,
      _m,
      Tr('Random() non sécurisé pour un jeton, un secret ou un identifiant',
          'Non-secure Random() for a token, secret or identifier'),
      Tr('Utiliser Random.secure() (générateur cryptographique du système).',
          'Use Random.secure() (the system cryptographic generator).')),
  RuleInfo(
      'DTSEC007',
      _sec,
      _m,
      Tr('URL en clair (http://) : contenu et échanges falsifiables ou lisibles',
          'Cleartext URL (http://): content and exchanges can be read or tampered with'),
      Tr('Utiliser https:// (et, sous Android, ne pas activer usesCleartextTraffic).',
          'Use https:// (and, on Android, do not enable usesCleartextTraffic).')),
  RuleInfo(
      'DTSEC008',
      _sec,
      _h,
      Tr('Requête SQL construite par interpolation ou concaténation (injection SQL)',
          'SQL query built by interpolation or concatenation (SQL injection)'),
      Tr('Passer les valeurs en paramètres : rawQuery(\'… WHERE id = ?\', [id]).',
          'Pass the values as parameters: rawQuery(\'… WHERE id = ?\', [id]).')),
  RuleInfo(
      'DTSEC009',
      _sec,
      _m,
      Tr('Mot de passe, jeton ou secret écrit dans les journaux (print, log)',
          'Password, token or secret written to the logs (print, log)'),
      Tr('Ne jamais journaliser un secret ; journaliser un identifiant ou une empreinte tronquée.',
          'Never log a secret; log an identifier or a truncated fingerprint instead.')),
  RuleInfo(
      'DTSEC010',
      _sec,
      _m,
      Tr('Secret enregistré en clair dans les préférences (SharedPreferences)',
          'Secret stored in clear in the preferences (SharedPreferences)'),
      Tr('Utiliser flutter_secure_storage (Keychain / Keystore) pour jetons et mots de passe.',
          'Use flutter_secure_storage (Keychain / Keystore) for tokens and passwords.')),
  RuleInfo(
      'DTROB001',
      _rob,
      _l,
      Tr('catch vide : l\'erreur est avalée sans trace',
          'Empty catch: the error is swallowed without a trace'),
      Tr('Journaliser l\'erreur, la traiter ou la relancer (rethrow) ; sinon, commenter pourquoi elle est ignorée.',
          'Log the error, handle it or rethrow it; otherwise comment why it is ignored.')),
  RuleInfo(
      'DTROB002',
      _rob,
      _m,
      Tr('Saisie interactive (stdin.readLineSync) dans un script sans terminal',
          'Interactive prompt (stdin.readLineSync) in a script without a terminal'),
      Tr('Remplacer la saisie par un argument de main(args), une variable d\'environnement ou un fichier.', 'Replace the prompt with a main(args) argument, an environment variable or a file.'),
      contexts: {ExecContext.cron, ExecContext.systemd}),
  RuleInfo(
      'DTROB003',
      _rob,
      _l,
      Tr('Appel http sans délai maximal : le programme peut rester bloqué',
          'http call without a timeout: the program may hang'),
      Tr('Ajouter .timeout(const Duration(seconds: 30)) et traiter TimeoutException.',
          'Add .timeout(const Duration(seconds: 30)) and handle TimeoutException.')),
  // ── systemd ───────────────────────────────────────────────────────────────
  RuleInfo(
      'SDSEC001',
      _sec,
      _m,
      Tr('Service exécuté en root (ni User= ni DynamicUser=)',
          'Service runs as root (neither User= nor DynamicUser=)'),
      Tr('Ajouter User=compte (compte dédié sans privilèges) ou DynamicUser=yes.',
          'Add User=account (dedicated unprivileged account) or DynamicUser=yes.')),
  RuleInfo(
      'SDSEC002',
      _sec,
      _m,
      Tr('Aucun durcissement du service (NoNewPrivileges, ProtectSystem, PrivateTmp…)',
          'No service hardening (NoNewPrivileges, ProtectSystem, PrivateTmp…)'),
      Tr('Ajouter NoNewPrivileges=yes, ProtectSystem=strict, ProtectHome=yes, PrivateTmp=yes ; mesurer avec systemd-analyze security.',
          'Add NoNewPrivileges=yes, ProtectSystem=strict, ProtectHome=yes, PrivateTmp=yes; measure with systemd-analyze security.')),
  RuleInfo(
      'SDSEC003',
      _sec,
      _h,
      Tr('Secret écrit en clair dans Environment= (visible par systemctl show)',
          'Secret written in clear in Environment= (visible through systemctl show)'),
      Tr('Utiliser LoadCredential= / EnvironmentFile= (fichier en chmod 600) plutôt qu\'Environment=.',
          'Use LoadCredential= / EnvironmentFile= (file with chmod 600) rather than Environment=.')),
  RuleInfo(
      'SDROB001',
      _rob,
      _h,
      Tr('Commande Exec* sans chemin absolu : systemd refuse l\'unité',
          'Exec* command without an absolute path: systemd rejects the unit'),
      Tr('Écrire le chemin complet : ExecStart=/usr/bin/programme.',
          'Write the full path: ExecStart=/usr/bin/program.')),
  RuleInfo(
      'SDROB002',
      _rob,
      _m,
      Tr('Restart=always sans RestartSec : redémarrages en boucle rapide',
          'Restart=always without RestartSec: fast restart loop'),
      Tr('Ajouter RestartSec=5 (et StartLimitIntervalSec / StartLimitBurst).',
          'Add RestartSec=5 (and StartLimitIntervalSec / StartLimitBurst).')),
  RuleInfo(
      'SDROB003',
      _rob,
      _l,
      Tr('Minuteur calendaire sans Persistent=true : exécution manquée si la machine était éteinte',
          'Calendar timer without Persistent=true: run missed if the machine was off'),
      Tr('Ajouter Persistent=true dans [Timer].',
          'Add Persistent=true in [Timer].')),
  RuleInfo(
      'SDMNT001',
      _mnt,
      _l,
      Tr('Pas de Description= dans [Unit]', 'No Description= in [Unit]'),
      Tr('Ajouter Description=… : elle s\'affiche dans systemctl et journalctl.',
          'Add Description=…: it is shown by systemctl and journalctl.')),
  // ── crontab ───────────────────────────────────────────────────────────────
  RuleInfo(
      'CRROB001',
      _rob,
      _m,
      Tr('Commande sans chemin absolu et sans PATH défini : cron n\'a qu\'un PATH minimal',
          'Command without an absolute path and no PATH set: cron has a minimal PATH'),
      Tr('Écrire le chemin complet de la commande, ou définir PATH= en tête de la crontab.',
          'Write the full path of the command, or set PATH= at the top of the crontab.')),
  RuleInfo(
      'CRROB002',
      _rob,
      _h,
      Tr('« % » non échappé : cron le remplace par un saut de ligne et tronque la commande',
          'Unescaped "%": cron turns it into a newline and truncates the command'),
      Tr('Écrire \\% (ou déplacer la commande dans un script).',
          'Write \\% (or move the command into a script).')),
  RuleInfo(
      'CRROB003',
      _rob,
      _l,
      Tr('Sortie non redirigée et pas de MAILTO : la sortie est envoyée par courriel local ou perdue',
          'Output not redirected and no MAILTO: output is mailed locally or lost'),
      Tr('Rediriger vers un journal (>> /var/log/x.log 2>&1) ou définir MAILTO=.',
          'Redirect to a log (>> /var/log/x.log 2>&1) or set MAILTO=.')),
  RuleInfo(
      'CRROB004',
      _rob,
      _l,
      Tr('Tâche chaque minute sans verrou : exécutions concurrentes possibles',
          'Every-minute job without a lock: concurrent runs possible'),
      Tr('Préfixer par flock -n /run/lock/nom.lock.',
          'Prefix with flock -n /run/lock/name.lock.')),
  RuleInfo(
      'CRSEC001',
      _sec,
      _h,
      Tr('Téléchargement exécuté directement (curl | sh) dans une tâche planifiée',
          'Download executed directly (curl | sh) in a scheduled job'),
      Tr('Installer un script vérifié (somme de contrôle, signature) et l\'appeler par son chemin.',
          'Install a verified script (checksum, signature) and call it by its path.')),
  RuleInfo(
      'CRSEC002',
      _sec,
      _h,
      Tr('Tâche lancée depuis un dossier modifiable par tous (/tmp, /var/tmp, /dev/shm, /home)',
          'Job run from a world-writable or user directory (/tmp, /var/tmp, /dev/shm, /home)'),
      Tr('Installer le script dans un dossier réservé (/usr/local/sbin, root:root, 755).',
          'Install the script in a reserved directory (/usr/local/sbin, root:root, 755).')),
  RuleInfo(
      'CRSEC003',
      _sec,
      _m,
      Tr('Mot de passe ou jeton sur la ligne de commande (visible dans ps)',
          'Password or token on the command line (visible in ps)'),
      Tr('Lire le secret dans un fichier protégé (chmod 600) ou l\'environnement du script.',
          'Read the secret from a protected file (chmod 600) or the script environment.')),
  // ── sudoers ───────────────────────────────────────────────────────────────
  RuleInfo(
      'SUSEC001',
      _sec,
      _c,
      Tr('NOPASSWD: ALL : toutes les commandes en root sans mot de passe',
          'NOPASSWD: ALL: every command as root without a password'),
      Tr('Lister les commandes nécessaires avec leurs arguments ; garder le mot de passe pour le reste.',
          'List the commands needed with their arguments; keep the password for the rest.')),
  RuleInfo(
      'SUSEC002',
      _sec,
      _m,
      Tr('Accès sudo complet attribué à un compte nominatif',
          'Full sudo access granted to an individual account'),
      Tr('Passer par un groupe d\'administration (%sudo, %wheel) ou restreindre les commandes.',
          'Go through an administration group (%sudo, %wheel) or restrict the commands.')),
  RuleInfo(
      'SUSEC003',
      _sec,
      _h,
      Tr('Joker dans une commande autorisée : injection d\'arguments possible',
          'Wildcard in an allowed command: argument injection possible'),
      Tr('Écrire les arguments exacts autorisés, ou encapsuler dans un script dédié.',
          'Write the exact allowed arguments, or wrap them in a dedicated script.')),
  RuleInfo(
      'SUSEC004',
      _sec,
      _h,
      Tr('Defaults affaiblissant la protection (!env_reset, !authenticate, env_keep sensible)',
          'Defaults weakening protection (!env_reset, !authenticate, sensitive env_keep)'),
      Tr('Retirer l\'option ; garder env_reset et authenticate, et ne conserver aucune variable de chargement (LD_*, PATH).',
          'Remove the option; keep env_reset and authenticate, and keep no loader variable (LD_*, PATH).')),
  RuleInfo(
      'SUSEC005',
      _sec,
      _h,
      Tr('Commande autorisée permettant une évasion vers un shell (éditeur, pager, interpréteur…)',
          'Allowed command that can escape to a shell (editor, pager, interpreter…)'),
      Tr('Utiliser sudoedit pour éditer un fichier, ou un script dédié qui n\'ouvre pas de shell (voir GTFOBins).',
          'Use sudoedit to edit a file, or a dedicated script that opens no shell (see GTFOBins).')),
];

/// Toutes les règles de ces langages.
final List<RuleInfo> langRuleCatalog = [
  for (final s in _scripts) ..._scriptRules(s),
  ..._specific,
];

// ── Références ───────────────────────────────────────────────────────────────

final Map<String, RuleRefs> langReferences = {
  for (final s in _scripts) ...{
    '${s.p}SEC001': const RuleRefs(cwe: [798], owasp: ['A07:2021']),
    '${s.p}SEC002': const RuleRefs(cwe: [78], owasp: ['A03:2021']),
    '${s.p}SEC003': const RuleRefs(cwe: [95], owasp: ['A03:2021']),
    '${s.p}SEC004': const RuleRefs(cwe: [295], owasp: ['A07:2021']),
    '${s.p}SEC005': const RuleRefs(cwe: [732], owasp: ['A01:2021']),
  },
  'PLSEC006': const RuleRefs(cwe: [78], owasp: ['A03:2021']),
  'RBSEC006': const RuleRefs(cwe: [502], owasp: ['A08:2021']),
  'RBSEC007': const RuleRefs(cwe: [78], owasp: ['A03:2021']),
  'JSSEC006': const RuleRefs(cwe: [338], owasp: ['A02:2021']),
  'DTSEC006': const RuleRefs(cwe: [338], owasp: ['A02:2021']),
  'DTSEC007': const RuleRefs(cwe: [319], owasp: ['A02:2021']),
  'DTSEC008': const RuleRefs(cwe: [89], owasp: ['A03:2021']),
  'DTSEC009': const RuleRefs(cwe: [532], owasp: ['A09:2021']),
  'DTSEC010': const RuleRefs(cwe: [312], owasp: ['A02:2021']),
  'DTROB001': const RuleRefs(cwe: [390]),
  'DTROB003': const RuleRefs(cwe: [1088]),
  'SDSEC001': const RuleRefs(cwe: [250]),
  'SDSEC002': const RuleRefs(cwe: [250]),
  'SDSEC003': const RuleRefs(cwe: [798], owasp: ['A07:2021']),
  'CRSEC001': const RuleRefs(cwe: [494], owasp: ['A08:2021']),
  'CRSEC002': const RuleRefs(cwe: [732], owasp: ['A01:2021']),
  'CRSEC003': const RuleRefs(cwe: [214]),
  'SUSEC001': const RuleRefs(cwe: [250], owasp: ['A01:2021']),
  'SUSEC002': const RuleRefs(cwe: [269], owasp: ['A01:2021']),
  'SUSEC003': const RuleRefs(cwe: [88], owasp: ['A03:2021']),
  'SUSEC004': const RuleRefs(cwe: [269], owasp: ['A01:2021']),
  'SUSEC005': const RuleRefs(cwe: [269], owasp: ['A01:2021']),
};

// ── Exemples « à éviter / à écrire » ─────────────────────────────────────────

CodeExample _en(String bad, String good, {String? goodEn}) =>
    CodeExample(bad, good, goodEn: goodEn);

final Map<String, CodeExample> langExamples = {
  // Perl
  'PLSEC001': _en(r'my $key = "9f86d081…";', r'my $key = $ENV{API_KEY};'),
  'PLSEC002': _en(r'system("rm -rf $dir");', r"system('rm', '-rf', $dir);"),
  'PLSEC003': _en(r'my $r = eval "$expr";', r'my $r = eval { compute() };'),
  'PLSEC004': _en(r'$ua->ssl_opts(verify_hostname => 0);',
      r'$ua->ssl_opts(verify_hostname => 1);'),
  'PLSEC005': _en('chmod 0777, \$file;', 'chmod 0755, \$file;'),
  'PLSEC006':
      _en(r'open(FH, $file) or die;', r"open(my $fh, '<', $file) or die;"),
  'PLROB001': _en('print "ok\\n";', 'use strict;\nprint "ok\\n";'),
  'PLROB002': _en('use strict;', 'use strict;\nuse warnings;'),
  'PLMNT001': _en('use strict;',
      '# Sauvegarde quotidienne de /srv.\n# Usage : backup.pl DESTINATION\nuse strict;',
      goodEn:
          '# Daily backup of /srv.\n# Usage: backup.pl DESTINATION\nuse strict;'),
  'PLPOR001': _en('#!/usr/bin/perl', '#!/usr/bin/env perl'),
  // Ruby
  'RBSEC001': _en('API_KEY = "9f86d081…"', 'API_KEY = ENV.fetch("API_KEY")'),
  'RBSEC002': _en('system("rm -rf #{dir}")', 'system("rm", "-rf", dir)'),
  'RBSEC003': _en('eval(params[:code])', 'handlers.fetch(name).call(args)'),
  'RBSEC004': _en('http.verify_mode = OpenSSL::SSL::VERIFY_NONE',
      'http.verify_mode = OpenSSL::SSL::VERIFY_PEER'),
  'RBSEC005': _en('File.chmod(0777, path)', 'File.chmod(0755, path)'),
  'RBSEC006': _en('data = Marshal.load(input)', 'data = JSON.parse(input)'),
  'RBSEC007': _en('content = open(path).read', 'content = File.read(path)'),
  'RBROB001': _en('rescue Exception => e', 'rescue StandardError => e'),
  'RBMNT001': _en('require "json"',
      '# Sauvegarde quotidienne de /srv.\n# Usage : backup.rb DESTINATION\nrequire "json"',
      goodEn:
          '# Daily backup of /srv.\n# Usage: backup.rb DESTINATION\nrequire "json"'),
  'RBPOR001': _en('#!/usr/bin/ruby', '#!/usr/bin/env ruby'),
  // Lua
  'LUSEC001':
      _en('local key = "9f86d081…"', 'local key = os.getenv("API_KEY")'),
  'LUSEC002': _en('os.execute("rm -rf " .. dir)',
      'os.execute(string.format("rm -rf %q", dir))'),
  'LUSEC003': _en('local f = load(code)', 'handlers[name]()'),
  'LUSEC004': _en('https.request{ url = u, verify = "none" }',
      'https.request{ url = u, verify = "peer", cafile = ca }'),
  'LUSEC005': _en(
      'os.execute("chmod 777 /srv/app")', 'os.execute("chmod 755 /srv/app")'),
  'LUMNT001': _en('local json = require("json")',
      '-- Sauvegarde quotidienne de /srv.\n-- Usage : lua backup.lua DESTINATION\nlocal json = require("json")',
      goodEn:
          '-- Daily backup of /srv.\n-- Usage: lua backup.lua DESTINATION\nlocal json = require("json")'),
  'LUPOR001': _en('#!/usr/bin/lua', '#!/usr/bin/env lua'),
  // Node.js
  'JSSEC001':
      _en('const key = "9f86d081…";', 'const key = process.env.API_KEY;'),
  'JSSEC002':
      _en(r'exec(`rm -rf ${dir}`);', 'execFile("rm", ["-rf", dir], callback);'),
  'JSSEC003': _en('eval(code);', 'handlers[name]();'),
  'JSSEC004':
      _en('{ rejectUnauthorized: false }', '{ rejectUnauthorized: true }'),
  'JSSEC005': _en('fs.chmodSync(file, 0o777);', 'fs.chmodSync(file, 0o755);'),
  'JSSEC006': _en('const token = Math.random().toString(36);',
      'const token = crypto.randomBytes(16).toString("hex");'),
  'JSROB001': _en(
      'const fs = require("fs");', '"use strict";\nconst fs = require("fs");'),
  'JSMNT001': _en('const fs = require("fs");',
      '// Sauvegarde quotidienne de /srv.\n// Usage : node backup.js DESTINATION\nconst fs = require("fs");',
      goodEn:
          '// Daily backup of /srv.\n// Usage: node backup.js DESTINATION\nconst fs = require("fs");'),
  'JSPOR001': _en('#!/usr/bin/node', '#!/usr/bin/env node'),
  // Dart / Flutter
  'DTSEC001': _en('const apiKey = "9f86d081…";',
      "final apiKey = Platform.environment['API_KEY'];"),
  'DTSEC002': _en(r'await Process.run("sh", ["-c", "rm -rf $dir"]);',
      "await Process.run('rm', ['-rf', dir]);"),
  'DTSEC003': _en("import 'dart:mirrors';",
      'final handlers = {"start": start, "stop": stop};'),
  'DTSEC004': _en('client.badCertificateCallback = (cert, host, port) => true;',
      'client.badCertificateCallback = (cert, host, port) => false;'),
  'DTSEC005': _en("await Process.run('chmod', ['777', path]);",
      "await Process.run('chmod', ['755', path]);"),
  'DTSEC006': _en('final token = Random().nextInt(1 << 32);',
      'final token = Random.secure().nextInt(1 << 32);'),
  'DTSEC007': _en("final url = Uri.parse('http://api.exemple.fr/v1');",
      "final url = Uri.parse('https://api.exemple.fr/v1');"),
  'DTSEC008': _en(
      r'''db.rawQuery("SELECT * FROM users WHERE name = '$name'");''',
      "db.rawQuery('SELECT * FROM users WHERE name = ?', [name]);"),
  'DTSEC009': _en(r"print('token = $token');", "print('connexion ouverte');",
      goodEn: "print('connection opened');"),
  'DTSEC010': _en("prefs.setString('auth_token', token);",
      "await secureStorage.write(key: 'auth_token', value: token);"),
  'DTROB001': _en('try {\n  run();\n} catch (e) {}',
      "try {\n  run();\n} catch (e) {\n  stderr.writeln('échec : \$e');\n}",
      goodEn:
          "try {\n  run();\n} catch (e) {\n  stderr.writeln('failed: \$e');\n}"),
  'DTROB002': _en('final answer = stdin.readLineSync();',
      'final answer = args.isEmpty ? null : args.first;'),
  'DTROB003': _en("final r = await http.get(Uri.parse(url));",
      "final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));"),
  'DTMNT001': _en("import 'dart:io';",
      '// Sauvegarde quotidienne de /srv.\n// Usage : dart backup.dart DESTINATION\nimport \'dart:io\';',
      goodEn:
          '// Daily backup of /srv.\n// Usage: dart backup.dart DESTINATION\nimport \'dart:io\';'),
  'DTPOR001': _en('#!/usr/bin/dart', '#!/usr/bin/env dart'),
  // systemd
  'SDSEC001': _en('[Service]\nExecStart=/usr/bin/app',
      '[Service]\nUser=app\nExecStart=/usr/bin/app'),
  'SDSEC002': _en('[Service]\nUser=app\nExecStart=/usr/bin/app',
      '[Service]\nUser=app\nExecStart=/usr/bin/app\nNoNewPrivileges=yes\nProtectSystem=strict\nPrivateTmp=yes'),
  'SDSEC003': _en('Environment=DB_PASSWORD=hunter2',
      'EnvironmentFile=/etc/app/secrets.env'),
  'SDROB001': _en('ExecStart=app --serve', 'ExecStart=/usr/bin/app --serve'),
  'SDROB002': _en('Restart=always', 'Restart=always\nRestartSec=5'),
  'SDROB003': _en('[Timer]\nOnCalendar=daily',
      '[Timer]\nOnCalendar=daily\nPersistent=true'),
  'SDMNT001': _en('[Unit]\nAfter=network.target',
      '[Unit]\nDescription=Sauvegarde quotidienne\nAfter=network.target',
      goodEn: '[Unit]\nDescription=Daily backup\nAfter=network.target'),
  // crontab
  'CRROB001': _en('0 3 * * * backup.sh', '0 3 * * * /usr/local/bin/backup.sh'),
  'CRROB002': _en(r'0 3 * * * tar czf /bak/$(date +%F).tgz /srv',
      r'0 3 * * * tar czf /bak/$(date +\%F).tgz /srv'),
  'CRROB003': _en('0 3 * * * /usr/local/bin/sync.sh',
      '0 3 * * * /usr/local/bin/sync.sh >> /var/log/sync.log 2>&1'),
  'CRROB004': _en('* * * * * /usr/local/bin/poll.sh',
      '* * * * * flock -n /run/lock/poll.lock /usr/local/bin/poll.sh'),
  'CRSEC001': _en('0 * * * * curl -s https://example.org/i.sh | sh',
      '0 * * * * /usr/local/sbin/update.sh'),
  'CRSEC002': _en(
      '0 * * * * root /tmp/run.sh', '0 * * * * root /usr/local/sbin/run.sh'),
  'CRSEC003': _en('0 * * * * /usr/local/bin/dump --password=hunter2',
      '0 * * * * /usr/local/bin/dump --defaults-file=/etc/dump.cnf'),
  // sudoers
  'SUSEC001': _en('alice ALL=(ALL) NOPASSWD: ALL',
      'alice ALL=(root) NOPASSWD: /usr/bin/systemctl restart app'),
  'SUSEC002': _en('alice ALL=(ALL:ALL) ALL', '%admins ALL=(ALL:ALL) ALL'),
  'SUSEC003': _en('bob ALL=(root) /usr/bin/rsync *',
      'bob ALL=(root) /usr/bin/rsync -a /srv/ /backup/'),
  'SUSEC004': _en('Defaults !env_reset', 'Defaults env_reset'),
  'SUSEC005': _en('carol ALL=(root) NOPASSWD: /usr/bin/vim /etc/app.conf',
      'carol ALL=(root) NOPASSWD: sudoedit /etc/app.conf'),
};
