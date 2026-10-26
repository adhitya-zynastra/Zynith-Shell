# Zynith — the desktop shell (native shell + Quickshell UI) and its niri session, for Fedora.
#
# Built from a git revision by packaging/rpm/build-rpms.sh, which passes:
#   --define "zynith_version X.Y.Z"  --define "zynith_release N"  --define "commit <sha>"  --define "snapdate YYYYMMDD"
# and the source tarball zynith-%%{version}.tar.gz made with `git archive` (packaging/rpm/build-rpms.sh).

%global zynith_version %{?zynith_version}%{!?zynith_version:0.1.0}
%global zynith_release %{?zynith_release}%{!?zynith_release:0}
%global commit %{?commit}%{!?commit:unknown}
%global shortcommit %(c=%{commit}; echo ${c:0:8})
%global snapdate %{?snapdate}%{!?snapdate:0}

Name:           zynith
Version:        %{zynith_version}
Release:        %{zynith_release}.%{snapdate}git%{shortcommit}%{?dist}
Summary:        Zynith, a desktop shell for the niri Wayland compositor
ExcludeArch:    %{ix86}

# Zynith is GPL-3.0-only. It includes MIT-licensed code whose notice is kept in LICENSES/, and vendored code
# under third_party/ (fzy and luau: MIT; material_color_utilities: Apache-2.0; wuffs: Apache-2.0 AND MIT); protocol
# XML under protocols/ keeps its own licences (BSD-3-Clause, HPND-sell-variant, LGPL-2.1-or-later, MIT); the bundled
# UI fonts are OFL-1.1.
License:        GPL-3.0-only AND MIT AND Apache-2.0 AND BSD-3-Clause AND HPND-sell-variant AND LGPL-2.1-or-later AND OFL-1.1
URL:            https://github.com/adhitya-zynastra/Zynith-Shell
Source0:        zynith-%{version}.tar.gz

# native shell (meson); the dependency set follows Fedora's own packaging of the upstream this shell derives from
BuildRequires:  meson
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig(sdbus-c++)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-protocols)
BuildRequires:  pkgconfig(wayland-egl)
BuildRequires:  pkgconfig(freetype2)
BuildRequires:  pkgconfig(fontconfig)
BuildRequires:  pkgconfig(cairo)
BuildRequires:  pkgconfig(cairo-ft)
BuildRequires:  pkgconfig(pango)
BuildRequires:  pkgconfig(pangocairo)
BuildRequires:  pkgconfig(pangoft2)
BuildRequires:  pkgconfig(harfbuzz)
BuildRequires:  pkgconfig(librsvg-2.0)
BuildRequires:  pkgconfig(xkbcommon)
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  pkgconfig(gobject-2.0)
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  pkgconfig(libsecret-1)
BuildRequires:  pkgconfig(libsodium)
BuildRequires:  pkgconfig(polkit-agent-1)
BuildRequires:  pkgconfig(polkit-gobject-1)
BuildRequires:  pkgconfig(libpipewire-0.3)
BuildRequires:  pkgconfig(wireplumber-0.5)
BuildRequires:  pkgconfig(libcurl)
BuildRequires:  pkgconfig(libqalculate)
BuildRequires:  pkgconfig(libxml-2.0)
BuildRequires:  pkgconfig(md4c)
BuildRequires:  json-static
BuildRequires:  pkgconfig(tomlplusplus)
BuildRequires:  pkgconfig(libical)
BuildRequires:  pam-devel
BuildRequires:  glibc-devel
BuildRequires:  pkgconfig(jemalloc)
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(glesv2)
BuildRequires:  stb_image_resize2-static
BuildRequires:  stb_image_write-static
BuildRequires:  pkgconfig(libwebp)
BuildRequires:  pkgconfig(libjxl)
BuildRequires:  pkgconfig(libjxl_threads)
BuildRequires:  pkgconfig(sndfile)
BuildRequires:  git-core
BuildRequires:  desktop-file-utils
# the UI's C++ plugin (cmake, Qt 6)
BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  qt6-rpm-macros
# UI sounds are synthesised at build time (deploy/sounds/generate.py)
BuildRequires:  python3

%description
Zynith is a desktop shell for the niri Wayland compositor: a native C++ shell that holds the services (audio,
network, power, notifications hand-over, lock screen, wallpaper, theme engine, IPC) and a Quickshell/QML interface that
draws everything you see — bars, the Zynith Island, the Control Panel, launcher, notification centre, on-screen
displays, desktop widgets and Settings.


%package        shell
Summary:        The Zynith native shell: services, lock screen, wallpaper and IPC
Requires:       hicolor-icon-theme
Requires:       pipewire
Requires:       git-core
Requires:       sound-theme-freedesktop
Recommends:     upower
Recommends:     gnome-keyring
Provides:       bundled(fzy)
Provides:       bundled(luau)
Provides:       bundled(material_color_utilities)
Provides:       bundled(wuffs)

%description    shell
The native half of Zynith (C++): the long-running services, the lock screen, the wallpaper renderer, the theme
engine and the command-line IPC (`zynith-shell msg …`); `zynith-ui` supervises it.


%package        ui
Summary:        The Zynith interface (Quickshell/QML) and its supervisor
Requires:       %{name}-shell%{?_isa} = %{version}-%{release}
Requires:       quickshell >= 0.3.1
Requires:       qt6-qtdeclarative%{?_isa}
Requires:       qt6-qtsvg%{?_isa}
Requires:       qt6-qtimageformats%{?_isa}
Requires:       socat
Requires:       libnotify
Requires:       zenity
Requires:       pipewire-utils
Requires:       xdg-utils
Requires:       python3
Requires:       jetbrains-mono-fonts-all

%description    ui
The Zynith UI: bars and the Zynith Island, the Control Panel, launcher, notification centre and popups, on-screen
displays, desktop widgets and the Settings app, written in QML for Quickshell, with its C++ plugin (Zynith.Native),
and `zynith-ui`, which starts and supervises both the UI and the native shell.


%package        desktop
Summary:        The Zynith desktop session on niri, with its default configuration
Requires:       %{name}-shell%{?_isa} = %{version}-%{release}
Requires:       %{name}-ui%{?_isa} = %{version}-%{release}
Requires:       niri
Requires:       xwayland-satellite
Requires:       xdg-desktop-portal-gnome
Requires:       xdg-desktop-portal-gtk
Requires:       gnome-keyring
Requires:       pipewire
Requires:       wireplumber
Requires:       pipewire-pulseaudio
Requires:       NetworkManager
Requires:       bluez
Requires:       upower
Requires:       polkit
Requires:       tuned-ppd
# the applications the default key bindings open (Super+Return, Super+E, Super+B)
Requires:       kitty
Requires:       Thunar
Recommends:     firefox

%description    desktop
A "Zynith" session for display managers: niri started through niri-session, with Zynith's default niri and Zynith
configuration copied into a user's home on first login (never over files that exist), and the services the desktop
relies on.


%package        live
Summary:        Zynith live-image setup (Fedora livesys)
Requires:       %{name}-desktop = %{version}-%{release}
Requires:       livesys-scripts
BuildArch:      noarch

%description    live
The livesys session script for a Zynith live image: logs the live user into Zynith and puts the installer in the
launcher. It acts only when the system was booted as a live image.


%prep
%autosetup -n zynith-%{version}


%conf
%meson -Dtests=disabled


%build
%meson_build
%{set_build_flags}
cmake -S ui/native -B build-ui-native -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=%{_prefix} \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
cmake --build build-ui-native %{?_smp_mflags}


%install
%meson_install

# ── the UI: the QML tree under /usr/share/zynith/ui (runtime files only), its plugin in Qt's qml directory ──
install -d %{buildroot}%{_datadir}/zynith/ui
cp -a ui/Common ui/Components ui/Modules ui/Services ui/Widgets ui/templates ui/assets \
      ui/shell.qml ui/settings.qml ui/zynith-ui \
      %{buildroot}%{_datadir}/zynith/ui/
echo "%{version}-%{release} (%{commit})" > %{buildroot}%{_datadir}/zynith/ui/VERSION
# the UI addresses the shared assets (icon font, emoji) as ../assets beside itself
ln -s ../zynith-shell/assets %{buildroot}%{_datadir}/zynith/assets
install -d %{buildroot}%{_bindir}
ln -s ../share/zynith/ui/zynith-ui %{buildroot}%{_bindir}/zynith-ui
install -d %{buildroot}%{_qt6_qmldir}/Zynith/Native
cp -a build-ui-native/qml/Zynith/Native/. %{buildroot}%{_qt6_qmldir}/Zynith/Native/
python3 deploy/sounds/generate.py %{buildroot}%{_datadir}/zynith/sounds >/dev/null
install -Dm0644 packaging/session/zynith-settings.desktop %{buildroot}%{_datadir}/applications/zynith-settings.desktop
install -Dm0644 ui/assets/brand/zynith-mark.png %{buildroot}%{_datadir}/icons/hicolor/512x512/apps/zynith.png
# the official configurations and the tool that applies them (zynith-config)
install -d %{buildroot}%{_datadir}/zynith/configs
cp -a configs/official %{buildroot}%{_datadir}/zynith/configs/
chmod 0755 %{buildroot}%{_datadir}/zynith/configs/official/zynith-config.py
ln -s ../share/zynith/configs/official/zynith-config.py %{buildroot}%{_bindir}/zynith-config

# ── the session ──
install -Dm0755 packaging/session/zynith-session %{buildroot}%{_bindir}/zynith-session
install -Dm0755 packaging/session/zynith-firstrun %{buildroot}%{_libexecdir}/zynith/zynith-firstrun
install -Dm0644 packaging/session/zynith.desktop %{buildroot}%{_datadir}/wayland-sessions/zynith.desktop
install -d %{buildroot}%{_datadir}/zynith/defaults
cp -a packaging/defaults/home %{buildroot}%{_datadir}/zynith/defaults/
echo "Zynith %{version}-%{release} (%{commit})" > %{buildroot}%{_datadir}/zynith/release

# ── live ──
install -Dm0755 packaging/live/livesys-zynith %{buildroot}%{_libexecdir}/livesys/sessions.d/livesys-zynith


%check
desktop-file-validate %{buildroot}%{_datadir}/applications/dev.zynith.Shell.desktop
desktop-file-validate %{buildroot}%{_datadir}/applications/zynith-settings.desktop
test -x %{buildroot}%{_bindir}/zynith-shell
test -f %{buildroot}%{_qt6_qmldir}/Zynith/Native/qmldir
test -f %{buildroot}%{_datadir}/zynith/sounds/notification.wav
python3 %{buildroot}%{_datadir}/zynith/configs/official/zynith-config.py validate
# the default niri configuration parses (niri is not a build dependency; checked by the ISO build instead)


%files shell
%license LICENSE LICENSES/*
%{_bindir}/zynith-shell
%{_datadir}/applications/dev.zynith.Shell.desktop
%{_datadir}/icons/hicolor/scalable/apps/zynith-shell.svg
%{_datadir}/zynith-shell

%files ui
%license LICENSE ui/assets/fonts/OFL.txt
%{_bindir}/zynith-ui
%{_bindir}/zynith-config
%dir %{_datadir}/zynith
%{_datadir}/zynith/configs
%{_datadir}/zynith/ui
%{_datadir}/zynith/assets
%{_datadir}/zynith/sounds
%{_qt6_qmldir}/Zynith
%{_datadir}/applications/zynith-settings.desktop
%{_datadir}/icons/hicolor/512x512/apps/zynith.png

%files desktop
%{_bindir}/zynith-session
%dir %{_libexecdir}/zynith
%{_libexecdir}/zynith/zynith-firstrun
%{_datadir}/wayland-sessions/zynith.desktop
%{_datadir}/zynith/defaults
%{_datadir}/zynith/release

%files live
%{_libexecdir}/livesys/sessions.d/livesys-zynith


%changelog
* Sun Oct 25 2026 Zynith <https://github.com/adhitya-zynastra/Zynith-Shell> - 0.1.0-0
- First packaging of Zynith for Fedora: native shell, UI, niri session, live-image setup
