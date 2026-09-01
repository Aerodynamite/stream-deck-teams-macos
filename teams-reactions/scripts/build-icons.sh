#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
assets_dir="$project_dir/assets"
plugin_dir="$project_dir/com.laurens-bolle.teams-reactions.sdPlugin"
plugin_images="$plugin_dir/imgs/plugin"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert is required to regenerate the PNG icons." >&2
  echo "Install librsvg with Homebrew, then rerun npm run build:icons." >&2
  exit 1
fi

mkdir -p "$plugin_images"
rsvg-convert -w 256 -h 256 -o "$plugin_images/marketplace.png" "$assets_dir/plugin.svg"
rsvg-convert -w 512 -h 512 -o "$plugin_images/marketplace@2x.png" "$assets_dir/plugin.svg"
rsvg-convert -w 28 -h 28 -o "$plugin_images/category-icon.png" "$assets_dir/category.svg"
rsvg-convert -w 56 -h 56 -o "$plugin_images/category-icon@2x.png" "$assets_dir/category.svg"

for reaction in like love applause laugh surprise; do
  action_images="$plugin_dir/imgs/actions/$reaction"
  mkdir -p "$action_images"
  rsvg-convert -w 20 -h 20 -o "$action_images/icon.png" "$assets_dir/$reaction-icon.svg"
  rsvg-convert -w 40 -h 40 -o "$action_images/icon@2x.png" "$assets_dir/$reaction-icon.svg"
  rsvg-convert -w 72 -h 72 -o "$action_images/key.png" "$assets_dir/$reaction-key.svg"
  rsvg-convert -w 144 -h 144 -o "$action_images/key@2x.png" "$assets_dir/$reaction-key.svg"
done

echo "Regenerated Stream Deck icons in: $plugin_dir/imgs"
