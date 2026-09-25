# Spec RPM de l'interface graphique check-script-gui (Flutter, Linux).
#
# Prérequis de build : SDK Flutter dans le PATH et les paquets de
# développement GTK ci-dessous. Orchestration : scripts/build-rpm.sh.
%{!?version: %global version 0.6.0}

%global debug_package %{nil}
%global __strip /bin/true

Name:           check-script-gui
Version:        %{version}
Release:        1%{?dist}
Summary:        Interface graphique de check-script (evaluation de scripts shell)

# À confirmer : aucune licence n'est encore choisie pour CheckScript.
License:        LicenseRef-Unspecified
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

%description
Interface graphique de check-script : source annote, notes par categorie
(radar), liste filtrable des problemes avec conseils de correction,
corrections automatiques avec apercu du diff, analyse d'un dossier et
tendance par rapport a une reference, export Markdown/AsciiDoc/HTML/JSON/SARIF.

%prep
%autosetup -n check_script-%{version}

%build
command -v flutter >/dev/null 2>&1 || {
  echo "Erreur : 'flutter' introuvable dans PATH (SDK Flutter requis)." >&2
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
GenericName=Évaluation de scripts shell
Comment=Évalue la sécurité, la robustesse et la maintenabilité de scripts shell
Exec=check-script-gui %F
Icon=check_script
Categories=Development;Security;Utility;
MimeType=application/x-shellscript;text/x-shellscript;
Terminal=false
DESKTOP

%files
%{_prefix}/lib/check_script/
%{_bindir}/check-script-gui
%{_datadir}/icons/hicolor/scalable/apps/check_script.svg
%{_datadir}/applications/check_script.desktop
