#!/usr/bin/env bash
# The bar model through the real config store: copies the fixtures to a scratch directory (the tests write and
# recover files) and runs tools/tests/tst_bar_store.qml against the built native plugin.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
ui="$here/../.."
plugin="${ZYNITH_NATIVE_BUILD:-$ui/../../build-zynith-native}/qml"
scratch=/tmp/zynith-bar-store-test
rm -rf "$scratch"
mkdir -p "$scratch"
for name in a b c; do cp "$here/fixtures/bars-v1.toml" "$scratch/$name.toml"; done
cp "$here/fixtures/bars-broken.toml" "$scratch/d.toml"
cp "$here/fixtures/bars-v1.toml" "$scratch/v1-original.toml"
cp "$here/fixtures/bars-broken.toml" "$scratch/broken-original.toml"
QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -import "$plugin" -input "$here/tst_bar_store.qml" "$@"
status=$?
rm -rf "$scratch"
exit $status
