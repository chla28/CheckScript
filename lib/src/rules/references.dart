/// Références normatives des règles : CWE (MITRE), OWASP Top 10 2021 et
/// OWASP Top 10 CI/CD, recommandations de l'ANSSI.
///
/// Une référence est une chaîne : `CWE-78`, `OWASP A03:2021`,
/// `OWASP CICD-SEC-4`, `ANSSI-BP-028 R59`, `ANSSI-FT-082 R7`,
/// `ANSSI OpenSSH R6`. Seules les correspondances directes sont indiquées :
/// beaucoup de règles de style ou de performance n'en ont pas.
///
/// Documents ANSSI : ANSSI-BP-028 « Recommandations de configuration d'un
/// système GNU/Linux » (v2.0, 2022) ; ANSSI-FT-082 « Recommandations de
/// sécurité relatives au déploiement de conteneurs Docker » (2020) ; note
/// technique « Recommandations pour un usage sécurisé d'(Open)SSH ».
library;

import '../model/finding.dart';
import 'same_rules.dart';

class RuleRefs {
  final List<int> cwe;
  final List<String> owasp;
  final List<String> anssi;
  const RuleRefs(
      {this.cwe = const [], this.owasp = const [], this.anssi = const []});

  List<String> get all => [
        for (final c in cwe) 'CWE-$c',
        for (final o in owasp) 'OWASP $o',
        ...anssi,
      ];
}

// Raccourcis.
const _a01 = 'A01:2021', _a02 = 'A02:2021', _a03 = 'A03:2021';
const _a05 = 'A05:2021', _a07 = 'A07:2021', _a08 = 'A08:2021';
const _a09 = 'A09:2021';
const _cicd3 = 'CICD-SEC-3', _cicd4 = 'CICD-SEC-4', _cicd5 = 'CICD-SEC-5';
const _cicd6 = 'CICD-SEC-6', _cicd9 = 'CICD-SEC-9';
String _bp(int r) => 'ANSSI-BP-028 R$r';

/// Références des règles intégrées.
final Map<String, RuleRefs> ruleReferences = {
  'SEC001': RuleRefs(cwe: [494], owasp: [_a08], anssi: [_bp(59)]),
  'SEC002': const RuleRefs(cwe: [798], owasp: [_a07]),
  'SEC003': const RuleRefs(cwe: [95, 78], owasp: [_a03]),
  'SEC004': RuleRefs(cwe: [732], owasp: [_a01], anssi: [_bp(50), _bp(54)]),
  'SEC005':
      const RuleRefs(cwe: [295], owasp: [_a07], anssi: ['ANSSI OpenSSH R6']),
  'SEC006': const RuleRefs(cwe: [319, 494], owasp: [_a02, _a08]),
  'SEC007': const RuleRefs(cwe: [73]),
  'SEC009': RuleRefs(cwe: [377, 59], anssi: [_bp(55)]),
  'SEC010': const RuleRefs(cwe: [214]),
  'SEC011': const RuleRefs(cwe: [829], owasp: [_a08]),
  'SEC012': const RuleRefs(cwe: [532], owasp: [_a09]),
  'SEC013': RuleRefs(cwe: [250], anssi: [_bp(56)]),
  'SEC014': const RuleRefs(cwe: [549]),
  'SEC015': RuleRefs(cwe: [426], anssi: [_bp(39)]),
  'SEC016': RuleRefs(cwe: [427], anssi: [_bp(39)]),
  'SEC017': const RuleRefs(cwe: [426]),
  'SEC018': RuleRefs(cwe: [269], owasp: [_a01], anssi: [_bp(50)]),
  'SEC019': RuleRefs(cwe: [494], owasp: [_a08], anssi: [_bp(59)]),
  'SEC020': const RuleRefs(cwe: [668], anssi: ['ANSSI OpenSSH R20']),
  'SEC021': const RuleRefs(cwe: [526]),
  'SEC022': const RuleRefs(cwe: [798], owasp: [_a07]),
  'SEC023': const RuleRefs(cwe: [78, 94], owasp: [_a03, _cicd4]),
  'SEC024': const RuleRefs(cwe: [1357], owasp: [_a08, _cicd3]),
  'SEC025': RuleRefs(cwe: [347, 494], owasp: [_a08, _cicd3], anssi: [_bp(59)]),
  'SEC026': const RuleRefs(cwe: [829], owasp: [_a08, _cicd3]),
  'DKR001': const RuleRefs(cwe: [1357], owasp: [_a08, _cicd3]),
  'DKR002':
      const RuleRefs(cwe: [250], owasp: [_a05], anssi: ['ANSSI-FT-082 R7']),
  'DKR003': const RuleRefs(cwe: [494], owasp: [_a08, _cicd9]),
  'DKR005': const RuleRefs(cwe: [798, 526], owasp: [_a07, _cicd6]),
  'DKR006': RuleRefs(anssi: [_bp(58)]),
  'CI001': const RuleRefs(cwe: [829, 1357], owasp: [_a08, _cicd3]),
  'CI002': const RuleRefs(cwe: [250, 272], owasp: [_a01, _cicd5]),
  'CI003': const RuleRefs(cwe: [829, 94], owasp: [_a08, _cicd4]),
  'CI004': const RuleRefs(cwe: [798], owasp: [_a07, _cicd6]),
  'CI005': const RuleRefs(cwe: [1357], owasp: [_a08, _cicd3]),
  'ROB001': const RuleRefs(cwe: [252]),
  'ROB002': const RuleRefs(cwe: [252]),
  'ROB003': const RuleRefs(cwe: [457]),
  'ROB004': const RuleRefs(cwe: [459]),
  'ROB005': const RuleRefs(cwe: [252]),
  'ROB011': const RuleRefs(cwe: [252]),
  'ROB013': const RuleRefs(cwe: [459]),
  'ROB014': const RuleRefs(cwe: [362]),
  'MNT003': const RuleRefs(cwe: [1124]),
  'MNT006': const RuleRefs(cwe: [546]),
  'POR005': const RuleRefs(cwe: [477]),
  'POR007': const RuleRefs(cwe: [477]),
  'PYSEC001': const RuleRefs(cwe: [798], owasp: [_a07]),
  'PYROB001': const RuleRefs(cwe: [1088]),
  'PYROB003': const RuleRefs(cwe: [362]),
  'PYROB004': const RuleRefs(cwe: [393]),
};

/// Références d'une règle : la sienne, sinon celle de la même règle sous le
/// code d'un autre outil ([sameRuleIds]).
List<String> referencesOf(String ruleId) {
  final own = ruleReferences[ruleId.toUpperCase()];
  if (own != null) return own.all;
  for (final same in sameRuleIds(ruleId.toUpperCase())) {
    final r = ruleReferences[same];
    if (r != null) return r.all;
  }
  return const [];
}

/// Références d'un problème : celles fournies par l'outil, celles de sa
/// règle, et celles des règles intégrées équivalentes (hadolint, zizmor…).
List<String> findingReferences(Finding f) {
  final out = <String>{
    ...f.refs,
    ...referencesOf(f.ruleId),
    for (final e in f.equivalents)
      if (!e.endsWith('*')) ...referencesOf(e),
  };
  return sortReferences(out);
}

/// Ordre d'affichage : CWE (numérique), OWASP, ANSSI.
List<String> sortReferences(Iterable<String> refs) {
  int rank(String r) => r.startsWith('CWE-')
      ? 0
      : r.startsWith('OWASP')
          ? 1
          : 2;
  int num(String r) => int.tryParse(r.substring(4)) ?? 0;
  return refs.toSet().toList()
    ..sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      if (c != 0) return c;
      return rank(a) == 0 ? num(a).compareTo(num(b)) : a.compareTo(b);
    });
}

/// Intitulés des références utilisées (et des catégories OWASP).
const Map<String, String> referenceTitles = {
  'CWE-59': 'Improper Link Resolution Before File Access',
  'CWE-73': 'External Control of File Name or Path',
  'CWE-78': 'Improper Neutralization of Special Elements used in an OS Command',
  'CWE-94': 'Improper Control of Generation of Code',
  'CWE-95':
      'Improper Neutralization of Directives in Dynamically Evaluated Code',
  'CWE-214': 'Invocation of Process Using Visible Sensitive Information',
  'CWE-250': 'Execution with Unnecessary Privileges',
  'CWE-252': 'Unchecked Return Value',
  'CWE-269': 'Improper Privilege Management',
  'CWE-272': 'Least Privilege Violation',
  'CWE-295': 'Improper Certificate Validation',
  'CWE-319': 'Cleartext Transmission of Sensitive Information',
  'CWE-347': 'Improper Verification of Cryptographic Signature',
  'CWE-362':
      'Concurrent Execution using Shared Resource with Improper Synchronization',
  'CWE-377': 'Insecure Temporary File',
  'CWE-393': 'Return of Wrong Status Code',
  'CWE-426': 'Untrusted Search Path',
  'CWE-427': 'Uncontrolled Search Path Element',
  'CWE-457': 'Use of Uninitialized Variable',
  'CWE-459': 'Incomplete Cleanup',
  'CWE-477': 'Use of Obsolete Function',
  'CWE-494': 'Download of Code Without Integrity Check',
  'CWE-526':
      'Cleartext Storage of Sensitive Information in an Environment Variable',
  'CWE-532': 'Insertion of Sensitive Information into Log File',
  'CWE-546': 'Suspicious Comment',
  'CWE-549': 'Missing Password Field Masking',
  'CWE-668': 'Exposure of Resource to Wrong Sphere',
  'CWE-732': 'Incorrect Permission Assignment for Critical Resource',
  'CWE-798': 'Use of Hard-coded Credentials',
  'CWE-829': 'Inclusion of Functionality from Untrusted Control Sphere',
  'CWE-1088': 'Synchronous Access of Remote Resource without Timeout',
  'CWE-1124': 'Excessively Deep Nesting',
  'CWE-1357': 'Reliance on Insufficiently Trustworthy Component',
  'OWASP A01:2021': 'Broken Access Control',
  'OWASP A02:2021': 'Cryptographic Failures',
  'OWASP A03:2021': 'Injection',
  'OWASP A04:2021': 'Insecure Design',
  'OWASP A05:2021': 'Security Misconfiguration',
  'OWASP A06:2021': 'Vulnerable and Outdated Components',
  'OWASP A07:2021': 'Identification and Authentication Failures',
  'OWASP A08:2021': 'Software and Data Integrity Failures',
  'OWASP A09:2021': 'Security Logging and Monitoring Failures',
  'OWASP A10:2021': 'Server-Side Request Forgery (SSRF)',
  'OWASP CICD-SEC-3': 'Dependency Chain Abuse',
  'OWASP CICD-SEC-4': 'Poisoned Pipeline Execution (PPE)',
  'OWASP CICD-SEC-5': 'Insufficient PBAC (Pipeline-Based Access Controls)',
  'OWASP CICD-SEC-6': 'Insufficient Credential Hygiene',
  'OWASP CICD-SEC-9': 'Improper Artifact Integrity Validation',
  'ANSSI-BP-028 R39': 'Modifier les directives de configuration sudo',
  'ANSSI-BP-028 R50':
      'Restreindre les droits d\'accès aux fichiers et aux répertoires sensibles',
  'ANSSI-BP-028 R54': 'Activer le sticky bit sur les répertoires inscriptibles',
  'ANSSI-BP-028 R55': 'Séparer les répertoires temporaires des utilisateurs',
  'ANSSI-BP-028 R56':
      'Éviter l\'usage d\'exécutables avec les droits spéciaux setuid et setgid',
  'ANSSI-BP-028 R58': 'N\'installer que les paquets strictement nécessaires',
  'ANSSI-BP-028 R59': 'Utiliser des dépôts de paquets de confiance',
  'ANSSI-FT-082 R7':
      'Démarrer les conteneurs avec un namespace USER ID distinct de l\'hôte',
  'ANSSI OpenSSH R6': 'S\'assurer de la légitimité du serveur contacté',
  'ANSSI OpenSSH R20': 'Le serveur hôte relais doit être un hôte de confiance',
};

const _owasp2021 = {
  'A01': 'A01_2021-Broken_Access_Control',
  'A02': 'A02_2021-Cryptographic_Failures',
  'A03': 'A03_2021-Injection',
  'A04': 'A04_2021-Insecure_Design',
  'A05': 'A05_2021-Security_Misconfiguration',
  'A06': 'A06_2021-Vulnerable_and_Outdated_Components',
  'A07': 'A07_2021-Identification_and_Authentication_Failures',
  'A08': 'A08_2021-Software_and_Data_Integrity_Failures',
  'A09': 'A09_2021-Security_Logging_and_Monitoring_Failures',
  'A10': 'A10_2021-Server-Side_Request_Forgery_%28SSRF%29',
};

const _cicd = {
  3: 'CICD-SEC-03-Dependency-Chain-Abuse',
  4: 'CICD-SEC-04-Poisoned-Pipeline-Execution',
  5: 'CICD-SEC-05-Insufficient-PBAC',
  6: 'CICD-SEC-06-Insufficient-Credential-Hygiene',
  9: 'CICD-SEC-09-Improper-Artifact-Integrity-Validation',
};

/// Page de documentation d'une référence (null si inconnue).
String? referenceUrl(String ref) {
  final cwe = RegExp(r'^CWE-(\d+)$').firstMatch(ref);
  if (cwe != null) {
    return 'https://cwe.mitre.org/data/definitions/${cwe[1]}.html';
  }
  final top10 = RegExp(r'^OWASP (A\d\d):2021$').firstMatch(ref);
  if (top10 != null && _owasp2021[top10[1]] != null) {
    return 'https://top10.owasp.org/2021/${_owasp2021[top10[1]]}/';
  }
  final ci = RegExp(r'^OWASP CICD-SEC-(\d+)$').firstMatch(ref);
  if (ci != null) {
    final page = _cicd[int.parse(ci[1]!)];
    return 'https://owasp.org/www-project-top-10-ci-cd-security-risks/'
        '${page ?? ''}';
  }
  if (ref.startsWith('ANSSI-BP-028')) {
    return 'https://messervices.cyber.gouv.fr/documents-guides/fr_np_linux_configuration-v2.0.pdf';
  }
  if (ref.startsWith('ANSSI-FT-082')) {
    return 'https://messervices.cyber.gouv.fr/documents-guides/docker_fiche_technique.pdf';
  }
  if (ref.startsWith('ANSSI OpenSSH')) {
    return 'https://messervices.cyber.gouv.fr/documents-guides/NT_OpenSSH.pdf';
  }
  return null;
}

/// [refs] contient une référence commençant par l'un des [filters] (sans
/// casse ; « A08 » vise « OWASP A08:2021 », « CICD » les risques CI/CD).
bool matchesReference(List<String> refs, List<String> filters) {
  final wanted = [for (final f in filters) f.trim().toUpperCase()];
  return refs.any((r) {
    final u = r.toUpperCase();
    final bare = u.startsWith('OWASP ') ? u.substring(6) : u;
    return wanted.any((w) => u.startsWith(w) || bare.startsWith(w));
  });
}

/// Famille d'une référence (regroupement dans les rapports).
String referenceFamily(String ref) => ref.startsWith('CWE-')
    ? 'CWE'
    : ref.startsWith('OWASP CICD')
        ? 'OWASP CI/CD'
        : ref.startsWith('OWASP')
            ? 'OWASP Top 10 2021'
            : 'ANSSI';
