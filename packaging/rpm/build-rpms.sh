#!/usr/bin/env bash
# packaging/rpm/build-rpms.sh — build Zynith's RPMs in a clean Fedora container and assemble a local repository.
#
#   packaging/rpm/build-rpms.sh                 from the committed HEAD (reproducible: the tarball is `git archive`)
#   packaging/rpm/build-rpms.sh --rev v0.1.0    from a tag or commit
#   packaging/rpm/build-rpms.sh --worktree      from the working tree as it is (development only; marked "dirty")
#
# Output (build/release/, never committed):
#   rpms/       zynith-{shell,ui,desktop,live}-*.rpm and the source RPM
#   repo/       a dnf repository: the Zynith RPMs + the pinned Quickshell build (see COPR_* below)
#   rpms.sha256 checksums of everything in rpms/ and repo/
#
# Needs only rootless podman on the host. The container is Fedora $FEDORA; its build dependencies come from the
# spec (dnf builddep). It runs at the lowest CPU priority on half the cores.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
OUT="${ZYNITH_RELEASE_DIR:-$ROOT/build/release}"
FEDORA="${FEDORA:-44}"
IMAGE="registry.fedoraproject.org/fedora:$FEDORA"
# Quickshell: Fedora $FEDORA's own package is an older snapshot; Zynith is developed and tested against this build
# from the errornointernet/quickshell COPR, with the cpptrace build it links against (Fedora has none). They are
# copied into the local repository (the installed system gets no COPR repository), each verified against the COPR's
# signing key.
COPR_BASE="https://download.copr.fedorainfracloud.org/results/errornointernet/quickshell"
COPR_PKGS="quickshell-0.3.1-2.fc$FEDORA.x86_64 cpptrace-1.0.4-1.patched.fc$FEDORA.x86_64"

rev=HEAD worktree=0
while (($#)); do
    case "$1" in
    --rev) rev="$2"; shift 2 ;;
    --worktree) worktree=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done
say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { echo "build-rpms: $*" >&2; exit 1; }
command -v podman >/dev/null || die "podman is required"

version="$(cat "$ROOT/VERSION")"
commit="$(git -C "$ROOT" rev-parse "$rev^{commit}")"
snapdate="$(git -C "$ROOT" show -s --format=%cd --date=format:%Y%m%d "$commit")"
release=0
mkdir -p "$OUT"/{src,rpms,repo,cache/dnf}
rm -f "$OUT"/rpms/*.rpm "$OUT"/repo/*.rpm
tarball="$OUT/src/zynith-$version.tar.gz"
if ((worktree)); then
    say "Source: working tree (based on ${commit:0:8}, uncommitted changes included) — for development only"
    commit="${commit}-dirty"
    # the files git tracks plus new files it does not ignore, as they are on disk
    (cd "$ROOT" && git ls-files -co --exclude-standard -z | tar --null -T - --transform "s,^,zynith-$version/," -czf "$tarball")
else
    say "Source: $rev = ${commit:0:8} (git archive)"
    git -C "$ROOT" archive --format=tar.gz --prefix="zynith-$version/" -o "$tarball" "$commit"
fi

say "Building in $IMAGE (nice 19, $(( $(nproc) / 2 )) jobs)"
nice -n 19 podman run --rm --security-opt label=disable \
    -v "$OUT:/out" -v "$ROOT/packaging/rpm/zynith.spec:/zynith.spec:ro" -v "$OUT/cache/dnf:/var/cache/libdnf5" \
    -e version="$version" -e release="$release" -e commit="$commit" -e snapdate="$snapdate" \
    -e jobs="$(( $(nproc) / 2 > 1 ? $(nproc) / 2 : 1 ))" \
    -e copr_base="$COPR_BASE" -e copr_pkgs="$COPR_PKGS" -e fedora="$FEDORA" \
    "$IMAGE" bash -euo pipefail -c '
        echo "keepcache=True" >> /etc/dnf/dnf.conf
        dnf -y -q install rpm-build rpmdevtools dnf-plugins-core createrepo_c >/dev/null
        dnf -y -q builddep /zynith.spec >/dev/null
        rpmdev-setuptree
        cp /out/src/zynith-$version.tar.gz ~/rpmbuild/SOURCES/
        defs=(--define "zynith_version $version" --define "zynith_release $release" --define "commit $commit"
              --define "snapdate $snapdate" --define "_smp_mflags -j$jobs")
        rpmbuild -ba "${defs[@]}" /zynith.spec > /out/rpmbuild.log 2>&1 || { tail -40 /out/rpmbuild.log; exit 1; }
        cp ~/rpmbuild/RPMS/*/*.rpm ~/rpmbuild/SRPMS/*.rpm /out/rpms/
        # the pinned Quickshell, its signature checked against the COPR key
        curl -fsSL -o /tmp/copr.key "$copr_base/pubkey.gpg" && rpm --import /tmp/copr.key
        for nvra in $copr_pkgs; do
            curl -fsSL -o "/out/repo/$nvra.rpm" "$copr_base/fedora-$fedora-x86_64/Packages/${nvra:0:1}/$nvra.rpm"
            rpm -K "/out/repo/$nvra.rpm" | grep -q "digests signatures OK" || { rpm -Kv "/out/repo/$nvra.rpm"; exit 1; }
        done
        # the image needs the packages, not their source or debug information
        cp /out/rpms/zynith-*.rpm /out/repo/ && rm -f /out/repo/*.src.rpm /out/repo/*-debuginfo-*.rpm /out/repo/*-debugsource-*.rpm
        createrepo_c -q /out/repo
        # every package must install from this repository and Fedora alone (what the image build will ask of it)
        dnf -q --setopt=install_weak_deps=False --repofrompath=zynith,file:///out/repo --setopt=zynith.gpgcheck=0 \
            install --assumeno zynith-desktop zynith-live >/tmp/closure.log 2>&1 || true
        if grep -qiE "failed to resolve|nothing provides|conflicting requests" /tmp/closure.log; then
            cat /tmp/closure.log; echo "the packages do not install: dependencies missing"; exit 1
        fi
    '
(cd "$OUT" && sha256sum rpms/*.rpm repo/*.rpm > rpms.sha256)
say "Built $(ls "$OUT"/rpms/*.rpm | wc -l) RPMs from ${commit:0:12}; repository: $OUT/repo"
ls -1 "$OUT"/repo/*.rpm | sed "s|$OUT/||"
