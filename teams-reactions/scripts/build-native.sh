#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
source_dir=${project_dir:h}
plugin_dir="$project_dir/com.laurens-bolle.teams-reactions.sdPlugin"
build_dir="$project_dir/.native-build"
module_cache="$build_dir/clang-module-cache"
binary="$plugin_dir/bin/teams-reaction"

mkdir -p "$plugin_dir/bin" "$module_cache"

xcrun clang \
  -O \
  -Wall \
  -Wextra \
  -fobjc-arc \
  -fmodules-cache-path="$module_cache" \
  -framework Foundation \
  -framework ApplicationServices \
  -framework AppKit \
  "$source_dir/TeamsReactionPOC.m" \
  -o "$binary"

codesign \
  --force \
  --sign - \
  --identifier com.laurens-bolle.teams-reactions.helper \
  "$binary"

echo "Built native helper: $binary"
