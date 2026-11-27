/// Anomalies déterministes : scénarios d'un script (`AB`), écarts dans un
/// parc (`AF`) et dérives depuis la référence (`AD`).
library;

import '../i18n.dart';
import '../script_info.dart';
import '../suppressions.dart';
import 'anomaly.dart';
import 'signals.dart';

/// Nombre minimal de scripts pour parler d'écart au parc : en dessous, tout
/// paraît unique.
const minFleetSize = 5;

/// Baisse de note à partir de laquelle la référence est jugée dépassée.
const scoreDropThreshold = 1.0;

String _t(Lang l, String fr, String en) => l == Lang.fr ? fr : en;

/// Comportements suspects d'un script.
List<Anomaly> detectBehaviours(ScriptInfo s, Lang lang,
    [List<Signal>? signals]) {
  final all = signals ?? extractSignals(s);
  List<Signal> of(SignalKind k) => [
        for (final x in all)
          if (x.kind == k) x
      ];
  final downloads = of(SignalKind.download);
  final piped = of(SignalKind.pipeToShell);
  final persistence = of(SignalKind.persistence);
  final uploads = of(SignalKind.upload);
  final hosts = of(SignalKind.host);
  final decodes = of(SignalKind.decode);
  final dynamics = of(SignalKind.dynamicExec);
  final verified = of(SignalKind.verify).isNotEmpty;
  final out = <Anomaly>[];

  void add(String id, AnomalyLevel level, String title, String detail,
      Iterable<Signal> from) {
    final lines = {for (final x in from) x.line}.toList()..sort();
    out.add(Anomaly(id, AnomalyKind.behaviour, level, title, detail, lines));
  }

  // Fichiers téléchargés (ou décodés) puis rendus exécutables ou lancés.
  List<Signal> ranAfter(List<Signal> sources) {
    final used = <Signal>[];
    for (final src in sources) {
      if (src.value.isEmpty) continue;
      String base(String p) => p.replaceFirst(RegExp(r'^\./'), '');
      final runs = [
        for (final x in [
          ...of(SignalKind.makeExecutable),
          ...of(SignalKind.execute)
        ])
          if (x.line >= src.line && base(x.value) == base(src.value)) x
      ];
      if (runs.isNotEmpty) used.addAll([src, ...runs]);
    }
    return used;
  }

  final fetchedAndRun = ranAfter(downloads);
  if (piped.isNotEmpty || (fetchedAndRun.isNotEmpty && !verified)) {
    add(
        'AB001',
        AnomalyLevel.high,
        _t(lang, 'Code téléchargé puis exécuté sans vérification',
            'Downloaded code executed without verification'),
        _t(
            lang,
            'Le script exécute ce qu\'il récupère sur le réseau, sans somme de contrôle ni signature.',
            'The script runs what it fetches from the network, with no checksum or signature.'),
        [...piped, ...fetchedAndRun]);
  }
  if ((downloads.isNotEmpty || piped.isNotEmpty) && persistence.isNotEmpty) {
    add(
        'AB002',
        AnomalyLevel.medium,
        _t(lang, 'Téléchargement suivi d\'une installation persistante',
            'Download followed by a persistent installation'),
        _t(
            lang,
            'Le contenu récupéré peut survivre aux redémarrages. Un installateur légitime le fait aussi : vérifier la source et ce qui est installé.',
            'Fetched content may survive reboots. A legitimate installer does this too: check the source and what is installed.'),
        [...downloads, ...piped, ...persistence]);
  }
  final hidden = [
    for (final d in decodes)
      if (dynamics.any((x) => x.line == d.line)) d,
    ...ranAfter(decodes),
  ];
  if (hidden.isNotEmpty) {
    add(
        'AB003',
        AnomalyLevel.high,
        _t(lang, 'Code masqué puis exécuté', 'Hidden code executed'),
        _t(
            lang,
            'Du contenu encodé, compressé ou chiffré est décodé puis exécuté : le code réel n\'est pas lisible dans le script.',
            'Encoded, compressed or encrypted content is decoded then executed: the real code cannot be read in the script.'),
        hidden);
  }
  final secrets = of(SignalKind.sensitiveRead);
  if (secrets.isNotEmpty && uploads.isNotEmpty) {
    add(
        'AB004',
        AnomalyLevel.high,
        _t(lang, 'Données sensibles et envoi sur le réseau',
            'Sensitive data and network upload'),
        _t(
            lang,
            'Le script touche à des fichiers sensibles (${{
              for (final x in secrets) x.value
            }.join(', ')}) et envoie des données.',
            'The script touches sensitive files (${{
              for (final x in secrets) x.value
            }.join(', ')}) and sends data out.'),
        [...secrets, ...uploads]);
  }
  final reverse = of(SignalKind.reverseShell);
  if (reverse.isNotEmpty) {
    add(
        'AB005',
        AnomalyLevel.high,
        _t(lang, 'Accès distant ouvert (shell inversé ou à l\'écoute)',
            'Remote access opened (reverse or bind shell)'),
        _t(lang, 'Un shell est relié à une connexion réseau.',
            'A shell is attached to a network connection.'),
        reverse);
  }
  final cleanup = of(SignalKind.cleanup);
  final sensitiveActions = [
    ...persistence,
    ...of(SignalKind.account),
    ...of(SignalKind.trustGrant),
    ...downloads,
    ...uploads,
    ...of(SignalKind.privilege),
  ];
  if (cleanup.isNotEmpty && sensitiveActions.isNotEmpty) {
    add(
        'AB006',
        AnomalyLevel.medium,
        _t(lang, 'Effacement de traces après des actions sensibles',
            'Trace removal along with sensitive actions'),
        _t(
            lang,
            'Journaux ou historique sont effacés par un script qui agit aussi sur le système ou le réseau.',
            'Logs or history are wiped by a script that also acts on the system or the network.'),
        cleanup);
  }
  final disable = of(SignalKind.disableDefence);
  if (disable.isNotEmpty &&
      (downloads.isNotEmpty ||
          piped.isNotEmpty ||
          persistence.isNotEmpty ||
          uploads.isNotEmpty)) {
    add(
        'AB007',
        AnomalyLevel.medium,
        _t(lang, 'Protection coupée avant une activité réseau ou persistante',
            'Defence disabled along with network or persistent activity'),
        _t(
            lang,
            'Pare-feu, SELinux ou audit sont désactivés par un script qui télécharge, envoie ou s\'installe.',
            'Firewall, SELinux or auditing are disabled by a script that downloads, uploads or installs itself.'),
        disable);
  }
  final accounts = of(SignalKind.account);
  final trust = of(SignalKind.trustGrant);
  if (accounts.isNotEmpty && trust.isNotEmpty) {
    add(
        'AB008',
        AnomalyLevel.medium,
        _t(lang, 'Compte créé ou modifié puis doté d\'un accès',
            'Account created or changed, then given access'),
        _t(
            lang,
            'Création de compte et octroi de droits (sudoers, clé SSH, groupe d\'administration) dans le même script.',
            'Account creation and rights granted (sudoers, SSH key, admin group) in the same script.'),
        [...accounts, ...trust]);
  }
  final blobs = of(SignalKind.encodedBlob);
  if (blobs.isNotEmpty) {
    add(
        'AB009',
        AnomalyLevel.low,
        _t(lang, 'Bloc encodé volumineux', 'Large encoded block'),
        _t(lang, 'Une longue chaîne encodée est écrite dans le script.',
            'A long encoded string is written in the script.'),
        blobs);
  }
  // Tâche persistante qui contacte elle-même le réseau (balise).
  final beacons = [
    for (final p in persistence)
      if (hosts.any((h) => h.line == p.line)) p
  ];
  if (beacons.isNotEmpty) {
    add(
        'AB010',
        AnomalyLevel.medium,
        _t(lang, 'Tâche persistante qui contacte le réseau',
            'Persistent task that contacts the network'),
        _t(lang, 'La tâche installée joint un hôte distant à chaque exécution.',
            'The installed task reaches a remote host on each run.'),
        beacons);
  }
  return out;
}

/// Écarts de chaque script par rapport aux autres : rien sous [minFleetSize]
/// scripts. Une liste par script, dans l'ordre de [profiles].
List<List<Anomaly>> detectOutliers(List<AnomalyProfile> profiles, Lang lang) {
  final out = [for (final _ in profiles) <Anomaly>[]];
  if (profiles.length < minFleetSize) return out;
  Map<String, int> count(Set<String> Function(AnomalyProfile) of) {
    final m = <String, int>{};
    for (final p in profiles) {
      for (final v in of(p)) {
        m[v] = (m[v] ?? 0) + 1;
      }
    }
    return m;
  }

  final capabilities = count((p) => p.capabilities);
  final hosts = count((p) => p.hosts);
  final commands = count((p) => p.commands);
  const risky = {
    'upload', 'persistence', 'privilege', 'account', 'trust-grant', //
    'disable-defence', 'trace-removal', 'remote-shell', 'sensitive-data',
  };
  final n = profiles.length;
  for (var i = 0; i < n; i++) {
    void add(String id, AnomalyLevel level, String title, String detail) =>
        out[i].add(Anomaly(id, AnomalyKind.outlier, level, title, detail));
    final onlyHosts = [
      for (final h in profiles[i].hosts)
        if (hosts[h] == 1) h
    ]..sort();
    if (onlyHosts.isNotEmpty) {
      add(
          'AF001',
          AnomalyLevel.low,
          _t(lang, 'Destination réseau propre à ce script',
              'Network destination specific to this script'),
          _t(
              lang,
              '${onlyHosts.join(', ')} : aucun des ${n - 1} autres scripts ne contacte cet hôte.',
              '${onlyHosts.join(', ')}: none of the ${n - 1} other scripts contacts this host.'));
    }
    final onlyCaps = [
      for (final c in profiles[i].capabilities)
        if (risky.contains(c) && capabilities[c] == 1) c
    ]..sort();
    if (onlyCaps.isNotEmpty) {
      add(
          'AF002',
          AnomalyLevel.medium,
          _t(lang, 'Capacité que seul ce script exerce',
              'Capability only this script uses'),
          _t(
              lang,
              '${onlyCaps.map((c) => capabilityLabel(c, lang)).join(', ')} — absent des ${n - 1} autres scripts.',
              '${onlyCaps.map((c) => capabilityLabel(c, lang)).join(', ')} — absent from the ${n - 1} other scripts.'));
    }
    final onlyCmds = [
      for (final c in profiles[i].commands)
        if (commands[c] == 1) c
    ]..sort();
    if (onlyCmds.isNotEmpty) {
      add(
          'AF003',
          AnomalyLevel.low,
          _t(lang, 'Commande sensible propre à ce script',
              'Sensitive command specific to this script'),
          _t(
              lang,
              '${onlyCmds.join(', ')} : aucun autre script du lot ne l\'utilise.',
              '${onlyCmds.join(', ')}: no other script of the batch uses it.'));
    }
  }
  return out;
}

/// Changements depuis la référence : [before] vient d'un rapport JSON produit
/// avec les anomalies (null : seule la note est comparée).
List<Anomaly> detectDrift(
    {required AnomalyProfile current,
    required AnomalyProfile? before,
    required double score,
    required double previousScore,
    required Lang lang}) {
  final out = <Anomaly>[];
  void add(String id, String title, String detail) => out
      .add(Anomaly(id, AnomalyKind.drift, AnomalyLevel.medium, title, detail));
  if (before != null) {
    final hosts = current.hosts.difference(before.hosts).toList()..sort();
    if (hosts.isNotEmpty) {
      add(
          'AD001',
          _t(lang, 'Nouvelle destination réseau', 'New network destination'),
          _t(lang, '${hosts.join(', ')} (absent de la référence).',
              '${hosts.join(', ')} (not in the baseline).'));
    }
    final caps = current.capabilities.difference(before.capabilities).toList()
      ..sort();
    if (caps.isNotEmpty) {
      final names = caps.map((c) => capabilityLabel(c, lang)).join(', ');
      add(
          'AD002',
          _t(lang, 'Nouvelle capacité du script', 'New script capability'),
          _t(lang, '$names (absent de la référence).',
              '$names (not in the baseline).'));
    }
  }
  final drop = ((previousScore - score) * 10).round() / 10;
  if (drop >= scoreDropThreshold) {
    String n(double v) => lang == Lang.fr ? '$v'.replaceAll('.', ',') : '$v';
    add('AD003', _t(lang, 'Chute de la note', 'Score drop'),
        '${n(previousScore)} → ${n(score)} (−${n(drop)}).');
  }
  return out;
}

String capabilityLabel(String id, Lang lang) => switch (id) {
      'download' => _t(lang, 'téléchargement', 'download'),
      'upload' => _t(lang, 'envoi de données', 'data upload'),
      'sensitive-data' => _t(lang, 'fichiers sensibles', 'sensitive files'),
      'persistence' => _t(lang, 'persistance', 'persistence'),
      'privilege' => _t(lang, 'élévation de droits', 'privilege elevation'),
      'account' => _t(lang, 'gestion de comptes', 'account management'),
      'trust-grant' => _t(lang, 'octroi d\'accès', 'access granting'),
      'trace-removal' => _t(lang, 'effacement de traces', 'trace removal'),
      'disable-defence' =>
        _t(lang, 'désactivation de protections', 'defence disabling'),
      'remote-shell' => _t(lang, 'shell distant', 'remote shell'),
      'decoding' => _t(lang, 'décodage de contenu', 'content decoding'),
      _ => id,
    };

/// Applique les directives `check-script disable=AB001` du script : les
/// lignes neutralisées sortent du constat, qui disparaît s'il n'en reste pas.
List<Anomaly> applySuppressions(ScriptInfo s, List<Anomaly> anomalies) {
  final sup = Suppressions.parse(s.embedded?.directiveLines ?? s.lines,
      python: s.dialect.isPython);
  if (sup.isEmpty) return anomalies;
  bool off(Set<String>? ids, String id) =>
      ids != null &&
      ids.any((x) =>
          x == 'ALL' ||
          x == id ||
          (x.endsWith('*') && id.startsWith(x.substring(0, x.length - 1))));
  final out = <Anomaly>[];
  for (final a in anomalies) {
    if (off(sup.file, a.id)) continue;
    final lines = [
      for (final l in a.lines)
        if (!off(sup.lines[l], a.id)) l
    ];
    if (a.lines.isNotEmpty && lines.isEmpty) continue;
    out.add(Anomaly(a.id, a.kind, a.level, a.title, a.detail, lines));
  }
  return out;
}
