# Spec RPM de l'interface graphique check-script-gui (Flutter, Linux).
#
# Prérequis de build : SDK Flutter dans le PATH et les paquets de
# développement GTK ci-dessous. Orchestration : scripts/build-rpm.sh.
%{!?version: %global version 0.20.0}

%global debug_package %{nil}
%global __strip /bin/true

Name:           check-script-gui
Version:        %{version}
Release:        1%{?dist}
Summary:        Graphical interface of check-script (shell and Python script evaluation)
Summary(fr):    Interface graphique de check-script (évaluation de scripts shell et Python)

# À confirmer : aucune licence n'est encore choisie pour CheckScript.
License:        LGPL-3.0-or-later AND OFL-1.1
Source0:        check_script-%{version}.tar.gz

ExclusiveArch:  x86_64

BuildRequires:  gtk3-devel
BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  clang
BuildRequires:  pkgconf-pkg-config

# Le bundle Flutter embarque son moteur et ses plugins (.so) dans son propre
# répertoire : le scan automatique les prendrait pour des dépendances système.
AutoReqProv:    no
Requires:       gtk3
Requires:       glibc
Requires:       xdg-utils
Recommends:     check-script
Recommends:     ShellCheck
Recommends:     shfmt
Recommends:     ruff

%description
Graphical interface of check-script: annotated source, scores by category
(radar chart), filterable list of issues with fix advice, automatic fixes
with diff preview, folder analysis and trend against a baseline,
Markdown/AsciiDoc/HTML/JSON/SARIF export.

%description -l fr
Interface graphique de check-script : source annoté, notes par catégorie
(radar), liste filtrable des problèmes avec conseils de correction,
corrections automatiques avec aperçu du diff, analyse d'un dossier et
tendance par rapport à une référence, export Markdown/AsciiDoc/HTML/JSON/SARIF.

%prep
%autosetup -n check_script-%{version}

%build
command -v flutter >/dev/null 2>&1 || {
  echo "Error: 'flutter' not found in PATH (Flutter SDK required)." >&2
  exit 1
}
# Les *FLAGS de redhat-rpm-config cassent le build clang de l'embedder.
unset CFLAGS CXXFLAGS FFLAGS FCFLAGS LDFLAGS VALAFLAGS RUSTFLAGS
pushd gui
flutter pub get
flutter build linux --release --build-name=%{version}
popd

%install
export QA_RPATHS=$(( 0x0001|0x0010 ))
install -d %{buildroot}%{_prefix}/lib/check_script
cp -r gui/build/linux/x64/release/bundle/. %{buildroot}%{_prefix}/lib/check_script/
chmod +x %{buildroot}%{_prefix}/lib/check_script/check_script_gui
install -d %{buildroot}%{_bindir}
ln -sf %{_prefix}/lib/check_script/check_script_gui %{buildroot}%{_bindir}/check-script-gui
install -Dm644 assets/check_script.svg \
  %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/check_script.svg
install -d %{buildroot}%{_datadir}/applications
cat > %{buildroot}%{_datadir}/applications/check_script.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=CheckScript
GenericName=Évaluation de scripts shell et Python
Comment=Évalue la sécurité, la robustesse et la maintenabilité de scripts shell et Python
Exec=check-script-gui %F
Icon=check_script
Categories=Development;Security;Utility;
MimeType=application/x-shellscript;text/x-shellscript;text/x-python;text/x-python3;
Terminal=false
DESKTOP

%files
%license LICENSE COPYING
%{_prefix}/lib/check_script/
%{_bindir}/check-script-gui
%{_datadir}/icons/hicolor/scalable/apps/check_script.svg
%{_datadir}/applications/check_script.desktop
