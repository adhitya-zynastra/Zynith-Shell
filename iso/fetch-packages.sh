#!/usr/bin/env bash
# iso/fetch-packages.sh — download every Fedora package the image and its builder need, once, into a local repository.
#
#   iso/fetch-packages.sh            (iso/build-iso.sh runs it)
#
# The package set is resolved from iso/zynith-live.ks (%packages, groups included) plus the packages Anaconda adds and
# the builder's own tools, in a clean Fedora container, against an empty root — so the result is the full closure.
# Downloads go to a persistent cache (build/release/cache/fedora-pkgs) with parallel connections; a later build only
# fetches what changed. The builder VM then installs from this repository first and from the network only as a
# fallback: building no longer depends on the builder VM's network.
#
# Output: build/release/fedora/ — a dnf repository (packages hard-linked from the cache) with Fedora's comps groups.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
REL="${ZYNITH_RELEASE_DIR:-$ROOT/build/release}"
FEDORA=44
CACHE="$REL/cache/fedora-pkgs"
OUT="$REL/fedora"
[[ -f "$REL/repo/repodata/repomd.xml" ]] || { echo "fetch-packages: build the Zynith RPMs first" >&2; exit 1; }
mkdir -p "$CACHE" "$REL/cache/dnf"
rm -rf "$OUT"; mkdir -p "$OUT/Packages"

# packages Anaconda adds to a kickstart install (time sync, firewall, language support, SELinux policy, filesystems)
anaconda_adds="chrony firewalld langpacks-en selinux-policy-targeted e2fsprogs xfsprogs"
# what the builder VM installs to run livemedia-creator
builder_tools="lorax lorax-lmc-novirt anaconda-tui pykickstart"

nice -n 19 podman run --rm --security-opt label=disable \
    -v "$REL:/rel" -v "$REL/repo:/zrepo:ro" -v "$ROOT/iso:/iso:ro" -v "$REL/cache/dnf:/var/cache/libdnf5" \
    -e fedora="$FEDORA" -e anaconda_adds="$anaconda_adds" -e builder_tools="$builder_tools" \
    "registry.fedoraproject.org/fedora:$FEDORA" bash -euo pipefail -c '
        echo "keepcache=True" >> /etc/dnf/dnf.conf
        # one mount for the cache and the repository, so packages can be hard-linked rather than copied
        ln -s /rel/cache/fedora-pkgs /pc && ln -s /rel/fedora /out
        dnf -y -q install createrepo_c zstd >/dev/null
        mapfile -t pkgs < <(sed -n "/^%packages/,/^%end/p" /iso/zynith-live.ks | grep -vE "^(%|#|$)")
        dl() {  # resolve against an empty root, download only, into the persistent cache
            rm -rf /tmp/root
            dnf -y -q --installroot=/tmp/root --use-host-config --releasever="$fedora" \
                --setopt=install_weak_deps=False --setopt=keepcache=True --setopt=max_parallel_downloads=10 \
                --setopt=cachedir=/pc --setopt=system_cachedir=/pc \
                --repofrompath=zynith,file:///zrepo --setopt=zynith.gpgcheck=0 \
                install --downloadonly "$@"
        }
        echo "resolving and downloading the image packages"
        dl "${pkgs[@]}" $anaconda_adds
        echo "resolving and downloading the builder tools"
        dl $builder_tools
        # every package from the Fedora repositories (Zynith and Quickshell come from their own repository)
        find -L /pc -path "*/packages/*.rpm" ! -path "/pc/zynith-*" -exec ln -f {} /out/Packages/ \;
        comps=$(ls -t /pc/fedora-*/repodata/*comps*.xml* | head -1)
        case "$comps" in *.zst) zstd -dq "$comps" -o /tmp/comps.xml ;; *.gz) gzip -dc "$comps" >/tmp/comps.xml ;; *.xz) xz -dc "$comps" >/tmp/comps.xml ;; *) cp "$comps" /tmp/comps.xml ;; esac
        createrepo_c -q -g /tmp/comps.xml /out
        n=$(ls /out/Packages | wc -l)
        ((n > 500)) || { echo "only $n packages in the local repository"; exit 1; }
        echo "$n packages, $(du -shL /out/Packages | cut -f1)"
    '
