# Spec RPM du CLI check-script.
#
# Prérequis de build : SDK Dart dans le PATH (aucun paquet « dart » dans les
# dépôts Fedora/RHEL) et asciidoctor pour la page de manuel. Orchestration :
# scripts/build-rpm.sh.
%{!?version: %global version 0.13.0}

# Binaire AOT de `dart compile exe` : pas d'information DWARF exploitable
# (sous-paquet debuginfo vide) et le strip automatique le corrompt (il ne
# garde que le runtime Dart, sans le snapshot applicatif). On neutralise les
# deux, comme pour les autres outils AuditTools.
%global debug_package %{nil}
%global __strip /bin/true

Name:           check-script
Version:        %{version}
Release:        1%{?dist}
Summary:        Evaluation de scripts shell (securite, robustesse, maintenabilite...)

# À confirmer : aucune licence n'est encore choisie pour CheckScript.
License:        LGPL-3.0-or-later
Source0:        check_script-%{version}.tar.gz

ExclusiveArch:  x86_64
BuildRequires:  rubygem-asciidoctor

# Outils d'analyse exploites s'ils sont presents (dependances faibles).
Recommends:     ShellCheck
Recommends:     shfmt
Recommends:     devscripts-checkbashisms
Suggests:       python3-bashate
# Scripts Python : paquets Fedora ; bandit, semgrep, radon, vermin et pyright
# s'installent par pipx (voir la documentation).
Recommends:     ruff
Recommends:     python3-mypy
Suggests:       pylint

%description
check-script note des scripts shell ou Python sur cinq categories (Securite,
Robustesse, Maintenabilite, Portabilite, Performance) avec le nombre de
problemes par severite, une note globale et un niveau A-E. Il exploite
ShellCheck, shfmt, bashate, checkbashisms, gitleaks, trufflehog et bash -n,
les complete par des regles integrees, corrige les defauts surs (--fix) et
produit des rapports terminal, Markdown, AsciiDoc, HTML, JSON, SARIF et
GitLab Code Quality.

%prep
%autosetup -n check_script-%{version}

%build
command -v dart >/dev/null 2>&1 || {
  echo "Erreur : 'dart' introuvable dans PATH (SDK Dart requis)." >&2
  exit 1
}
dart pub get
dart compile exe bin/check_script.dart -o check-script
asciidoctor -b manpage doc/check-script.1.adoc -o check-script.1

%install
install -Dm755 check-script %{buildroot}%{_bindir}/check-script
install -Dm644 check-script.1 %{buildroot}%{_mandir}/man1/check-script.1
install -Dm644 completions/check-script.bash \
  %{buildroot}%{_datadir}/bash-completion/completions/check-script
install -Dm644 completions/_check-script \
  %{buildroot}%{_datadir}/zsh/site-functions/_check-script
install -Dm644 doc/checkscript.example.yaml \
  %{buildroot}%{_docdir}/%{name}/checkscript.example.yaml

%files
%license LICENSE COPYING
%doc README.md CHANGELOG.md doc/user.adoc doc/developer.adoc
%{_docdir}/%{name}/checkscript.example.yaml
%{_bindir}/check-script
%{_mandir}/man1/check-script.1*
%{_datadir}/bash-completion/completions/check-script
%{_datadir}/zsh/site-functions/_check-script
