#!/usr/bin/env bash
# iso/build-iso.sh — build the Zynith live/install ISO (Fedora 44, x86_64).
#
#   iso/build-iso.sh                  RPMs from the committed HEAD, then the ISO
#   iso/build-iso.sh --rev v0.1.0     from a tag or commit
#   iso/build-iso.sh --worktree       RPMs from the working tree (development only)
#   iso/build-iso.sh --reuse-rpms     use build/release/repo as it is
#
# How: the Zynith RPMs are built in a rootless Fedora container (packaging/rpm/build-rpms.sh). The image is made by
# Fedora's livemedia-creator (lorax, --no-virt) from iso/zynith-live.ks, inside a disposable Fedora 44 Cloud VM run
# with the host's QEMU/KVM — so the host needs no image tools, no root and no packages beyond podman and qemu. The
# kickstart and the local repository go in on a raw disk (a tar stream), the ISO and logs come out on another.
#
# Output: build/release/iso/
#   zynith-<version>-<date>-x86_64.iso, its .sha256, manifest.txt (every package and version in the image),
#   build-info.txt (sources, revisions, sizes) and the builder's logs (lmc.log, program.log, console.log)
#
# Needs: podman, qemu-system-x86_64 and qemu-img, read/write access to /dev/kvm, curl, gpgv, python3, ~40 GB free
# under build/. Downloads: the Fedora Cloud image (once, ~500 MB, checksum and signature verified) and the packages.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
REL="${ZYNITH_RELEASE_DIR:-$ROOT/build/release}"
WORK="$REL/builder"
OUTDIR="$REL/iso"
FEDORA=44
CLOUD_BASE="https://dl.fedoraproject.org/pub/fedora/linux/releases/$FEDORA/Cloud/x86_64/images"
CLOUD_IMAGE="Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2"
CLOUD_CHECKSUM="Fedora-Cloud-44-1.7-x86_64-CHECKSUM"
FEDORA_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$FEDORA-primary"
VM_MEM="${ZYNITH_BUILDER_MEM:-5120}"
VM_CPUS="${ZYNITH_BUILDER_CPUS:-$(( $(nproc) / 2 > 1 ? $(nproc) / 2 : 1 ))}"
TIMEOUT_MIN="${ZYNITH_BUILDER_TIMEOUT:-180}"

rpm_args=() reuse=0
while (($#)); do
    case "$1" in
    --rev) rpm_args+=(--rev "$2"); shift 2 ;;
    --worktree) rpm_args+=(--worktree); shift ;;
    --reuse-rpms) reuse=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done
say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { echo "build-iso: $*" >&2; exit 1; }
for t in podman qemu-system-x86_64 qemu-img curl gpg gpgv python3 tar; do command -v "$t" >/dev/null || die "$t is required"; done
[[ -r /dev/kvm && -w /dev/kvm ]] || die "/dev/kvm is not accessible (the builder VM needs KVM)"
version="$(cat "$ROOT/VERSION")"

# ── 1. the Zynith RPMs and the local repository ──
if ((reuse)); then
    [[ -f "$REL/repo/repodata/repomd.xml" ]] || die "no repository at $REL/repo (run without --reuse-rpms)"
else
    "$ROOT/packaging/rpm/build-rpms.sh" "${rpm_args[@]}"
fi
ls "$REL"/repo/zynith-desktop-*.rpm >/dev/null 2>&1 || die "the repository has no zynith-desktop package"
ls "$REL"/repo/quickshell-*.rpm >/dev/null 2>&1 || die "the repository has no quickshell package"

# ── 1b. the Fedora packages, downloaded once on the host (persistent cache; only changes are fetched again) ──
say "Fetching the Fedora packages into a local repository"
"$ROOT/iso/fetch-packages.sh" || die "the Fedora packages could not be resolved or downloaded"

# ── 2. the kickstart parses for Fedora $FEDORA ──
say "Validating iso/zynith-live.ks"
podman run --rm --security-opt label=disable -v "$ROOT/iso:/iso:ro" "registry.fedoraproject.org/fedora:$FEDORA" \
    bash -c "dnf -y -q install pykickstart >/dev/null && ksvalidator -v F$FEDORA /iso/zynith-live.ks" \
    || die "the kickstart does not validate"

# ── 3. the builder: Fedora Cloud, verified ──
mkdir -p "$WORK" "$OUTDIR"
if [[ ! -f "$WORK/$CLOUD_IMAGE.verified" ]]; then
    say "Downloading the Fedora $FEDORA Cloud image (builder)"
    curl -fL --progress-bar -o "$WORK/$CLOUD_IMAGE" "$CLOUD_BASE/$CLOUD_IMAGE"
    curl -fsSL -o "$WORK/$CLOUD_CHECKSUM" "$CLOUD_BASE/$CLOUD_CHECKSUM"
    # gpgv needs the key as a keyring file (it cannot read one from a pipe)
    gpg --dearmor <"$FEDORA_KEY" >"$WORK/fedora-$FEDORA.gpg"
    gpgv --keyring "$WORK/fedora-$FEDORA.gpg" "$WORK/$CLOUD_CHECKSUM" 2>/dev/null \
        || die "the CHECKSUM file's signature does not verify against $FEDORA_KEY"
    (cd "$WORK" && grep -E "^SHA256 \($CLOUD_IMAGE\)" "$CLOUD_CHECKSUM" | sha256sum -c --status) \
        || die "the Cloud image does not match its signed checksum"
    touch "$WORK/$CLOUD_IMAGE.verified"
fi
rm -f "$WORK/builder.qcow2" "$WORK/in.raw" "$WORK/out.raw"
qemu-img create -q -f qcow2 -b "$WORK/$CLOUD_IMAGE" -F qcow2 "$WORK/builder.qcow2" 60G

# inputs: the kickstart and the repository, as a tar stream on a raw disk
stage="$WORK/in"; rm -rf "$stage"; mkdir -p "$stage/iso"
cp "$ROOT/iso/zynith-live.ks" "$stage/iso/"
cp -a "$REL/repo" "$stage/repo"
cp -a "$REL/fedora" "$stage/fedora"
tar -C "$stage" -cf "$WORK/in.raw" .
truncate -s %1M "$WORK/in.raw"
truncate -s 12G "$WORK/out.raw"

# cloud-init (NoCloud over HTTP, bound to the host's loopback; the VM reaches it as 10.0.2.2)
seed="$WORK/seed"; rm -rf "$seed"; mkdir -p "$seed"
stamp="$(date -u +%Y%m%d)"
iso_name="zynith-$version-$stamp-x86_64.iso"
printf 'instance-id: zynith-builder-%s\nlocal-hostname: zynith-builder\n' "$(date +%s)" >"$seed/meta-data"
cat >"$seed/user-data" <<EOF
#cloud-config
# the builder does one job and powers off; no login is configured
write_files:
  - path: /root/build.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -uxo pipefail
      exec > /root/build.log 2>&1
      mkdir -p /mnt/zynith/out
      finish() {
        cp /root/build.log /var/tmp/lmc/*.log /tmp/*.log /mnt/zynith/out/ 2>/dev/null
        journalctl -b --no-pager > /mnt/zynith/out/builder-journal.log 2>&1
        tar -C /mnt/zynith/out -cf /dev/vdc .
        sync
        systemctl poweroff
      }
      trap finish EXIT
      tar -C /mnt/zynith -xf /dev/vdb
      echo "deltarpm=False" >> /etc/dnf/dnf.conf
      # from the local repository; the network only if something is missing there
      dnf -y --repo=local --repofrompath=local,file:///mnt/zynith/fedora --setopt=local.gpgcheck=1 \\
        --setopt=local.gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$FEDORA-x86_64 \\
        install lorax lorax-lmc-novirt anaconda-tui pykickstart \\
        || dnf -y install lorax lorax-lmc-novirt anaconda-tui pykickstart || exit 1
      setenforce 0
      livemedia-creator --no-virt --make-iso --iso-only \\
        --ks /mnt/zynith/iso/zynith-live.ks --resultdir /var/tmp/lmc/result --tmp /var/tmp \\
        --logfile /var/tmp/lmc/lmc.log --project "Zynith $version on Fedora" --releasever $FEDORA \\
        --volid "Zynith-$version" --iso-name "$iso_name"
      rc=\$?
      echo "livemedia-creator exit \$rc"
      [ -f "/var/tmp/lmc/result/$iso_name" ] && mv "/var/tmp/lmc/result/$iso_name" /mnt/zynith/out/
      exit \$rc
runcmd:
  - [ bash, /root/build.sh ]
EOF
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
python3 -m http.server --bind 127.0.0.1 --directory "$seed" "$port" >"$WORK/seed-http.log" 2>&1 &
http_pid=$!
trap 'kill $http_pid 2>/dev/null || true' EXIT

# ── 4. build ──
say "Building the image in the builder VM ($VM_CPUS CPUs, $VM_MEM MiB, at most $TIMEOUT_MIN min; console: $WORK/console.log)"
nice -n 19 timeout "${TIMEOUT_MIN}m" qemu-system-x86_64 \
    -enable-kvm -cpu host -smp "$VM_CPUS" -m "$VM_MEM" -machine q35 \
    -drive file="$WORK/builder.qcow2",if=virtio,format=qcow2 \
    -drive file="$WORK/in.raw",if=virtio,format=raw,readonly=on \
    -drive file="$WORK/out.raw",if=virtio,format=raw \
    -nic user,model=virtio-net-pci \
    -smbios "type=1,serial=ds=nocloud;s=http://10.0.2.2:$port/" \
    -display none -serial file:"$WORK/console.log" -monitor none \
    || die "the builder VM did not finish (timeout or QEMU error); see $WORK/console.log"

# ── 5. collect ──
res="$WORK/result"; rm -rf "$res"; mkdir -p "$res"
tar -C "$res" -xf "$WORK/out.raw" 2>/dev/null || die "the builder produced no output (see $WORK/console.log)"
cp "$res"/*.log "$OUTDIR/" 2>/dev/null || true
[[ -f "$res/$iso_name" ]] || die "no ISO was produced; see $OUTDIR/lmc.log and $OUTDIR/build.log"
mv -f "$res/$iso_name" "$OUTDIR/"
[[ -f "$res/manifest.txt" ]] && cp "$res/manifest.txt" "$OUTDIR/manifest.txt"
(cd "$OUTDIR" && sha256sum "$iso_name" >"$iso_name.sha256")
{
    echo "Zynith $version ISO, built $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "zynith:      $(rpm -qp --qf '%{name}-%{version}-%{release}' "$REL"/repo/zynith-desktop-*.rpm 2>/dev/null) (the release carries the source commit)"
    echo "kickstart:   iso/zynith-live.ks @ $(git -C "$ROOT" rev-parse HEAD)$(git -C "$ROOT" diff --quiet -- iso/ || echo ' (modified)')"
    echo "fedora:      $FEDORA x86_64 (builder: $CLOUD_IMAGE)"
    echo "packages:    $(wc -l <"$OUTDIR/manifest.txt" 2>/dev/null || echo ?) (manifest.txt)"
    echo "size:        $(stat -c %s "$OUTDIR/$iso_name") bytes"
    echo "sha256:      $(cut -d' ' -f1 "$OUTDIR/$iso_name.sha256")"
} >"$OUTDIR/build-info.txt"
cat "$OUTDIR/build-info.txt"
rm -f "$WORK/builder.qcow2" "$WORK/in.raw" "$WORK/out.raw"
say "ISO: $OUTDIR/$iso_name"
