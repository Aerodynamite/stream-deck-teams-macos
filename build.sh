#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
build_dir="$script_dir/.build"
module_cache="$build_dir/clang-module-cache"
binary="$build_dir/teams-reaction"

mkdir -p "$build_dir" "$module_cache"

xcrun clang \
  -O \
  -Wall \
  -Wextra \
  -fobjc-arc \
  -fmodules-cache-path="$module_cache" \
  -framework Foundation \
  -framework ApplicationServices \
  -framework AppKit \
  "$script_dir/TeamsReactionPOC.m" \
  -o "$binary"

codesign --force --sign - --identifier com.local.TeamsReactionPOC "$binary"

echo "Built: $binary"
echo "First test: $binary inspect"
