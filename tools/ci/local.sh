#!/usr/bin/env bash
# tools/ci/local.sh — run the CI checks (tools/ci/check.sh) in a Fedora 44 container, as CI does.
#
#   tools/ci/local.sh                       every stage
#   tools/ci/local.sh hygiene packaging     some stages
#
# The working tree is copied in as git sees it (tracked files plus new files that are not ignored), so build
# directories and ignored files never reach the container. Runs at the lowest CPU priority on half the cores.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
stages=("$@")
((${#stages[@]})) || stages=(hygiene format packaging native ui)
jobs=$(( $(nproc) / 2 > 1 ? $(nproc) / 2 : 1 ))
cache="$ROOT/build/release/cache/dnf"
mkdir -p "$cache"

rc=0
for stage in "${stages[@]}"; do
    printf '\n\033[1m### %s\033[0m\n' "$stage"
    (cd "$ROOT" && git ls-files -co --exclude-standard -z | tar --null -T - -cf -) |
        nice -n 19 podman run --rm -i --security-opt label=disable -v "$cache:/var/cache/libdnf5" -e JOBS="$jobs" \
            registry.fedoraproject.org/fedora:44 bash -euo pipefail -c '
                echo "keepcache=True" >> /etc/dnf/dnf.conf
                mkdir /src && cd /src && tar -xf -
                # the checks read the tree through git, as in a CI checkout
                dnf -y -q install git-core >/dev/null 2>&1
                git init -q && git add -A && git -c user.name=ci -c user.email=ci@localhost commit -qm tree
                tools/ci/check.sh deps "$0" >/tmp/deps.log 2>&1 || { cat /tmp/deps.log; exit 1; }
                tools/ci/check.sh "$0"' "$stage" || rc=1
done
exit $rc
