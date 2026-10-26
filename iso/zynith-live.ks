# Zynith live image — Fedora 44, x86_64
#
# Built by iso/build-iso.sh with livemedia-creator (lorax) --no-virt inside a disposable Fedora 44 builder VM.
# The Zynith packages come from the local repository built by packaging/rpm/build-rpms.sh (/mnt/zynith/repo in the
# builder); everything else from Fedora 44 and its updates, through the local copy made by iso/fetch-packages.sh.
#
# The image boots into a live Zynith session (SDDM autologin, set up by livesys-zynith). Installing is Fedora's own
# Anaconda live installer ("Install to Hard Drive" in the launcher, or `liveinst`): it asks for the target disk and
# shows and confirms every change before writing anything. Nothing is partitioned or formatted by booting this image.

lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'
timezone UTC
selinux --enforcing
firewall --enabled --service=mdns
network --bootproto=dhcp --device=link --activate
services --enabled=NetworkManager,ModemManager,livesys,livesys-late,sddm,bluetooth --disabled=sshd
rootpw --lock
shutdown

# the build target (livemedia-creator makes the live root from this); not the installed system's layout, which
# Anaconda decides with the user at install time
bootloader --location=none
zerombr
clearpart --all --initlabel
reqpart
part / --size=12288 --fstype=ext4

# Fedora 44 and its updates, downloaded beforehand by iso/fetch-packages.sh into a local repository; the mirrors are a
# fallback for anything missing there (a higher cost: used only when the local repository has no candidate)
url --url=file:///mnt/zynith/fedora
repo --name=fedora-mirrors --mirrorlist="https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-44&arch=x86_64" --cost=2000
repo --name=updates-mirrors --mirrorlist="https://mirrors.fedoraproject.org/mirrorlist?repo=updates-released-f44&arch=x86_64" --cost=2000
# not added to the installed system: there is no published Zynith repository yet (see docs: updating)
repo --name=zynith --baseurl=file:///mnt/zynith/repo

%packages --exclude-weakdeps
# ── boot and live infrastructure ──
kernel
kernel-modules
kernel-modules-extra
dracut-live
dracut-config-generic
livesys-scripts
shim-x64
grub2-efi-x64
grub2-efi-x64-cdboot
grub2-pc
grub2-pc-modules
grub2-tools
grub2-tools-extra
efibootmgr
syslinux
memtest86+

# ── installer (Fedora Anaconda, live mode) ──
anaconda
anaconda-live
anaconda-install-env-deps
@anaconda-tools

# ── base system ──
@core
@hardware-support
@networkmanager-submodules
glibc-langpack-en
NetworkManager-wifi
NetworkManager-bluetooth
bluez
fwupd
linux-firmware
alsa-sof-firmware
mesa-dri-drivers
mesa-vulkan-drivers
pipewire
wireplumber
pipewire-pulseaudio
tuned-ppd
upower
polkit
flatpak

# ── login ──
sddm
sddm-wayland-generic

# ── Zynith ──
zynith-desktop
zynith-live
google-noto-sans-fonts
google-noto-sans-mono-fonts
google-noto-color-emoji-fonts
adwaita-icon-theme
firefox
xdg-user-dirs

# ── diagnostics and recovery ──
pciutils
usbutils
lshw
inxi
smartmontools
nvme-cli
dmidecode
parted
gdisk
dosfstools
btrfs-progs
cryptsetup
rsync
nano
vim-minimal
bash-completion
htop
%end

%post
# a live system: tmpfs /var/tmp, no stale machine identity, no rescue images
systemctl enable tmp.mount
cat >> /etc/fstab << EOF
vartmp   /var/tmp    tmpfs   defaults   0  0
EOF

# livesys: the session it sets up for the live user (packaging/live/livesys-zynith)
cat > /etc/sysconfig/livesys << EOF
livesys_session="zynith"
EOF

systemctl set-default graphical.target

# which Zynith and Fedora this image is (also shown by the Zynith Settings → About page through /usr/share/zynith/release)
releasever=$(rpm -q --qf '%{version}\n' --whatprovides system-release)
cat > /etc/zynith-image << EOF
ZYNITH_IMAGE_BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ZYNITH_PACKAGE=$(rpm -q zynith-desktop)
FEDORA_RELEASE=${releasever}
EOF

rm -f /var/lib/rpm/__db*
basearch=$(uname -m)
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-${releasever}-${basearch}
echo "Packages within this live image"
rpm -qa --qf '%{size}\t%{name}-%{version}-%{release}.%{arch}\n' | sort -rn
rm -f /var/lib/rpm/__db*
/usr/bin/mandb >/dev/null 2>&1 || :
rm -f /core*
rm -f /var/lib/systemd/random-seed
echo 'File created by kickstart. See systemd-update-done.service(8).' | tee /etc/.updated >/var/.updated
rm -f /boot/*-rescue*
rm -f /etc/machine-id
touch /etc/machine-id
%end

# the package manifest, outside the image (livemedia-creator runs this in the builder)
%post --nochroot
mkdir -p /mnt/zynith/out
chroot "${ANA_INSTALL_PATH:-/mnt/sysimage}" rpm -qa --qf '%{name}-%{version}-%{release}.%{arch}\n' 2>/dev/null | sort > /mnt/zynith/out/manifest.txt || :
%end
