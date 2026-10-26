# The Zynith ISO

The Zynith ISO is a live and installable image of **Fedora Linux 44** (x86_64) with **niri** and **Zynith**. It
boots into a live Zynith session. From there, Fedora's own installer, **Anaconda**, installs it to a disk.

> **Status: in development.** No ISO has been published. See [Validation status](#validation-status) for what has
> been tested and on what. Never install it on a machine whose data you have not backed up.

## What is in it

- Fedora 44: kernel, firmware, Mesa (Intel, AMD and the open NVIDIA drivers), PipeWire, NetworkManager, BlueZ,
  power profiles (`tuned-ppd`), Flatpak and Firefox.
- niri, the Zynith packages (`zynith-shell`, `zynith-ui`, `zynith-desktop`, `zynith-live`) and the pinned
  Quickshell 0.3.1 build. See [Packaging](packaging.md).
- SDDM as the login screen, with the **Zynith** session.
- The Anaconda installer in live mode ("Install to Hard Drive" in the launcher, or `liveinst` in a terminal).
- Tools for diagnosis and recovery: `lshw`, `inxi`, `smartctl`, `nvme`, `parted`, `gdisk`, `cryptsetup`, `btrfs`
  and an editor.

Every package and version in a build is listed in its `manifest.txt`.

It does not contain: proprietary drivers, codecs outside Fedora, a published Zynith package repository, or any
file from the machine it was built on. The default configuration comes from `packaging/defaults/` in this
repository.

### Defaults that matter for security

- SELinux is enforcing. The firewall is enabled (mDNS allowed). `sshd` is disabled.
- `root` is locked.
- The live user (`liveuser`) has no password and passwordless `sudo`, as in Fedora's own live images. It exists
  only in the live session.
- The installed system has only the accounts you create in the installer.
- Booting the ISO never partitions, formats or writes to a disk. Only the installer writes, and only to the disk
  you select, after you confirm.

## Building

Needs rootless podman and QEMU/KVM on an x86_64 Fedora host (read/write access to `/dev/kvm`), about 40 GB free
under `build/`, and a network connection (the first build downloads about 2–3 GB of Fedora packages). No root access and no image tools on the host.

```sh
iso/build-iso.sh                    # the RPMs from the committed HEAD, then the ISO
iso/build-iso.sh --rev v0.1.0       # from a tag
iso/build-iso.sh --reuse-rpms       # with the RPMs already in build/release/repo
```

How the build works:

1. `packaging/rpm/build-rpms.sh` builds the Zynith RPMs in a clean Fedora 44 container and makes a local
   repository with them and the pinned Quickshell build.
2. `iso/fetch-packages.sh` resolves every Fedora package the image needs (from the kickstart, groups included) in a
   clean container and downloads them once, with parallel connections, into a persistent cache
   (`build/release/cache/fedora-pkgs`). A local repository is made from it. Later builds fetch only what changed,
   and the builder installs from this repository, using the Fedora mirrors only for anything missing.
3. The kickstart `iso/zynith-live.ks` is validated with `ksvalidator`.
4. The builder is the Fedora 44 Cloud image. It is downloaded once, and its signed checksum is verified against
   Fedora's key on the host.
5. A disposable builder VM runs `livemedia-creator --no-virt --make-iso` on the kickstart. The VM runs at low
   priority on half the cores, with a time limit. The kickstart and the repository go in on one virtual disk, and
   the ISO and logs come out on another. The VM is then deleted.

Output, in `build/release/iso/`:

| File | What |
|---|---|
| `zynith-<version>-<date>-x86_64.iso` | the image |
| `zynith-<version>-<date>-x86_64.iso.sha256` | its SHA-256 |
| `manifest.txt` | every package in the image, with its version |
| `build-info.txt` | what it was built from: the Zynith packages' version and commit, the kickstart's revision, the Fedora release and the builder image |
| `*.log` | the builder's logs (`build.log`, `lmc.log`, `program.log`, `builder-journal.log`) |

A full build, RPMs included, takes about an hour on an 8-core laptop.

## Verifying a download

```sh
sha256sum -c zynith-0.1.0-<date>-x86_64.iso.sha256
```

It must print `OK`. Published ISOs will also be listed with their checksums on the release page.

## Writing it to a USB stick

Everything on the stick is erased. With **Fedora Media Writer** (Flatpak `org.fedoraproject.MediaWriter`), choose
*Select .iso file*, then the stick.

Or with `dd`. First find the stick's device name, and make sure it is the stick and not an internal disk:

```sh
lsblk -o NAME,SIZE,MODEL,TRAN          # the stick shows TRAN "usb"
sudo dd if=zynith-0.1.0-<date>-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

## Booting and installing

1. Boot from the stick through the firmware's one-time boot menu (often F12, F10, F8 or Esc at power-on). The
   menu offers *Start Zynith* and *Test this media & start Zynith*.
2. The live session starts on its own. Try it before installing: display, input, network, audio.
3. Start **Install to Hard Drive** from the launcher (or run `liveinst` in a terminal).
4. Anaconda asks for language, keyboard and time zone, and for the **installation destination**. Pick the target
   disk yourself, and choose automatic or custom partitioning. Before anything is written, Anaconda shows the
   changes and asks for confirmation.
5. Create your user account (with administrator rights), then *Begin Installation*. Reboot when it finishes, and
   remove the stick.
6. At the login screen choose the **Zynith** session. On the first login `zynith-firstrun` sets up the default
   configuration.

### Installing beside another operating system

Anaconda can install into free space and leave other partitions alone. Shrink the other system's partition from
that system first. On Windows:

- turn off Fast Startup;
- have the BitLocker recovery key at hand, because firmware changes can ask for it;
- do not install onto a disk you have not backed up.

## Updating an installed system

- Fedora's packages update as on any Fedora system: `sudo dnf upgrade`, or GNOME Software if you install it.
- **Zynith's packages have no repository yet**, so `dnf` does not update them. Build newer RPMs (see
  [Packaging](packaging.md#updates)) and install them with `sudo dnf upgrade ./zynith-*.rpm ./quickshell-*.rpm ./cpptrace-*.rpm`.
- Upgrades never change files in home directories. `zynith-firstrun` only adds default files an account does not
  have yet.

## Recovery

| Problem | What to do |
|---|---|
| The installed system does not boot after an update | choose the previous kernel in the GRUB menu (hold Shift or press Esc during boot to show it) |
| The Zynith session does not start | switch to a text console with Ctrl+Alt+F3, log in, and follow [Recovery](building.md#recovery); the **niri** session in the login screen's session list starts niri with the same configuration |
| The configuration is broken | move `~/.config/zynith` or `~/.config/niri` aside and log in again; `zynith-firstrun` puts the defaults back |
| The disk needs repair, or files need rescuing | boot the ISO: the live session has the disk tools above, and nothing is mounted or changed until you do it |

## Hardware notes

The image is generic. It contains no configuration for a particular machine, and hardware-specific choices are left
to the installed system.

### Graphics

Zynith needs OpenGL ES 3.0. Intel and AMD integrated graphics are what it is developed on.

**NVIDIA**: the image has only the open drivers (nouveau, and NVK for Vulkan). Support for recent NVIDIA GPUs in
the open drivers is still developing, and Zynith has not been tested on any NVIDIA GPU. On a laptop with both an
integrated and an NVIDIA GPU, use the firmware's hybrid mode, so that the integrated GPU drives the internal display,
for the live session and the installation.

NVIDIA's proprietary driver is not in the image. It can be added to an installed system from RPM Fusion
(`akmod-nvidia`). With Secure Boot on, the locally built kernel module must be signed with a key enrolled through
MOK. Follow RPM Fusion's NVIDIA instructions. This is untested with Zynith.

### Displays

niri chooses each display's preferred mode. Settings → Displays changes the mode, scale and orientation.

Variable refresh rate is off by default; niri supports it per display (`variable-refresh-rate`). HDR is not
configured by niri or Zynith.

### Laptops with hybrid graphics

- Use the firmware's hybrid mode (not discrete-GPU-only) for the live session and the installation, so that the
  integrated GPU drives the internal display through an open driver.
- Booting with Secure Boot on uses Fedora's signed shim and kernel unchanged.
- Suspend and resume, keyboard backlights, fan and vendor power modes, and external outputs on a discrete GPU depend
  on the machine and have not been validated. Report what works and what does not in an issue, with the model and the
  output of `inxi -Fxz` (which leaves out serial numbers and addresses).

## Testing in a virtual machine

```sh
iso/test-vm.sh live                 # UEFI, through the ISO's own boot loader
iso/test-vm.sh live --bios          # legacy BIOS
iso/test-vm.sh live --secure-boot   # UEFI with Secure Boot (Microsoft and Fedora keys enrolled)
iso/test-vm.sh console              # the ISO's kernel booted directly, with a serial console for scripted checks
iso/test-vm.sh install              # the same, with a blank 40 GB virtual disk to install to
iso/test-vm.sh installed            # boot the installed virtual disk
iso/test-vm.sh stop
```

The VMs are headless. `iso/vmctl.py` takes screenshots and runs commands on the serial console, for example:

```sh
iso/vmctl.py screendump build/release/vm/qmp.sock live.png
iso/vmctl.py run build/release/vm/serial.sock 'systemctl --failed'
```

The automated installation test runs Anaconda with the kickstart `iso/tests/install-vm.ks` inside the VM. That
kickstart erases the VM's own blank virtual disk, and it is not part of the image.

## Validation status

| Check | Result |
|---|---|
| Kickstart validates (`ksvalidator -v F44`) | passed |
| RPMs build in a clean container, `%check` passes | *pending* |
| ISO builds | *pending* |
| UEFI boot to the live Zynith session (VM) | *pending* |
| BIOS boot (VM) | *pending* |
| Secure Boot (VM) | *pending* |
| Installation to a virtual disk, reboot, first login (VM) | *pending* |
| Any physical machine | **not tested** |

## Known limitations

- No Zynith package repository: installed systems do not receive Zynith updates through `dnf`.
- No physical hardware has been tested.
- The open NVIDIA drivers' support for current GPUs is limited, and the proprietary driver is a manual step after
  installation.
- Live wallpapers (animated) need a renderer that is not packaged.
- The native shell's plugins come from upstream catalogues and have not been curated for Zynith.
- Some optional features of the native shell use services run by the Noctalia project. See
  [SECURITY](../../SECURITY.md#network-services).
