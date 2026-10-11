#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/dropform-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
npm --prefix ui run typecheck
npm --prefix ui test
swift build --disable-sandbox
BIN_DIR=$(swift build --show-bin-path --disable-sandbox)
"$BIN_DIR/Dropform" --self-test
