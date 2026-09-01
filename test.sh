#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
build_dir="$script_dir/.build"
module_cache="$build_dir/clang-module-cache"
test_binary="$build_dir/launcher-scoring-tests"

mkdir -p "$build_dir" "$module_cache"

xcrun clang \
  -O \
  -Wall \
  -Wextra \
  -Wno-unused-function \
  -fobjc-arc \
  -fmodules-cache-path="$module_cache" \
  -framework Foundation \
  -framework ApplicationServices \
  -framework AppKit \
  "$script_dir/tests/LauncherScoringTests.m" \
  -o "$test_binary"

"$test_binary"
