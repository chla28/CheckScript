/// Inventaire des commandes externes d'un script shell : nom, lignes,
/// présence sur la machine d'analyse, paquet qui la fournit (dnf, apt).
/// Une commande introuvable, que le script ne vérifie pas lui-même
/// (`command -v jq`), est signalée (ROB017).
library;

import '../model/finding.dart';
import '../rules/catalog.dart';
import '../script_info.dart';
import 'analyzer.dart';
import 'ast.dart';
import 'shell_lexer.dart';

/// Une commande externe utilisée par le script.
class CommandUse {
  /// Nom tel qu'écrit (`jq`, `/opt/app/bin/outil`).
  final String name;

  /// Lignes où elle est lancée.
  final List<int> lines;

  /// Présente sur la machine d'analyse (null : non vérifié).
  final bool? found;

  /// Chemin résolu (si présente).
  final String? path;

  /// Paquets qui la fournissent (Fedora/RHEL, Debian/Ubuntu), si connus.
  final String? dnf, apt;

  /// Le script vérifie lui-même sa présence (`command -v`, `type`, `hash`).
  final bool checked;

  const CommandUse(this.name, this.lines,
      {this.found, this.path, this.dnf, this.apt, this.checked = false});

  String get base => name.split('/').last;

  Map<String, Object?> toJson() => {
        'name': name,
        'lines': lines,
        if (found != null) 'found': found,
        if (path != null) 'path': path,
        if (dnf != null) 'dnf': dnf,
        if (apt != null) 'apt': apt,
        if (checked) 'checked': true,
      };

  factory CommandUse.fromJson(Map<String, Object?> j) => CommandUse(
        '${j['name']}',
        [for (final l in j['lines'] as List? ?? const []) (l as num).toInt()],
        found: j['found'] as bool?,
        path: j['path'] as String?,
        dnf: j['dnf'] as String?,
        apt: j['apt'] as String?,
        checked: j['checked'] == true,
      );
}

/// Mots-clés et commandes internes du shell (bash, POSIX, ksh, zsh courants).
const shellBuiltins = {
  // Mots-clés.
  'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until', 'do', //
  'done', 'case', 'esac', 'in', 'function', 'select', 'time', '!', '{', '}',
  '[[', ']]', 'coproc',
  // Commandes internes.
  ':', '.', 'source', 'alias', 'unalias', 'bg', 'fg', 'jobs', 'bind',
  'break', 'continue', 'builtin', 'caller', 'cd', 'command', 'compgen',
  'complete', 'compopt', 'declare', 'typeset', 'dirs', 'disown', 'echo',
  'enable', 'eval', 'exec', 'exit', 'export', 'false', 'true', 'fc',
  'getopts', 'hash', 'help', 'history', 'kill', 'let', 'local', 'logout',
  'mapfile', 'readarray', 'popd', 'pushd', 'printf', 'pwd', 'read',
  'readonly', 'return', 'set', 'shift', 'shopt', 'suspend', 'test', '[',
  'times', 'trap', 'type', 'ulimit', 'umask', 'unset', 'wait', 'print',
  'setopt', 'unsetopt', 'autoload', 'zmodload', 'noglob', 'whence',
};

/// Préfixes qui lancent la commande donnée en argument.
const _wrappers = {
  'sudo', 'doas', 'env', 'exec', 'nohup', 'nice', 'ionice', 'timeout', //
  'stdbuf', 'xargs', 'command', 'time', 'chroot', 'runuser', 'setsid',
  'flock', 'watch', 'strace', 'unbuffer',
};

/// Options des préfixes suivies d'une valeur (sudo -u app cmd).
const Map<String, Set<String>> _valueOptions = {
  'sudo': {'-u', '-g', '-C', '-h', '-p', '-r', '-t', '-U', '-D'},
  'doas': {'-u', '-C'},
  'env': {'-u', '-C', '-S'},
  'timeout': {'-s', '-k', '--signal', '--kill-after'},
  'nice': {'-n'},
  'ionice': {'-c', '-n', '-p'},
  'xargs': {'-I', '-n', '-P', '-d', '-L', '-s', '-E', '-a'},
  'stdbuf': {'-i', '-o', '-e'},
  'chroot': {'--userspec', '--groups'},
  'runuser': {'-u', '-g', '-l'},
  'flock': {'-w', '-E', '-c'},
  'watch': {'-n', '-d'},
  'strace': {'-o', '-e', '-p', '-s', '-u'},
};

/// Commandes de base (coreutils et équivalents), présentes sur toute
/// distribution : jamais signalées comme introuvables.
const baseCommands = {
  'ls', 'cp', 'mv', 'rm', 'cat', 'mkdir', 'rmdir', 'chmod', 'chown', //
  'chgrp', 'date', 'head', 'tail', 'sort', 'uniq', 'wc', 'tr', 'cut',
  'basename', 'dirname', 'readlink', 'realpath', 'touch', 'tee', 'sleep',
  'env', 'id', 'whoami', 'uname', 'df', 'du', 'stat', 'ln', 'mktemp',
  'timeout', 'nohup', 'nice', 'seq', 'yes', 'expr', 'dd', 'sync', 'md5sum',
  'sha1sum', 'sha256sum', 'sha512sum', 'base64', 'install', 'printenv',
  'tac', 'nl', 'od', 'fold', 'paste', 'join', 'split', 'comm', 'shuf',
  'numfmt', 'stdbuf', 'sh', 'bash', 'grep', 'sed', 'awk', 'find', 'xargs',
  'tar', 'gzip', 'gunzip', 'zcat', 'ps', 'kill', 'test', 'true', 'false',
};

/// Paquets fournissant les commandes courantes : (dnf, apt).
const Map<String, (String, String)> commandPackages = {
  'jq': ('jq', 'jq'),
  'yq': ('yq', 'yq'),
  'curl': ('curl', 'curl'),
  'wget': ('wget', 'wget'),
  'rsync': ('rsync', 'rsync'),
  'git': ('git', 'git'),
  'unzip': ('unzip', 'unzip'),
  'zip': ('zip', 'zip'),
  'bzip2': ('bzip2', 'bzip2'),
  'xz': ('xz', 'xz-utils'),
  'zstd': ('zstd', 'zstd'),
  '7z': ('p7zip-plugins', '7zip'),
  'openssl': ('openssl', 'openssl'),
  'gpg': ('gnupg2', 'gnupg'),
  'ssh': ('openssh-clients', 'openssh-client'),
  'scp': ('openssh-clients', 'openssh-client'),
  'sftp': ('openssh-clients', 'openssh-client'),
  'ssh-keygen': ('openssh', 'openssh-client'),
  'sshpass': ('sshpass', 'sshpass'),
  'python3': ('python3', 'python3'),
  'pip3': ('python3-pip', 'python3-pip'),
  'perl': ('perl', 'perl'),
  'gawk': ('gawk', 'gawk'),
  'bc': ('bc', 'bc'),
  'sqlite3': ('sqlite', 'sqlite3'),
  'mysql': ('mariadb', 'mariadb-client'),
  'mysqldump': ('mariadb', 'mariadb-client'),
  'psql': ('postgresql', 'postgresql-client'),
  'pg_dump': ('postgresql', 'postgresql-client'),
  'redis-cli': ('redis', 'redis-tools'),
  'docker': ('docker-ce-cli', 'docker.io'),
  'podman': ('podman', 'podman'),
  'buildah': ('buildah', 'buildah'),
  'skopeo': ('skopeo', 'skopeo'),
  'ansible': ('ansible-core', 'ansible'),
  'ansible-playbook': ('ansible-core', 'ansible'),
  'make': ('make', 'make'),
  'gcc': ('gcc', 'gcc'),
  'xmllint': ('libxml2', 'libxml2-utils'),
  'xmlstarlet': ('xmlstarlet', 'xmlstarlet'),
  'xsltproc': ('libxslt', 'xsltproc'),
  'envsubst': ('gettext', 'gettext-base'),
  'dig': ('bind-utils', 'dnsutils'),
  'nslookup': ('bind-utils', 'dnsutils'),
  'host': ('bind-utils', 'bind9-host'),
  'ip': ('iproute', 'iproute2'),
  'ss': ('iproute', 'iproute2'),
  'ifconfig': ('net-tools', 'net-tools'),
  'netstat': ('net-tools', 'net-tools'),
  'route': ('net-tools', 'net-tools'),
  'nc': ('nmap-ncat', 'netcat-openbsd'),
  'ncat': ('nmap-ncat', 'ncat'),
  'nmap': ('nmap', 'nmap'),
  'tcpdump': ('tcpdump', 'tcpdump'),
  'traceroute': ('traceroute', 'traceroute'),
  'ping': ('iputils', 'iputils-ping'),
  'iptables': ('iptables-nft', 'iptables'),
  'nft': ('nftables', 'nftables'),
  'firewall-cmd': ('firewalld', 'firewalld'),
  'systemctl': ('systemd', 'systemd'),
  'journalctl': ('systemd', 'systemd'),
  'crontab': ('cronie', 'cron'),
  'at': ('at', 'at'),
  'flock': ('util-linux', 'util-linux'),
  'getopt': ('util-linux', 'util-linux'),
  'column': ('util-linux', 'bsdextrautils'),
  'lsblk': ('util-linux', 'util-linux'),
  'mount': ('util-linux', 'mount'),
  'logger': ('util-linux', 'bsdutils'),
  'pgrep': ('procps-ng', 'procps'),
  'pkill': ('procps-ng', 'procps'),
  'free': ('procps-ng', 'procps'),
  'watch': ('procps-ng', 'procps'),
  'lsof': ('lsof', 'lsof'),
  'strace': ('strace', 'strace'),
  'file': ('file', 'file'),
  'which': ('which', 'debianutils'),
  'sudo': ('sudo', 'sudo'),
  'useradd': ('shadow-utils', 'passwd'),
  'usermod': ('shadow-utils', 'passwd'),
  'chpasswd': ('shadow-utils', 'passwd'),
  'mail': ('s-nail', 'mailutils'),
  'sendmail': ('postfix', 'postfix'),
  'tree': ('tree', 'tree'),
  'pv': ('pv', 'pv'),
  'parallel': ('parallel', 'parallel'),
  'inotifywait': ('inotify-tools', 'inotify-tools'),
  'diff': ('diffutils', 'diffutils'),
  'cmp': ('diffutils', 'diffutils'),
  'patch': ('patch', 'patch'),
  'iconv': ('glibc-common', 'libc-bin'),
  'dos2unix': ('dos2unix', 'dos2unix'),
  'convert': ('ImageMagick', 'imagemagick'),
  'ffmpeg': ('ffmpeg-free', 'ffmpeg'),
  'shellcheck': ('ShellCheck', 'shellcheck'),
  'shfmt': ('shfmt', 'shfmt'),
  'tmux': ('tmux', 'tmux'),
  'screen': ('screen', 'screen'),
  'vim': ('vim-enhanced', 'vim'),
  'less': ('less', 'less'),
  'rg': ('ripgrep', 'ripgrep'),
  'fd': ('fd-find', 'fd-find'),
  'htop': ('htop', 'htop'),
  'mkfs.ext4': ('e2fsprogs', 'e2fsprogs'),
  'rpm': ('rpm', 'rpm'),
  'dnf': ('dnf', '—'),
  'yum': ('yum', '—'),
  'apt-get': ('—', 'apt'),
  'dpkg': ('—', 'dpkg'),
  'hostname': ('hostname', 'hostname'),
  'awk': ('gawk', 'mawk'),
};

/// Commandes externes du script (nom → lignes), dans l'ordre d'apparition :
/// commandes internes, fonctions du script, variables et affectations
/// exclues ; le préfixe (sudo, env, xargs…) et la commande qu'il lance
/// sont retenus tous les deux.
Map<String, List<int>> externalCommands(ScriptInfo s, {AstFacts? ast}) {
  final functions = <String>{
    if (ast != null)
      for (final f in ast.functions) f.name
    else
      for (final l in s.lines)
        if (RegExp(r'^\s*(?:function\s+)?([A-Za-z_][\w.:-]*)\s*\(\s*\)|^\s*function\s+([A-Za-z_][\w.:-]*)')
                .firstMatch(l)
            case final m?)
          m[1] ?? m[2]!,
  };
  final out = <String, List<int>>{};
  void add(String name, int line) {
    if (name.isEmpty ||
        shellBuiltins.contains(name) ||
        functions.contains(name) ||
        name.contains(r'$') ||
        name.contains('=') ||
        name.startsWith('-') ||
        !RegExp(r'^[\w./+-]+$').hasMatch(name)) {
      return;
    }
    final lines = out.putIfAbsent(name, () => []);
    if (!lines.contains(line)) lines.add(line);
  }

  // Commande lancée par un préfixe : premier argument qui n'est ni une
  // option ni une affectation (timeout 5 cmd : durée ignorée).
  void wrapped(String wrapper, List<String?> args, int line) {
    final valued = _valueOptions[wrapper] ?? const <String>{};
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == null) return; // expansion : commande inconnue
      if (valued.contains(a)) {
        i++; // option suivie de sa valeur (sudo -u app)
        continue;
      }
      if (a.startsWith('-') || a.contains('=')) continue;
      if ((wrapper == 'timeout' || wrapper == 'nice' || wrapper == 'flock') &&
          RegExp(r'^[\d.]+[smhd]?$|^/').hasMatch(a) &&
          i + 1 < args.length) {
        continue;
      }
      add(a, line);
      if (_wrappers.contains(a)) wrapped(a, args.sublist(i + 1), line);
      return;
    }
  }

  if (ast != null) {
    for (final c in ast.commands) {
      add(c.name, c.line);
      if (_wrappers.contains(c.name)) wrapped(c.name, c.args, c.line);
    }
    return out;
  }
  // Sans arbre syntaxique : premier mot de chaque commande de la ligne.
  final sep = RegExp(r'\|\||&&|[;|&(){}`]|\$\(');
  for (final l in lexScript(s.lines)) {
    if (l.inHeredoc || l.number == 1 && l.raw.startsWith('#!')) continue;
    for (final part in l.bare.split(sep)) {
      final words = part.trim().split(RegExp(r'\s+'));
      var i = 0;
      while (
          i < words.length && RegExp(r'^[A-Za-z_]\w*\+?=').hasMatch(words[i])) {
        i++; // affectations en tête
      }
      if (i >= words.length || words[i].isEmpty) continue;
      final name = words[i];
      if (RegExp(r'^(?:if|then|else|elif|do|while|until|!|time)$')
              .hasMatch(name) &&
          i + 1 < words.length) {
        final rest = words.sublist(i + 1);
        add(rest.first, l.number);
        continue;
      }
      add(name, l.number);
      if (_wrappers.contains(name)) {
        wrapped(name, words.sublist(i + 1), l.number);
      }
    }
  }
  return out;
}

/// Le script vérifie la présence de [name] (`command -v`, `type`, `hash`,
/// `which`).
bool checksCommand(String content, String name) => RegExp(
        r'(?:\bcommand[ \t]+-[vV]|\btype(?:[ \t]+-\w+)*|\bhash|\bwhich)'
        r'''(?:[ \t]+[^\s;&|]+)*?[ \t]+["']?'''
        '${RegExp.escape(name)}'
        r'''["']?(?=[\s;&|)]|$)''',
        multiLine: true)
    .hasMatch(content);

/// Inventaire des commandes externes, et problèmes ROB017.
class CommandsAnalyzer extends Analyzer {
  @override
  String get name => 'commands';

  /// Scripts shell seuls : les commandes d'un Dockerfile ou d'une CI
  /// s'exécutent ailleurs que sur la machine d'analyse.
  @override
  bool appliesTo(ScriptInfo script) =>
      super.appliesTo(script) && script.embedded == null;

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final ast = await loadAst(ctx);
    final used = externalCommands(ctx.script, ast: ast);
    if (used.isEmpty) {
      return AnalyzerResult(ToolRun(name, ToolStatus.ok, detail: '0'), const [],
          const <CommandUse>[]);
    }
    // Présence : un seul shell, `command -v` pour chaque nom.
    final r = await ctx.run('sh', [
      '-c',
      r'for c do p=$(command -v -- "$c" 2>/dev/null) && printf "%s\t%s\n" "$c" "$p"; done; :',
      'sh',
      ...used.keys,
    ]);
    final found = <String, String>{
      if (r != null)
        for (final l in r.stdout.split('\n'))
          if (l.contains('\t')) l.split('\t').first: l.split('\t').last,
    };
    final uses = [
      for (final e in used.entries)
        () {
          final base = e.key.split('/').last;
          final pkg = commandPackages[base];
          return CommandUse(e.key, e.value,
              found: r == null ? null : found.containsKey(e.key),
              path: found[e.key],
              dnf: pkg?.$1,
              apt: pkg?.$2,
              checked: checksCommand(ctx.script.content, e.key));
        }(),
    ];
    final info = ruleInfo('ROB017');
    final findings = [
      for (final u in uses)
        if (u.found == false && !u.checked && !baseCommands.contains(u.base))
          Finding(
            tool: 'builtin',
            ruleId: info.id,
            category: info.category,
            severity: info.severity,
            line: u.lines.first,
            message: '${info.title.of(ctx.lang)} (${u.name}'
                '${u.dnf == null ? '' : ' — dnf : ${u.dnf}, apt : ${u.apt}'})',
            hint: info.fix.of(ctx.lang),
          ),
    ];
    return AnalyzerResult(
        ToolRun(name, ToolStatus.ok,
            detail: '${uses.length}', findings: findings.length),
        findings,
        uses);
  }
}

/// Paquets à installer pour un ensemble de scripts : (dnf, apt) triés, sans
/// doublon ni commande de base.
(List<String>, List<String>) requiredPackages(Iterable<CommandUse> uses) {
  final dnf = <String>{}, apt = <String>{};
  for (final u in uses) {
    if (baseCommands.contains(u.base)) continue;
    if (u.dnf != null && u.dnf != '—') dnf.add(u.dnf!);
    if (u.apt != null && u.apt != '—') apt.add(u.apt!);
  }
  return (dnf.toList()..sort(), apt.toList()..sort());
}

/// Libellé court d'un inventaire (terminal) : `curl, jq ✗, rsync`.
String commandsLine(List<CommandUse> uses) => [
      for (final u in uses) u.found == false ? '${u.name} ✗' : u.name,
    ].join(', ');
