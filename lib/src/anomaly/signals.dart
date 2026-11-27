/// Extraction de signaux : faits élémentaires relevés ligne à ligne
/// (téléchargement, persistance, envoi de données…). Un signal seul n'est pas
/// une anomalie ; leur combinaison peut en être une (`scenarios.dart`).
library;

import '../analyzers/lang_rules.dart' show stripComments;
import '../analyzers/shell_lexer.dart';
import '../script_info.dart';
import 'anomaly.dart';

enum SignalKind {
  download,
  pipeToShell,
  upload,
  sensitiveRead,
  makeExecutable,
  execute,
  decode,
  dynamicExec,
  encodedBlob,
  persistence,
  privilege,
  account,
  trustGrant,
  cleanup,
  disableDefence,
  reverseShell,
  verify,
  host,
}

class Signal {
  final SignalKind kind;
  final int line;

  /// Fichier ou hôte concerné, quand il est lisible dans la ligne.
  final String value;

  const Signal(this.kind, this.line, [this.value = '']);
}

/// Ligne logique : les continuations `\` sont jointes.
class _Line {
  final int number;
  final String text;
  const _Line(this.number, this.text);
}

List<_Line> _logicalLines(ScriptInfo s) {
  final code = s.dialect.isShell
      ? [for (final l in lexScript(s.lines)) l.code]
      : stripComments(s.lines, s.dialect);
  final out = <_Line>[];
  for (var i = 0; i < code.length; i++) {
    final start = i;
    var text = code[i];
    while (text.endsWith('\\') && i + 1 < code.length) {
      text = '${text.substring(0, text.length - 1)} ${code[++i].trim()}';
    }
    if (text.trim().isNotEmpty) out.add(_Line(start + 1, text));
  }
  return out;
}

RegExp _re(String p) => RegExp(p, caseSensitive: false);

final _downloader = _re(r'\b(?:curl|wget|fetch)\b[^|;&]*(?:https?|ftp)://'
    r'|\b(?:curl|wget)\b[^|;&]*\$'
    r'|\burlopen\s*\(|\burlretrieve\s*\(|\brequests\.get\s*\('
    r'|\bInvoke-WebRequest\b|\bURI\.open\b|\bNet::HTTP\.get\b'
    r'|\bhttps?\.get\s*\(|\bfetch\s*\(\s*["\x27]http|\bhttp\.get\s*\('
    r'|\bLWP::Simple\b|\bgetstore\s*\(');
final _outputFile = _re(
    r'(?:\s-o\s+|\s--output[= ]|\s-O\s+(?=[/.$~])|>\s*)["\x27]?([\w./$~{}-]+)');
final _pipeShell = _re(
    r'\b(?:curl|wget|fetch)\b[^|;]*\|\s*(?:sudo\s+(?:-\S+\s+)*)?(?:env\s+)?'
    r'(?:/(?:usr/)?(?:local/)?bin/)?(?:(?:ba|da|z|k)?sh|python[23]?|perl|ruby)\b'
    r'|\b(?:(?:ba|da|z|k)?sh|source|eval)\b[^|;]*(?:<\(|\$\()\s*(?:curl|wget)\b');
final _upload = _re(
    r'\bcurl\b[^|;&]*\s(?:-d|--data(?:-binary|-raw|-urlencode)?|-F|--form|-T|--upload-file|-X\s*(?:POST|PUT))\b'
    r'|\bwget\b[^|;&]*--post-(?:data|file)'
    r'|\b(?:nc|ncat|netcat)\b\s+(?!-l)[^|;&]*\s\d{2,5}\b[^|;&]*<'
    r'|\|\s*(?:nc|ncat|netcat|curl)\b'
    r'|\b(?:scp|rsync)\b[^|;&]*\s[\w.-]+@[\w.-]+:'
    r'|\brequests\.(?:post|put)\s*\(|\bhttp\.(?:post|put)\s*\(');
final _sensitive =
    _re(r'/etc/shadow\b|\.ssh/id_\w+\b(?!\.pub)|\.aws/credentials|\.netrc\b'
        r'|\.docker/config\.json|\.kube/config|\.gnupg/|\.bash_history\b'
        r'|\bwallet\.dat\b|\.config/gcloud');
final _chmodX = _re(
    r'\bchmod\s+(?:-\w+\s+)*(?:[ugoa]*\+[rw]*x[rwxst]*|0?[1357][0-7]{2}|0?[0-7][1357][0-7])\s+["\x27]?([\w./$~{}-]+)');
final _execPath = _re(
    r'(?:^\s*|[;&|]\s*)(?:sudo\s+)?(?:(?:ba|da|z|k)?sh\s+|source\s+|\.\s+|exec\s+|nohup\s+)?["\x27]?((?:\./|/tmp/|/var/tmp/|/dev/shm/|\$\w*TMP\w*/)[\w./-]+)'
    r'|(?:^\s*|[;&|]\s*)(?:sudo\s+)?(?:ba|da|z|k)?sh\s+["\x27]?([\w./$~{}-]+)');
final _decode = _re(
    r'\bbase(?:64|32)\b[^|;&]*\s(?:-d\b|--decode\b|-D\b)|\bxxd\b[^|;&]*\s-r\b'
    r'|\bopenssl\b[^|;&]*\s-d\b|\bb64decode\s*\(|\batob\s*\('
    r'|Buffer\.from\([^)]*["\x27]base64["\x27]|\bbase64\.decode\b'
    r'|\bunpack\s*\(\s*["\x27]m|\bgunzip\s+-c\b|\bzcat\b');
final _dynamic = _re(
    r'\beval\b|\|\s*(?:sudo\s+)?(?:ba|da|z|k)?sh\b|\|\s*(?:python[23]?|perl|ruby)\b'
    r'|\bexec\s*\(|\bnew\s+Function\b|\bsh\s+-c\s+["\x27]?\$\(');
final _blob = RegExp(r'[A-Za-z0-9+/]{120,}={0,2}|(?:\\x[0-9A-Fa-f]{2}){12,}');
final _write = r'(?:>>?|\btee\b|\bcp\b|\bmv\b|\binstall\b|\bln\b|\bsed\s+-i\b)';
final _persistFile = _re('$_write'
    r'[^|;&]*(?:/etc/cron(?:\.d|\.daily|\.hourly|\.weekly|tab)|/var/spool/cron'
    r'|/etc/systemd/system/|\.config/systemd/user/|/etc/rc\.local|/etc/init\.d/'
    r'|/etc/profile(?:\.d/|\b)|\.(?:bashrc|bash_profile|profile|zshrc)\b'
    r'|/etc/ld\.so\.preload|\.config/autostart/)');
final _persistCmd = _re(
    r'\bsystemctl\s+(?:--user\s+)?enable\b|\bcrontab\s+(?:-u\s+\S+\s+)?(?:-(?![lr]\b)|["\x27]?[\w./$]+)'
    r'|\|\s*crontab\b|\bchkconfig\b[^|;&]*\bon\b|\bupdate-rc\.d\b[^|;&]*\bdefaults\b');
final _privilege = _re(
    r'(?:^\s*|[;&|(]\s*)(?:sudo|doas)\s|\bsu\s+-(?:\s|$)|\bsu\s+root\b'
    r'|\bchmod\s+(?:-\w+\s+)*(?:[ugoa]*\+[rwx]*s|0?[2467][0-7]{3}\b)|\bsetcap\b');
final _account = _re(
    r'(?:^\s*|[;&|]\s*)(?:sudo\s+)?(?:useradd|adduser|chpasswd)\b|\bpasswd\s+--stdin\b'
    r'|\busermod\b[^|;&]*\s-[a-zA-Z]*G\s*\S*(?:sudo|wheel|root|docker)');
final _trust = _re('$_write'
    r'[^|;&]*(?:authorized_keys|/etc/sudoers|/etc/passwd\b|/etc/pam\.d/)'
    r'|\bNOPASSWD\b|\busermod\b[^|;&]*\s-[a-zA-Z]*G\s*\S*(?:sudo|wheel|root)');
final _cleanup = _re(
    r'\bhistory\s+-c\b|\bunset\s+HISTFILE\b|\bHISTSIZE=0\b|\bHISTFILE=/dev/null\b'
    r'|\bset\s+\+o\s+history\b|\bshred\b[^|;&]*(?:/var/log|history)'
    r'|\brm\b[^|;&]*(?:/var/log/|\.bash_history|\.zsh_history)'
    r'|\btruncate\b[^|;&]*/var/log|(?:^\s*|[;&]\s*):?\s*>\s*/var/log/'
    r'|\bjournalctl\b[^|;&]*--vacuum|\bwevtutil\s+cl\b');
final _disable = _re(
    r'\bsetenforce\s+(?:0|permissive)\b|\biptables\s+(?:-t\s+\w+\s+)?(?:-F|--flush)\b'
    r'|\bnft\s+flush\b|\bufw\s+disable\b'
    r'|\bsystemctl\s+(?:stop|disable|mask)\b[^|;&]*(?:firewalld|auditd|apparmor|fail2ban|ufw|rsyslog)'
    r'|SELINUX=(?:disabled|permissive)');
final _reverse = _re(
    r'(?:>&|&>)\s*/dev/(?:tcp|udp)/[^|;]*[<>]&|\b(?:ba|z)?sh\b[^|;]*(?:>&|&>)\s*/dev/(?:tcp|udp)/'
    r'|\b(?:nc|ncat|netcat)\b[^|;&]*\s-[a-zA-Z]*[ec]\s+["\x27]?(?:/bin/)?(?:ba)?sh'
    r'|\bsocat\b[^|;&]*\bEXEC:[^|;&]*sh|\bpty\.spawn\s*\(|\bos\.dup2\s*\(');
final _verify =
    _re(r'\b(?:sha(?:1|256|512)sum|b2sum|md5sum)\b[^|;&]*(?:\s-c\b|--check)'
        r'|\|\s*(?:sha(?:256|512)sum|b2sum)\s+(?:-c|--check)'
        r'|\bgpgv?\b[^|;&]*--verify|\bcosign\s+verify|\bminisign\s+-V');
final _url = _re(
    r'(?:https?|ftp|wss?)://(?:[^\s/@"\x27]*@)?([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])');
final _devTcp = _re(r'/dev/(?:tcp|udp)/([\w.-]+)/');
final _sshHost =
    _re(r'\b(?:ssh|scp|rsync|sftp)\b[^|;&]*?\s(?:[\w.-]+)@([\w.-]+)');

/// Hôtes qui ne sortent pas de la machine : sans intérêt pour la comparaison.
bool _local(String host) =>
    host == 'localhost' ||
    host.startsWith('127.') ||
    host == '0.0.0.0' ||
    host == '[::1]';

/// Signaux du script, dans l'ordre des lignes.
List<Signal> extractSignals(ScriptInfo s) {
  final out = <Signal>[];
  for (final l in _logicalLines(s)) {
    final t = l.text;
    void add(SignalKind k, [String value = '']) =>
        out.add(Signal(k, l.number, value));
    if (_pipeShell.hasMatch(t)) add(SignalKind.pipeToShell);
    if (_downloader.hasMatch(t)) {
      add(SignalKind.download, _outputFile.firstMatch(t)?.group(1) ?? '');
    }
    if (_upload.hasMatch(t)) add(SignalKind.upload);
    if (_sensitive.hasMatch(t)) {
      add(SignalKind.sensitiveRead, _sensitive.firstMatch(t)![0]!);
    }
    for (final m in _chmodX.allMatches(t)) {
      add(SignalKind.makeExecutable, m[1]!);
    }
    for (final m in _execPath.allMatches(t)) {
      add(SignalKind.execute, m[1] ?? m[2] ?? '');
    }
    if (_decode.hasMatch(t)) {
      add(SignalKind.decode, _outputFile.firstMatch(t)?.group(1) ?? '');
    }
    if (_dynamic.hasMatch(t)) add(SignalKind.dynamicExec);
    if (_blob.hasMatch(t)) add(SignalKind.encodedBlob);
    if (_persistFile.hasMatch(t) || _persistCmd.hasMatch(t)) {
      add(SignalKind.persistence);
    }
    if (_privilege.hasMatch(t)) add(SignalKind.privilege);
    if (_account.hasMatch(t)) add(SignalKind.account);
    if (_trust.hasMatch(t)) add(SignalKind.trustGrant);
    if (_cleanup.hasMatch(t)) add(SignalKind.cleanup);
    if (_disable.hasMatch(t)) add(SignalKind.disableDefence);
    if (_reverse.hasMatch(t)) add(SignalKind.reverseShell);
    if (_verify.hasMatch(t)) add(SignalKind.verify);
    for (final re in [_url, _devTcp, _sshHost]) {
      for (final m in re.allMatches(t)) {
        final host = m[1]!.toLowerCase();
        if (!_local(host)) add(SignalKind.host, host);
      }
    }
  }
  return out;
}

/// Commandes sensibles suivies d'un script à l'autre : les commandes
/// courantes (cp, grep…) noieraient la comparaison.
const trackedCommands = {
  'curl', 'wget', 'nc', 'ncat', 'netcat', 'socat', 'ssh', 'scp', 'sftp', //
  'rsync', 'base64', 'openssl', 'crontab', 'useradd', 'adduser', 'usermod',
  'iptables', 'nft', 'nmap', 'tcpdump', 'dd', 'shred', 'setenforce', 'sudo',
  'chattr', 'insmod', 'modprobe',
};

final _commandWord =
    RegExp(r'(?:^\s*|[;&|(]\s*|\$\(\s*|\bsudo\s+)([a-z][\w-]*)');

/// Capacités, hôtes et commandes sensibles du script.
AnomalyProfile profileOf(ScriptInfo s, [List<Signal>? signals]) {
  final found = signals ?? extractSignals(s);
  const named = {
    SignalKind.download: 'download',
    SignalKind.pipeToShell: 'download',
    SignalKind.upload: 'upload',
    SignalKind.sensitiveRead: 'sensitive-data',
    SignalKind.persistence: 'persistence',
    SignalKind.privilege: 'privilege',
    SignalKind.account: 'account',
    SignalKind.trustGrant: 'trust-grant',
    SignalKind.cleanup: 'trace-removal',
    SignalKind.disableDefence: 'disable-defence',
    SignalKind.reverseShell: 'remote-shell',
    SignalKind.decode: 'decoding',
  };
  return AnomalyProfile(
    capabilities: {
      for (final x in found)
        if (named[x.kind] case final n?) n
    },
    hosts: {
      for (final x in found)
        if (x.kind == SignalKind.host) x.value
    },
    commands: {
      for (final l in _logicalLines(s))
        for (final m in _commandWord.allMatches(l.text))
          if (trackedCommands.contains(m[1])) m[1]!
    },
  );
}
